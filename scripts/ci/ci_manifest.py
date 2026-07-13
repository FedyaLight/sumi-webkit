#!/usr/bin/env python3
"""Strict validation and queries for Sumi's authoritative CI test manifest."""

import argparse
import json
import re
import sys
from pathlib import Path, PurePosixPath


ALLOWED_KINDS = {"swift-package", "xcode-test"}
ID_PATTERN = re.compile(r"^[a-z][a-z0-9-]*$")
SELECTOR_PATTERN = re.compile(
    r"^[A-Za-z_][A-Za-z0-9_.-]*/[A-Za-z_][A-Za-z0-9_.-]*(?:/[A-Za-z_][A-Za-z0-9_.-]*)?$"
)


class ManifestError(ValueError):
    pass


def _reject_duplicate_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ManifestError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def _expect_object(value, context):
    if not isinstance(value, dict):
        raise ManifestError(f"{context} must be an object")


def _expect_keys(value, required, context):
    _expect_object(value, context)
    missing = required - value.keys()
    unknown = value.keys() - required
    if missing:
        raise ManifestError(f"{context} is missing: {', '.join(sorted(missing))}")
    if unknown:
        raise ManifestError(f"{context} has unknown entries: {', '.join(sorted(unknown))}")


def _expect_string(value, context):
    if not isinstance(value, str) or not value.strip():
        raise ManifestError(f"{context} must be a non-empty string")


def _expect_id(value, context):
    _expect_string(value, context)
    if not ID_PATTERN.fullmatch(value):
        raise ManifestError(f"{context} must match {ID_PATTERN.pattern}")


def _expect_relative_path(value, context, repo_root):
    _expect_string(value, context)
    path = PurePosixPath(value)
    if path.is_absolute() or path.as_posix() != value or ".." in path.parts:
        raise ManifestError(f"{context} must be a normalized repository-relative path")
    resolved = repo_root.joinpath(*path.parts)
    if not resolved.exists():
        raise ManifestError(f"{context} does not exist: {value}")
    return resolved


def _validate_toolchains(toolchains):
    _expect_object(toolchains, "toolchains")
    if not toolchains:
        raise ManifestError("toolchains must not be empty")
    required = {"name", "runner", "developer_dir", "xcode_version", "selection_note"}
    for toolchain_id, toolchain in toolchains.items():
        _expect_id(toolchain_id, "toolchain id")
        context = f"toolchain {toolchain_id}"
        _expect_keys(toolchain, required, context)
        for field in required:
            _expect_string(toolchain[field], f"{context}.{field}")
        if not re.fullmatch(r"macos-[0-9]+(?:-arm64)?", toolchain["runner"]):
            raise ManifestError(f"{context}.runner must be an explicit macOS runner label")
        if not re.fullmatch(r"[0-9]+\.[0-9]+(?:\.[0-9]+)?", toolchain["xcode_version"]):
            raise ManifestError(f"{context}.xcode_version must be a dotted version")
        expected_dir = (
            f"/Applications/Xcode_{toolchain['xcode_version']}.app/Contents/Developer"
        )
        if toolchain["developer_dir"] != expected_dir:
            raise ManifestError(
                f"{context}.developer_dir must select xcode_version at {expected_dir}"
            )


def _validate_xcode(xcode, repo_root):
    required = {"project", "destination", "parallel_testing_enabled"}
    _expect_keys(xcode, required, "xcode")
    project = _expect_relative_path(xcode["project"], "xcode.project", repo_root)
    if project.suffix != ".xcodeproj" or not project.is_dir():
        raise ManifestError("xcode.project must name an existing .xcodeproj directory")
    _expect_string(xcode["destination"], "xcode.destination")
    if not isinstance(xcode["parallel_testing_enabled"], bool):
        raise ManifestError("xcode.parallel_testing_enabled must be a boolean")


def _validate_suite(suite, repo_root, xcode_project):
    common = {"id", "name", "kind"}
    _expect_object(suite, "suite")
    kind = suite.get("kind")
    if kind not in ALLOWED_KINDS:
        raise ManifestError(f"suite has unknown kind: {kind!r}")
    required = common | (
        {"path"} if kind == "swift-package" else {"scheme", "configuration", "selectors"}
    )
    context = f"suite {suite.get('id', '<missing>')}"
    _expect_keys(suite, required, context)
    _expect_id(suite["id"], f"{context}.id")
    _expect_string(suite["name"], f"{context}.name")

    if kind == "swift-package":
        package = _expect_relative_path(suite["path"], f"{context}.path", repo_root)
        if not package.is_dir() or not (package / "Package.swift").is_file():
            raise ManifestError(f"{context}.path must contain Package.swift")
        return

    _expect_string(suite["scheme"], f"{context}.scheme")
    _expect_string(suite["configuration"], f"{context}.configuration")
    scheme_path = (
        xcode_project / "xcshareddata" / "xcschemes" / f"{suite['scheme']}.xcscheme"
    )
    if not scheme_path.is_file():
        raise ManifestError(f"{context}.scheme is not a shared scheme: {suite['scheme']}")
    selectors = suite["selectors"]
    if not isinstance(selectors, list):
        raise ManifestError(f"{context}.selectors must be an array")
    seen = set()
    for selector in selectors:
        _expect_string(selector, f"{context}.selector")
        if not SELECTOR_PATTERN.fullmatch(selector):
            raise ManifestError(f"{context} has malformed selector: {selector}")
        if selector in seen:
            raise ManifestError(f"{context} has duplicate selector: {selector}")
        seen.add(selector)


def load_manifest(path, repo_root):
    try:
        with path.open(encoding="utf-8") as manifest_file:
            data = json.load(manifest_file, object_pairs_hook=_reject_duplicate_keys)
    except ManifestError:
        raise
    except (OSError, json.JSONDecodeError) as error:
        raise ManifestError(f"cannot read {path}: {error}") from error

    top_level = {"version", "toolchains", "xcode", "profiles", "suites"}
    _expect_keys(data, top_level, "manifest")
    if type(data["version"]) is not int or data["version"] != 1:
        raise ManifestError("manifest.version must be integer 1")
    _validate_toolchains(data["toolchains"])
    _validate_xcode(data["xcode"], repo_root)

    suites = data["suites"]
    if not isinstance(suites, list) or not suites:
        raise ManifestError("suites must be a non-empty array")
    project = repo_root / data["xcode"]["project"]
    suites_by_id = {}
    for suite in suites:
        _validate_suite(suite, repo_root, project)
        suite_id = suite["id"]
        if suite_id in suites_by_id:
            raise ManifestError(f"duplicate suite id: {suite_id}")
        suites_by_id[suite_id] = suite

    profiles = data["profiles"]
    _expect_object(profiles, "profiles")
    if not profiles:
        raise ManifestError("profiles must not be empty")
    for profile_id, profile in profiles.items():
        _expect_id(profile_id, "profile id")
        context = f"profile {profile_id}"
        _expect_keys(profile, {"toolchain", "suites"}, context)
        _expect_string(profile["toolchain"], f"{context}.toolchain")
        if profile["toolchain"] not in data["toolchains"]:
            raise ManifestError(f"{context} references unknown toolchain: {profile['toolchain']}")
        if not isinstance(profile["suites"], list) or not profile["suites"]:
            raise ManifestError(f"{context}.suites must be a non-empty array")
        seen = set()
        for suite_id in profile["suites"]:
            _expect_string(suite_id, f"{context}.suite")
            if suite_id not in suites_by_id:
                raise ManifestError(f"{context} references unknown suite: {suite_id}")
            if suite_id in seen:
                raise ManifestError(f"{context} has duplicate suite: {suite_id}")
            seen.add(suite_id)

    return data, suites_by_id


def _selected_suites(data, suites_by_id, profile_id, kind):
    profile = data["profiles"].get(profile_id)
    if profile is None:
        raise ManifestError(f"unknown profile: {profile_id}")
    if kind is not None and kind not in ALLOWED_KINDS:
        raise ManifestError(f"unknown suite kind: {kind}")
    selected = [suites_by_id[suite_id] for suite_id in profile["suites"]]
    if kind is not None:
        selected = [suite for suite in selected if suite["kind"] == kind]
    if not selected:
        raise ManifestError(f"profile {profile_id} has no suites of kind {kind}")
    return selected


def _build_parser(default_manifest, default_repo_root):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=default_manifest)
    parser.add_argument("--repo-root", type=Path, default=default_repo_root)
    commands = parser.add_subparsers(dest="command", required=True)

    commands.add_parser("validate")
    for command in ("list", "matrix"):
        selection = commands.add_parser(command)
        selection.add_argument("profile")
        selection.add_argument("kind", nargs="?")

    suite_field = commands.add_parser("suite-field")
    suite_field.add_argument("suite")
    suite_field.add_argument("field")
    selectors = commands.add_parser("selectors")
    selectors.add_argument("suite")
    toolchain_field = commands.add_parser("toolchain-field")
    toolchain_field.add_argument("profile")
    toolchain_field.add_argument("field")
    xcode_field = commands.add_parser("xcode-field")
    xcode_field.add_argument("field")
    return parser


def main(argv=None):
    script_dir = Path(__file__).resolve().parent
    parser = _build_parser(script_dir / "test-manifest.json", script_dir.parent.parent)
    args = parser.parse_args(argv)
    repo_root = args.repo_root.resolve()
    try:
        data, suites_by_id = load_manifest(args.manifest.resolve(), repo_root)
        if args.command == "validate":
            print(f"CI manifest valid: {args.manifest}")
        elif args.command in {"list", "matrix"}:
            selected = _selected_suites(data, suites_by_id, args.profile, args.kind)
            if args.command == "list":
                print("\n".join(suite["id"] for suite in selected))
            else:
                include = []
                for suite in selected:
                    item = {"suite": suite["id"], "name": suite["name"]}
                    if suite["kind"] == "xcode-test":
                        item.update(
                            scheme=suite["scheme"], configuration=suite["configuration"]
                        )
                    include.append(item)
                print(json.dumps({"include": include}, separators=(",", ":")))
        elif args.command == "suite-field":
            suite = suites_by_id.get(args.suite)
            if suite is None:
                raise ManifestError(f"unknown suite: {args.suite}")
            if args.field not in suite or args.field == "selectors":
                raise ManifestError(f"suite {args.suite} has no scalar field: {args.field}")
            print(suite[args.field])
        elif args.command == "selectors":
            suite = suites_by_id.get(args.suite)
            if suite is None:
                raise ManifestError(f"unknown suite: {args.suite}")
            if suite["kind"] != "xcode-test":
                raise ManifestError(f"suite {args.suite} does not have test selectors")
            print("\n".join(suite["selectors"]))
        elif args.command == "toolchain-field":
            profile = data["profiles"].get(args.profile)
            if profile is None:
                raise ManifestError(f"unknown profile: {args.profile}")
            toolchain = data["toolchains"][profile["toolchain"]]
            if args.field not in toolchain:
                raise ManifestError(f"unknown toolchain field: {args.field}")
            print(toolchain[args.field])
        elif args.command == "xcode-field":
            if args.field not in data["xcode"]:
                raise ManifestError(f"unknown xcode field: {args.field}")
            value = data["xcode"][args.field]
            print("YES" if value is True else "NO" if value is False else value)
    except ManifestError as error:
        print(f"manifest error: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())

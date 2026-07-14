#!/usr/bin/env python3
"""Strict validation and queries for Sumi's authoritative CI test manifest."""

import argparse
import collections
import json
import re
import sys
from pathlib import Path, PurePosixPath


ALLOWED_KINDS = {"swift-package", "xcode-test"}
ID_PATTERN = re.compile(r"^[a-z][a-z0-9-]*$")
SELECTOR_PATTERN = re.compile(
    r"^[A-Za-z_][A-Za-z0-9_]*/[A-Za-z_][A-Za-z0-9_]*(?:/[A-Za-z_][A-Za-z0-9_]*)?$"
)
CLASS_DECLARATION_PATTERN = re.compile(
    r"^[ \t]*(?:(?:@[A-Za-z_][^\n]*|(?:final|private|fileprivate|internal|public|open|nonisolated))[ \t\r\n]+)*"
    r"class[ \t\r\n]+([A-Za-z_][A-Za-z0-9_]*)[ \t\r\n]*:[ \t\r\n]*"
    r"([A-Za-z_][A-Za-z0-9_\.]*)[^{}]*\{",
    re.MULTILINE,
)
EXTENSION_DECLARATION_PATTERN = re.compile(
    r"^[ \t]*extension[ \t\r\n]+([A-Za-z_][A-Za-z0-9_\.]*)(?:[^{}]*)\{",
    re.MULTILINE,
)
TEST_METHOD_PATTERN = re.compile(
    r"^[ \t]*(?:(?:@[A-Za-z_][^\n]*)[ \t\r\n]+)*"
    r"(?:(?:final|internal|public|open|nonisolated|override)"
    r"[ \t\r\n]+)*func[ \t\r\n]+(test[A-Za-z0-9_]*)[ \t\r\n]*\(",
    re.MULTILINE,
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
        expected_dir = f"/Applications/Xcode_{toolchain['xcode_version']}.app/Contents/Developer"
        if toolchain["developer_dir"] != expected_dir:
            raise ManifestError(
                f"{context}.developer_dir must select xcode_version at {expected_dir}"
            )


def _pbx_objects(project_file):
    try:
        text = project_file.read_text(encoding="utf-8")
    except OSError as error:
        raise ManifestError(f"cannot read {project_file}: {error}") from error
    header = re.compile(
        r"^[ \t]*([A-Fa-f0-9]+)[ \t]+/\*[ \t]*(.*?)[ \t]*\*/[ \t]*=[ \t]*\{",
        re.MULTILINE,
    )
    objects = []
    for match in header.finditer(text):
        depth = 0
        end = None
        for index in range(match.end() - 1, len(text)):
            if text[index] == "{":
                depth += 1
            elif text[index] == "}":
                depth -= 1
                if depth == 0:
                    end = index
                    break
        if end is not None:
            objects.append((match.group(1), match.group(2), text[match.end() : end]))
    return objects


def _pbx_scalar(body, field, value):
    return re.search(
        rf"^[ \t]*{re.escape(field)}[ \t]*=[ \t]*\"?{re.escape(value)}\"?;",
        body,
        re.MULTILINE,
    ) is not None


def _validate_target_membership(project, target):
    project_file = project / "project.pbxproj"
    objects = _pbx_objects(project_file)
    source_groups = [
        object_id
        for object_id, _, body in objects
        if _pbx_scalar(body, "isa", "PBXFileSystemSynchronizedRootGroup")
        and _pbx_scalar(body, "path", target["source_path"])
    ]
    if len(source_groups) != 1:
        raise ManifestError(
            f"test target {target['module']} source_path must name exactly one "
            "PBXFileSystemSynchronizedRootGroup"
        )
    source_group = source_groups[0]
    native_targets = [
        body
        for _, _, body in objects
        if _pbx_scalar(body, "isa", "PBXNativeTarget")
        and _pbx_scalar(body, "name", target["target"])
    ]
    if len(native_targets) != 1:
        raise ManifestError(
            f"test target {target['module']} must name exactly one PBXNativeTarget"
        )
    membership = re.search(
        r"fileSystemSynchronizedGroups[ \t]*=[ \t]*\((.*?)\);",
        native_targets[0],
        re.DOTALL,
    )
    if membership is None or source_group not in membership.group(1):
        raise ManifestError(
            f"test target {target['module']} does not own synchronized source path "
            f"{target['source_path']}"
        )


def _scrub_swift_source(source):
    """Blank comments and strings while preserving byte offsets and newlines."""
    result = list(source)
    index = 0
    length = len(source)
    while index < length:
        if source.startswith("//", index):
            end = source.find("\n", index)
            end = length if end == -1 else end
            for cursor in range(index, end):
                result[cursor] = " "
            index = end
            continue
        if source.startswith("/*", index):
            start = index
            depth = 1
            index += 2
            while index < length and depth:
                if source.startswith("/*", index):
                    depth += 1
                    index += 2
                elif source.startswith("*/", index):
                    depth -= 1
                    index += 2
                else:
                    index += 1
            for cursor in range(start, index):
                if result[cursor] != "\n":
                    result[cursor] = " "
            continue

        hashes = 0
        while index + hashes < length and source[index + hashes] == "#":
            hashes += 1
        quote = index + hashes
        if quote < length and source[quote] == '"':
            triple = source.startswith('"""', quote)
            opener_length = hashes + (3 if triple else 1)
            closing = ('"""' if triple else '"') + ("#" * hashes)
            start = index
            index += opener_length
            while index < length:
                if source.startswith(closing, index):
                    index += len(closing)
                    break
                if not triple and hashes == 0 and source[index] == "\\":
                    index += 2
                else:
                    index += 1
            for cursor in range(start, min(index, length)):
                if result[cursor] != "\n":
                    result[cursor] = " "
            continue
        index += 1
    return "".join(result)


def _matching_brace(source, opening):
    depth = 0
    for index in range(opening, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return index
    raise ManifestError("Swift test source contains an unmatched declaration brace")


def _discover_test_inventory(module, target, source_path):
    swift_files = sorted(source_path.rglob("*.swift"))
    if not swift_files:
        raise ManifestError(f"test target {module} has no Swift sources")

    declarations = collections.defaultdict(list)
    class_files = collections.defaultdict(set)
    methods = collections.defaultdict(set)
    method_files = collections.defaultdict(set)

    for source_file in swift_files:
        try:
            scrubbed = _scrub_swift_source(source_file.read_text(encoding="utf-8"))
        except OSError as error:
            raise ManifestError(f"cannot read {source_file}: {error}") from error
        regions = []
        for match in CLASS_DECLARATION_PATTERN.finditer(scrubbed):
            name = match.group(1)
            base = match.group(2).split(".")[-1]
            opening = match.end() - 1
            declarations[name].append((base, source_file))
            class_files[name].add(source_file)
            regions.append((opening, _matching_brace(scrubbed, opening), name))
        for match in EXTENSION_DECLARATION_PATTERN.finditer(scrubbed):
            opening = match.end() - 1
            regions.append(
                (
                    opening,
                    _matching_brace(scrubbed, opening),
                    match.group(1).split(".")[-1],
                )
            )
        for method in TEST_METHOD_PATTERN.finditer(scrubbed):
            owners = [region for region in regions if region[0] < method.start() < region[1]]
            if not owners:
                continue
            owner = max(owners, key=lambda region: region[0])[2]
            method_name = method.group(1)
            if method_name in methods[owner]:
                raise ManifestError(f"duplicate test method declaration: {module}/{owner}/{method_name}")
            methods[owner].add(method_name)
            method_files[owner].add(source_file)

    xctest_classes = {
        name
        for name, candidates in declarations.items()
        if any(base == "XCTestCase" for base, _ in candidates)
    }
    changed = True
    while changed:
        changed = False
        for name, candidates in declarations.items():
            if name not in xctest_classes and any(
                base in xctest_classes for base, _ in candidates
            ):
                xctest_classes.add(name)
                changed = True

    duplicate_tests = [name for name in xctest_classes if len(declarations[name]) != 1]
    if duplicate_tests:
        raise ManifestError(
            f"test target {module} has duplicate XCTest class declarations: "
            f"{', '.join(sorted(duplicate_tests))}"
        )

    base_by_class = {
        name: declarations[name][0][0]
        for name in xctest_classes
    }
    effective_methods = {}

    def inherited_methods(name, stack=()):
        if name in effective_methods:
            return effective_methods[name]
        if name in stack:
            raise ManifestError(f"XCTest inheritance cycle in test target {module}: {name}")
        result = set(methods[name])
        base = base_by_class[name]
        if base in xctest_classes:
            result.update(inherited_methods(base, stack + (name,)))
        effective_methods[name] = result
        return result

    for name in xctest_classes:
        inherited_methods(name)
    runnable_classes = {name for name in xctest_classes if effective_methods[name]}
    helper_classes = xctest_classes - runnable_classes
    test_source_files = set()
    for name in runnable_classes:
        test_source_files.update(class_files[name])
        test_source_files.update(method_files[name])
    helper_source_files = set(swift_files) - test_source_files
    xctest_helper_source_files = {
        source_file
        for name in helper_classes
        for source_file in class_files[name]
        if source_file in helper_source_files
    }
    return {
        "module": module,
        "target": target,
        "source_path": source_path,
        "swift_files": set(swift_files),
        "test_source_files": test_source_files,
        "helper_source_files": helper_source_files,
        "xctest_helper_source_files": xctest_helper_source_files,
        "non_xctest_helper_source_files": helper_source_files
        - xctest_helper_source_files,
        "methods": effective_methods,
        "runnable_classes": runnable_classes,
        "helper_classes": helper_classes,
    }


def _validate_xcode(xcode, repo_root):
    required = {"project", "destination", "parallel_testing_enabled", "test_targets"}
    _expect_keys(xcode, required, "xcode")
    project = _expect_relative_path(xcode["project"], "xcode.project", repo_root)
    if project.suffix != ".xcodeproj" or not project.is_dir():
        raise ManifestError("xcode.project must name an existing .xcodeproj directory")
    _expect_string(xcode["destination"], "xcode.destination")
    if xcode["parallel_testing_enabled"] is not False:
        raise ManifestError("xcode.parallel_testing_enabled must remain false")
    targets = xcode["test_targets"]
    if not isinstance(targets, list) or not targets:
        raise ManifestError("xcode.test_targets must be a non-empty array")
    inventories = {}
    target_names = set()
    for target in targets:
        context = f"test target {target.get('module', '<missing>')}"
        _expect_keys(
            target,
            {"module", "target", "source_path", "exhaustive_profile"},
            context,
        )
        for field in ("module", "target", "source_path"):
            _expect_string(target[field], f"{context}.{field}")
        if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", target["module"]):
            raise ManifestError(f"{context}.module must be a Swift module identifier")
        if target["module"] in inventories:
            raise ManifestError(f"duplicate test target module: {target['module']}")
        if target["target"] in target_names:
            raise ManifestError(f"duplicate Xcode test target: {target['target']}")
        target_names.add(target["target"])
        if target["exhaustive_profile"] is not None:
            _expect_id(target["exhaustive_profile"], f"{context}.exhaustive_profile")
        source_path = _expect_relative_path(
            target["source_path"], f"{context}.source_path", repo_root
        )
        if not source_path.is_dir():
            raise ManifestError(f"{context}.source_path must be a directory")
        _validate_target_membership(project, target)
        inventories[target["module"]] = _discover_test_inventory(
            target["module"], target["target"], source_path
        )
    return project, inventories


def _selector_parts(selector):
    module, class_name, *method = selector.split("/")
    return module, class_name, method[0] if method else None


def _validate_selector(selector, context, inventories):
    _expect_string(selector, context)
    if not SELECTOR_PATTERN.fullmatch(selector):
        raise ManifestError(f"{context} is malformed: {selector}")
    module, class_name, method = _selector_parts(selector)
    inventory = inventories.get(module)
    if inventory is None:
        raise ManifestError(f"{context} names undeclared test target module: {module}")
    if class_name not in inventory["runnable_classes"]:
        raise ManifestError(f"{context} names no runnable XCTest class: {selector}")
    if method is not None and method not in inventory["methods"][class_name]:
        raise ManifestError(f"{context} names no XCTest method: {selector}")


def _validate_selector_list(selectors, context, inventories):
    if not isinstance(selectors, list) or not selectors:
        raise ManifestError(f"{context} must be a non-empty array")
    seen = set()
    for selector in selectors:
        _validate_selector(selector, f"{context} selector", inventories)
        if selector in seen:
            raise ManifestError(f"{context} has duplicate selector: {selector}")
        seen.add(selector)
    if selectors != sorted(selectors):
        raise ManifestError(f"{context} selectors must be sorted")


def _validate_suite(suite, repo_root, xcode_project, inventories):
    common = {"id", "name", "kind"}
    _expect_object(suite, "suite")
    kind = suite.get("kind")
    if kind not in ALLOWED_KINDS:
        raise ManifestError(f"suite has unknown kind: {kind!r}")
    required = common | (
        {"path"}
        if kind == "swift-package"
        else {"scheme", "configuration", "role", "selectors"}
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
    _expect_id(suite["role"], f"{context}.role")
    scheme_path = (
        xcode_project / "xcshareddata" / "xcschemes" / f"{suite['scheme']}.xcscheme"
    )
    if not scheme_path.is_file():
        raise ManifestError(f"{context}.scheme is not a shared scheme: {suite['scheme']}")
    _validate_selector_list(suite["selectors"], f"{context}.selectors", inventories)


def _selection_is_owned(selector, owned_selectors):
    if selector in owned_selectors:
        return True
    module, class_name, method = _selector_parts(selector)
    if method is None:
        return False
    return f"{module}/{class_name}" in owned_selectors


def _effective_selectors(profile_entry, suite):
    selection = profile_entry["selection"]
    return suite.get("selectors", []) if selection == "all" else selection


def _validate_profiles(data, suites_by_id, inventories):
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
        seen_suites = set()
        seen_selectors = set()
        for entry in profile["suites"]:
            _expect_keys(entry, {"suite", "selection"}, f"{context} suite entry")
            suite_id = entry["suite"]
            _expect_string(suite_id, f"{context}.suite")
            suite = suites_by_id.get(suite_id)
            if suite is None:
                raise ManifestError(f"{context} references unknown suite: {suite_id}")
            if suite_id in seen_suites:
                raise ManifestError(f"{context} has duplicate suite: {suite_id}")
            seen_suites.add(suite_id)
            selection = entry["selection"]
            if selection != "all":
                if suite["kind"] != "xcode-test":
                    raise ManifestError(
                        f"{context} package suite {suite_id} selection must be all"
                    )
                _validate_selector_list(
                    selection, f"{context} suite {suite_id} selection", inventories
                )
                for selector in selection:
                    if not _selection_is_owned(selector, suite["selectors"]):
                        raise ManifestError(
                            f"{context} selector is not owned by suite {suite_id}: {selector}"
                        )
            effective = _effective_selectors(entry, suite)
            overlap = seen_selectors.intersection(effective)
            if overlap:
                raise ManifestError(
                    f"{context} selects a selector more than once: {sorted(overlap)[0]}"
                )
            seen_selectors.update(effective)

    selected_suites = {
        entry["suite"]
        for profile in profiles.values()
        for entry in profile["suites"]
    }
    orphaned = sorted(suites_by_id.keys() - selected_suites)
    if orphaned:
        raise ManifestError(f"suite is not selected by any profile: {orphaned[0]}")


def _selected_entries(data, suites_by_id, profile_id, kind):
    profile = data["profiles"].get(profile_id)
    if profile is None:
        raise ManifestError(f"unknown profile: {profile_id}")
    if kind is not None and kind not in ALLOWED_KINDS:
        raise ManifestError(f"unknown suite kind: {kind}")
    selected = [
        (entry, suites_by_id[entry["suite"]]) for entry in profile["suites"]
    ]
    if kind is not None:
        selected = [pair for pair in selected if pair[1]["kind"] == kind]
    if not selected:
        raise ManifestError(f"profile {profile_id} has no suites of kind {kind}")
    return selected


def _validate_exhaustive_ownership(data, suites_by_id, inventories):
    exact_selectors = {}
    for suite in data["suites"]:
        if suite["kind"] != "xcode-test":
            continue
        for selector in suite["selectors"]:
            if selector in exact_selectors:
                raise ManifestError(
                    f"selector is duplicated by suites {exact_selectors[selector]} and "
                    f"{suite['id']}: {selector}"
                )
            exact_selectors[selector] = suite["id"]

    for target in data["xcode"]["test_targets"]:
        profile_id = target["exhaustive_profile"]
        if profile_id is None:
            continue
        if profile_id not in data["profiles"]:
            raise ManifestError(
                f"test target {target['module']} references unknown exhaustive profile: {profile_id}"
            )
        owner_by_class = {}
        for entry, suite in _selected_entries(
            data, suites_by_id, profile_id, "xcode-test"
        ):
            if entry["selection"] != "all":
                raise ManifestError(
                    f"exhaustive profile {profile_id} suite {suite['id']} must select all"
                )
            for selector in suite["selectors"]:
                module, class_name, method = _selector_parts(selector)
                if module != target["module"]:
                    continue
                if method is not None:
                    raise ManifestError(
                        f"exhaustive selector must own an XCTest class, not a method: {selector}"
                    )
                if class_name in owner_by_class:
                    raise ManifestError(
                        f"exhaustive XCTest class has duplicate ownership: {module}/{class_name}"
                    )
                owner_by_class[class_name] = suite["id"]
        actual = inventories[target["module"]]["runnable_classes"]
        missing = sorted(actual - owner_by_class.keys())
        extra = sorted(owner_by_class.keys() - actual)
        if missing:
            raise ManifestError(
                f"exhaustive profile {profile_id} is missing XCTest class: "
                f"{target['module']}/{missing[0]}"
            )
        if extra:
            raise ManifestError(
                f"exhaustive profile {profile_id} owns unknown XCTest class: "
                f"{target['module']}/{extra[0]}"
            )

        for other_profile, profile in data["profiles"].items():
            for entry in profile["suites"]:
                suite = suites_by_id[entry["suite"]]
                if suite["kind"] != "xcode-test":
                    continue
                for selector in _effective_selectors(entry, suite):
                    module, class_name, _ = _selector_parts(selector)
                    if module != target["module"]:
                        continue
                    owner = owner_by_class[class_name]
                    if entry["suite"] != owner:
                        raise ManifestError(
                            f"profile {other_profile} silently redefines nightly owner {owner} "
                            f"for {module}/{class_name} as {entry['suite']}"
                        )


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
    if type(data["version"]) is not int or data["version"] != 2:
        raise ManifestError("manifest.version must be integer 2")
    _validate_toolchains(data["toolchains"])
    project, inventories = _validate_xcode(data["xcode"], repo_root)

    suites = data["suites"]
    if not isinstance(suites, list) or not suites:
        raise ManifestError("suites must be a non-empty array")
    suites_by_id = {}
    xcode_roles = {}
    for suite in suites:
        _validate_suite(suite, repo_root, project, inventories)
        suite_id = suite["id"]
        if suite_id in suites_by_id:
            raise ManifestError(f"duplicate suite id: {suite_id}")
        suites_by_id[suite_id] = suite
        if suite["kind"] == "xcode-test":
            previous = xcode_roles.get(suite["role"])
            if previous is not None:
                raise ManifestError(
                    f"duplicate Xcode suite role {suite['role']}: {previous}, {suite_id}"
                )
            xcode_roles[suite["role"]] = suite_id

    _validate_profiles(data, suites_by_id, inventories)
    _validate_exhaustive_ownership(data, suites_by_id, inventories)
    return data, suites_by_id, inventories


def _matrix(profile_id, selected):
    include = []
    for _, suite in selected:
        item = {"profile": profile_id, "suite": suite["id"], "name": suite["name"]}
        if suite["kind"] == "xcode-test":
            stem = f"{profile_id}-{suite['id']}"
            item.update(
                role=suite["role"],
                scheme=suite["scheme"],
                configuration=suite["configuration"],
                result_bundle=f"build/BuildResults/{stem}.xcresult",
                build_result_bundle=f"build/BuildResults/{stem}-build.xcresult",
            )
        include.append(item)
    return {"include": include}


def _inventory_report(data, suites_by_id, inventories):
    targets = {}
    for module, inventory in sorted(inventories.items()):
        targets[module] = {
            "swift_source_files": len(inventory["swift_files"]),
            "test_source_files": len(inventory["test_source_files"]),
            "helper_only_source_files": len(inventory["helper_source_files"]),
            "xctest_helper_source_files": len(
                inventory["xctest_helper_source_files"]
            ),
            "non_xctest_helper_source_files": len(
                inventory["non_xctest_helper_source_files"]
            ),
            "runnable_test_classes": len(inventory["runnable_classes"]),
            "xctest_helper_classes": len(inventory["helper_classes"]),
            "test_methods": sum(
                len(inventory["methods"][name])
                for name in inventory["runnable_classes"]
            ),
        }
    suites = {
        suite_id: {
            "kind": suite["kind"],
            "owned_selectors": len(suite.get("selectors", [])),
        }
        for suite_id, suite in sorted(suites_by_id.items())
    }
    profiles = {}
    for profile_id in sorted(data["profiles"]):
        entries = _selected_entries(data, suites_by_id, profile_id, None)
        profiles[profile_id] = {
            "suite_processes": len(entries),
            "package_processes": sum(pair[1]["kind"] == "swift-package" for pair in entries),
            "xcode_processes": sum(pair[1]["kind"] == "xcode-test" for pair in entries),
            "effective_xcode_selectors": sum(
                len(_effective_selectors(entry, suite))
                for entry, suite in entries
                if suite["kind"] == "xcode-test"
            ),
        }
    return {"targets": targets, "suites": suites, "profiles": profiles}


def _build_parser(default_manifest, default_repo_root):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=default_manifest)
    parser.add_argument("--repo-root", type=Path, default=default_repo_root)
    commands = parser.add_subparsers(dest="command", required=True)

    commands.add_parser("validate")
    commands.add_parser("inventory")
    for command in ("list", "matrix"):
        selection = commands.add_parser(command)
        selection.add_argument("profile")
        selection.add_argument("kind", nargs="?")

    suite_field = commands.add_parser("suite-field")
    suite_field.add_argument("suite")
    suite_field.add_argument("field")
    selectors = commands.add_parser("selectors")
    selectors.add_argument("suite")
    selectors.add_argument("profile", nargs="?")
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
        data, suites_by_id, inventories = load_manifest(args.manifest.resolve(), repo_root)
        if args.command == "validate":
            counts = ", ".join(
                f"{module}: {len(inventory['runnable_classes'])} classes, "
                f"{len(inventory['helper_classes'])} XCTest helpers, "
                f"{len(inventory['helper_source_files'])} helper-only sources"
                for module, inventory in sorted(inventories.items())
            )
            print(f"CI manifest valid: {args.manifest} ({counts})")
        elif args.command == "inventory":
            print(json.dumps(_inventory_report(data, suites_by_id, inventories), indent=2))
        elif args.command in {"list", "matrix"}:
            selected = _selected_entries(data, suites_by_id, args.profile, args.kind)
            if args.command == "list":
                print("\n".join(suite["id"] for _, suite in selected))
            else:
                print(json.dumps(_matrix(args.profile, selected), separators=(",", ":")))
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
            selectors = suite["selectors"]
            if args.profile is not None:
                entries = _selected_entries(data, suites_by_id, args.profile, None)
                matching = [entry for entry, selected in entries if selected["id"] == args.suite]
                if not matching:
                    raise ManifestError(
                        f"profile {args.profile} does not select suite {args.suite}"
                    )
                selectors = _effective_selectors(matching[0], suite)
            print("\n".join(selectors))
        elif args.command == "toolchain-field":
            profile = data["profiles"].get(args.profile)
            if profile is None:
                raise ManifestError(f"unknown profile: {args.profile}")
            toolchain = data["toolchains"][profile["toolchain"]]
            if args.field not in toolchain:
                raise ManifestError(f"unknown toolchain field: {args.field}")
            print(toolchain[args.field])
        elif args.command == "xcode-field":
            if args.field not in data["xcode"] or args.field == "test_targets":
                raise ManifestError(f"unknown scalar xcode field: {args.field}")
            value = data["xcode"][args.field]
            print("YES" if value is True else "NO" if value is False else value)
    except ManifestError as error:
        print(f"manifest error: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())

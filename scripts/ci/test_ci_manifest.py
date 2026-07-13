#!/usr/bin/env python3

import copy
import importlib.util
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("ci_manifest.py")
REPO_ROOT = MODULE_PATH.parents[2]
RUNNER = REPO_ROOT / "scripts/ci/run_tests.sh"
SPEC = importlib.util.spec_from_file_location("ci_manifest", MODULE_PATH)
ci_manifest = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ci_manifest)


class ManifestTests(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.repo = Path(self.temporary_directory.name)
        (self.repo / "Packages/One").mkdir(parents=True)
        (self.repo / "Packages/One/Package.swift").write_text("// package\n")
        schemes = self.repo / "Sumi.xcodeproj/xcshareddata/xcschemes"
        schemes.mkdir(parents=True)
        (schemes / "Sumi.xcscheme").write_text("<Scheme/>\n")
        self.manifest = {
            "version": 1,
            "toolchains": {
                "production": {
                    "name": "Xcode 26.6 on macOS 26",
                    "runner": "macos-26",
                    "developer_dir": "/Applications/Xcode_26.6.app/Contents/Developer",
                    "xcode_version": "26.6",
                    "selection_note": "Pinned explicitly.",
                }
            },
            "xcode": {
                "project": "Sumi.xcodeproj",
                "destination": "platform=macOS",
                "parallel_testing_enabled": False,
            },
            "profiles": {
                "pr": {
                    "toolchain": "production",
                    "suites": ["one", "smoke"],
                }
            },
            "suites": [
                {
                    "id": "one",
                    "name": "Package One",
                    "kind": "swift-package",
                    "path": "Packages/One",
                },
                {
                    "id": "smoke",
                    "name": "Smoke",
                    "kind": "xcode-test",
                    "scheme": "Sumi",
                    "configuration": "Debug",
                    "selectors": ["SumiTests/SmokeTests/testSmoke"],
                },
            ],
        }

    def tearDown(self):
        self.temporary_directory.cleanup()

    def write_manifest(self, value=None):
        path = self.repo / "manifest.json"
        path.write_text(json.dumps(self.manifest if value is None else value))
        return path

    def load(self, value=None):
        return ci_manifest.load_manifest(self.write_manifest(value), self.repo)

    def test_valid_manifest_selects_ordered_suites_and_matrix_fields(self):
        data, suites = self.load()
        selected = ci_manifest._selected_suites(data, suites, "pr", None)
        self.assertEqual([suite["id"] for suite in selected], ["one", "smoke"])
        xcode = ci_manifest._selected_suites(data, suites, "pr", "xcode-test")
        self.assertEqual(xcode[0]["scheme"], "Sumi")

    def test_duplicate_json_key_fails_closed(self):
        path = self.repo / "manifest.json"
        path.write_text('{"version": 1, "version": 1}')
        with self.assertRaisesRegex(ci_manifest.ManifestError, "duplicate JSON key"):
            ci_manifest.load_manifest(path, self.repo)

    def test_unknown_suite_kind_fails_closed(self):
        value = copy.deepcopy(self.manifest)
        value["suites"][0]["kind"] = "mystery"
        with self.assertRaisesRegex(ci_manifest.ManifestError, "unknown kind"):
            self.load(value)

    def test_unknown_suite_entry_fails_closed(self):
        value = copy.deepcopy(self.manifest)
        value["suites"][0]["extra"] = True
        with self.assertRaisesRegex(ci_manifest.ManifestError, "unknown entries"):
            self.load(value)

    def test_missing_package_path_fails_closed(self):
        value = copy.deepcopy(self.manifest)
        value["suites"][0]["path"] = "Packages/Missing"
        with self.assertRaisesRegex(ci_manifest.ManifestError, "does not exist"):
            self.load(value)

    def test_duplicate_profile_suite_fails_closed(self):
        value = copy.deepcopy(self.manifest)
        value["profiles"]["pr"]["suites"].append("one")
        with self.assertRaisesRegex(ci_manifest.ManifestError, "duplicate suite"):
            self.load(value)

    def test_duplicate_selector_fails_closed(self):
        value = copy.deepcopy(self.manifest)
        selector = value["suites"][1]["selectors"][0]
        value["suites"][1]["selectors"].append(selector)
        with self.assertRaisesRegex(ci_manifest.ManifestError, "duplicate selector"):
            self.load(value)


class RunnerWorkingDirectoryTests(unittest.TestCase):
    def test_foreign_cwd_queries_and_xcode_command_use_repository_root(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary_path = Path(temporary_directory)
            foreign_cwd = temporary_path / "foreign"
            stub_bin = temporary_path / "bin"
            foreign_cwd.mkdir()
            stub_bin.mkdir()

            command_log = temporary_path / "xcodebuild.log"
            fake_xcodebuild = stub_bin / "xcodebuild"
            fake_xcodebuild.write_text(
                "#!/usr/bin/env bash\n"
                "set -euo pipefail\n"
                "{\n"
                "  printf 'cwd=%s\\n' \"$PWD\"\n"
                "  printf 'arg=%s\\n' \"$@\"\n"
                "} > \"$SUMI_TEST_XCODEBUILD_LOG\"\n"
            )
            fake_xcodebuild.chmod(0o755)

            environment = os.environ.copy()
            environment["PATH"] = f"{stub_bin}{os.pathsep}{environment['PATH']}"
            environment["SUMI_TEST_XCODEBUILD_LOG"] = str(command_log)
            environment["SUMI_CI_DERIVED_DATA"] = str(temporary_path / "derived-data")
            environment["SUMI_CI_RESULT_BUNDLE"] = str(temporary_path / "result.xcresult")

            validation = subprocess.run(
                [RUNNER, "validate"],
                cwd=foreign_cwd,
                env=environment,
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertIn("CI manifest valid", validation.stdout)
            project = subprocess.run(
                [RUNNER, "xcode-field", "project"],
                cwd=foreign_cwd,
                env=environment,
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertEqual(project.stdout.strip(), "Sumi.xcodeproj")

            subprocess.run(
                [RUNNER, "run", "pr-smoke"],
                cwd=foreign_cwd,
                env=environment,
                check=True,
                capture_output=True,
                text=True,
            )
            log_lines = command_log.read_text().splitlines()
            self.assertEqual(log_lines[0], f"cwd={REPO_ROOT}")
            arguments = [line.removeprefix("arg=") for line in log_lines[1:]]
            project_index = arguments.index("-project")
            self.assertEqual(arguments[project_index + 1], "Sumi.xcodeproj")
            self.assertIn(
                "-only-testing:SumiTests/DeferredProtectedCommandSchedulerTests",
                arguments,
            )


if __name__ == "__main__":
    unittest.main()

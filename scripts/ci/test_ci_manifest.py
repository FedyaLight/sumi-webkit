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
MANIFEST = REPO_ROOT / "scripts/ci/test-manifest.json"
PR_WORKFLOW = REPO_ROOT / ".github/workflows/sumi-ci.yml"
NIGHTLY_WORKFLOW = REPO_ROOT / ".github/workflows/sumi-nightly.yml"
ARCHITECTURE_WORKFLOW = REPO_ROOT / ".github/workflows/architecture-guardrails.yml"
SPEC = importlib.util.spec_from_file_location("ci_manifest", MODULE_PATH)
ci_manifest = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ci_manifest)


class ManifestTests(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.repo = Path(self.temporary_directory.name)
        (self.repo / "Packages/One").mkdir(parents=True)
        (self.repo / "Packages/One/Package.swift").write_text("// package\n")
        project = self.repo / "Sumi.xcodeproj"
        schemes = project / "xcshareddata/xcschemes"
        schemes.mkdir(parents=True)
        (schemes / "Sumi.xcscheme").write_text("<Scheme/>\n")
        (self.repo / "SumiTests").mkdir()
        (self.repo / "SumiTests/PolicyTests.swift").write_text(
            "import XCTest\n"
            "final class PolicyTests: XCTestCase {\n"
            "    func testPolicy() {}\n"
            "}\n"
        )
        (self.repo / "SumiTests/ServiceTests.swift").write_text(
            "import XCTest\n"
            "class SharedTestCase: XCTestCase {}\n"
            "final class ServiceTests: SharedTestCase {\n"
            "    func testService() {}\n"
            "    static func testStaticFixture() {}\n"
            "    class func testClassFixture() {}\n"
            "    private func testPrivateFixture() {}\n"
            "    fileprivate func testFilePrivateFixture() {}\n"
            "}\n"
        )
        (self.repo / "SumiTests/ServiceExtensionTests.swift").write_text(
            "extension ServiceTests {\n"
            "    @MainActor\n"
            "    public func testExtendedService() async throws {}\n"
            "}\n"
        )
        (self.repo / "SumiTests/TestSupport.swift").write_text(
            "final class TestSupport {}\n"
        )
        (project / "project.pbxproj").write_text(
            "{\n"
            "  objects = {\n"
            "    A111 /* SumiTests */ = {\n"
            "      isa = PBXFileSystemSynchronizedRootGroup;\n"
            "      path = SumiTests;\n"
            "    };\n"
            "    B111 /* SumiTests */ = {\n"
            "      isa = PBXNativeTarget;\n"
            "      fileSystemSynchronizedGroups = (\n"
            "        A111 /* SumiTests */,\n"
            "      );\n"
            "      name = SumiTests;\n"
            "    };\n"
            "  };\n"
            "}\n"
        )
        self.manifest = {
            "version": 2,
            "toolchains": {
                "production": {
                    "name": "Xcode 27 preview",
                    "runner": "xcode-27",
                    "developer_dir": "/Applications/Xcode_27.0.app/Contents/Developer",
                    "xcode_version": "27.0",
                    "selection_note": "Pinned explicitly.",
                }
            },
            "xcode": {
                "project": "Sumi.xcodeproj",
                "destination": "platform=macOS",
                "parallel_testing_enabled": False,
                "test_targets": [
                    {
                        "module": "SumiTests",
                        "target": "SumiTests",
                        "source_path": "SumiTests",
                        "exhaustive_profile": "nightly",
                    }
                ],
            },
            "profiles": {
                "pr": {
                    "toolchain": "production",
                    "suites": [
                        {"suite": "one", "selection": "all"},
                        {
                            "suite": "policy",
                            "selection": ["SumiTests/PolicyTests/testPolicy"],
                        },
                        {
                            "suite": "services",
                            "selection": ["SumiTests/ServiceTests/testService"],
                        },
                    ],
                },
                "nightly": {
                    "toolchain": "production",
                    "suites": [
                        {"suite": "one", "selection": "all"},
                        {"suite": "policy", "selection": "all"},
                        {"suite": "services", "selection": "all"},
                    ],
                },
            },
            "suites": [
                {
                    "id": "one",
                    "name": "Package One",
                    "kind": "swift-package",
                    "path": "Packages/One",
                },
                {
                    "id": "policy",
                    "name": "Policy",
                    "kind": "xcode-test",
                    "scheme": "Sumi",
                    "configuration": "Debug",
                    "role": "pure-policy",
                    "selectors": ["SumiTests/PolicyTests"],
                },
                {
                    "id": "services",
                    "name": "Services",
                    "kind": "xcode-test",
                    "scheme": "Sumi",
                    "configuration": "Debug",
                    "role": "ui-free-app-services",
                    "selectors": ["SumiTests/ServiceTests"],
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

    def test_valid_manifest_has_ordered_matrices_unique_paths_and_helper_inventory(self):
        data, suites, inventories = self.load()
        selected = ci_manifest._selected_entries(data, suites, "pr", None)
        self.assertEqual(
            [suite["id"] for _, suite in selected], ["one", "policy", "services"]
        )
        matrix = ci_manifest._matrix(
            "nightly",
            ci_manifest._selected_entries(data, suites, "nightly", "xcode-test"),
        )["include"]
        self.assertEqual(len({item["result_bundle"] for item in matrix}), 2)
        self.assertEqual(len({item["build_result_bundle"] for item in matrix}), 2)
        inventory = inventories["SumiTests"]
        self.assertEqual(inventory["runnable_classes"], {"PolicyTests", "ServiceTests"})
        self.assertEqual(inventory["helper_classes"], {"SharedTestCase"})
        self.assertEqual(
            inventory["methods"]["ServiceTests"],
            {"testService", "testExtendedService"},
        )
        self.assertIn(self.repo / "SumiTests/TestSupport.swift", inventory["helper_source_files"])

    def test_duplicate_json_key_fails_closed(self):
        path = self.repo / "manifest.json"
        path.write_text('{"version": 2, "version": 2}')
        with self.assertRaisesRegex(ci_manifest.ManifestError, "duplicate JSON key"):
            ci_manifest.load_manifest(path, self.repo)

    def test_unknown_suite_kind_fails_closed(self):
        value = copy.deepcopy(self.manifest)
        value["suites"][0]["kind"] = "mystery"
        with self.assertRaisesRegex(ci_manifest.ManifestError, "unknown kind"):
            self.load(value)

    def test_unrecognized_runner_label_fails_closed(self):
        value = copy.deepcopy(self.manifest)
        value["toolchains"]["production"]["runner"] = "latest-macos"
        with self.assertRaisesRegex(ci_manifest.ManifestError, "explicit GitHub macOS or Xcode"):
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
        value["profiles"]["pr"]["suites"].append(
            {"suite": "one", "selection": "all"}
        )
        with self.assertRaisesRegex(ci_manifest.ManifestError, "duplicate suite"):
            self.load(value)

    def test_orphan_suite_fails_closed(self):
        value = copy.deepcopy(self.manifest)
        for profile in value["profiles"].values():
            profile["suites"] = [
                entry for entry in profile["suites"] if entry["suite"] != "one"
            ]
        with self.assertRaisesRegex(ci_manifest.ManifestError, "not selected by any profile"):
            self.load(value)

    def test_duplicate_nightly_class_ownership_fails_closed(self):
        value = copy.deepcopy(self.manifest)
        value["suites"][2]["selectors"].append("SumiTests/PolicyTests")
        value["suites"][2]["selectors"].sort()
        with self.assertRaisesRegex(ci_manifest.ManifestError, "more than once"):
            self.load(value)

    def test_missing_nightly_class_fails_closed(self):
        value = copy.deepcopy(self.manifest)
        value["profiles"]["nightly"]["suites"] = [
            entry
            for entry in value["profiles"]["nightly"]["suites"]
            if entry["suite"] != "services"
        ]
        with self.assertRaisesRegex(ci_manifest.ManifestError, "missing XCTest class"):
            self.load(value)

    def test_missing_class_selector_fails_closed(self):
        value = copy.deepcopy(self.manifest)
        value["suites"][1]["selectors"] = ["SumiTests/MissingTests"]
        with self.assertRaisesRegex(ci_manifest.ManifestError, "no runnable XCTest class"):
            self.load(value)

    def test_missing_method_selector_fails_closed(self):
        value = copy.deepcopy(self.manifest)
        value["profiles"]["pr"]["suites"][1]["selection"] = [
            "SumiTests/PolicyTests/testMissing"
        ]
        with self.assertRaisesRegex(ci_manifest.ManifestError, "no XCTest method"):
            self.load(value)

    def test_helper_xctest_class_cannot_be_selected(self):
        value = copy.deepcopy(self.manifest)
        value["suites"][1]["selectors"] = ["SumiTests/SharedTestCase"]
        with self.assertRaisesRegex(ci_manifest.ManifestError, "no runnable XCTest class"):
            self.load(value)

    def test_profile_subset_cannot_move_a_class_to_another_shard(self):
        value = copy.deepcopy(self.manifest)
        value["profiles"]["pr"]["suites"][2]["selection"] = [
            "SumiTests/PolicyTests/testPolicy"
        ]
        with self.assertRaisesRegex(ci_manifest.ManifestError, "not owned by suite"):
            self.load(value)

    def test_unsorted_selectors_fail_closed(self):
        value = copy.deepcopy(self.manifest)
        value["suites"][1]["selectors"] = [
            "SumiTests/ServiceTests",
            "SumiTests/PolicyTests",
        ]
        with self.assertRaisesRegex(ci_manifest.ManifestError, "must be sorted"):
            self.load(value)

    def test_parallel_testing_cannot_be_enabled(self):
        value = copy.deepcopy(self.manifest)
        value["xcode"]["parallel_testing_enabled"] = True
        with self.assertRaisesRegex(ci_manifest.ManifestError, "must remain false"):
            self.load(value)

    def test_source_path_must_have_xcode_target_membership(self):
        project = self.repo / "Sumi.xcodeproj/project.pbxproj"
        project.write_text(project.read_text().replace("A111 /* SumiTests */,", ""))
        with self.assertRaisesRegex(ci_manifest.ManifestError, "does not own"):
            self.load()


class RepositoryContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data, cls.suites, cls.inventories = ci_manifest.load_manifest(
            MANIFEST, REPO_ROOT
        )

    def test_repository_ownership_matches_discovery_without_count_freezes(self):
        unit = self.inventories["SumiTests"]
        role_suites = {
            "pure-policy": "app-pure-policy",
            "persistence-migration": "app-persistence-migration",
            "ui-free-app-services": "app-ui-free-services",
            "webkit-heavy-app": "app-webkit-heavy",
        }
        self.assertEqual(
            {self.suites[suite_id]["role"] for suite_id in role_suites.values()},
            set(role_suites),
        )
        owned_classes = [
            selector.removeprefix("SumiTests/")
            for suite_id in role_suites.values()
            for selector in self.suites[suite_id]["selectors"]
        ]
        self.assertEqual(len(owned_classes), len(set(owned_classes)))
        self.assertEqual(set(owned_classes), unit["runnable_classes"])
        self.assertTrue(unit["helper_classes"])
        self.assertTrue(unit["helper_source_files"])
        self.assertTrue(unit["xctest_helper_source_files"])
        self.assertTrue(unit["non_xctest_helper_source_files"])
        self.assertTrue(unit["helper_classes"].isdisjoint(owned_classes))

    def test_matrices_have_expected_processes_and_unique_result_paths(self):
        pr = ci_manifest._matrix(
            "pr", ci_manifest._selected_entries(self.data, self.suites, "pr", "xcode-test")
        )["include"]
        nightly = ci_manifest._matrix(
            "nightly",
            ci_manifest._selected_entries(
                self.data, self.suites, "nightly", "xcode-test"
            ),
        )["include"]
        self.assertEqual(len(pr), 4)
        self.assertEqual(len(nightly), 5)
        self.assertEqual(
            sum(
                len(ci_manifest._effective_selectors(entry, suite))
                for entry, suite in ci_manifest._selected_entries(
                    self.data, self.suites, "pr", "xcode-test"
                )
            ),
            23,
        )
        for matrix in (pr, nightly):
            self.assertEqual(len({item["role"] for item in matrix}), len(matrix))
            self.assertEqual(
                len({item["result_bundle"] for item in matrix}), len(matrix)
            )
            self.assertEqual(
                len({item["build_result_bundle"] for item in matrix}), len(matrix)
            )

    def test_every_suite_is_reachable_and_performance_is_an_owned_profile_subset(self):
        selected_suites = {
            entry["suite"]
            for profile in self.data["profiles"].values()
            for entry in profile["suites"]
        }
        self.assertEqual(selected_suites, set(self.suites))
        performance = self.data["profiles"]["performance"]["suites"]
        self.assertEqual(
            [entry["suite"] for entry in performance],
            ["app-pure-policy", "app-webkit-heavy"],
        )
        self.assertTrue(all(entry["selection"] for entry in performance))
        for entry in performance:
            owned = self.suites[entry["suite"]]["selectors"]
            self.assertTrue(
                all(
                    ci_manifest._selection_is_owned(selector, owned)
                    for selector in entry["selection"]
                )
            )

    def test_workflows_derive_matrices_and_enforce_parallel_job_policy(self):
        for workflow, profile in ((PR_WORKFLOW, "pr"), (NIGHTLY_WORKFLOW, "nightly")):
            text = workflow.read_text()
            self.assertIn("scripts/ci/preflight.sh fast", text)
            self.assertIn(f"matrix {profile} swift-package", text)
            self.assertIn(f"matrix {profile} xcode-test", text)
            self.assertIn(f"run {profile} \"${{{{ matrix.suite }}}}\"", text)
            self.assertGreaterEqual(text.count("fail-fast: false"), 2)
            self.assertIn("max-parallel: 4", text)
            self.assertNotIn("max-parallel: 1", text)
            self.assertNotIn("-only-testing:", text)
            self.assertNotIn("xcodebuild", text)
            self.assertIn("matrix.build_result_bundle", text)
            self.assertIn("matrix.result_bundle", text)
            self.assertNotIn("app-pure-policy", text)
            app_job = text.split("  app-tests:\n", 1)[1]
            self.assertTrue(app_job.startswith("    name:"))
            self.assertIn("    needs: manifest\n", app_job)
            self.assertNotIn("architecture-packages", app_job)
        subprocess.run(
            [
                "ruby",
                "-e",
                'require "yaml"; ARGV.each { |path| YAML.parse_file(path) }',
                PR_WORKFLOW,
                NIGHTLY_WORKFLOW,
            ],
            check=True,
        )

        architecture_text = ARCHITECTURE_WORKFLOW.read_text()
        self.assertIn("scripts/ci/preflight.sh portable", architecture_text)
        self.assertNotIn("run: scripts/check_architecture_guardrails.sh", architecture_text)

    def test_item_49_baseline_remains_attributable_to_webkit_shard(self):
        self.assertIn(
            "SumiTests/SafariExtensionScriptingRuntimeTests",
            self.suites["app-webkit-heavy"]["selectors"],
        )


class RunnerWorkingDirectoryTests(unittest.TestCase):
    def test_foreign_cwd_uses_two_phase_xcode_boundary_and_profile_selectors(self):
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
                "  printf 'invocation\\n'\n"
                "  printf 'cwd=%s\\n' \"$PWD\"\n"
                "  printf 'arg=%s\\n' \"$@\"\n"
                "} >> \"$SUMI_TEST_XCODEBUILD_LOG\"\n"
            )
            fake_xcodebuild.chmod(0o755)

            environment = os.environ.copy()
            environment["PATH"] = f"{stub_bin}{os.pathsep}{environment['PATH']}"
            environment["SUMI_TEST_XCODEBUILD_LOG"] = str(command_log)
            environment["SUMI_CI_DERIVED_DATA"] = str(temporary_path / "derived-data")
            environment["SUMI_CI_BUILD_RESULT_BUNDLE"] = str(
                temporary_path / "build.xcresult"
            )
            environment["SUMI_CI_RESULT_BUNDLE"] = str(
                temporary_path / "test.xcresult"
            )
            localization_catalog = temporary_path / "Localizable.xcstrings"
            localization_catalog.write_text(
                '{"sourceLanguage":"en","strings":{},"version":"1.0"}\n'
            )
            environment["SUMI_CI_LOCALIZATION_CATALOG"] = str(localization_catalog)

            validation = subprocess.run(
                [RUNNER, "validate"],
                cwd=foreign_cwd,
                env=environment,
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertIn("CI manifest valid", validation.stdout)
            subprocess.run(
                [RUNNER, "run", "pr", "app-pure-policy"],
                cwd=foreign_cwd,
                env=environment,
                check=True,
                capture_output=True,
                text=True,
            )
            invocations = command_log.read_text().split("invocation\n")[1:]
            self.assertEqual(len(invocations), 2)
            build, test = invocations
            self.assertIn(f"cwd={REPO_ROOT}\n", build)
            self.assertIn(f"cwd={REPO_ROOT}\n", test)
            self.assertIn("arg=build-for-testing\n", build)
            self.assertIn("arg=test-without-building\n", test)
            self.assertNotIn("arg=-only-testing:", build)
            self.assertIn(
                "arg=-only-testing:SumiTests/RuntimeStateCoalescerTests\n", test
            )
            for invocation in invocations:
                self.assertIn("arg=-parallel-testing-enabled\narg=NO\n", invocation)
            self.assertIn(f"arg={temporary_path / 'build.xcresult'}\n", build)
            self.assertIn(f"arg={temporary_path / 'test.xcresult'}\n", test)

    def test_xcode_suite_fails_when_build_changes_localization_catalog(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            temporary_path = Path(temporary_directory)
            stub_bin = temporary_path / "bin"
            stub_bin.mkdir()

            fake_xcodebuild = stub_bin / "xcodebuild"
            fake_xcodebuild.write_text(
                "#!/usr/bin/env bash\n"
                "set -euo pipefail\n"
                "if [[ \" $* \" == *\" build-for-testing \"* ]]; then\n"
                "  printf '\\n' >> \"$SUMI_CI_LOCALIZATION_CATALOG\"\n"
                "fi\n"
            )
            fake_xcodebuild.chmod(0o755)

            localization_catalog = temporary_path / "Localizable.xcstrings"
            localization_catalog.write_text(
                '{"sourceLanguage":"en","strings":{},"version":"1.0"}\n'
            )
            environment = os.environ.copy()
            environment["PATH"] = f"{stub_bin}{os.pathsep}{environment['PATH']}"
            environment["SUMI_CI_LOCALIZATION_CATALOG"] = str(localization_catalog)
            environment["SUMI_CI_DERIVED_DATA"] = str(temporary_path / "derived-data")
            environment["SUMI_CI_BUILD_RESULT_BUNDLE"] = str(
                temporary_path / "build.xcresult"
            )
            environment["SUMI_CI_RESULT_BUNDLE"] = str(
                temporary_path / "test.xcresult"
            )

            result = subprocess.run(
                [RUNNER, "run", "pr", "app-pure-policy"],
                env=environment,
                capture_output=True,
                text=True,
            )

            self.assertEqual(result.returncode, 1)
            self.assertIn(
                "Xcode localization extraction changed Localizable.xcstrings",
                result.stderr,
            )


if __name__ == "__main__":
    unittest.main()

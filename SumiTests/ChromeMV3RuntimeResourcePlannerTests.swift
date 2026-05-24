import Foundation
import XCTest

@testable import Sumi

final class ChromeMV3RuntimeResourcePlannerTests: XCTestCase {
    func testPlannerSelectsServiceWorkerWrapperForBackgroundServiceWorker() throws {
        let fixture = try plan(for: [
            "manifest_version": 3,
            "name": "Service Worker",
            "version": "1.0",
            "background": [
                "service_worker": "background.js",
            ],
        ])

        XCTAssertTrue(
            fixture.plan.requires(.serviceWorkerWrapperClassic)
        )
        XCTAssertTrue(
            fixture.plan.requires(.chromeShimServiceWorker)
        )
        XCTAssertTrue(
            fixture.plan.requires(.chromeShimCommon)
        )
        XCTAssertTrue(fixture.plan.manifestRewriteRequiredLater)
        XCTAssertFalse(fixture.plan.runtimeLoadable)
        XCTAssertFalse(fixture.plan.executableRuntimeFilesWritten)

        let wrapper = try requirement(
            .serviceWorkerWrapperClassic,
            in: fixture.plan
        )
        XCTAssertEqual(wrapper.sourceAPIs, [.runtime])
        XCTAssertEqual(wrapper.sourceManifestFields, ["background.service_worker"])
        XCTAssertTrue(wrapper.inert)
        XCTAssertTrue(wrapper.manifestRewriteRequiredLater)
        XCTAssertTrue(wrapper.fixtureVerificationRequiredLater)
    }

    func testPlannerSelectsModuleServiceWorkerWrapperForModuleBackground() throws {
        let fixture = try plan(for: [
            "manifest_version": 3,
            "name": "Module Service Worker",
            "version": "1.0",
            "background": [
                "service_worker": "background.js",
                "type": "module",
            ],
        ])

        XCTAssertTrue(fixture.plan.requires(.serviceWorkerWrapperModule))
        XCTAssertFalse(fixture.plan.requires(.serviceWorkerWrapperClassic))
    }

    func testPlannerSelectsContentShimForContentScripts() throws {
        let fixture = try plan(for: [
            "manifest_version": 3,
            "name": "Content Scripts",
            "version": "1.0",
            "content_scripts": [
                [
                    "matches": ["https://example.com/*"],
                    "js": ["content.js"],
                ],
            ],
        ])

        let contentShim = try requirement(
            .chromeShimContentScript,
            in: fixture.plan
        )
        XCTAssertEqual(contentShim.sourceAPIs, [.runtime, .scripting])
        XCTAssertEqual(contentShim.sourceManifestFields, ["content_scripts"])
        XCTAssertTrue(contentShim.inert)
        XCTAssertTrue(contentShim.manifestRewriteRequiredLater)
        XCTAssertTrue(contentShim.fixtureVerificationRequiredLater)
    }

    func testPlannerSelectsExtensionPageShimForActionPopupAndOptionsPage() throws {
        let fixture = try plan(for: [
            "manifest_version": 3,
            "name": "Extension Pages",
            "version": "1.0",
            "action": [
                "default_popup": "popup.html",
            ],
            "options_ui": [
                "page": "options.html",
                "open_in_tab": true,
            ],
        ])

        let pageShim = try requirement(
            .chromeShimExtensionPage,
            in: fixture.plan
        )
        XCTAssertEqual(pageShim.sourceAPIs, [.action, .runtime])
        XCTAssertEqual(
            pageShim.sourceManifestFields,
            ["action.default_popup", "options_ui.page"]
        )
        XCTAssertTrue(pageShim.inert)
        XCTAssertTrue(pageShim.manifestRewriteRequiredLater)
        XCTAssertTrue(pageShim.fixtureVerificationRequiredLater)
    }

    func testPlannerMarksNativeMessagingHostBridgeAsInertAndDeferred() throws {
        let fixture = try plan(for: [
            "manifest_version": 3,
            "name": "Native Messaging",
            "version": "1.0",
            "background": [
                "service_worker": "background.js",
            ],
            "permissions": [
                "nativeMessaging",
            ],
        ])

        let bridge = try requirement(.hostBridgeStub, in: fixture.plan)
        XCTAssertEqual(bridge.sourceAPIs, [.nativeMessaging])
        XCTAssertEqual(bridge.sourceManifestFields, ["permissions.nativeMessaging"])
        XCTAssertTrue(bridge.inert)
        XCTAssertFalse(bridge.manifestRewriteRequiredLater)
        XCTAssertTrue(bridge.fixtureVerificationRequiredLater)

        let deferred = try XCTUnwrap(
            fixture.plan.deferredCapabilityPlans.first { $0.api == .nativeMessaging }
        )
        XCTAssertFalse(deferred.nativeHostPlanningOnly)
        XCTAssertEqual(deferred.runtimeTemplateModuleNames, [.hostBridgeStub])
        XCTAssertTrue(deferred.fixtureVerificationRequiredLater)
        XCTAssertFalse(fixture.plan.runtimeLoadable)
    }

    func testSidePanelOffscreenAndIdentityRemainDeferredPlanningOnly() throws {
        let fixture = try plan(for: [
            "manifest_version": 3,
            "name": "Deferred APIs",
            "version": "1.0",
            "permissions": [
                "identity",
                "offscreen",
                "sidePanel",
            ],
            "side_panel": [
                "default_path": "sidepanel.html",
            ],
        ])

        XCTAssertFalse(fixture.plan.requires(.chromeShimExtensionPage))
        XCTAssertFalse(fixture.plan.requires(.hostBridgeStub))
        XCTAssertFalse(fixture.plan.requires(.chromeShimContentScript))
        XCTAssertFalse(fixture.plan.requires(.chromeShimServiceWorker))
        XCTAssertFalse(fixture.plan.requires(.serviceWorkerWrapperClassic))
        XCTAssertFalse(fixture.plan.requires(.serviceWorkerWrapperModule))

        XCTAssertEqual(
            fixture.plan.deferredCapabilityPlans.map(\.api),
            [.identity, .offscreen, .sidePanel]
        )
        for deferred in fixture.plan.deferredCapabilityPlans {
            XCTAssertTrue(deferred.nativeHostPlanningOnly)
            XCTAssertEqual(deferred.runtimeTemplateModuleNames, [])
        }
    }

    func testTemplateCatalogIsDeterministicAndForbiddenRuntimeScanSafe() throws {
        let templates = ChromeMV3RuntimeResourceTemplateCatalog.allTemplates
        XCTAssertEqual(
            templates.map(\.moduleName),
            ChromeMV3RuntimeTemplateModuleName.allCases.sorted()
        )
        XCTAssertEqual(Set(templates.map(\.fileName)).count, templates.count)
        XCTAssertTrue(templates.allSatisfy(\.inert))
        XCTAssertTrue(templates.allSatisfy { $0.runtimeLoadable == false })

        let forbiddenFragments = [
            "set" + "Timeout",
            "set" + "Interval",
            "connect" + "Native",
            "send" + "NativeMessage",
            "add" + "EventListener(",
            "chrome.runtime." + "onMessage",
            "browser.runtime." + "onMessage",
            "document.create" + "Element(",
            "append" + "Child(",
        ]

        for template in templates {
            XCTAssertTrue(
                template.outputRelativePath.hasPrefix(
                    ChromeMV3RuntimeResourceTemplateCatalog.runtimeDirectoryName
                )
            )
            XCTAssertTrue(template.contents.contains("notWired: true"))
            XCTAssertTrue(template.contents.contains("runtimeLoadable: false"))
            for forbidden in forbiddenFragments {
                XCTAssertFalse(
                    template.contents.contains(forbidden),
                    "\(template.fileName) contains \(forbidden)"
                )
            }
        }
    }

    func testPlannerSourceDoesNotConstructRuntimeObjects() throws {
        let source = try String(
            contentsOf: projectRoot()
                .appendingPathComponent(
                    "Sumi/Models/Extension/ChromeMV3/ChromeMV3RuntimeResources.swift"
                ),
            encoding: .utf8
        )
        for forbidden in [
            "import " + "WebKit",
            "WKWebExtension" + "Controller(",
            "WKWebExtension" + "Context(",
            "WK" + "WebExtension(",
            "webExtension" + "Controller =",
            "add" + "UserScript",
            "connect" + "Native",
            "NativeMessaging" + "Handler(",
        ] {
            XCTAssertFalse(source.contains(forbidden), forbidden)
        }
    }

    private struct PlannerFixture {
        var manifest: ChromeMV3Manifest
        var report: ChromeMV3InstallReport
        var plan: ChromeMV3RuntimeResourcePlan
    }

    private func plan(for manifestObject: [String: Any]) throws -> PlannerFixture {
        let manifest = try ChromeMV3ManifestValidator.validateJSONObject(
            manifestObject
        )
        let report = ChromeMV3InstallReporter.report(for: manifest)
        let plan = ChromeMV3RuntimeResourcePlanner.plan(
            manifest: manifest,
            installReport: report
        )
        return PlannerFixture(manifest: manifest, report: report, plan: plan)
    }

    private func requirement(
        _ moduleName: ChromeMV3RuntimeTemplateModuleName,
        in plan: ChromeMV3RuntimeResourcePlan
    ) throws -> ChromeMV3RuntimeTemplateRequirement {
        try XCTUnwrap(
            plan.templateRequirements.first {
                $0.templateModuleName == moduleName
            }
        )
    }

    private func projectRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

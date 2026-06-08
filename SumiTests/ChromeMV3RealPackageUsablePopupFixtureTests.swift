import AppKit
import Foundation
import SwiftData
import XCTest

@testable import Sumi

final class ChromeMV3RealPackageUsablePopupFixtureTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    @MainActor
    func testRealPackageUsablePopupReachesUsableUIThroughLocalUnpackedFlow()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Real-package usable popup fixture requires macOS 15.5.")
        }
        let packageRoot = try XCTUnwrap(
            ChromeMV3RealPackageUsablePopupFixtureLocation.packageRoot(),
            "Sumi usable popup fixture package is unavailable."
        )

        let root = try makeTemporaryDirectory()
        let profileID = UUID()
        let module = try makeModule(
            enabled: true,
            includesModelContext: true,
            useFileBackedPopupHost: true
        )
        let install = module.chromeMV3InstallUnpackedThroughManager(
            rootURL: root,
            sourceURL: packageRoot,
            profileID: profileID.uuidString,
            enableInternal: true
        )
        let record = try XCTUnwrap(install.lifecycleOperationResult?.record)
        XCTAssertTrue(install.succeeded, install.diagnostics.joined(separator: "\n"))
        _ = await waitForEnabledExtension(
            in: module,
            extensionId: record.extensionID
        )

        let stage = try ChromeMV3OriginalBundleStore(
            rootURL: root,
            now: { Date(timeIntervalSince1970: 601) }
        ).stageUnpackedDirectory(at: packageRoot)
        let generated = try ChromeMV3GeneratedBundleWriter(rootURL: root)
            .writeGeneratedBundle(
                originalBundleRecord: stage.originalBundleRecord,
                manifestSnapshot: stage.manifestSnapshot,
                planningRecord: stage.generatedBundlePlan
            )
        let generatedPopupURL = generated.generatedBundleRootURL
            .appendingPathComponent("popup.html")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: generatedPopupURL.path),
            "Generated package should preserve action.default_popup popup.html."
        )

        let currentPage = syntheticPageContext(profileID: record.profileID)
        let section = try XCTUnwrap(
            module.chromeMV3URLHubSectionViewModelIfEnabled(
                rootURL: root,
                currentPage: currentPage
            )
        )
        let hubRow = try XCTUnwrap(
            section.rows.first { $0.extensionID == record.extensionID }
        )
        XCTAssertTrue(hubRow.installed)
        XCTAssertTrue(hubRow.enabled)
        XCTAssertTrue(hubRow.generatedBundleAvailable)
        XCTAssertEqual(hubRow.sourceType, .localUnpacked)

        let currentTab = Tab(url: URL(string: "https://example.com/login")!)
        currentTab.profileId = profileID
        let result = await module.openActionPopupFromURLHub(
            extensionId: record.extensionID,
            currentTab: currentTab
        )

        defer {
            _ = module.chromeMV3ClosePopupOptionsThroughManager(
                profileID: record.profileID,
                extensionID: record.extensionID
            )
        }

        XCTAssertTrue(result.opened, result.message ?? "popup blocked")
        XCTAssertNil(result.blocker)
        XCTAssertTrue(
            result.sanitizedBridgeSnapshotDiagnostics.contains {
                $0.contains("selectedPopupPath=controlledCompatibilityActionPopup")
            },
            result.sanitizedBridgeSnapshotDiagnostics.joined(separator: " | ")
        )

        let domProbe = try await waitForBaselineDOMProbe(
            module: module,
            profileID: record.profileID,
            extensionID: record.extensionID
        )
        let snapshot = try await waitForPopupBridgeSnapshot(
            module: module,
            profileID: record.profileID,
            extensionID: record.extensionID
        )
        let outcome = ChromeMV3ControlledPopupBaselineClassifier
            .classifyRealPackageUsablePopup(
                opened: result.opened,
                preflightBlocker: result.blocker,
                domProbe: domProbe,
                snapshot: snapshot
            )

        XCTAssertEqual(domProbe.outcome, "ok")
        XCTAssertTrue(domProbe.coarseUsable)
        XCTAssertGreaterThan(domProbe.visibleTextLength, 0)
        XCTAssertGreaterThan(domProbe.controlCount, 0)
        XCTAssertTrue(
            snapshot.jsDebugRouteEvents.contains {
                $0.apiName == "runtime.getManifest"
                    && $0.resultClassifier == "manifestReturned"
            }
        )
        XCTAssertTrue(
            snapshot.callRecords.contains {
                $0.namespace == "storage" && $0.methodName == "local.set"
                    && $0.succeeded
            }
        )
        XCTAssertTrue(
            snapshot.callRecords.contains {
                $0.namespace == "storage" && $0.methodName == "local.get"
                    && $0.succeeded
            }
        )
        XCTAssertTrue(
            snapshot.sanitizedBridgeRouteRecords.contains {
                $0.apiName == "runtime.sendMessage"
            }
        )
        XCTAssertTrue(
            snapshot.sanitizedBridgeRouteRecords.contains {
                $0.apiName == "runtime.connect"
            }
        )
        XCTAssertTrue(
            snapshot.sanitizedBridgeRouteRecords.contains {
                $0.apiName == "tabs.query"
            }
        )
        XCTAssertTrue(
            snapshot.callRecords.contains {
                $0.namespace == "permissions" && $0.methodName == "contains"
            }
        )
        XCTAssertTrue(
            snapshot.callRecords.contains {
                $0.namespace == "permissions" && $0.methodName == "getAll"
            }
        )
        XCTAssertEqual(outcome, .usableUI)
    }

    // MARK: - Harness

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        temporaryDirectories.append(directory)
        return directory
    }

    @MainActor
    private func makeModule(
        enabled: Bool,
        includesModelContext: Bool,
        useFileBackedPopupHost: Bool
    ) throws -> SumiExtensionsModule {
        let harness = TestDefaultsHarness()
        let registry = SumiModuleRegistry(
            settingsStore:
                SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.setEnabled(enabled, for: .extensions)
        let loadingMode: ChromeMV3ProductPopupOptionsLoadingMode =
            .controlledCompatibilityDefault
        _ = useFileBackedPopupHost
        let popupFactory: @MainActor () -> ChromeMV3PopupOptionsWebViewFactory =
            {
                ChromeMV3ProductPopupOptionsWKWebViewFactory(
                    loadingMode: loadingMode
                )
            }
        guard includesModelContext else {
            return SumiExtensionsModule(
                moduleRegistry: registry,
                chromeMV3PopupOptionsWebViewFactory: popupFactory
            )
        }
        let container = try ModelContainer(
            for: Schema([ExtensionEntity.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return SumiExtensionsModule(
            moduleRegistry: registry,
            context: ModelContext(container),
            chromeMV3PopupOptionsWebViewFactory: popupFactory
        )
    }

    @MainActor
    private func waitForEnabledExtension(
        in module: SumiExtensionsModule,
        extensionId: String
    ) async -> InstalledExtension? {
        for _ in 0..<20 {
            if let installedExtension = module.surfaceStore.enabledExtensions.first(
                where: { $0.id == extensionId }
            ) {
                return installedExtension
            }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return module.surfaceStore.enabledExtensions.first {
            $0.id == extensionId
        }
    }

    @MainActor
    private func waitForBaselineDOMProbe(
        module: SumiExtensionsModule,
        profileID: String,
        extensionID: String
    ) async throws -> ChromeMV3ControlledPopupBaselineDOMProbe {
        let script = """
        (() => {
          const status = document.getElementById('baseline-status');
          const button = document.getElementById('baseline-button');
          const text = document.body && document.body.innerText
            ? document.body.innerText.trim()
            : "";
          const outcome = status
            ? (status.dataset.outcome || 'missing')
            : 'missing';
          const coarseUsable =
            outcome === 'ok'
            && !!button
            && text.length > 0;
          return JSON.stringify({
            outcome: outcome,
            hasButton: !!button,
            visibleTextLength: text.length,
            controlCount: document.querySelectorAll(
              'button,input,a[href]'
            ).length,
            coarseUsable: coarseUsable
          });
        })();
        """
        for _ in 0..<240 {
            let raw = try await module
                .chromeMV3PopupOptionsEvaluateJavaScriptForTesting(
                    profileID: profileID,
                    extensionID: extensionID,
                    script: script
                ) as? String
            if let raw,
               let data = raw.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any]
            {
                let probe = ChromeMV3ControlledPopupBaselineDOMProbe(
                    outcome: object["outcome"] as? String ?? "missing",
                    hasButton: object["hasButton"] as? Bool ?? false,
                    visibleTextLength: object["visibleTextLength"] as? Int ?? 0,
                    controlCount: object["controlCount"] as? Int ?? 0,
                    coarseUsable: object["coarseUsable"] as? Bool ?? false
                )
                if probe.outcome == "ok" || probe.outcome == "fail" {
                    return probe
                }
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let raw = try await module
            .chromeMV3PopupOptionsEvaluateJavaScriptForTesting(
                profileID: profileID,
                extensionID: extensionID,
                script: script
            ) as? String ?? "{}"
        let object =
            raw.data(using: .utf8).flatMap {
                try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
            } ?? [:]
        return ChromeMV3ControlledPopupBaselineDOMProbe(
            outcome: object["outcome"] as? String ?? "missing",
            hasButton: object["hasButton"] as? Bool ?? false,
            visibleTextLength: object["visibleTextLength"] as? Int ?? 0,
            controlCount: object["controlCount"] as? Int ?? 0,
            coarseUsable: object["coarseUsable"] as? Bool ?? false
        )
    }

    @MainActor
    private func waitForPopupBridgeSnapshot(
        module: SumiExtensionsModule,
        profileID: String,
        extensionID: String
    ) async throws -> ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot {
        for _ in 0..<240 {
            if let snapshot =
                module.chromeMV3PopupOptionsBridgeDiagnosticsSnapshotForTesting(
                    profileID: profileID,
                    extensionID: extensionID
                ),
                snapshot.jsDebugRouteEvents.isEmpty == false
            {
                let manifestReturned = snapshot.jsDebugRouteEvents.contains {
                    $0.apiName == "runtime.getManifest"
                        && $0.resultClassifier == "manifestReturned"
                }
                let finalCheckpoint = snapshot.jsDebugRouteEvents.contains {
                    $0.eventKind == "postBootstrapCheckpoint"
                        && $0.diagnostics.contains("phase=final")
                }
                if manifestReturned && finalCheckpoint {
                    return snapshot
                }
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        return try XCTUnwrap(
            module.chromeMV3PopupOptionsBridgeDiagnosticsSnapshotForTesting(
                profileID: profileID,
                extensionID: extensionID
            ),
            "No controlled popup bridge diagnostics snapshot was captured."
        )
    }

    private func syntheticPageContext(
        profileID: String
    ) -> ChromeMV3URLHubCurrentPageContext {
        ChromeMV3URLHubCurrentPageContext(
            profileID: profileID,
            tabID: "sumi-usable-popup-urlhub-tab",
            permissionBrokerTabID: 42,
            documentID: "sumi-usable-popup-urlhub-document",
            urlString:
                ChromeMV3URLHubDeveloperPreviewModelBuilder
                .syntheticDiagnosticURLString,
            tabSurface: .normalTab
        )
    }
}

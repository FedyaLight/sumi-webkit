import Foundation
import XCTest

@testable import Sumi

final class WebExtensionStorageCleanupPlannerTests: XCTestCase {
    private let planner = WebExtensionStorageCleanupPlanner.shared

    func testStoredDataCandidateIgnoresStateOnlyDirectory() {
        XCTAssertFalse(
            planner.hasStoredDataCandidate(
                in: .init(
                    directoryExists: false,
                    entryNames: [],
                    hasRegisteredContentScriptsStore: false,
                    hasLocalStorageStore: false,
                    hasSyncStorageStore: false
                )
            )
        )

        XCTAssertFalse(
            planner.hasStoredDataCandidate(
                in: .init(
                    directoryExists: true,
                    entryNames: ["State.plist"],
                    hasRegisteredContentScriptsStore: false,
                    hasLocalStorageStore: false,
                    hasSyncStorageStore: false
                )
            )
        )

        XCTAssertTrue(
            planner.hasStoredDataCandidate(
                in: .init(
                    directoryExists: true,
                    entryNames: ["LocalStorage.db", "State.plist"],
                    hasRegisteredContentScriptsStore: false,
                    hasLocalStorageStore: true,
                    hasSyncStorageStore: false
                )
            )
        )
    }

    func testCapabilitySnapshotReportsStorageAndDynamicScriptStores() {
        let snapshot = planner.storeCapabilitySnapshot(
            for: [
                "permissions": ["storage", "scripting", "tabs"],
            ],
            unsupportedAPIs: [
                "browser.scripting.registerContentScripts",
                "browser.tabs.executeScript",
            ]
        )

        XCTAssertFalse(snapshot.usesWebKitCompatibilityPrelude)
        XCTAssertTrue(snapshot.mayTouchDynamicContentScriptStore)
        XCTAssertTrue(snapshot.mayTouchSyncStorageStore)
        XCTAssertEqual(snapshot.declaredPermissions, ["scripting", "storage", "tabs"])
        XCTAssertEqual(
            snapshot.unsupportedAPIs,
            [
                "browser.scripting.registerContentScripts",
                "browser.tabs.executeScript",
            ]
        )
    }

    func testMissingOptionalStoreCleanupErrorIsBenignWithoutActionableSignals() {
        let classification = planner.classifyCleanupErrors(
            [
                NSError(
                    domain: "NSCocoaErrorDomain",
                    code: 4,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "open(/tmp/ext/LocalStorage.db): No such file or directory",
                    ]
                ),
            ],
            extensionId: "ext-cleanup",
            preCleanupSnapshot: stateOnlySnapshot(),
            postCleanupSnapshot: stateOnlySnapshot()
        )

        XCTAssertEqual(classification.benignOptionalStoreDiagnostics.count, 1)
        XCTAssertTrue(classification.actionableDiagnostics.isEmpty)
    }

    func testNonOptionalCleanupErrorRemainsActionable() {
        let classification = planner.classifyCleanupErrors(
            [
                NSError(
                    domain: "NSCocoaErrorDomain",
                    code: 13,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "open(/tmp/ext/ImportantStore.db): Permission denied",
                    ]
                ),
            ],
            extensionId: "ext-cleanup",
            preCleanupSnapshot: stateOnlySnapshot(),
            postCleanupSnapshot: stateOnlySnapshot()
        )

        XCTAssertTrue(classification.benignOptionalStoreDiagnostics.isEmpty)
        XCTAssertEqual(classification.actionableDiagnostics.count, 1)
    }

    private func stateOnlySnapshot() -> WebExtensionStorageCleanupPlanner.StorageSnapshot {
        .init(
            directoryExists: true,
            entryNames: ["State.plist"],
            hasRegisteredContentScriptsStore: false,
            hasLocalStorageStore: false,
            hasSyncStorageStore: false
        )
    }
}

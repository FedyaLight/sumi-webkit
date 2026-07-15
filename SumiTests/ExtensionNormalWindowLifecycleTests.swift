import SwiftData
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class ExtensionNormalWindowLifecycleTests: XCTestCase {
    func testTabCloseClaimIsExactAndRejectsNestedClose() {
        let generation = ExtensionTabPublicationRevision(generation: 41)
        let firstTab = Tab(url: URL(string: "https://first.example")!)
        let secondTab = Tab(url: URL(string: "https://second.example")!)
        for tab in [firstTab, secondTab] {
            tab.extensionPageRuntimeOwner.prepareGeneration(generation)
            tab.extensionPageRuntimeOwner.markDidOpenTab(
                generation: generation
            )
        }

        XCTAssertTrue(
            firstTab.extensionPageRuntimeOwner
                .claimDidOpenTabNotificationForClose(
                    generation: generation
                )
        )
        XCTAssertFalse(
            firstTab.extensionPageRuntimeOwner
                .claimDidOpenTabNotificationForClose(
                    generation: generation
                )
        )
        XCTAssertTrue(
            secondTab.extensionPageRuntimeOwner
                .hasDidOpenTabNotification(for: generation)
        )
    }

    func testRuntimeTeardownInvalidatesInFlightReconciliation() throws {
        let container = try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [
                ModelConfiguration(isStoredInMemoryOnly: true),
            ]
        )
        let profile = Profile(name: "Lifecycle")
        let attachedRuntime = ExtensionAttachedRuntimeCapture()
        let manager = makeSafariExtensionTestExtensionManager(
            context: container.mainContext,
            initialProfile: profile,
            attachedRuntimeCapture: attachedRuntime
        )
        let browserManager = makeSafariExtensionTestBrowserManager(
            profile: profile
        )
        manager.attach(browserManager: browserManager)
        let lifecycle = attachedRuntime.runtime.publications.normalWindows
        let token = try XCTUnwrap(
            lifecycle.beginRuntimeReconciliation()
        )

        XCTAssertTrue(lifecycle.closeAllForRuntimeTeardown())
        XCTAssertFalse(
            lifecycle.finishRuntimeReconciliation(
                token,
                republishing: []
            )
        )
        XCTAssertFalse(lifecycle.opened(BrowserWindowState()))
        XCTAssertFalse(lifecycle.closeAllForRuntimeTeardown())
    }
}

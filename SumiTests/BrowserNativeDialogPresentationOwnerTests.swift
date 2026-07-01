import AppKit
import XCTest

@testable import Sumi

@MainActor
final class NativeDialogPresentationOwnerTests: XCTestCase {
    func testQuitDialogRunsNativeDismissalOrchestrationInOrder() {
        let harness = NativeDialogOwnerHarness()

        harness.owner.showQuitDialog()

        XCTAssertEqual(
            harness.events,
            [
                "overlay-dismissal",
                "floating-dismissal:true",
                "theme-commit",
                "terminate",
            ]
        )
    }

    func testBrowsingDataPresentationTargetsActiveWindowAndRunsPreparation() throws {
        let registry = WindowRegistry()
        let activeWindow = BrowserWindowState()
        registry.register(activeWindow)
        registry.setActive(activeWindow)

        let harness = NativeDialogOwnerHarness(windowRegistry: registry)

        harness.owner.presentBrowsingDataSheet()

        let presentation = try XCTUnwrap(harness.presentation)
        XCTAssertEqual(presentation.windowID, activeWindow.id)
        XCTAssertTrue(harness.owner.isNativeModalPresented(in: activeWindow.id))

        let anyWindowID: UUID? = nil
        XCTAssertTrue(harness.owner.isNativeModalPresented(in: anyWindowID))
        XCTAssertFalse(harness.owner.isNativeModalPresented(in: UUID()))
        XCTAssertEqual(harness.events, ["overlay-dismissal", "theme-discard"])

        guard case .browsingData = presentation.kind else {
            return XCTFail("Expected browsing data presentation")
        }
    }

    func testReplacingPresentationInvokesExistingBasicAuthDismissal() throws {
        let registry = WindowRegistry()
        let windowState = BrowserWindowState()
        registry.register(windowState)
        registry.setActive(windowState)

        let harness = NativeDialogOwnerHarness(windowRegistry: registry)
        var cancelCount = 0
        let session = BasicAuthSheetSession(
            model: BasicAuthDialogModel(host: "example.com"),
            onSubmit: { _, _, _ in /* No-op. */ },
            onCancel: {
                cancelCount += 1
            }
        )

        XCTAssertTrue(harness.owner.presentBasicAuthSheet(session, in: windowState))

        harness.owner.presentNoticeSheet(
            BrowserNoticeSheetModel(
                title: "Notice",
                message: "Replacement notice"
            )
        )

        XCTAssertEqual(cancelCount, 1)
        let presentation = try XCTUnwrap(harness.presentation)
        guard case .notice = presentation.kind else {
            return XCTFail("Expected replacement notice presentation")
        }
        XCTAssertEqual(
            harness.events,
            [
                "overlay-dismissal",
                "theme-discard",
                "overlay-dismissal",
                "theme-discard",
            ]
        )
    }

    func testExplicitDismissDoesNotInvokeBasicAuthDismissalCallback() {
        let windowState = BrowserWindowState()
        let harness = NativeDialogOwnerHarness()
        var cancelCount = 0
        let session = BasicAuthSheetSession(
            model: BasicAuthDialogModel(host: "example.com"),
            onSubmit: { _, _, _ in /* No-op. */ },
            onCancel: {
                cancelCount += 1
            }
        )

        XCTAssertTrue(harness.owner.presentBasicAuthSheet(session, in: windowState))

        harness.owner.dismissNativeModalPresentation()

        XCTAssertNil(harness.presentation)
        XCTAssertEqual(cancelCount, 0)
        XCTAssertEqual(harness.recoveredWindowCount, 1)
    }

    func testSidebarSourcePresentationStartsAndFinishesDialogSessionOnBindingDismiss() throws {
        let windowState = BrowserWindowState()
        let source = windowState.resolveSidebarPresentationSource()
        let harness = NativeDialogOwnerHarness()

        harness.owner.presentNoticeSheet(
            BrowserNoticeSheetModel(
                title: "Notice",
                message: "Sidebar notice"
            ),
            source: source
        )

        let presentation = try XCTUnwrap(harness.presentation)
        XCTAssertEqual(presentation.windowID, windowState.id)
        XCTAssertEqual(presentation.transientSessionToken?.kind, .dialog)
        XCTAssertTrue(
            windowState.sidebarTransientSessionCoordinator.hasPinnedTransientUI(for: windowState.id)
        )

        harness.owner.nativeModalPresentationBindingDismissed(for: UUID())

        XCTAssertNotNil(harness.presentation)
        XCTAssertTrue(
            windowState.sidebarTransientSessionCoordinator.hasPinnedTransientUI(for: windowState.id)
        )

        harness.owner.nativeModalPresentationBindingDismissed(for: windowState.id)

        XCTAssertNil(harness.presentation)
        XCTAssertFalse(
            windowState.sidebarTransientSessionCoordinator.hasPinnedTransientUI(for: windowState.id)
        )
        XCTAssertEqual(harness.recoveredWindowCount, 0)
    }
}

@MainActor
private final class NativeDialogOwnerHarness {
    var presentation: BrowserNativeModalPresentation?
    var windowRegistry: WindowRegistry?
    var events: [String] = []
    private var recoveredWindows: [NSWindow?] = []

    var recoveredWindowCount: Int {
        recoveredWindows.count
    }

    lazy var owner = BrowserNativeDialogPresentationOwner(
        dependencies: BrowserNativeDialogPresentationOwner.Dependencies(
            windowRegistry: { [weak self] in
                self?.windowRegistry
            },
            nativeModalPresentation: { [weak self] in
                self?.presentation
            },
            setNativeModalPresentation: { [weak self] presentation in
                self?.presentation = presentation
            },
            postCollapsedSidebarOverlayDismissal: { [weak self] in
                self?.events.append("overlay-dismissal")
            },
            dismissFloatingBarForActiveWindow: { [weak self] preserveDraft in
                self?.events.append("floating-dismissal:\(preserveDraft)")
            },
            dismissThemePickerDiscardingIfNeeded: { [weak self] in
                self?.events.append("theme-discard")
            },
            dismissThemePickerCommittingIfNeeded: { [weak self] in
                self?.events.append("theme-commit")
            },
            terminateApplication: { [weak self] in
                self?.events.append("terminate")
            },
            keyWindow: {
                nil
            },
            mainWindow: {
                nil
            },
            recoverSidebarHost: { [weak self] window in
                self?.recoveredWindows.append(window)
            }
        )
    )

    init(windowRegistry: WindowRegistry? = nil) {
        self.windowRegistry = windowRegistry
    }
}

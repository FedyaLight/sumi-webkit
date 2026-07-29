import AppKit
import XCTest

@testable import Sumi

@MainActor
final class NativeDialogPresentationOwnerTests: XCTestCase {
    func testCollapsedSidebarOverlayDismissalPostsNotification() {
        let harness = NativeDialogOwnerHarness()
        let notification = expectation(
            forNotification: .sumiShouldHideCollapsedSidebarOverlay,
            object: nil
        )

        harness.owner.requestCollapsedSidebarOverlayDismissal()

        wait(for: [notification], timeout: 0.1)
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
        let source = windowState.resolveSidebarPresentationSource(in: nil)
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
    let windowRegistry: WindowRegistry
    private let browser: BrowserManager
    private let modalState = BrowserNativeModalPresentationState()
    private let recovery = NativeDialogRecoveryRecorder()

    var recoveredWindowCount: Int {
        recovery.recoveredWindowCount
    }

    var presentation: BrowserNativeModalPresentation? {
        modalState.presentation
    }

    lazy var owner = BrowserNativeDialogPresentationOwner(
        modal: BrowserNativeModalTransaction(
            state: modalState,
            windows: windowRegistry,
            recovery: recovery
        ),
        commandPalette: browser.commandPalettePresentation,
        themes: browser.workspaceThemeEditorOwner,
        sharing: BrowserSharingPickerPresentationOwner(windows: windowRegistry),
        alerts: BrowserNativeAlertPresenter(
            windows: windowRegistry,
            settings: browser.settingsState
        )
    )

    init(windowRegistry: WindowRegistry = WindowRegistry()) {
        self.windowRegistry = windowRegistry
        browser = BrowserManager(
            windowRegistry: windowRegistry,
            sidebarHostRecoveryCoordinator: recovery
        )
    }
}

@MainActor
private final class NativeDialogRecoveryRecorder: SidebarHostRecoveryHandling {
    private(set) var recoveredWindowCount = 0

    func sync(anchor _: NSView, window _: NSWindow?) {}

    func unregister(anchor _: NSView) {}

    func recover(in _: NSWindow?) {
        recoveredWindowCount += 1
    }

    func recover(anchor _: NSView?) {}
}

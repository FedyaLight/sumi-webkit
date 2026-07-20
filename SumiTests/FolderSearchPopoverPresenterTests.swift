import AppKit
import SwiftUI
import XCTest

@testable import Sumi

@MainActor
final class FolderSearchPopoverPresenterTests: XCTestCase {
    func testPresentationIsDeferredBeyondCurrentAppKitUpdate() throws {
        let delayedActions = ManualMainActorDelayedActionScheduler()
        var showCount = 0
        let presenter = FolderSearchPopoverPresenter(
            delayedActions: delayedActions.scheduler,
            showPopover: { _, _, _, _ in
                showCount += 1
            }
        )
        let windowState = BrowserWindowState()
        let settings = SumiSettingsService(userDefaults: TestDefaultsHarness().defaults)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let anchorView = NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 32))
        try XCTUnwrap(window.contentView).addSubview(anchorView)
        let source = windowState.sidebarTransientSessionCoordinator.preparedPresentationSource(
            window: window,
            ownerView: anchorView
        )

        presenter.present(
            request: makeRequest(folderID: UUID()),
            in: windowState,
            themeContext: .default,
            presentationContext: FolderSearchPopoverPresentationContext(
                sidebarPosition: .left,
                settings: settings
            ),
            source: source
        )

        XCTAssertEqual(showCount, 0)
        XCTAssertEqual(delayedActions.pendingActionCount, 1)

        delayedActions.runNext()

        XCTAssertEqual(showCount, 1)
    }

    func testReplacementWaitsForClosedSessionAndNextAppKitUpdate() throws {
        let delayedActions = ManualMainActorDelayedActionScheduler()
        var showCount = 0
        var shownPopovers: [NSPopover] = []
        let presenter = FolderSearchPopoverPresenter(
            delayedActions: delayedActions.scheduler,
            showPopover: { popover, _, _, _ in
                showCount += 1
                shownPopovers.append(popover)
            },
            isPopoverShown: { _ in true },
            closePopover: { _ in }
        )
        let windowState = BrowserWindowState()
        let settings = SumiSettingsService(userDefaults: TestDefaultsHarness().defaults)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let anchorView = NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 32))
        try XCTUnwrap(window.contentView).addSubview(anchorView)
        let source = windowState.sidebarTransientSessionCoordinator.preparedPresentationSource(
            window: window,
            ownerView: anchorView
        )
        let presentationContext = FolderSearchPopoverPresentationContext(
            sidebarPosition: .left,
            settings: settings
        )

        presenter.present(
            request: makeRequest(folderID: UUID()),
            in: windowState,
            themeContext: .default,
            presentationContext: presentationContext,
            source: source
        )
        delayedActions.runNext()
        XCTAssertEqual(showCount, 1)

        presenter.present(
            request: makeRequest(folderID: UUID()),
            in: windowState,
            themeContext: .default,
            presentationContext: presentationContext,
            source: source
        )

        XCTAssertEqual(showCount, 1)
        XCTAssertEqual(delayedActions.pendingActionCount, 0)

        presenter.popoverDidClose(
            Notification(name: NSPopover.didCloseNotification, object: shownPopovers[0])
        )

        XCTAssertEqual(showCount, 1)
        XCTAssertEqual(delayedActions.pendingActionCount, 1)

        delayedActions.runNext()

        XCTAssertEqual(showCount, 2)
    }

    private func makeRequest(folderID: UUID) -> FolderSearchPopoverRequest {
        FolderSearchPopoverRequest(
            folderID: folderID,
            folderName: "Folder",
            candidates: [
                FolderSearchCandidate(
                    id: "candidate",
                    kind: .shortcut(UUID()),
                    title: "Candidate",
                    secondaryText: "",
                    icon: Image(systemName: "link"),
                    searchText: "candidate",
                    activate: {}
                )
            ]
        )
    }
}

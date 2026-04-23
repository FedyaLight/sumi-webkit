import XCTest

@testable import Sumi

@MainActor
final class DownloadsPopoverStateTests: XCTestCase {
    func testWindowDownloadsPopoverStateIsTransientAndDismissedByDefault() {
        let windowState = BrowserWindowState()

        XCTAssertFalse(windowState.isDownloadsPopoverPresented)

        windowState.isDownloadsPopoverPresented = true

        XCTAssertTrue(windowState.isDownloadsPopoverPresented)

        windowState.isDownloadsPopoverPresented = false
        XCTAssertFalse(windowState.isDownloadsPopoverPresented)
    }

    func testDownloadsButtonStateDefaultsToVisibleInactiveManagerState() throws {
        let manager = DownloadManager()

        XCTAssertFalse(manager.hasActiveDownloads)
        XCTAssertFalse(manager.hasInactiveDownloads)
        XCTAssertEqual(manager.activeDownloadCount, 0)
        XCTAssertNil(manager.combinedProgressFraction)
    }

    func testRetryableFailedItemStateIsIndependentFromPopoverListState() throws {
        let manager = DownloadManager()
        let item = DownloadItem(
            downloadURL: URL(string: "https://example.com/retry.bin")!,
            fileName: "retry.bin",
            state: .failed,
            error: .failed(message: "Network error", resumeData: Data([1]), isRetryable: true)
        )

        XCTAssertTrue(item.canRetry)
        XCTAssertTrue(manager.items.isEmpty)
    }

    func testClearInactiveAvailabilityTracksCurrentSessionItems() throws {
        let manager = DownloadManager()
        let active = manager.beginExternalDownload(
            originalURL: URL(string: "https://example.com/active.bin")!,
            suggestedFilename: "active.bin",
            sourceProgress: Progress(totalUnitCount: -1)
        )

        XCTAssertFalse(manager.hasInactiveDownloads)

        manager.clearInactiveDownloads()
        XCTAssertEqual(manager.items.map(\.id), [active.id])

        manager.failExternalDownload(active, error: URLError(.networkConnectionLost))

        XCTAssertTrue(manager.hasInactiveDownloads)

        manager.clearInactiveDownloads()

        XCTAssertTrue(manager.items.isEmpty)
        XCTAssertFalse(manager.hasInactiveDownloads)
    }

    func testPopoverContentSizeUsesSingleSlotForEmptyAndOneItemList() throws {
        let emptyManager = DownloadManager()
        let presenter = DownloadsPopoverPresenter()

        XCTAssertEqual(presenter.contentSize(for: emptyManager).height, 122)

        let oneItemManager = DownloadManager()
        _ = oneItemManager.beginExternalDownload(
            originalURL: URL(string: "https://example.com/active.bin")!,
            suggestedFilename: "active.bin",
            sourceProgress: Progress(totalUnitCount: 100)
        )

        let oneItemHeight = presenter.contentSize(for: oneItemManager).height

        XCTAssertEqual(oneItemHeight, 122)
        XCTAssertEqual(oneItemHeight, presenter.contentSize(for: emptyManager).height)
    }

    func testPopoverContentSizeGrowsAndCapsListHeight() throws {
        let presenter = DownloadsPopoverPresenter()
        let oneItemManager = DownloadManager()
        _ = oneItemManager.beginExternalDownload(
            originalURL: URL(string: "https://example.com/one.bin")!,
            suggestedFilename: "one.bin",
            sourceProgress: Progress(totalUnitCount: 100)
        )

        let twoItemManager = DownloadManager()
        for index in 0..<2 {
            _ = twoItemManager.beginExternalDownload(
                originalURL: URL(string: "https://example.com/two-\(index).bin")!,
                suggestedFilename: "two-\(index).bin",
                sourceProgress: Progress(totalUnitCount: 100)
            )
        }

        let cappedManager = DownloadManager()
        for index in 0..<20 {
            _ = cappedManager.beginExternalDownload(
                originalURL: URL(string: "https://example.com/capped-\(index).bin")!,
                suggestedFilename: "capped-\(index).bin",
                sourceProgress: Progress(totalUnitCount: 100)
            )
        }

        XCTAssertGreaterThan(
            presenter.contentSize(for: twoItemManager).height,
            presenter.contentSize(for: oneItemManager).height
        )
        XCTAssertEqual(presenter.contentSize(for: cappedManager).height, 382)
        XCTAssertLessThanOrEqual(presenter.contentSize(for: cappedManager).height, 390)
    }

    func testDownloadsTransientSessionPinsCollapsedSidebarWithoutPersistentReveal() throws {
        let windowState = BrowserWindowState()
        windowState.isSidebarVisible = false
        windowState.sidebarWidth = 250
        windowState.savedSidebarWidth = 300

        let source = windowState.sidebarTransientSessionCoordinator.preparedPresentationSource(
            window: nil
        )
        let token = windowState.sidebarTransientSessionCoordinator.beginSession(
            kind: .downloadsPopover,
            source: source,
            path: "DownloadsPopoverStateTests"
        )

        XCTAssertFalse(windowState.isSidebarVisible)
        XCTAssertEqual(windowState.sidebarWidth, 250)
        XCTAssertEqual(windowState.savedSidebarWidth, 300)
        XCTAssertTrue(windowState.sidebarTransientSessionCoordinator.hasPinnedTransientUI(for: windowState.id))
        XCTAssertTrue(
            SidebarHoverOverlayTransientPinningPolicy.shouldPinHoverSidebar(
                transientWindowID: windowState.sidebarTransientSessionCoordinator.currentPresentationWindowID,
                currentWindowID: windowState.id,
                isSidebarVisible: windowState.isSidebarVisible
            )
        )

        windowState.sidebarTransientSessionCoordinator.finishSession(
            token,
            reason: "DownloadsPopoverStateTests"
        )

        XCTAssertFalse(windowState.sidebarTransientSessionCoordinator.hasPinnedTransientUI(for: windowState.id))
        XCTAssertFalse(windowState.isSidebarVisible)
        XCTAssertEqual(windowState.sidebarWidth, 250)
        XCTAssertEqual(windowState.savedSidebarWidth, 300)
    }
}

import Combine
import SumiDomain
import XCTest

@testable import Sumi

@MainActor
final class DomainRuntimeOwnerTests: XCTestCase {
    func testCompositorInvalidationCoalescesPerWindowAndNativeRoutingIsImmediate() async {
        let firstWindow = BrowserWindowState()
        let secondWindow = BrowserWindowState()

        firstWindow.compositorInvalidation.refresh()
        firstWindow.compositorInvalidation.refresh()
        firstWindow.compositorInvalidation.invalidateNativeSurfaceRouting()

        XCTAssertEqual(firstWindow.compositorInvalidation.compositorVersion, 0)
        XCTAssertEqual(firstWindow.compositorInvalidation.nativeSurfaceRoutingRevision, 1)
        XCTAssertEqual(secondWindow.compositorInvalidation.compositorVersion, 0)

        await drainMainActorTasks()

        XCTAssertEqual(firstWindow.compositorInvalidation.compositorVersion, 1)
        XCTAssertEqual(secondWindow.compositorInvalidation.compositorVersion, 0)
    }

    func testSidebarInputRecoveryCoalescesReasonsAndEmitsWindowDiagnostic() async {
        let windowID = UUID()
        var diagnostics: [SidebarInputRecoveryOwner.Diagnostic] = []
        let owner = SidebarInputRecoveryOwner(windowID: windowID) {
            diagnostics.append($0)
        }

        owner.scheduleRehydrate(reason: .menuEnded)
        owner.scheduleRehydrate(reason: .ownerUnresolvedAfterSoftRecovery)

        XCTAssertEqual(owner.generation, 0)
        XCTAssertTrue(diagnostics.isEmpty)

        await drainMainActorTasks()

        XCTAssertEqual(owner.generation, 1)
        XCTAssertEqual(diagnostics, [SidebarInputRecoveryOwner.Diagnostic(
            generation: 1,
            windowID: windowID,
            reasons: [.menuEnded, .ownerUnresolvedAfterSoftRecovery]
        )])
        XCTAssertEqual(
            diagnostics.first?.message,
            "Sidebar input recovery generation=1 window=\(windowID.uuidString) reason=menu-ended,owner-unresolved-after-soft-recovery"
        )
    }

    func testSidebarFolderProjectionCoalescesLastUpdatePerFolder() async {
        let folderID = UUID()
        let firstChildID = UUID()
        let finalChildID = UUID()
        let owner = SidebarFolderProjectionCoalescer()

        owner.scheduleUpdate(
            for: folderID,
            projectedChildIDs: [firstChildID],
            hasActiveProjection: false
        )
        owner.scheduleUpdate(
            for: folderID,
            projectedChildIDs: [finalChildID],
            hasActiveProjection: true
        )

        XCTAssertEqual(owner.projection(for: folderID), .empty)

        await drainMainQueue()

        XCTAssertEqual(
            owner.projection(for: folderID),
            SidebarFolderProjectionState(
                projectedChildIDs: [finalChildID],
                hasActiveProjection: true
            )
        )
    }

    func testTabLoadingProgressPublishesWithoutInvalidatingTab() {
        let tab = Tab()
        var tabPublicationCount = 0
        var progressValues: [Double] = []
        let tabCancellable = tab.objectWillChange.sink {
            tabPublicationCount += 1
        }
        let progressCancellable = tab.loadingProgress.$estimatedProgress
            .dropFirst()
            .sink { progressValues.append($0) }

        tab.estimatedProgress = 0.42

        XCTAssertEqual(tabPublicationCount, 0)
        XCTAssertEqual(progressValues, [0.42])
        withExtendedLifetime((tabCancellable, progressCancellable)) {}
    }

    func testScheduledOwnersDoNotExtendTheirWindowLifetime() async {
        weak var weakCompositor: WindowCompositorInvalidationOwner?
        weak var weakProjection: SidebarFolderProjectionCoalescer?

        do {
            let compositor = WindowCompositorInvalidationOwner()
            let projection = SidebarFolderProjectionCoalescer()
            weakCompositor = compositor
            weakProjection = projection
            compositor.refresh()
            projection.scheduleUpdate(
                for: UUID(),
                projectedChildIDs: [UUID()],
                hasActiveProjection: true
            )
        }

        XCTAssertNil(weakCompositor)
        XCTAssertNil(weakProjection)
        await drainMainActorTasks()
        await drainMainQueue()
    }
}

@MainActor
private func drainMainActorTasks() async {
    await Task.yield()
    await Task.yield()
}

@MainActor
private func drainMainQueue() async {
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async {
            continuation.resume()
        }
    }
}

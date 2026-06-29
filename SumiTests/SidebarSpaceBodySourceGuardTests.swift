import XCTest

final class SidebarSpaceBodySourceGuardTests: XCTestCase {
    func testSpaceViewUsesNamedStructuralRevisionReader() throws {
        let source = try Self.source(named: "Sumi/Components/Sidebar/SpaceSection/SpaceView.swift")

        XCTAssertTrue(source.contains("SidebarTabStructuralRevisionReader"))
        XCTAssertFalse(source.contains("let _ = browserManager.tabStructuralRevision"))
    }

    func testTabFolderBodyUsesProjectionInsteadOfManagerBackedGetters() throws {
        let source = try Self.source(named: "Sumi/Components/Sidebar/SpaceSection/TabFolderView.swift")
        let bodySource = try Self.sourceRange(
            in: source,
            from: "var body: some View",
            to: "private func refreshLiveFolderIfNeeded"
        )

        XCTAssertTrue(bodySource.contains("SidebarFolderViewProjectionReader"))
        XCTAssertTrue(source.contains("SidebarFolderViewProjection"))

        for forbidden in [
            "browserManager.tabManager",
            "browserManager.liveFolderManager",
            "browserManager.profileManager",
            "baseFolderItems",
            "liveFolderItems",
            "sortedFolderItems(",
        ] {
            XCTAssertFalse(bodySource.contains(forbidden), "TabFolderView.body should not contain \(forbidden)")
        }

        XCTAssertFalse(source.contains("private var baseFolderItems"))
        XCTAssertFalse(source.contains("private var liveFolderItems"))
        XCTAssertFalse(source.contains("private func sortedFolderItems"))
    }

    func testTabFolderViewDoesNotOwnFolderDragDisplayProjectionRules() throws {
        let folderSource = try Self.source(named: "Sumi/Components/Sidebar/SpaceSection/TabFolderView.swift")
        let projectionSource = try Self.source(named: "Sumi/Components/Sidebar/SpaceSection/SidebarFolderViewProjection.swift")

        XCTAssertTrue(projectionSource.contains("struct SidebarFolderDragDisplayProjection"))
        XCTAssertTrue(projectionSource.contains("enum SidebarFolderDisplayProjection"))
        XCTAssertFalse(projectionSource.contains("SidebarDragState.shared"))

        for forbidden in [
            "dragState.projectionDragScope",
            "dragState.projectionFolderDropIntent",
            "dragState.shouldHideCommittedCrossContainerPlaceholder",
            "private func folderDisplayEntries",
            "private func folderDisplayID",
        ] {
            XCTAssertFalse(folderSource.contains(forbidden), "TabFolderView should not own \(forbidden)")
        }
    }

    func testActiveSwiftUISidebarReadsInjectedDragState() throws {
        let hostSource = try Self.source(named: "Sumi/Components/Sidebar/SidebarPresentationContext.swift")
        XCTAssertTrue(hostSource.contains("let sidebarDragState: SidebarDragState"))
        XCTAssertTrue(hostSource.contains(".environmentObject(context.sidebarDragState)"))
        XCTAssertTrue(hostSource.contains(".environmentObject(context.sidebarDragState.locationTracker)"))

        let columnRootSource = try Self.source(named: "Sumi/Components/Sidebar/SidebarColumnRepresentable.swift")
        XCTAssertTrue(columnRootSource.contains("var sidebarDragState: SidebarDragState = SidebarDragState.shared"))
        XCTAssertTrue(columnRootSource.contains("sidebarDragState: sidebarDragState"))

        let hoverRootSource = try Self.source(named: "Sumi/Components/Sidebar/SidebarHoverOverlayView.swift")
        XCTAssertTrue(hoverRootSource.contains("sidebarDragState: SidebarDragState = SidebarDragState.shared"))
        XCTAssertTrue(hoverRootSource.contains("sidebarDragState: dragState"))

        for path in [
            "Navigation/Sidebar/SpacesSideBarView.swift",
            "Sumi/Components/Sidebar/CollapsedSidebarOverlayHost.swift",
            "Sumi/Components/Sidebar/PinnedButtons/PinnedGrid.swift",
            "Sumi/Components/Sidebar/SidebarDDGHover.swift",
            "Sumi/Components/Sidebar/SpaceSection/SpaceView.swift",
            "Sumi/Components/Sidebar/SpaceSection/SpaceRegularTabsSection.swift",
            "Sumi/Components/Sidebar/SpaceSection/TabFolderView.swift",
        ] {
            let source = try Self.source(named: path)
            XCTAssertFalse(source.contains("SidebarDragState.shared"), "\(path) should use injected sidebar drag state")
        }
    }

    func testTabFolderContextMenusAreOwnedByActionOwner() throws {
        let folderSource = try Self.source(named: "Sumi/Components/Sidebar/SpaceSection/TabFolderView.swift")
        let ownerSource = try Self.source(named: "Sumi/Components/Sidebar/SpaceSection/TabFolderContextMenuActionOwner.swift")

        XCTAssertTrue(ownerSource.contains("struct TabFolderContextMenuActionOwner"))
        XCTAssertTrue(ownerSource.contains("func folderShortcutContextMenuEntries"))
        XCTAssertTrue(ownerSource.contains("func liveFolderItemContextMenuEntries"))
        XCTAssertTrue(ownerSource.contains("func folderHeaderContextMenuEntries"))
        XCTAssertTrue(ownerSource.contains("private func liveFolderHeaderContextMenuEntries"))
        XCTAssertTrue(ownerSource.contains("private func refreshIntervalSubmenu"))
        XCTAssertTrue(ownerSource.contains("private func presentShortcutLinkEditor"))

        for forbidden in [
            "private func folderShortcutContextMenuEntries",
            "private func liveFolderItemContextMenuEntries",
            "private func folderHeaderContextMenuEntries",
            "private func liveFolderHeaderContextMenuEntries",
            "private func refreshIntervalSubmenu",
            "private func presentShortcutLinkEditor",
        ] {
            XCTAssertFalse(folderSource.contains(forbidden), "TabFolderView should not own \(forbidden)")
        }
    }

    func testSpaceScrollChromeNotificationsKeepSynchronousMainActorBoundary() throws {
        let source = try Self.source(named: "Sumi/Components/Sidebar/SpaceSection/SpaceScrollChrome.swift")
        let observationSource = try Self.sourceRange(
            in: source,
            from: "private func syncScrollBoundsObservation",
            to: "private func configurePassiveScrollIndicator"
        )

        XCTAssertTrue(observationSource.contains("forName: NSView.boundsDidChangeNotification"))
        XCTAssertTrue(observationSource.contains("forName: NSView.frameDidChangeNotification"))
        XCTAssertEqual(observationSource.components(separatedBy: "queue: nil").count - 1, 2)
        XCTAssertEqual(observationSource.components(separatedBy: "MainActor.assumeIsolated").count - 1, 2)
        XCTAssertFalse(observationSource.contains("Task { @MainActor"))
    }

    private static func sourceRange(
        in source: String,
        from startMarker: String,
        to endMarker: String
    ) throws -> String {
        let start = try XCTUnwrap(source.range(of: startMarker)?.lowerBound)
        let end = try XCTUnwrap(
            source.range(of: endMarker, range: start..<source.endIndex)?.lowerBound
        )
        return String(source[start..<end])
    }

    private static func source(named path: String) throws -> String {
        let url = repoRoot.appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static var repoRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        url.deleteLastPathComponent()
        url.deleteLastPathComponent()
        return url
    }
}

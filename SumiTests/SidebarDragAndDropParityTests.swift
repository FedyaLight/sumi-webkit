import XCTest
import SwiftData
import AppKit
import SwiftUI
@testable import Sumi

private let sidebarTestInteractivePageFrame = CGRect(x: 0, y: 0, width: 320, height: 1200)

@MainActor
private func makeSidebarContextMenuController(
    interactionState: SidebarInteractionState
) -> SidebarContextMenuController {
    SidebarContextMenuController(
        interactionState: interactionState,
        transientSessionCoordinator: SidebarTransientSessionCoordinator(
            windowID: UUID(),
            interactionState: interactionState
        )
    )
}

private extension SidebarInteractionState {
    @discardableResult
    func beginContextMenuSessionForTesting() -> UUID {
        let tokenID = UUID()
        beginSession(kind: .contextMenu, tokenID: tokenID)
        return tokenID
    }

    func endContextMenuSessionForTesting(_ tokenID: UUID) {
        endSession(kind: .contextMenu, tokenID: tokenID)
    }
}

@MainActor
private final class SidebarContextMenuControllerTestingSession {
    let token: SidebarTransientSessionToken
    weak var ownerView: NSView?
    let onMenuVisibilityChanged: (Bool) -> Void
    var didBecomeVisible = false
    var menuEndTrackingObserver: NSObjectProtocol?
    var windowCloseObserver: NSObjectProtocol?

    init(
        token: SidebarTransientSessionToken,
        ownerView: NSView,
        onMenuVisibilityChanged: @escaping (Bool) -> Void
    ) {
        self.token = token
        self.ownerView = ownerView
        self.onMenuVisibilityChanged = onMenuVisibilityChanged
    }

    deinit {
        if let menuEndTrackingObserver {
            NotificationCenter.default.removeObserver(menuEndTrackingObserver)
        }
        if let windowCloseObserver {
            NotificationCenter.default.removeObserver(windowCloseObserver)
        }
    }
}

@MainActor
private var sidebarContextMenuControllerTestingSessions:
    [ObjectIdentifier: [UUID: SidebarContextMenuControllerTestingSession]] = [:]

@MainActor
extension SidebarContextMenuController {
    func beginMenuSessionForTesting(
        ownerView: NSView? = nil,
        menu: NSMenu?,
        onMenuVisibilityChanged: @escaping (Bool) -> Void = { _ in }
    ) -> UUID {
        forceCloseActiveSessionForTesting()

        let resolvedOwnerView = ownerView ?? NSView(frame: .zero)
        transientSessionCoordinator.prepareMenuPresentationSource(ownerView: resolvedOwnerView)
        let source = transientSessionCoordinator.preparedPresentationSource(
            window: resolvedOwnerView.window,
            ownerView: resolvedOwnerView
        )
        let token = transientSessionCoordinator.beginSession(
            kind: .contextMenu,
            source: source,
            path: "test.sidebar-context-menu",
            preservePendingSource: true
        )
        let sessionID = UUID()
        let session = SidebarContextMenuControllerTestingSession(
            token: token,
            ownerView: resolvedOwnerView,
            onMenuVisibilityChanged: onMenuVisibilityChanged
        )
        let controllerID = ObjectIdentifier(self)
        sidebarContextMenuControllerTestingSessions[controllerID, default: [:]][sessionID] = session

        if let menu {
            session.menuEndTrackingObserver = NotificationCenter.default.addObserver(
                forName: NSMenu.didEndTrackingNotification,
                object: menu,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.finishMenuSessionForTesting(sessionID: sessionID)
                }
            }
        }

        if let window = resolvedOwnerView.window {
            session.windowCloseObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.finishMenuSessionForTesting(sessionID: sessionID)
                }
            }
        }

        return sessionID
    }

    func beginMenuSessionForTesting(
        ownerView: NSView? = nil,
        onMenuVisibilityChanged: @escaping (Bool) -> Void = { _ in }
    ) -> UUID {
        beginMenuSessionForTesting(
            ownerView: ownerView,
            menu: nil,
            onMenuVisibilityChanged: onMenuVisibilityChanged
        )
    }

    func markMenuOpenedForTesting(sessionID: UUID) {
        sidebarContextMenuControllerTestingSessions[ObjectIdentifier(self)]?[sessionID]?.didBecomeVisible = true
    }

    func markMenuClosedForTesting(sessionID: UUID) {
        _ = sidebarContextMenuControllerTestingSessions[ObjectIdentifier(self)]?[sessionID]
    }

    func finishMenuSessionForTesting(sessionID: UUID) {
        let controllerID = ObjectIdentifier(self)
        guard var sessions = sidebarContextMenuControllerTestingSessions[controllerID],
              let session = sessions.removeValue(forKey: sessionID)
        else { return }

        sidebarContextMenuControllerTestingSessions[controllerID] = sessions.isEmpty ? nil : sessions
        transientSessionCoordinator.endSession(session.token)

        if session.didBecomeVisible {
            DispatchQueue.main.async {
                session.onMenuVisibilityChanged(true)
                session.onMenuVisibilityChanged(false)
            }
        }
    }

    func detachOwnerViewForTesting(_ ownerView: NSView) {
        let controllerID = ObjectIdentifier(self)
        let sessionIDs = sidebarContextMenuControllerTestingSessions[controllerID, default: [:]]
            .filter { $0.value.ownerView === ownerView }
            .map(\.key)
        sessionIDs.forEach { finishMenuSessionForTesting(sessionID: $0) }
    }

    func forceCloseActiveSessionForTesting() {
        let controllerID = ObjectIdentifier(self)
        let sessionIDs = Array(sidebarContextMenuControllerTestingSessions[controllerID, default: [:]].keys)
        sessionIDs.forEach { finishMenuSessionForTesting(sessionID: $0) }
    }

    func runPointerRecoveryForTesting(aroundOwnerView ownerView: NSView) {
        sidebarRecoveryCoordinator.recover(in: ownerView.window)
        sidebarRecoveryCoordinator.recover(anchor: ownerView)
    }

    func configureBackgroundMenuForTesting(
        entriesProvider: @escaping () -> [SidebarContextMenuEntry],
        onMenuVisibilityChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        configureBackgroundMenu(
            entriesProvider: entriesProvider,
            onMenuVisibilityChanged: onMenuVisibilityChanged
        )
    }
}

private extension SidebarDragState {
    func interactivePage(for spaceId: UUID) -> SidebarPageGeometryMetrics? {
        pageGeometryByKey.values.first {
            $0.renderMode == .interactive && $0.spaceId == spaceId
        }
    }

    func updatePageGeometry(
        spaceId: UUID,
        profileId: UUID?,
        frame: CGRect,
        renderMode: SidebarPageGeometryRenderMode,
        publish: Bool = true
    ) {
        applyPageGeometry(
            spaceId: spaceId,
            profileId: profileId,
            frame: frame,
            renderMode: renderMode,
            generation: activeGeometryGeneration
        )
        if publish {
            publishGeometrySnapshotForTesting()
        }
    }

    func updateSectionFrame(
        spaceId: UUID,
        section: SidebarSectionPrefix,
        frame: CGRect,
        publish: Bool = true
    ) {
        applySectionFrame(
            spaceId: spaceId,
            section: section,
            frame: frame,
            generation: activeGeometryGeneration
        )
        if publish {
            publishGeometrySnapshotForTesting()
        }
    }

    func updateFolderDropTarget(
        folderId: UUID,
        spaceId: UUID,
        topLevelIndex: Int,
        childCount: Int,
        isOpen: Bool,
        region: SidebarFolderDragRegion,
        frame: CGRect
    ) {
        applyFolderDropTarget(
            folderId: folderId,
            spaceId: spaceId,
            topLevelIndex: topLevelIndex,
            childCount: childCount,
            isOpen: isOpen,
            region: region,
            frame: frame,
            isActive: true,
            generation: activeGeometryGeneration
        )
        publishGeometrySnapshotForTesting()
    }

    func updateTopLevelPinnedItemTarget(
        itemId: UUID,
        kind: SidebarTopLevelPinnedItemKind,
        spaceId: UUID,
        topLevelIndex: Int,
        frame: CGRect
    ) {
        applyTopLevelPinnedItemTarget(
            itemId: itemId,
            kind: kind,
            spaceId: spaceId,
            topLevelIndex: topLevelIndex,
            frame: frame,
            isActive: true,
            generation: activeGeometryGeneration
        )
        publishGeometrySnapshotForTesting()
    }

    func updateFolderChildDropTarget(
        folderId: UUID,
        childId: UUID,
        index: Int,
        frame: CGRect
    ) {
        applyFolderChildDropTarget(
            folderId: folderId,
            childId: childId,
            index: index,
            frame: frame,
            isActive: true,
            generation: activeGeometryGeneration
        )
        publishGeometrySnapshotForTesting()
    }

    func updateRegularListHitTarget(spaceId: UUID, frame: CGRect, itemCount: Int) {
        applyRegularListHitTarget(
            spaceId: spaceId,
            frame: frame,
            itemCount: itemCount,
            generation: activeGeometryGeneration
        )
        publishGeometrySnapshotForTesting()
    }

    func updateEssentialsLayoutMetrics(
        spaceId: UUID,
        profileId: UUID?,
        frame: CGRect,
        dropFrame: CGRect,
        itemCount: Int,
        columnCount: Int,
        firstSyntheticRowSlot: Int? = nil,
        rowCount: Int,
        itemSize: CGSize,
        gridSpacing: CGFloat,
        canAcceptDrop: Bool = true,
        visibleItemCount: Int? = nil,
        visibleRowCount: Int? = nil,
        maxDropRowCount: Int? = nil,
        dropSlotFrames: [SidebarEssentialsDropSlotMetrics] = []
    ) {
        let resolvedVisibleRowCount = max(
            visibleRowCount ?? Self.resolvedMetricsRowCount(
                for: frame.height,
                itemSize: itemSize,
                gridSpacing: gridSpacing,
                fallback: rowCount
            ),
            1
        )
        let resolvedMaxDropRowCount = max(
            maxDropRowCount ?? Self.resolvedMetricsRowCount(
                for: dropFrame.height,
                itemSize: itemSize,
                gridSpacing: gridSpacing,
                fallback: resolvedVisibleRowCount
            ),
            resolvedVisibleRowCount,
            1
        )

        applyEssentialsLayoutMetrics(
            spaceId: spaceId,
            profileId: profileId,
            frame: frame,
            dropFrame: dropFrame,
            dropSlotFrames: dropSlotFrames,
            itemCount: itemCount,
            columnCount: columnCount,
            firstSyntheticRowSlot: firstSyntheticRowSlot,
            rowCount: rowCount,
            itemSize: itemSize,
            gridSpacing: gridSpacing,
            canAcceptDrop: canAcceptDrop,
            visibleItemCount: visibleItemCount ?? itemCount,
            visibleRowCount: resolvedVisibleRowCount,
            maxDropRowCount: resolvedMaxDropRowCount,
            generation: activeGeometryGeneration
        )
        publishGeometrySnapshotForTesting()
    }

    private static func resolvedMetricsRowCount(
        for height: CGFloat,
        itemSize: CGSize,
        gridSpacing: CGFloat,
        fallback: Int
    ) -> Int {
        guard itemSize.height > 0 else { return max(fallback, 1) }
        let stride = max(itemSize.height + gridSpacing, 1)
        let derivedRows = Int(floor(max(height - itemSize.height, 0) / stride)) + 1
        return max(fallback, derivedRows, 1)
    }
}

@MainActor
private func ensureSidebarInteractivePage(
    _ state: SidebarDragState,
    spaceId: UUID,
    profileId: UUID? = nil,
    frame: CGRect = sidebarTestInteractivePageFrame
) {
    guard state.interactivePage(for: spaceId) == nil else { return }
    guard state.pageGeometryByKey.values.allSatisfy({ $0.renderMode != .interactive }) else { return }
    state.updatePageGeometry(
        spaceId: spaceId,
        profileId: profileId,
        frame: frame,
        renderMode: .interactive
    )
}

@MainActor
private func registerSidebarSectionFrame(
    _ state: SidebarDragState,
    spaceId: UUID,
    section: SidebarSectionPrefix,
    frame: CGRect,
    profileId: UUID? = nil
) {
    ensureSidebarInteractivePage(state, spaceId: spaceId, profileId: profileId)
    state.updateSectionFrame(spaceId: spaceId, section: section, frame: frame)
}

@MainActor
private func registerSidebarRegularHitTarget(
    _ state: SidebarDragState,
    spaceId: UUID,
    frame: CGRect,
    itemCount: Int,
    profileId: UUID? = nil
) {
    ensureSidebarInteractivePage(state, spaceId: spaceId, profileId: profileId)
    state.updateRegularListHitTarget(spaceId: spaceId, frame: frame, itemCount: itemCount)
}

@MainActor
private func registerSidebarEssentialsMetrics(
    _ state: SidebarDragState,
    spaceId: UUID,
    profileId: UUID? = nil,
    frame: CGRect,
    dropFrame: CGRect? = nil,
    itemCount: Int,
    columnCount: Int,
    firstSyntheticRowSlot: Int? = nil,
    rowCount: Int? = nil,
    itemSize: CGSize,
    gridSpacing: CGFloat,
    canAcceptDrop: Bool = true,
    visibleItemCount: Int? = nil,
    visibleRowCount: Int? = nil,
    maxDropRowCount: Int? = nil,
    dropSlotFrames: [SidebarEssentialsDropSlotMetrics] = []
) {
    ensureSidebarInteractivePage(state, spaceId: spaceId, profileId: profileId)
    let resolvedRowCount = rowCount
        ?? max(1, Int(ceil(Double(max(itemCount, 1)) / Double(max(columnCount, 1)))))
    state.updateEssentialsLayoutMetrics(
        spaceId: spaceId,
        profileId: profileId,
        frame: frame,
        dropFrame: dropFrame ?? frame,
        itemCount: itemCount,
        columnCount: columnCount,
        firstSyntheticRowSlot: firstSyntheticRowSlot,
        rowCount: resolvedRowCount,
        itemSize: itemSize,
        gridSpacing: gridSpacing,
        canAcceptDrop: canAcceptDrop,
        visibleItemCount: visibleItemCount,
        visibleRowCount: visibleRowCount,
        maxDropRowCount: maxDropRowCount,
        dropSlotFrames: dropSlotFrames
    )
}

@MainActor
final class SidebarCurrentDragResolverTests: XCTestCase {
    private var state: SidebarDragState!

    override func setUp() {
        super.setUp()
        state = SidebarDragState()
    }

    override func tearDown() {
        state = nil
        super.tearDown()
    }

    func testDragLocationMapperFlipsWindowPointIntoSwiftUITopLeftSpace() {
        let location = SidebarDragLocationMapper.swiftUITopLeftPoint(
            windowPoint: CGPoint(x: 80, y: 292),
            contentHeight: 400
        )

        XCTAssertEqual(location, CGPoint(x: 80, y: 108))
    }

    func testDragLocationMapperUsesSwiftUILayoutTopBoundaryWhenChromeIsPresent() {
        let location = SidebarDragLocationMapper.swiftUITopLeftPoint(
            windowPoint: CGPoint(x: 80, y: 220),
            topBoundaryY: 328
        )

        XCTAssertEqual(location, CGPoint(x: 80, y: 108))
    }

    func testDragLocationMapperKeepsDropAndPreviewInFullContentSpace() {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 320, height: 400),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        let windowPoint = CGPoint(x: 80, y: 220)

        let dropLocation = SidebarDragLocationMapper.swiftUIGlobalPoint(
            fromWindowPoint: windowPoint,
            in: window
        )
        let previewLocation = SidebarDragLocationMapper.swiftUIPreviewPoint(
            fromWindowPoint: windowPoint,
            in: window
        )

        XCTAssertEqual(dropLocation, CGPoint(x: 80, y: 180))
        XCTAssertEqual(previewLocation, dropLocation)
    }

    func testDragLocationMapperPrefersCurrentMousePointForSourceCallbacks() {
        let callbackPoint = NSPoint(x: 10, y: 20)
        let currentMousePoint = NSPoint(x: 100, y: 220)

        XCTAssertEqual(
            SidebarDragLocationMapper.preferredSourceScreenPoint(
                callbackScreenPoint: callbackPoint,
                currentMouseScreenPoint: currentMousePoint
            ),
            currentMousePoint
        )
        XCTAssertEqual(
            SidebarDragLocationMapper.preferredSourceScreenPoint(
                callbackScreenPoint: callbackPoint,
                currentMouseScreenPoint: nil
            ),
            callbackPoint
        )
    }

    func testConvertedCursorRowsResolveSpacePinnedSlotsWithoutVerticalOffset() {
        let spaceId = UUID()
        let draggedTab = SumiDragItem(tabId: UUID(), title: "Dragged")
        let swiftUILayoutTopBoundary: CGFloat = 360
        registerSidebarSectionFrame(
            state,
            spaceId: spaceId,
            section: .spacePinned,
            frame: CGRect(
                x: 0,
                y: 100,
                width: 240,
                height: SidebarRowLayout.rowHeight * 4
            )
        )

        let cursorRows: [(topLeftY: CGFloat, expectedSlot: Int)] = [
            (108, 0),
            (144, 1),
            (180, 2),
        ]

        for row in cursorRows {
            let windowPoint = CGPoint(
                x: 80,
                y: swiftUILayoutTopBoundary - row.topLeftY
            )
            let location = SidebarDragLocationMapper.swiftUITopLeftPoint(
                windowPoint: windowPoint,
                topBoundaryY: swiftUILayoutTopBoundary
            )

            XCTAssertEqual(
                resolve(location, spaceId: spaceId, draggedItem: draggedTab).slot,
                .spacePinned(spaceId: spaceId, slot: row.expectedSlot)
            )
        }
    }

    func testFolderDragItemUsesFolderKind() {
        let folderId = UUID()
        let item = SumiDragItem.folder(folderId: folderId, title: "Folder")

        XCTAssertEqual(item.tabId, folderId)
        XCTAssertEqual(item.kind, .folder)
        XCTAssertEqual(item.title, "Folder")
    }

    func testFolderDragItemRoundTripsThroughPasteboard() {
        let folderId = UUID()
        let item = SumiDragItem.folder(folderId: folderId, title: "Folder")
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("sumi.folder-drag.\(UUID().uuidString)"))
        pasteboard.clearContents()

        pasteboard.writeObjects([item.pasteboardItem()])

        XCTAssertEqual(SumiDragItem.fromPasteboard(pasteboard), item)
    }

    func testFolderDragItemPasteboardItemRoundTripsThroughPasteboard() {
        let folderId = UUID()
        let item = SumiDragItem.folder(folderId: folderId, title: "Folder")
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("sumi.folder-native-drag.\(UUID().uuidString)"))
        pasteboard.clearContents()

        XCTAssertTrue(pasteboard.writeObjects([item.pasteboardItem()]))

        XCTAssertEqual(SumiDragItem.fromPasteboard(pasteboard), item)
    }

    func testClosedFolderHeaderTopBandResolvesBeforeThenContain() {
        let spaceId = UUID()
        let folderId = UUID()
        registerFolder(
            folderId,
            spaceId: spaceId,
            topLevelIndex: 3,
            childCount: 2,
            isOpen: false,
            headerFrame: CGRect(x: 0, y: 100, width: 240, height: 40)
        )
        let draggedTab = SumiDragItem(tabId: UUID(), title: "Dragged")

        let before = resolve(CGPoint(x: 80, y: 106), spaceId: spaceId, draggedItem: draggedTab)
        XCTAssertEqual(before.slot, .spacePinned(spaceId: spaceId, slot: 3))
        XCTAssertEqual(before.folderIntent, .none)

        for y in [112, 120, 134] as [CGFloat] {
            let contain = resolve(CGPoint(x: 80, y: y), spaceId: spaceId, draggedItem: draggedTab)
            XCTAssertEqual(contain.slot, .folder(folderId: folderId, slot: 2))
            XCTAssertEqual(contain.folderIntent, .contain(folderId: folderId))
        }
    }

    func testOpenFolderBodyUsesRowMidpointForChildInsertion() {
        let spaceId = UUID()
        let folderId = UUID()
        registerFolder(
            folderId,
            spaceId: spaceId,
            topLevelIndex: 1,
            childCount: 3,
            isOpen: true,
            bodyFrame: CGRect(x: 0, y: 200, width: 240, height: SidebarRowLayout.rowHeight * 3)
        )
        let draggedTab = SumiDragItem(tabId: UUID(), title: "Dragged")

        XCTAssertEqual(
            resolve(CGPoint(x: 80, y: 217), spaceId: spaceId, draggedItem: draggedTab).slot,
            .folder(folderId: folderId, slot: 0)
        )

        let afterFirstMidpoint = resolve(
            CGPoint(x: 80, y: 219),
            spaceId: spaceId,
            draggedItem: draggedTab
        )
        XCTAssertEqual(afterFirstMidpoint.slot, .folder(folderId: folderId, slot: 1))
        XCTAssertEqual(afterFirstMidpoint.folderIntent, .insertIntoFolder(folderId: folderId, index: 1))

        XCTAssertEqual(
            resolve(CGPoint(x: 80, y: 307), spaceId: spaceId, draggedItem: draggedTab).slot,
            .folder(folderId: folderId, slot: 3)
        )
    }

    func testOpenFolderChildFramesDefineInteriorSlotsAndAfterBoundary() {
        let spaceId = UUID()
        let folderId = UUID()
        let draggedTab = SumiDragItem(tabId: UUID(), title: "Dragged")
        registerFolder(
            folderId,
            spaceId: spaceId,
            topLevelIndex: 2,
            childCount: 3,
            isOpen: true,
            headerFrame: CGRect(x: 0, y: 100, width: 240, height: SidebarRowLayout.rowHeight),
            bodyFrame: CGRect(x: 0, y: 136, width: 240, height: 144),
            childFrames: [
                CGRect(x: 14, y: 144, width: 226, height: SidebarRowLayout.rowHeight),
                CGRect(x: 14, y: 184, width: 226, height: SidebarRowLayout.rowHeight),
                CGRect(x: 14, y: 224, width: 226, height: SidebarRowLayout.rowHeight),
            ]
        )

        XCTAssertEqual(
            resolve(CGPoint(x: 80, y: 142), spaceId: spaceId, draggedItem: draggedTab).slot,
            .folder(folderId: folderId, slot: 0)
        )
        XCTAssertEqual(
            resolve(CGPoint(x: 80, y: 163), spaceId: spaceId, draggedItem: draggedTab).slot,
            .folder(folderId: folderId, slot: 1)
        )
        XCTAssertEqual(
            resolve(CGPoint(x: 80, y: 182), spaceId: spaceId, draggedItem: draggedTab).slot,
            .folder(folderId: folderId, slot: 1)
        )
        XCTAssertEqual(
            resolve(CGPoint(x: 80, y: 204), spaceId: spaceId, draggedItem: draggedTab).slot,
            .folder(folderId: folderId, slot: 2)
        )

        let belowLastRow = resolve(CGPoint(x: 80, y: 262), spaceId: spaceId, draggedItem: draggedTab)
        XCTAssertEqual(belowLastRow.slot, .spacePinned(spaceId: spaceId, slot: 3))
        XCTAssertEqual(belowLastRow.folderIntent, .none)
    }

    func testOpenFolderHeaderResolvesToFirstChildInsertionSlot() {
        let spaceId = UUID()
        let folderId = UUID()
        registerFolder(
            folderId,
            spaceId: spaceId,
            topLevelIndex: 1,
            childCount: 3,
            isOpen: true,
            headerFrame: CGRect(x: 0, y: 100, width: 240, height: 40)
        )

        let before = resolve(
            CGPoint(x: 80, y: 106),
            spaceId: spaceId,
            draggedItem: SumiDragItem(tabId: UUID(), title: "Dragged")
        )
        XCTAssertEqual(before.slot, .spacePinned(spaceId: spaceId, slot: 1))
        XCTAssertEqual(before.folderIntent, .none)

        let resolution = resolve(
            CGPoint(x: 80, y: 120),
            spaceId: spaceId,
            draggedItem: SumiDragItem(tabId: UUID(), title: "Dragged")
        )

        XCTAssertEqual(resolution.slot, .folder(folderId: folderId, slot: 0))
        XCTAssertEqual(resolution.folderIntent, .insertIntoFolder(folderId: folderId, index: 0))
    }

    func testOpenLastFolderAfterZoneResolvesTopLevelAfterFolder() {
        let spaceId = UUID()
        let folderId = UUID()
        registerFolder(
            folderId,
            spaceId: spaceId,
            topLevelIndex: 4,
            childCount: 2,
            isOpen: true,
            headerFrame: CGRect(x: 0, y: 100, width: 240, height: SidebarRowLayout.rowHeight),
            bodyFrame: CGRect(x: 0, y: 136, width: 240, height: SidebarRowLayout.rowHeight * 2),
            afterFrame: CGRect(x: 0, y: 208, width: 240, height: 18)
        )

        let resolution = resolve(
            CGPoint(x: 80, y: 216),
            spaceId: spaceId,
            draggedItem: SumiDragItem(tabId: UUID(), title: "Dragged")
        )

        XCTAssertEqual(resolution.slot, .spacePinned(spaceId: spaceId, slot: 5))
        XCTAssertEqual(resolution.folderIntent, .none)
    }

    func testClosedAndEmptyFoldersResolveContainDropsToTail() {
        let spaceId = UUID()
        let closedFolderId = UUID()
        let emptyFolderId = UUID()
        let draggedTab = SumiDragItem(tabId: UUID(), title: "Dragged")

        registerFolder(
            closedFolderId,
            spaceId: spaceId,
            topLevelIndex: 0,
            childCount: 3,
            isOpen: false,
            bodyFrame: CGRect(x: 0, y: 40, width: 240, height: SidebarRowLayout.rowHeight)
        )

        let closedResolution = resolve(CGPoint(x: 80, y: 50), spaceId: spaceId, draggedItem: draggedTab)
        XCTAssertEqual(closedResolution.slot, .folder(folderId: closedFolderId, slot: 3))
        XCTAssertEqual(closedResolution.folderIntent, .contain(folderId: closedFolderId))

        resetState()
        registerFolder(
            emptyFolderId,
            spaceId: spaceId,
            topLevelIndex: 0,
            childCount: 0,
            isOpen: true,
            bodyFrame: CGRect(x: 0, y: 40, width: 240, height: SidebarRowLayout.rowHeight)
        )

        let emptyResolution = resolve(CGPoint(x: 80, y: 50), spaceId: spaceId, draggedItem: draggedTab)
        XCTAssertEqual(emptyResolution.slot, .folder(folderId: emptyFolderId, slot: 0))
        XCTAssertEqual(emptyResolution.folderIntent, .insertIntoFolder(folderId: emptyFolderId, index: 0))
    }

    func testFolderHitTargetWinsOverOverlappingSpacePinnedFrame() {
        let spaceId = UUID()
        let folderId = UUID()
        registerSidebarSectionFrame(
            state,
            spaceId: spaceId,
            section: .spacePinned,
            frame: CGRect(x: 0, y: 0, width: 240, height: 200)
        )
        registerFolder(
            folderId,
            spaceId: spaceId,
            topLevelIndex: 1,
            childCount: 2,
            isOpen: false,
            headerFrame: CGRect(x: 0, y: 36, width: 240, height: SidebarRowLayout.rowHeight)
        )

        let resolution = resolve(
            CGPoint(x: 80, y: 54),
            spaceId: spaceId,
            draggedItem: SumiDragItem(tabId: UUID(), title: "Dragged")
        )

        XCTAssertEqual(resolution.slot, .folder(folderId: folderId, slot: 2))
        XCTAssertEqual(resolution.folderIntent, .contain(folderId: folderId))
    }

    func testFolderDragCanReorderAtTopLevelButCannotDropIntoFolder() {
        let spaceId = UUID()
        let folderId = UUID()
        let draggedFolder = SumiDragItem.folder(folderId: UUID(), title: "Other Folder")
        registerFolder(
            folderId,
            spaceId: spaceId,
            topLevelIndex: 2,
            childCount: 4,
            isOpen: true,
            headerFrame: CGRect(x: 0, y: 100, width: 240, height: 40),
            bodyFrame: CGRect(x: 0, y: 140, width: 240, height: SidebarRowLayout.rowHeight * 4),
            afterFrame: CGRect(x: 0, y: 284, width: 240, height: 18)
        )

        XCTAssertEqual(
            resolve(CGPoint(x: 80, y: 106), spaceId: spaceId, draggedItem: draggedFolder).slot,
            .spacePinned(spaceId: spaceId, slot: 2)
        )
        XCTAssertEqual(
            resolve(CGPoint(x: 80, y: 134), spaceId: spaceId, draggedItem: draggedFolder).slot,
            .spacePinned(spaceId: spaceId, slot: 3)
        )
        XCTAssertEqual(
            resolve(CGPoint(x: 80, y: 120), spaceId: spaceId, draggedItem: draggedFolder).slot,
            .spacePinned(spaceId: spaceId, slot: 3)
        )
        XCTAssertEqual(
            resolve(CGPoint(x: 80, y: 160), spaceId: spaceId, draggedItem: draggedFolder).slot,
            .spacePinned(spaceId: spaceId, slot: 2)
        )
        XCTAssertEqual(
            resolve(CGPoint(x: 80, y: 292), spaceId: spaceId, draggedItem: draggedFolder).slot,
            .spacePinned(spaceId: spaceId, slot: 3)
        )
    }

    func testFolderDragUsesCompositeTopLevelFrameOverOpenFolderBody() {
        let spaceId = UUID()
        let folderId = UUID()
        let draggedFolder = SumiDragItem.folder(folderId: UUID(), title: "Other Folder")
        registerSidebarSectionFrame(
            state,
            spaceId: spaceId,
            section: .spacePinned,
            frame: CGRect(x: 0, y: 80, width: 240, height: 260)
        )
        registerTopLevelPinnedItem(
            itemId: folderId,
            kind: .folder(folderId),
            spaceId: spaceId,
            topLevelIndex: 2,
            frame: CGRect(x: 0, y: 100, width: 240, height: 180)
        )
        registerFolder(
            folderId,
            spaceId: spaceId,
            topLevelIndex: 2,
            childCount: 4,
            isOpen: true,
            headerFrame: CGRect(x: 0, y: 100, width: 240, height: SidebarRowLayout.rowHeight),
            bodyFrame: CGRect(x: 0, y: 136, width: 240, height: SidebarRowLayout.rowHeight * 4)
        )

        XCTAssertEqual(
            resolve(CGPoint(x: 80, y: 150), spaceId: spaceId, draggedItem: draggedFolder).slot,
            .spacePinned(spaceId: spaceId, slot: 2)
        )
        XCTAssertEqual(
            resolve(CGPoint(x: 80, y: 230), spaceId: spaceId, draggedItem: draggedFolder).slot,
            .spacePinned(spaceId: spaceId, slot: 3)
        )
        XCTAssertEqual(
            resolve(CGPoint(x: 80, y: 150), spaceId: spaceId, draggedItem: .folder(folderId: folderId, title: "Self")).slot,
            .empty
        )
    }

    func testMixedTopLevelPinnedUsesReportedItemFramesForVariableHeightFolders() {
        let spaceId = UUID()
        let firstShortcutId = UUID()
        let folderId = UUID()
        let lastShortcutId = UUID()
        let draggedTab = SumiDragItem(tabId: UUID(), title: "Dragged")
        registerSidebarSectionFrame(
            state,
            spaceId: spaceId,
            section: .spacePinned,
            frame: CGRect(x: 0, y: 100, width: 240, height: 260)
        )
        registerTopLevelPinnedItem(
            itemId: firstShortcutId,
            kind: .shortcut(firstShortcutId),
            spaceId: spaceId,
            topLevelIndex: 0,
            frame: CGRect(x: 0, y: 100, width: 240, height: SidebarRowLayout.rowHeight)
        )
        registerTopLevelPinnedItem(
            itemId: folderId,
            kind: .folder(folderId),
            spaceId: spaceId,
            topLevelIndex: 1,
            frame: CGRect(x: 0, y: 140, width: 240, height: 150)
        )
        registerTopLevelPinnedItem(
            itemId: lastShortcutId,
            kind: .shortcut(lastShortcutId),
            spaceId: spaceId,
            topLevelIndex: 2,
            frame: CGRect(x: 0, y: 300, width: 240, height: SidebarRowLayout.rowHeight)
        )

        XCTAssertEqual(
            resolve(CGPoint(x: 80, y: 112), spaceId: spaceId, draggedItem: draggedTab).slot,
            .spacePinned(spaceId: spaceId, slot: 0)
        )
        XCTAssertEqual(
            resolve(CGPoint(x: 80, y: 130), spaceId: spaceId, draggedItem: draggedTab).slot,
            .spacePinned(spaceId: spaceId, slot: 1)
        )
        XCTAssertEqual(
            resolve(CGPoint(x: 80, y: 160), spaceId: spaceId, draggedItem: draggedTab).slot,
            .spacePinned(spaceId: spaceId, slot: 1)
        )
        XCTAssertEqual(
            resolve(CGPoint(x: 80, y: 250), spaceId: spaceId, draggedItem: draggedTab).slot,
            .spacePinned(spaceId: spaceId, slot: 2)
        )
        XCTAssertEqual(
            resolve(CGPoint(x: 80, y: 322), spaceId: spaceId, draggedItem: draggedTab).slot,
            .spacePinned(spaceId: spaceId, slot: 3)
        )
    }

    func testEmptyEssentialsRevealBandResolvesToFirstSlot() {
        let spaceId = UUID()
        let draggedTab = SumiDragItem(tabId: UUID(), title: "Dragged")
        let essentialsDropHeight: CGFloat = 32
        registerSidebarSectionFrame(
            state,
            spaceId: spaceId,
            section: .essentials,
            frame: CGRect(x: 0, y: 0, width: 240, height: essentialsDropHeight)
        )
        registerSidebarEssentialsMetrics(
            state,
            spaceId: spaceId,
            frame: CGRect(x: 0, y: 0, width: 240, height: essentialsDropHeight),
            itemCount: 0,
            columnCount: 1,
            itemSize: CGSize(width: 96, height: 32),
            gridSpacing: 8
        )

        XCTAssertEqual(
            resolve(CGPoint(x: 80, y: 16), spaceId: spaceId, draggedItem: draggedTab).slot,
            .essentials(slot: 0)
        )
    }

    func testEmptySpacePinnedRevealBandResolvesToFirstSlot() {
        let spaceId = UUID()
        let draggedTab = SumiDragItem(tabId: UUID(), title: "Dragged")
        let pinnedDropHeight = SidebarRowLayout.rowHeight
        registerSidebarSectionFrame(
            state,
            spaceId: spaceId,
            section: .spacePinned,
            frame: CGRect(x: 0, y: 100, width: 240, height: pinnedDropHeight)
        )

        XCTAssertEqual(
            resolve(CGPoint(x: 80, y: 108), spaceId: spaceId, draggedItem: draggedTab).slot,
            .spacePinned(spaceId: spaceId, slot: 0)
        )
    }

    func testEssentialsResolutionUsesReportedColumnCount() {
        let spaceId = UUID()
        let draggedTab = SumiDragItem(tabId: UUID(), title: "Dragged")
        registerSidebarSectionFrame(
            state,
            spaceId: spaceId,
            section: .essentials,
            frame: CGRect(x: 0, y: 0, width: 228, height: 72)
        )
        registerSidebarEssentialsMetrics(
            state,
            spaceId: spaceId,
            frame: CGRect(x: 0, y: 0, width: 228, height: 72),
            itemCount: 4,
            columnCount: 2,
            itemSize: CGSize(width: 110, height: 32),
            gridSpacing: 8
        )

        XCTAssertEqual(
            resolve(CGPoint(x: 170, y: 18), spaceId: spaceId, draggedItem: draggedTab).slot,
            .essentials(slot: 1)
        )
        XCTAssertEqual(
            resolve(CGPoint(x: 24, y: 50), spaceId: spaceId, draggedItem: draggedTab).slot,
            .essentials(slot: 2)
        )
    }

    func testEssentialsDropFrameAllowsSecondRowPreviewBelowFullFirstRow() {
        let spaceId = UUID()
        let draggedTab = SumiDragItem(tabId: UUID(), title: "Dragged")
        registerSidebarSectionFrame(
            state,
            spaceId: spaceId,
            section: .essentials,
            frame: CGRect(x: 0, y: 0, width: 228, height: 32)
        )
        registerSidebarEssentialsMetrics(
            state,
            spaceId: spaceId,
            frame: CGRect(x: 0, y: 0, width: 228, height: 32),
            dropFrame: CGRect(x: 0, y: 0, width: 228, height: 72),
            itemCount: 3,
            columnCount: 3,
            rowCount: 1,
            itemSize: CGSize(width: 70, height: 32),
            gridSpacing: 8
        )

        let resolution = resolve(
            CGPoint(x: 24, y: 50),
            spaceId: spaceId,
            draggedItem: draggedTab
        )

        XCTAssertEqual(resolution.slot, .essentials(slot: 3))
    }

    func testEssentialsDropFrameStopsExtendingWhenCapacityReached() {
        let spaceId = UUID()
        let draggedTab = SumiDragItem(tabId: UUID(), title: "Dragged")
        registerSidebarSectionFrame(
            state,
            spaceId: spaceId,
            section: .essentials,
            frame: CGRect(x: 0, y: 0, width: 228, height: 152)
        )
        registerSidebarEssentialsMetrics(
            state,
            spaceId: spaceId,
            frame: CGRect(x: 0, y: 0, width: 228, height: 152),
            dropFrame: CGRect(x: 0, y: 0, width: 228, height: 152),
            itemCount: 12,
            columnCount: 3,
            rowCount: 4,
            itemSize: CGSize(width: 70, height: 32),
            gridSpacing: 8,
            canAcceptDrop: false
        )

        let resolution = resolve(
            CGPoint(x: 24, y: 170),
            spaceId: spaceId,
            draggedItem: draggedTab
        )

        XCTAssertEqual(resolution.slot, .empty)
    }

    func testEssentialsResolutionUsesExplicitSlotFramesForHoverPreviewAndFinalSlot() {
        let spaceId = UUID()
        let itemId = UUID()
        let draggedTab = SumiDragItem(tabId: itemId, title: "Dragged")
        let dropSlotFrames = [
            SidebarEssentialsDropSlotMetrics(
                slot: 0,
                frame: CGRect(x: 0, y: 0, width: 70, height: 32)
            ),
            SidebarEssentialsDropSlotMetrics(
                slot: 1,
                frame: CGRect(x: 80, y: 0, width: 70, height: 32)
            ),
            SidebarEssentialsDropSlotMetrics(
                slot: 2,
                frame: CGRect(x: 100, y: 40, width: 70, height: 32)
            ),
            SidebarEssentialsDropSlotMetrics(
                slot: 3,
                frame: CGRect(x: 0, y: 40, width: 70, height: 32)
            ),
        ]
        registerSidebarSectionFrame(
            state,
            spaceId: spaceId,
            section: .essentials,
            frame: CGRect(x: 0, y: 0, width: 180, height: 32)
        )
        registerSidebarEssentialsMetrics(
            state,
            spaceId: spaceId,
            frame: CGRect(x: 0, y: 0, width: 180, height: 32),
            dropFrame: CGRect(x: 0, y: 0, width: 180, height: 72),
            itemCount: 3,
            columnCount: 2,
            firstSyntheticRowSlot: 2,
            rowCount: 1,
            itemSize: CGSize(width: 70, height: 32),
            gridSpacing: 8,
            visibleItemCount: 3,
            visibleRowCount: 1,
            maxDropRowCount: 2,
            dropSlotFrames: dropSlotFrames
        )
        state.beginInternalDragSession(
            itemId: itemId,
            location: CGPoint(x: 30, y: 52),
            previewKind: .row,
            previewAssets: [
                .row: makePreviewAsset(),
                .essentialsTile: makePreviewAsset(),
            ]
        )

        let hoverResolution = SidebarDropResolver.updateState(
            location: CGPoint(x: 30, y: 52),
            state: state,
            draggedItem: draggedTab
        )
        let finalResolution = SidebarDropResolver.resolve(
            location: CGPoint(x: 30, y: 52),
            state: state,
            draggedItem: draggedTab
        )

        XCTAssertEqual(hoverResolution, finalResolution)
        XCTAssertEqual(state.hoveredSlot, .essentials(slot: 3))
        XCTAssertEqual(
            state.essentialsPreviewState(for: spaceId),
            SidebarEssentialsPreviewState(expandedDropRowCount: 2, ghostSlot: 3)
        )
    }

    func testInteractiveHoveredPageScopesEssentialsResolutionToSecondaryProfile() {
        let mainSpaceId = UUID()
        let secondarySpaceId = UUID()
        let mainProfileId = UUID()
        let secondaryProfileId = UUID()
        let draggedTab = SumiDragItem(tabId: UUID(), title: "Dragged")

        state.updatePageGeometry(
            spaceId: secondarySpaceId,
            profileId: secondaryProfileId,
            frame: CGRect(x: 0, y: 0, width: 260, height: 320),
            renderMode: .interactive
        )

        state.updateSectionFrame(
            spaceId: mainSpaceId,
            section: .essentials,
            frame: CGRect(x: 0, y: 0, width: 260, height: 72)
        )
        state.updateEssentialsLayoutMetrics(
            spaceId: mainSpaceId,
            profileId: mainProfileId,
            frame: CGRect(x: 0, y: 0, width: 260, height: 72),
            dropFrame: CGRect(x: 0, y: 0, width: 260, height: 72),
            itemCount: 4,
            columnCount: 2,
            rowCount: 2,
            itemSize: CGSize(width: 110, height: 32),
            gridSpacing: 8,
            canAcceptDrop: true
        )

        state.updateSectionFrame(
            spaceId: secondarySpaceId,
            section: .essentials,
            frame: CGRect(x: 0, y: 12, width: 260, height: 72)
        )
        state.updateEssentialsLayoutMetrics(
            spaceId: secondarySpaceId,
            profileId: secondaryProfileId,
            frame: CGRect(x: 0, y: 12, width: 260, height: 72),
            dropFrame: CGRect(x: 0, y: 12, width: 260, height: 72),
            itemCount: 4,
            columnCount: 3,
            rowCount: 2,
            itemSize: CGSize(width: 81, height: 32),
            gridSpacing: 8,
            canAcceptDrop: true
        )

        let resolution = SidebarDropResolver.resolve(
            location: CGPoint(x: 210, y: 30),
            state: state,
            draggedItem: draggedTab
        )

        XCTAssertEqual(resolution.slot, .essentials(slot: 2))
    }

    func testInteractiveHoveredPageScopesSpacePinnedResolutionToSecondarySpace() {
        let mainSpaceId = UUID()
        let secondarySpaceId = UUID()
        let draggedTab = SumiDragItem(tabId: UUID(), title: "Dragged")

        state.updatePageGeometry(
            spaceId: secondarySpaceId,
            profileId: UUID(),
            frame: CGRect(x: 0, y: 0, width: 260, height: 320),
            renderMode: .interactive
        )

        state.updateSectionFrame(
            spaceId: mainSpaceId,
            section: .spacePinned,
            frame: CGRect(x: 0, y: 80, width: 260, height: 120)
        )
        state.updateSectionFrame(
            spaceId: secondarySpaceId,
            section: .spacePinned,
            frame: CGRect(x: 0, y: 100, width: 260, height: 120)
        )

        let resolution = SidebarDropResolver.resolve(
            location: CGPoint(x: 90, y: 140),
            state: state,
            draggedItem: draggedTab
        )

        XCTAssertEqual(resolution.slot, .spacePinned(spaceId: secondarySpaceId, slot: 1))
    }

    func testCurrentDragScopeRejectsCrossSpaceDropTarget() {
        let currentSpaceId = UUID()
        let otherSpaceId = UUID()
        let draggedTab = SumiDragItem(tabId: UUID(), title: "Dragged")
        let scope = SidebarDragScope(
            spaceId: currentSpaceId,
            sourceContainer: .spaceRegular(currentSpaceId),
            sourceItemId: draggedTab.tabId,
            sourceItemKind: .tab
        )

        state.updatePageGeometry(
            spaceId: otherSpaceId,
            profileId: nil,
            frame: CGRect(x: 0, y: 0, width: 260, height: 320),
            renderMode: .interactive
        )
        state.updateSectionFrame(
            spaceId: otherSpaceId,
            section: .spacePinned,
            frame: CGRect(x: 0, y: 100, width: 260, height: 120)
        )

        let resolution = SidebarDropResolver.resolve(
            location: CGPoint(x: 90, y: 140),
            state: state,
            draggedItem: draggedTab,
            scope: scope
        )

        XCTAssertEqual(resolution.slot, .empty)
    }

    func testCurrentDragScopeRejectsCrossProfileDropTarget() {
        let spaceId = UUID()
        let currentProfileId = UUID()
        let otherProfileId = UUID()
        let draggedTab = SumiDragItem(tabId: UUID(), title: "Dragged")
        let scope = SidebarDragScope(
            spaceId: spaceId,
            profileId: currentProfileId,
            sourceContainer: .spaceRegular(spaceId),
            sourceItemId: draggedTab.tabId,
            sourceItemKind: .tab
        )

        state.updatePageGeometry(
            spaceId: spaceId,
            profileId: otherProfileId,
            frame: CGRect(x: 0, y: 0, width: 260, height: 320),
            renderMode: .interactive
        )
        state.updateSectionFrame(
            spaceId: spaceId,
            section: .essentials,
            frame: CGRect(x: 0, y: 0, width: 260, height: 72)
        )
        state.updateEssentialsLayoutMetrics(
            spaceId: spaceId,
            profileId: otherProfileId,
            frame: CGRect(x: 0, y: 0, width: 260, height: 72),
            dropFrame: CGRect(x: 0, y: 0, width: 260, height: 72),
            itemCount: 2,
            columnCount: 2,
            rowCount: 1,
            itemSize: CGSize(width: 110, height: 32),
            gridSpacing: 8,
            canAcceptDrop: true
        )

        let resolution = SidebarDropResolver.resolve(
            location: CGPoint(x: 90, y: 20),
            state: state,
            draggedItem: draggedTab,
            scope: scope
        )

        XCTAssertEqual(resolution.slot, .empty)
    }

    func testTransitionSnapshotPageIsNotAcceptedAsScopedDropTarget() {
        let spaceId = UUID()
        let draggedTab = SumiDragItem(tabId: UUID(), title: "Dragged")
        let scope = SidebarDragScope(
            spaceId: spaceId,
            sourceContainer: .spaceRegular(spaceId),
            sourceItemId: draggedTab.tabId,
            sourceItemKind: .tab
        )

        state.applyPageGeometry(
            spaceId: spaceId,
            profileId: nil,
            frame: CGRect(x: 0, y: 0, width: 260, height: 320),
            renderMode: .transitionSnapshot,
            generation: state.activeGeometryGeneration
        )
        state.updateSectionFrame(
            spaceId: spaceId,
            section: .spacePinned,
            frame: CGRect(x: 0, y: 100, width: 260, height: 120)
        )

        let resolution = SidebarDropResolver.resolve(
            location: CGPoint(x: 90, y: 140),
            state: state,
            draggedItem: draggedTab,
            scope: scope
        )

        XCTAssertEqual(resolution.slot, .empty)
    }

    func testDragScopeRejectsDifferentWindowId() {
        let sourceWindowId = UUID()
        let targetWindowId = UUID()
        let scope = SidebarDragScope(
            windowId: sourceWindowId,
            spaceId: UUID(),
            sourceContainer: .spaceRegular(UUID()),
            sourceItemId: UUID(),
            sourceItemKind: .tab
        )

        XCTAssertTrue(scope.matches(windowId: sourceWindowId))
        XCTAssertFalse(scope.matches(windowId: targetWindowId))
    }

    func testDropBelowExpandedFolderBlockResolvesRegularSectionInsteadOfFolder() {
        let spaceId = UUID()
        let folderId = UUID()
        let draggedTab = SumiDragItem(tabId: UUID(), title: "Dragged")
        registerFolder(
            folderId,
            spaceId: spaceId,
            topLevelIndex: 0,
            childCount: 2,
            isOpen: true,
            headerFrame: CGRect(x: 0, y: 100, width: 240, height: SidebarRowLayout.rowHeight),
            bodyFrame: CGRect(x: 0, y: 136, width: 240, height: SidebarRowLayout.rowHeight * 2),
            afterFrame: CGRect(x: 0, y: 208, width: 240, height: 18)
        )
        registerSidebarSectionFrame(
            state,
            spaceId: spaceId,
            section: .spaceRegular,
            frame: CGRect(x: 0, y: 226, width: 240, height: 120)
        )
        registerSidebarRegularHitTarget(
            state,
            spaceId: spaceId,
            frame: CGRect(x: 0, y: 226, width: 240, height: SidebarRowLayout.rowHeight * 2),
            itemCount: 2
        )

        XCTAssertEqual(
            resolve(CGPoint(x: 80, y: 232), spaceId: spaceId, draggedItem: draggedTab).slot,
            .spaceRegular(spaceId: spaceId, slot: 0)
        )
    }

    func testRegularListHitFrameIgnoresSectionChromeAndPreservesTailDrop() {
        let spaceId = UUID()
        let draggedTab = SumiDragItem(tabId: UUID(), title: "Dragged")
        registerSidebarSectionFrame(
            state,
            spaceId: spaceId,
            section: .spaceRegular,
            frame: CGRect(x: 0, y: 300, width: 240, height: 220)
        )
        registerSidebarRegularHitTarget(
            state,
            spaceId: spaceId,
            frame: CGRect(x: 0, y: 340, width: 240, height: SidebarRowLayout.rowHeight * 3),
            itemCount: 3
        )

        XCTAssertEqual(
            resolve(CGPoint(x: 80, y: 320), spaceId: spaceId, draggedItem: draggedTab).slot,
            .empty
        )
        XCTAssertEqual(
            resolve(CGPoint(x: 80, y: 341), spaceId: spaceId, draggedItem: draggedTab).slot,
            .spaceRegular(spaceId: spaceId, slot: 0)
        )
        XCTAssertEqual(
            resolve(CGPoint(x: 80, y: 377), spaceId: spaceId, draggedItem: draggedTab).slot,
            .spaceRegular(spaceId: spaceId, slot: 1)
        )
        XCTAssertEqual(
            resolve(CGPoint(x: 80, y: 455), spaceId: spaceId, draggedItem: draggedTab).slot,
            .spaceRegular(spaceId: spaceId, slot: 3)
        )
    }

    private func resolve(
        _ location: CGPoint,
        spaceId: UUID,
        draggedItem: SumiDragItem?
    ) -> SidebarDropResolution {
        ensureSidebarInteractivePage(state, spaceId: spaceId)
        return SidebarDropResolver.resolve(
            location: location,
            state: state,
            draggedItem: draggedItem
        )
    }

    private func registerFolder(
        _ folderId: UUID,
        spaceId: UUID,
        topLevelIndex: Int,
        childCount: Int,
        isOpen: Bool,
        headerFrame: CGRect? = nil,
        bodyFrame: CGRect? = nil,
        afterFrame: CGRect? = nil,
        childFrames: [CGRect] = []
    ) {
        if let headerFrame {
            state.updateFolderDropTarget(
                folderId: folderId,
                spaceId: spaceId,
                topLevelIndex: topLevelIndex,
                childCount: childCount,
                isOpen: isOpen,
                region: .header,
                frame: headerFrame
            )
        }

        if let bodyFrame {
            state.updateFolderDropTarget(
                folderId: folderId,
                spaceId: spaceId,
                topLevelIndex: topLevelIndex,
                childCount: childCount,
                isOpen: isOpen,
                region: .body,
                frame: bodyFrame
            )
        }

        if let afterFrame {
            state.updateFolderDropTarget(
                folderId: folderId,
                spaceId: spaceId,
                topLevelIndex: topLevelIndex,
                childCount: childCount,
                isOpen: isOpen,
                region: .after,
                frame: afterFrame
            )
        }

        for (index, childFrame) in childFrames.enumerated() {
            state.updateFolderChildDropTarget(
                folderId: folderId,
                childId: UUID(),
                index: index,
                frame: childFrame
            )
        }
    }

    private func registerTopLevelPinnedItem(
        itemId: UUID,
        kind: SidebarTopLevelPinnedItemKind,
        spaceId: UUID,
        topLevelIndex: Int,
        frame: CGRect
    ) {
        state.updateTopLevelPinnedItemTarget(
            itemId: itemId,
            kind: kind,
            spaceId: spaceId,
            topLevelIndex: topLevelIndex,
            frame: frame
        )
    }

    private func makePreviewAsset() -> SidebarDragPreviewAsset {
        let imageSize = CGSize(width: 80, height: 32)
        let image = NSImage(size: imageSize)
        return SidebarDragPreviewAsset(
            image: image,
            size: imageSize,
            anchorOffset: CGPoint(x: 8, y: 8)
        )
    }

    private func resetState() {
        state = SidebarDragState()
    }

}

@MainActor
final class SidebarDragStateTests: XCTestCase {
    private var state: SidebarDragState!

    override func setUp() {
        super.setUp()
        state = SidebarDragState()
    }

    override func tearDown() {
        state = nil
        super.tearDown()
    }

    func testBeginInternalDragSessionPublishesImmediatePreviewState() {
        let itemId = UUID()
        let location = CGPoint(x: 42, y: 64)
        let previewLocation = CGPoint(x: 42, y: 96)

        state.beginInternalDragSession(
            itemId: itemId,
            location: location,
            previewLocation: previewLocation,
            previewKind: .row,
            previewAssets: [.row: makePreviewAsset()]
        )

        XCTAssertTrue(state.isDragging)
        XCTAssertTrue(state.isInternalDragSession)
        XCTAssertEqual(state.activeDragItemId, itemId)
        XCTAssertEqual(state.dragLocation, location)
        XCTAssertEqual(state.previewDragLocation, previewLocation)
        XCTAssertEqual(state.previewKind, .row)
        XCTAssertNotNil(state.previewAssets[.row])
    }

    func testDropResolverUpdatesLogicalAndPreviewLocationsSeparately() {
        let itemId = UUID()
        state.beginInternalDragSession(
            itemId: itemId,
            location: CGPoint(x: 0, y: 0),
            previewKind: .row,
            previewAssets: [.row: makePreviewAsset()]
        )

        SidebarDropResolver.updateState(
            location: CGPoint(x: 24, y: 48),
            previewLocation: CGPoint(x: 24, y: 120),
            state: state,
            draggedItem: SumiDragItem(tabId: itemId, title: "Dragged")
        )

        XCTAssertEqual(state.dragLocation, CGPoint(x: 24, y: 48))
        XCTAssertEqual(state.previewDragLocation, CGPoint(x: 24, y: 120))
    }

    func testResetInteractionStateClearsPreviewAndHoverState() {
        let itemId = UUID()
        let folderId = UUID()
        let spaceId = UUID()
        state.beginInternalDragSession(
            itemId: itemId,
            location: CGPoint(x: 12, y: 18),
            previewKind: .row,
            previewAssets: [.row: makePreviewAsset()]
        )
        state.hoveredSlot = .spaceRegular(spaceId: spaceId, slot: 1)
        state.folderDropIntent = .contain(folderId: folderId)
        state.activeHoveredFolderId = folderId
        state.activeSplitTarget = .left
        registerSidebarEssentialsMetrics(
            state,
            spaceId: spaceId,
            frame: CGRect(x: 0, y: 0, width: 200, height: 32),
            itemCount: 0,
            columnCount: 1,
            itemSize: CGSize(width: 96, height: 32),
            gridSpacing: 8
        )

        state.resetInteractionState()

        XCTAssertFalse(state.isDragging)
        XCTAssertEqual(state.hoveredSlot, .empty)
        XCTAssertEqual(state.folderDropIntent, .none)
        XCTAssertNil(state.activeHoveredFolderId)
        XCTAssertNil(state.activeSplitTarget)
        XCTAssertNil(state.activeDragItemId)
        XCTAssertNil(state.dragLocation)
        XCTAssertNil(state.previewKind)
        XCTAssertTrue(state.previewAssets.isEmpty)
        XCTAssertFalse(state.isInternalDragSession)
        XCTAssertFalse(state.essentialsLayoutMetricsBySpace.isEmpty)
        XCTAssertFalse(state.pageGeometryByKey.isEmpty)
    }

    func testGeometryRevisionIsCoalescedPerMainQueueTurn() async {
        await drainMainQueue()
        let initialRevision = state.geometryRevision

        state.requestGeometryRefresh()
        state.requestGeometryRefresh()
        state.requestGeometryRefresh()
        state.requestGeometryRefresh()

        XCTAssertEqual(state.geometryRevision, initialRevision)

        await drainMainQueue()
        let firstRevision = state.geometryRevision

        XCTAssertEqual(firstRevision, initialRevision + 1)

        state.requestGeometryRefresh()
        await drainMainQueue()

        XCTAssertEqual(state.geometryRevision, firstRevision + 1)
    }

    func testGeometrySnapshotPublishesOncePerMainQueueTurn() async {
        let spaceId = UUID()
        let initialSnapshot = state.geometrySnapshot

        state.updatePageGeometry(
            spaceId: spaceId,
            profileId: nil,
            frame: CGRect(x: 0, y: 0, width: 200, height: 300),
            renderMode: .interactive,
            publish: false
        )
        state.updateSectionFrame(
            spaceId: spaceId,
            section: .spaceRegular,
            frame: CGRect(x: 0, y: 0, width: 200, height: 40),
            publish: false
        )

        XCTAssertEqual(state.geometrySnapshot, initialSnapshot)

        await drainMainQueue()

        XCTAssertEqual(
            state.geometrySnapshot.pageGeometryByKey[SidebarPageGeometryKey(spaceId: spaceId, profileId: nil)]?.frame,
            CGRect(x: 0, y: 0, width: 200, height: 300)
        )
        XCTAssertEqual(
            state.geometrySnapshot.sectionFramesBySpace[SidebarSectionGeometryKey(spaceId: spaceId, section: .spaceRegular)],
            CGRect(x: 0, y: 0, width: 200, height: 40)
        )
    }

    func testResetInteractionStatePreservesGeometryCaches() {
        let spaceId = UUID()

        state.updatePageGeometry(
            spaceId: spaceId,
            profileId: nil,
            frame: CGRect(x: 0, y: 0, width: 240, height: 360),
            renderMode: .interactive
        )
        state.updateSectionFrame(
            spaceId: spaceId,
            section: .spacePinned,
            frame: CGRect(x: 0, y: 80, width: 240, height: 120)
        )
        state.updateEssentialsLayoutMetrics(
            spaceId: spaceId,
            profileId: nil,
            frame: CGRect(x: 0, y: 0, width: 240, height: 32),
            dropFrame: CGRect(x: 0, y: 0, width: 240, height: 72),
            itemCount: 3,
            columnCount: 3,
            rowCount: 1,
            itemSize: CGSize(width: 72, height: 32),
            gridSpacing: 8,
            canAcceptDrop: true,
            visibleItemCount: 3,
            visibleRowCount: 1,
            maxDropRowCount: 2
        )
        state.beginInternalDragSession(
            itemId: UUID(),
            location: CGPoint(x: 32, y: 44),
            previewKind: .row,
            previewAssets: [.row: makePreviewAsset()]
        )

        state.resetInteractionState()

        XCTAssertFalse(state.isDragging)
        XCTAssertEqual(state.sidebarGeometryGeneration, 0)
        XCTAssertEqual(state.pageGeometryByKey.count, 1)
        XCTAssertNotNil(state.sectionFrame(for: .spacePinned, in: spaceId))
        XCTAssertNotNil(state.essentialsLayoutMetricsBySpace[spaceId])
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
        await Task.yield()
    }

    func testEssentialsPreviewStateLatchesExpandedRowInsideDropFrame() {
        let spaceId = UUID()
        let itemId = UUID()

        state.updatePageGeometry(
            spaceId: spaceId,
            profileId: nil,
            frame: CGRect(x: 0, y: 0, width: 240, height: 360),
            renderMode: .interactive
        )
        state.updateEssentialsLayoutMetrics(
            spaceId: spaceId,
            profileId: nil,
            frame: CGRect(x: 0, y: 0, width: 240, height: 32),
            dropFrame: CGRect(x: 0, y: 0, width: 240, height: 72),
            itemCount: 3,
            columnCount: 3,
            rowCount: 1,
            itemSize: CGSize(width: 72, height: 32),
            gridSpacing: 8,
            canAcceptDrop: true,
            visibleItemCount: 3,
            visibleRowCount: 1,
            maxDropRowCount: 2
        )
        state.beginInternalDragSession(
            itemId: itemId,
            location: CGPoint(x: 32, y: 48),
            previewKind: .row,
            previewAssets: [
                .row: makePreviewAsset(),
                .essentialsTile: makePreviewAsset(),
            ]
        )

        SidebarDropResolver.updateState(
            location: CGPoint(x: 32, y: 48),
            state: state,
            draggedItem: SumiDragItem(tabId: itemId, title: "Dragged")
        )

        XCTAssertEqual(state.hoveredSlot, .essentials(slot: 3))
        XCTAssertEqual(
            state.essentialsPreviewState(for: spaceId),
            SidebarEssentialsPreviewState(expandedDropRowCount: 2, ghostSlot: 3)
        )

        state.resetInteractionState()
        XCTAssertNil(state.essentialsPreviewState(for: spaceId))
    }

    func testEssentialsPreviewStateDoesNotLatchSecondRowForThirdTile() {
        let spaceId = UUID()
        let itemId = UUID()

        state.updatePageGeometry(
            spaceId: spaceId,
            profileId: nil,
            frame: CGRect(x: 0, y: 0, width: 240, height: 360),
            renderMode: .interactive
        )
        state.updateEssentialsLayoutMetrics(
            spaceId: spaceId,
            profileId: nil,
            frame: CGRect(x: 0, y: 0, width: 240, height: 32),
            dropFrame: CGRect(x: 0, y: 0, width: 240, height: 32),
            itemCount: 3,
            columnCount: 3,
            rowCount: 1,
            itemSize: CGSize(width: 72, height: 32),
            gridSpacing: 8,
            canAcceptDrop: true,
            visibleItemCount: 2,
            visibleRowCount: 1,
            maxDropRowCount: 1
        )
        state.beginInternalDragSession(
            itemId: itemId,
            location: CGPoint(x: 170, y: 16),
            previewKind: .row,
            previewAssets: [
                .row: makePreviewAsset(),
                .essentialsTile: makePreviewAsset(),
            ]
        )

        SidebarDropResolver.updateState(
            location: CGPoint(x: 170, y: 16),
            state: state,
            draggedItem: SumiDragItem(tabId: itemId, title: "Dragged")
        )

        XCTAssertEqual(state.hoveredSlot, .essentials(slot: 2))
        XCTAssertNil(state.essentialsPreviewState(for: spaceId))
    }

    func testPendingGeometryEpochPreservesActiveGeometryUntilCommittedPagePublishes() {
        let mainSpaceId = UUID()
        let secondarySpaceId = UUID()
        let mainProfileId = UUID()
        let secondaryProfileId = UUID()

        state.updatePageGeometry(
            spaceId: mainSpaceId,
            profileId: mainProfileId,
            frame: CGRect(x: 0, y: 0, width: 240, height: 360),
            renderMode: .interactive
        )
        state.updateSectionFrame(
            spaceId: mainSpaceId,
            section: .essentials,
            frame: CGRect(x: 0, y: 0, width: 240, height: 32)
        )
        state.updateSectionFrame(
            spaceId: mainSpaceId,
            section: .spacePinned,
            frame: CGRect(x: 0, y: 80, width: 240, height: 120)
        )
        state.updateSectionFrame(
            spaceId: mainSpaceId,
            section: .spaceRegular,
            frame: CGRect(x: 0, y: 220, width: 240, height: 120)
        )
        state.updateEssentialsLayoutMetrics(
            spaceId: mainSpaceId,
            profileId: mainProfileId,
            frame: CGRect(x: 0, y: 0, width: 240, height: 32),
            dropFrame: CGRect(x: 0, y: 0, width: 240, height: 32),
            itemCount: 3,
            columnCount: 3,
            rowCount: 1,
            itemSize: CGSize(width: 72, height: 32),
            gridSpacing: 8,
            canAcceptDrop: true
        )
        state.updateRegularListHitTarget(
            spaceId: mainSpaceId,
            frame: CGRect(x: 0, y: 220, width: 240, height: SidebarRowLayout.rowHeight * 2),
            itemCount: 2
        )

        state.beginPendingGeometryEpoch(
            expectedSpaceId: secondarySpaceId,
            profileId: secondaryProfileId
        )

        XCTAssertEqual(state.activeGeometryGeneration, 0)
        XCTAssertEqual(state.pendingGeometryGeneration, 1)
        XCTAssertEqual(state.interactivePage(for: mainSpaceId)?.spaceId, mainSpaceId)

        let draggedTab = SumiDragItem(tabId: UUID(), title: "Dragged")
        let mainResolution = SidebarDropResolver.resolve(
            location: CGPoint(x: 80, y: 140),
            state: state,
            draggedItem: draggedTab
        )
        XCTAssertEqual(mainResolution.slot, .spacePinned(spaceId: mainSpaceId, slot: 2))

        guard let pendingGeneration = state.pendingGeometryGeneration else {
            return XCTFail("Missing pending generation")
        }

        state.applyPageGeometry(
            spaceId: secondarySpaceId,
            profileId: secondaryProfileId,
            frame: CGRect(x: 0, y: 0, width: 260, height: 360),
            renderMode: .interactive,
            generation: pendingGeneration
        )
        state.applySectionFrame(
            spaceId: secondarySpaceId,
            section: .essentials,
            frame: CGRect(x: 0, y: 0, width: 260, height: 32),
            generation: pendingGeneration
        )
        state.applySectionFrame(
            spaceId: secondarySpaceId,
            section: .spacePinned,
            frame: CGRect(x: 0, y: 90, width: 260, height: 120),
            generation: pendingGeneration
        )
        state.applySectionFrame(
            spaceId: secondarySpaceId,
            section: .spaceRegular,
            frame: CGRect(x: 0, y: 230, width: 260, height: 120),
            generation: pendingGeneration
        )
        state.applyEssentialsLayoutMetrics(
            spaceId: secondarySpaceId,
            profileId: secondaryProfileId,
            frame: CGRect(x: 0, y: 0, width: 260, height: 32),
            dropFrame: CGRect(x: 0, y: 0, width: 260, height: 32),
            itemCount: 3,
            columnCount: 3,
            rowCount: 1,
            itemSize: CGSize(width: 78, height: 32),
            gridSpacing: 8,
            canAcceptDrop: true,
            visibleItemCount: 3,
            visibleRowCount: 1,
            maxDropRowCount: 1,
            generation: pendingGeneration
        )
        state.applyRegularListHitTarget(
            spaceId: secondarySpaceId,
            frame: CGRect(x: 0, y: 230, width: 260, height: SidebarRowLayout.rowHeight * 2),
            itemCount: 2,
            generation: pendingGeneration
        )
        state.publishGeometrySnapshotForTesting()

        XCTAssertEqual(state.pendingGeometryGeneration, nil)
        XCTAssertEqual(state.activeGeometryGeneration, pendingGeneration)
        XCTAssertEqual(state.interactivePage(for: secondarySpaceId)?.spaceId, secondarySpaceId)
        XCTAssertNil(state.interactivePage(for: mainSpaceId))

        let secondaryResolution = SidebarDropResolver.resolve(
            location: CGPoint(x: 80, y: 140),
            state: state,
            draggedItem: draggedTab
        )
        XCTAssertEqual(
            secondaryResolution.slot,
            .spacePinned(spaceId: secondarySpaceId, slot: 1)
        )
    }

    func testSnapshotPageGeometryDoesNotPromotePendingRuntimeStore() {
        let mainSpaceId = UUID()
        let secondarySpaceId = UUID()
        let mainProfileId = UUID()
        let secondaryProfileId = UUID()

        state.updatePageGeometry(
            spaceId: mainSpaceId,
            profileId: mainProfileId,
            frame: CGRect(x: 0, y: 0, width: 240, height: 360),
            renderMode: .interactive
        )
        state.updateSectionFrame(
            spaceId: mainSpaceId,
            section: .essentials,
            frame: CGRect(x: 0, y: 0, width: 240, height: 32)
        )
        state.updateSectionFrame(
            spaceId: mainSpaceId,
            section: .spacePinned,
            frame: CGRect(x: 0, y: 80, width: 240, height: 120)
        )
        state.updateSectionFrame(
            spaceId: mainSpaceId,
            section: .spaceRegular,
            frame: CGRect(x: 0, y: 220, width: 240, height: 120)
        )
        state.updateEssentialsLayoutMetrics(
            spaceId: mainSpaceId,
            profileId: mainProfileId,
            frame: CGRect(x: 0, y: 0, width: 240, height: 32),
            dropFrame: CGRect(x: 0, y: 0, width: 240, height: 32),
            itemCount: 3,
            columnCount: 3,
            rowCount: 1,
            itemSize: CGSize(width: 72, height: 32),
            gridSpacing: 8,
            canAcceptDrop: true
        )
        state.updateRegularListHitTarget(
            spaceId: mainSpaceId,
            frame: CGRect(x: 0, y: 220, width: 240, height: SidebarRowLayout.rowHeight * 2),
            itemCount: 2
        )

        state.beginPendingGeometryEpoch(
            expectedSpaceId: secondarySpaceId,
            profileId: secondaryProfileId
        )

        guard let pendingGeneration = state.pendingGeometryGeneration else {
            return XCTFail("Missing pending generation")
        }

        state.applyPageGeometry(
            spaceId: secondarySpaceId,
            profileId: secondaryProfileId,
            frame: CGRect(x: 0, y: 0, width: 260, height: 360),
            renderMode: .transitionSnapshot,
            generation: pendingGeneration
        )
        state.applySectionFrame(
            spaceId: secondarySpaceId,
            section: .essentials,
            frame: CGRect(x: 0, y: 0, width: 260, height: 32),
            generation: pendingGeneration
        )
        state.applySectionFrame(
            spaceId: secondarySpaceId,
            section: .spacePinned,
            frame: CGRect(x: 0, y: 90, width: 260, height: 120),
            generation: pendingGeneration
        )
        state.applySectionFrame(
            spaceId: secondarySpaceId,
            section: .spaceRegular,
            frame: CGRect(x: 0, y: 230, width: 260, height: 120),
            generation: pendingGeneration
        )
        state.applyEssentialsLayoutMetrics(
            spaceId: secondarySpaceId,
            profileId: secondaryProfileId,
            frame: CGRect(x: 0, y: 0, width: 260, height: 32),
            dropFrame: CGRect(x: 0, y: 0, width: 260, height: 32),
            itemCount: 3,
            columnCount: 3,
            rowCount: 1,
            itemSize: CGSize(width: 78, height: 32),
            gridSpacing: 8,
            canAcceptDrop: true,
            visibleItemCount: 3,
            visibleRowCount: 1,
            maxDropRowCount: 1,
            generation: pendingGeneration
        )
        state.applyRegularListHitTarget(
            spaceId: secondarySpaceId,
            frame: CGRect(x: 0, y: 230, width: 260, height: SidebarRowLayout.rowHeight * 2),
            itemCount: 2,
            generation: pendingGeneration
        )

        XCTAssertEqual(state.activeGeometryGeneration, 0)
        XCTAssertEqual(state.pendingGeometryGeneration, pendingGeneration)
        XCTAssertEqual(state.interactivePage(for: mainSpaceId)?.spaceId, mainSpaceId)
        XCTAssertNil(state.interactivePage(for: secondarySpaceId))

        let resolution = SidebarDropResolver.resolve(
            location: CGPoint(x: 80, y: 140),
            state: state,
            draggedItem: SumiDragItem(tabId: UUID(), title: "Dragged")
        )
        XCTAssertEqual(resolution.slot, .spacePinned(spaceId: mainSpaceId, slot: 2))
    }

    func testFloatingPreviewPolicyPromotesRowToEssentialsTileOnEssentialsHover() {
        let rowAsset = makePreviewAsset()
        let tileAsset = makePreviewAsset()
        let folderAsset = makePreviewAsset()

        XCTAssertEqual(
            SidebarFloatingDragPreviewPolicy.resolvedPreviewKind(
                baseKind: .row,
                hoveredSlot: .essentials(slot: 0),
                previewAssets: [
                    .row: rowAsset,
                    .essentialsTile: tileAsset,
                ]
            ),
            .essentialsTile
        )
        XCTAssertEqual(
            SidebarFloatingDragPreviewPolicy.resolvedPreviewKind(
                baseKind: .row,
                hoveredSlot: .spaceRegular(spaceId: UUID(), slot: 0),
                previewAssets: [.row: rowAsset]
            ),
            .row
        )
        XCTAssertEqual(
            SidebarFloatingDragPreviewPolicy.resolvedPreviewKind(
                baseKind: .essentialsTile,
                hoveredSlot: .spacePinned(spaceId: UUID(), slot: 0),
                previewAssets: [
                    .row: rowAsset,
                    .essentialsTile: tileAsset,
                ]
            ),
            .row
        )
        XCTAssertEqual(
            SidebarFloatingDragPreviewPolicy.resolvedPreviewKind(
                baseKind: .essentialsTile,
                hoveredSlot: .folder(folderId: UUID(), slot: 0),
                previewAssets: [
                    .row: rowAsset,
                    .essentialsTile: tileAsset,
                ]
            ),
            .row
        )
        XCTAssertEqual(
            SidebarFloatingDragPreviewPolicy.resolvedPreviewKind(
                baseKind: .folderRow,
                hoveredSlot: .essentials(slot: 0),
                previewAssets: [
                    .folderRow: folderAsset,
                    .essentialsTile: tileAsset,
                ]
            ),
            .folderRow
        )
    }

    func testFloatingPreviewModelPolicyUsesDropZoneAsSourceOfTruth() {
        let model = makePreviewModel(baseKind: .essentialsTile)

        XCTAssertEqual(
            SidebarFloatingDragPreviewPolicy.resolvedPreviewKind(
                model: model,
                hoveredSlot: .essentials(slot: 0)
            ),
            .essentialsTile
        )
        XCTAssertEqual(
            SidebarFloatingDragPreviewPolicy.resolvedPreviewKind(
                model: model,
                hoveredSlot: .spacePinned(spaceId: UUID(), slot: 0)
            ),
            .row
        )
        XCTAssertEqual(
            SidebarFloatingDragPreviewPolicy.resolvedPreviewKind(
                model: model,
                hoveredSlot: .spaceRegular(spaceId: UUID(), slot: 0)
            ),
            .row
        )
        XCTAssertEqual(
            SidebarFloatingDragPreviewPolicy.resolvedPreviewKind(
                model: model,
                hoveredSlot: .folder(folderId: UUID(), slot: 0)
            ),
            .row
        )

        let regularModel = makePreviewModel(baseKind: .row)
        XCTAssertEqual(
            SidebarFloatingDragPreviewPolicy.resolvedPreviewKind(
                model: regularModel,
                hoveredSlot: .essentials(slot: 0)
            ),
            .essentialsTile
        )

        let folderModel = makePreviewModel(
            item: SumiDragItem.folder(folderId: UUID(), title: "Folder"),
            baseKind: .folderRow
        )
        XCTAssertEqual(
            SidebarFloatingDragPreviewPolicy.resolvedPreviewKind(
                model: folderModel,
                hoveredSlot: .essentials(slot: 0)
            ),
            .folderRow
        )
    }

    func testPreviewModelAnchorUsesTopLeadingCoordinates() {
        let normalized = SidebarDragPreviewModel.normalizedTopLeadingAnchor(
            fromBottomLeading: CGPoint(x: 25, y: 15),
            in: CGSize(width: 100, height: 60)
        )
        let model = makePreviewModel(
            normalizedTopLeadingAnchor: normalized
        )

        XCTAssertEqual(normalized.x, 0.25, accuracy: 0.001)
        XCTAssertEqual(normalized.y, 0.75, accuracy: 0.001)
        XCTAssertEqual(
            model.anchorOffset(in: CGSize(width: 200, height: 40)),
            CGPoint(x: 50, y: 30)
        )
    }

    func testSourceSideUpdateResolvesHoveredSlotImmediately() {
        let spaceId = UUID()
        let itemId = UUID()
        let location = CGPoint(x: 64, y: 3)

        registerSidebarSectionFrame(
            state,
            spaceId: spaceId,
            section: .essentials,
            frame: CGRect(x: 0, y: 0, width: 240, height: 6)
        )
        registerSidebarEssentialsMetrics(
            state,
            spaceId: spaceId,
            frame: CGRect(x: 0, y: 0, width: 240, height: 6),
            itemCount: 0,
            columnCount: 1,
            itemSize: CGSize(width: 96, height: 32),
            gridSpacing: 8
        )
        state.beginInternalDragSession(
            itemId: itemId,
            location: location,
            previewKind: .row,
            previewAssets: [.row: makePreviewAsset()]
        )

        SidebarDropResolver.updateState(
            location: location,
            state: state,
            draggedItem: SumiDragItem(tabId: itemId, title: "Dragged")
        )

        XCTAssertEqual(state.dragLocation, location)
        XCTAssertEqual(state.hoveredSlot, .essentials(slot: 0))
        XCTAssertEqual(state.folderDropIntent, .none)
        XCTAssertNil(state.activeHoveredFolderId)
    }

    func testSourceSideUpdateTracksMoveWithoutOverlayReentry() {
        let spaceId = UUID()
        let itemId = UUID()

        registerSidebarSectionFrame(
            state,
            spaceId: spaceId,
            section: .spaceRegular,
            frame: CGRect(x: 0, y: 200, width: 240, height: 120)
        )
        registerSidebarRegularHitTarget(
            state,
            spaceId: spaceId,
            frame: CGRect(x: 0, y: 200, width: 240, height: SidebarRowLayout.rowHeight * 2),
            itemCount: 2
        )
        state.beginInternalDragSession(
            itemId: itemId,
            location: CGPoint(x: 80, y: 210),
            previewKind: .row,
            previewAssets: [.row: makePreviewAsset()]
        )

        SidebarDropResolver.updateState(
            location: CGPoint(x: 80, y: 210),
            state: state,
            draggedItem: SumiDragItem(tabId: itemId, title: "Dragged")
        )
        XCTAssertEqual(state.hoveredSlot, .spaceRegular(spaceId: spaceId, slot: 0))

        SidebarDropResolver.updateState(
            location: CGPoint(x: 80, y: 274),
            state: state,
            draggedItem: SumiDragItem(tabId: itemId, title: "Dragged")
        )
        XCTAssertEqual(state.hoveredSlot, .spaceRegular(spaceId: spaceId, slot: 2))
    }

    private func makePreviewAsset() -> SidebarDragPreviewAsset {
        let imageSize = CGSize(width: 12, height: 12)
        let image = NSImage(size: imageSize)
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: imageSize)).fill()
        image.unlockFocus()
        return SidebarDragPreviewAsset(
            image: image,
            size: imageSize,
            anchorOffset: .zero
        )
    }

    private func makePreviewModel(
        item: SumiDragItem = SumiDragItem(tabId: UUID(), title: "Dragged"),
        baseKind: SidebarDragPreviewKind = .row,
        normalizedTopLeadingAnchor: CGPoint = CGPoint(x: 0.5, y: 0.5)
    ) -> SidebarDragPreviewModel {
        SidebarDragPreviewModel(
            item: item,
            sourceZone: .essentials,
            baseKind: baseKind,
            previewIcon: Image(systemName: "globe"),
            chromeTemplateSystemImageName: nil,
            sourceSize: CGSize(width: 48, height: 48),
            normalizedTopLeadingAnchor: normalizedTopLeadingAnchor,
            pinnedConfig: .large,
            shortcutPresentationState: .launcherOnly,
            folderGlyphPresentation: nil,
            folderGlyphPalette: nil
        )
    }
}

@MainActor
final class SidebarEssentialsProjectionPolicyTests: XCTestCase {
    private var state: SidebarDragState!

    override func setUp() {
        super.setUp()
        state = SidebarDragState()
    }

    override func tearDown() {
        state = nil
        super.tearDown()
    }

    func testProjectedLayoutStretchesSingleTileToFullRow() {
        let configuration = PinnedTabsConfiguration.large
        let pins = [makeEssentialPin(index: 0)]
        let width = (CGFloat(3) * configuration.minWidth) + (CGFloat(2) * configuration.gridSpacing)

        let projection = SidebarEssentialsProjectionPolicy.make(
            items: pins,
            width: width,
            configuration: configuration,
            dragState: state
        )

        XCTAssertEqual(projection.columnCount, 3)
        XCTAssertEqual(projection.rows.count, 1)
        XCTAssertEqual(projection.rows.first?.visualColumnCount, 1)
        XCTAssertEqual(projection.rows.first?.tileSize.width ?? 0, width, accuracy: 0.001)
    }

    func testProjectedLayoutSplitsTwoTilesAcrossOneRow() {
        let configuration = PinnedTabsConfiguration.large
        let pins = [
            makeEssentialPin(index: 0),
            makeEssentialPin(index: 1),
        ]
        let width = (CGFloat(3) * configuration.minWidth) + (CGFloat(2) * configuration.gridSpacing)
        let expectedTileWidth = (width - configuration.gridSpacing) / 2

        let projection = SidebarEssentialsProjectionPolicy.make(
            items: pins,
            width: width,
            configuration: configuration,
            dragState: state
        )

        XCTAssertEqual(projection.columnCount, 3)
        XCTAssertEqual(projection.rows.count, 1)
        XCTAssertEqual(projection.rows.first?.visualColumnCount, 2)
        XCTAssertEqual(projection.rows.first?.tileSize.width ?? 0, expectedTileWidth, accuracy: 0.001)
    }

    func testProjectedLayoutKeepsThirdTileInFirstRow() {
        let configuration = PinnedTabsConfiguration.large
        let pins = [
            makeEssentialPin(index: 0),
            makeEssentialPin(index: 1),
        ]
        let width = (CGFloat(3) * configuration.minWidth) + (CGFloat(2) * configuration.gridSpacing)

        state.beginInternalDragSession(
            itemId: UUID(),
            location: .zero,
            previewKind: .row,
            previewAssets: [
                .row: makePreviewAsset(),
                .essentialsTile: makePreviewAsset(),
            ]
        )
        state.hoveredSlot = .essentials(slot: 2)

        let projection = SidebarEssentialsProjectionPolicy.make(
            items: pins,
            width: width,
            configuration: configuration,
            dragState: state
        )

        XCTAssertEqual(projection.projectedItemCount, 3)
        XCTAssertEqual(projection.columnCount, 3)
        XCTAssertEqual(projection.rows.count, 1)
        XCTAssertEqual(projection.rows.first?.visualColumnCount, 3)
        XCTAssertEqual(projection.layoutItems.map { $0?.id }, [pins[0].id, pins[1].id, nil])
        XCTAssertEqual(
            SidebarEssentialsProjectionPolicy.neededRowCountAfterDrop(
                itemIDs: pins.map(\.id),
                visibleItemCount: projection.visibleItemCount,
                layoutItemCount: projection.projectedItemCount,
                columnCount: projection.columnCount,
                canAcceptDrop: projection.canAcceptDrop,
                dragState: state
            ),
            1
        )
    }

    func testProjectedLayoutStartsSecondRowAtFourthTile() {
        let configuration = PinnedTabsConfiguration.large
        let pins = [
            makeEssentialPin(index: 0),
            makeEssentialPin(index: 1),
            makeEssentialPin(index: 2),
        ]
        let width = (CGFloat(4) * configuration.minWidth) + (CGFloat(3) * configuration.gridSpacing)

        state.beginInternalDragSession(
            itemId: UUID(),
            location: .zero,
            previewKind: .row,
            previewAssets: [
                .row: makePreviewAsset(),
                .essentialsTile: makePreviewAsset(),
            ]
        )
        state.hoveredSlot = .essentials(slot: 3)

        let projection = SidebarEssentialsProjectionPolicy.make(
            items: pins,
            width: width,
            configuration: configuration,
            dragState: state
        )

        XCTAssertEqual(projection.projectedItemCount, 4)
        XCTAssertEqual(projection.columnCount, 3)
        XCTAssertEqual(projection.rows.count, 2)
        XCTAssertEqual(projection.rows.first?.visualColumnCount, 3)
        XCTAssertEqual(projection.rows.last?.visualColumnCount, 1)
        XCTAssertEqual(projection.rows.last?.tileSize.width ?? 0, width, accuracy: 0.001)
        XCTAssertEqual(projection.layoutItems.map { $0?.id }, [pins[0].id, pins[1].id, pins[2].id, nil])
    }

    func testProjectedLayoutStretchesFourthCommittedTileOnSecondRow() {
        let configuration = PinnedTabsConfiguration.large
        let pins = [
            makeEssentialPin(index: 0),
            makeEssentialPin(index: 1),
            makeEssentialPin(index: 2),
            makeEssentialPin(index: 3),
        ]
        let width = (CGFloat(3) * configuration.minWidth) + (CGFloat(2) * configuration.gridSpacing)

        let projection = SidebarEssentialsProjectionPolicy.make(
            items: pins,
            width: width,
            configuration: configuration,
            dragState: state
        )

        XCTAssertEqual(projection.projectedItemCount, 4)
        XCTAssertEqual(projection.columnCount, 3)
        XCTAssertEqual(projection.rows.count, 2)
        XCTAssertEqual(projection.rows.first?.visualColumnCount, 3)
        XCTAssertEqual(projection.rows.last?.visualColumnCount, 1)
        XCTAssertEqual(projection.rows.last?.tileSize.width ?? 0, width, accuracy: 0.001)
        XCTAssertEqual(projection.layoutItems.map { $0?.id }, pins.map(\.id))
    }

    func testProjectedLayoutRemovesDraggedEssentialBeforeGhostInsert() {
        let configuration = PinnedTabsConfiguration.large
        let pins = [
            makeEssentialPin(index: 0),
            makeEssentialPin(index: 1),
            makeEssentialPin(index: 2),
        ]
        let draggedPin = pins[1]
        let width = (CGFloat(3) * configuration.minWidth) + (CGFloat(2) * configuration.gridSpacing)

        state.beginInternalDragSession(
            itemId: draggedPin.id,
            location: .zero,
            previewKind: .essentialsTile,
            previewAssets: [.essentialsTile: makePreviewAsset()]
        )
        state.hoveredSlot = .essentials(slot: 0)

        let projection = SidebarEssentialsProjectionPolicy.make(
            items: pins,
            width: width,
            configuration: configuration,
            dragState: state
        )

        XCTAssertEqual(projection.projectedItemCount, 3)
        XCTAssertEqual(projection.columnCount, 3)
        XCTAssertEqual(projection.rows.count, 1)
        XCTAssertEqual(projection.layoutItems.map { $0?.id }, [nil, pins[0].id, pins[2].id])
    }

    func testOutboundDragKeepsDraggedEssentialFootprintReserved() {
        let configuration = PinnedTabsConfiguration.large
        let pins = [
            makeEssentialPin(index: 0),
            makeEssentialPin(index: 1),
            makeEssentialPin(index: 2),
        ]
        let draggedPin = pins[1]
        let width = (CGFloat(3) * configuration.minWidth) + (CGFloat(2) * configuration.gridSpacing)

        state.beginInternalDragSession(
            itemId: draggedPin.id,
            location: .zero,
            previewKind: .essentialsTile,
            previewAssets: [.essentialsTile: makePreviewAsset()]
        )
        state.hoveredSlot = .spaceRegular(spaceId: UUID(), slot: 0)

        let projection = SidebarEssentialsProjectionPolicy.make(
            items: pins,
            width: width,
            configuration: configuration,
            dragState: state
        )

        XCTAssertEqual(projection.projectedItemCount, 3)
        XCTAssertEqual(projection.visibleRowCount, 1)
        XCTAssertEqual(projection.layoutItems.map { $0?.id }, pins.map(\.id))
    }

    private func makeEssentialPin(index: Int) -> ShortcutPin {
        ShortcutPin(
            id: UUID(),
            role: .essential,
            index: index,
            launchURL: URL(string: "https://example\(index).com")!,
            title: "Pin \(index)"
        )
    }

    private func makePreviewAsset() -> SidebarDragPreviewAsset {
        let imageSize = CGSize(width: 12, height: 12)
        let image = NSImage(size: imageSize)
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: imageSize)).fill()
        image.unlockFocus()
        return SidebarDragPreviewAsset(
            image: image,
            size: imageSize,
            anchorOffset: .zero
        )
    }
}

@MainActor
final class SumiNativeDragPreviewParityTests: XCTestCase {
    func testFolderRowPreviewMatchesRowSemanticsAndProducesVisibleImage() throws {
        let descriptor = SumiNativeDragPreviewDescriptor(
            item: SumiDragItem.folder(folderId: UUID(), title: "Folder"),
            previewIcon: nil,
            sourceZone: .spacePinned(UUID()),
            sourceSize: CGSize(width: 220, height: SidebarRowLayout.rowHeight),
            sourceOffsetFromBottomLeading: CGPoint(x: 42, y: 18),
            pinnedConfig: .large,
            folderGlyphPresentation: SumiFolderGlyphPresentationState(
                iconValue: "zen:bookmark",
                isOpen: false,
                hasActiveProjection: false
            ),
            folderGlyphPalette: SumiFolderGlyphPalette(
                backFill: .red,
                frontFill: .blue,
                stroke: .black,
                iconForeground: .white,
                backOverlayTop: .white.opacity(0.1),
                backOverlayBottom: .black.opacity(0.1),
                frontOverlayTop: .white.opacity(0.1),
                frontOverlayBottom: .black.opacity(0.1)
            )
        )
        let factory = SumiNativeDragImageFactory.shared

        let rowSize = factory.size(for: .row, descriptor: descriptor)
        let folderSize = factory.size(for: .folderRow, descriptor: descriptor)
        XCTAssertEqual(folderSize.width, rowSize.width)
        XCTAssertEqual(folderSize.height, rowSize.height)

        let rowOffset = factory.offset(for: .row, descriptor: descriptor)
        let folderOffset = factory.offset(for: .folderRow, descriptor: descriptor)
        XCTAssertEqual(folderOffset.x, rowOffset.x)
        XCTAssertEqual(folderOffset.y, rowOffset.y)

        let image = factory.image(for: .folderRow, descriptor: descriptor, sourceView: nil)
        XCTAssertEqual(image.size.width, 220)
        XCTAssertEqual(image.size.height, SidebarRowLayout.rowHeight)
        XCTAssertTrue(try imageHasVisiblePixels(image))
    }

    private func imageHasVisiblePixels(_ image: NSImage) throws -> Bool {
        let data = try XCTUnwrap(image.tiffRepresentation)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: data))

        let samplePoints = [
            CGPoint(x: 0.5, y: 0.5),
            CGPoint(x: 0.25, y: 0.5),
            CGPoint(x: 0.75, y: 0.5),
        ]

        for point in samplePoints {
            let x = max(0, min(Int(CGFloat(rep.pixelsWide - 1) * point.x), rep.pixelsWide - 1))
            let y = max(0, min(Int(CGFloat(rep.pixelsHigh - 1) * point.y), rep.pixelsHigh - 1))
            if (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.01 {
                return true
            }
        }

        return false
    }
}

@MainActor
final class SidebarContextMenuBuilderTests: XCTestCase {
    func testGenericAppKitContextMenuHostOnlyCapturesContextMenuTriggers() {
        let state = SidebarInteractionState()
        let host = SumiAppKitContextMenuHostView(frame: NSRect(x: 0, y: 0, width: 80, height: 36))
        let controller = makeSidebarContextMenuController(interactionState: state)
        host.controller = controller
        host.entriesProvider = {
            [
                .action(
                    SidebarContextMenuAction(
                        title: "Action",
                        action: {}
                    )
                )
            ]
        }

        XCTAssertFalse(
            host.canHandleContextMenu(
                for: Self.mouseEvent(type: .leftMouseDown),
                at: NSPoint(x: 12, y: 12)
            )
        )
        XCTAssertTrue(
            host.canHandleContextMenu(
                for: Self.mouseEvent(type: .rightMouseDown),
                at: NSPoint(x: 12, y: 12)
            )
        )
        XCTAssertTrue(
            host.canHandleContextMenu(
                for: Self.mouseEvent(type: .leftMouseDown, modifierFlags: [.control]),
                at: NSPoint(x: 12, y: 12)
            )
        )
        XCTAssertFalse(
            host.canHandleContextMenu(
                for: Self.mouseEvent(type: .mouseMoved),
                at: NSPoint(x: 12, y: 12)
            )
        )
        XCTAssertFalse(
            host.canHandleContextMenu(
                for: Self.mouseEvent(type: .rightMouseDown),
                at: NSPoint(x: 120, y: 12)
            )
        )

        host.reset()

        XCTAssertFalse(
            host.canHandleContextMenu(
                for: Self.mouseEvent(type: .rightMouseDown),
                at: NSPoint(x: 12, y: 12)
            )
        )
    }

    func testFolderHeaderContextMenuWithoutCustomIconUsesExpectedOrder() {
        let builder = makeBuilder(
            entries: makeFolderHeaderContextMenuEntries(
                hasCustomIcon: false,
                callbacks: .init(
                    onRename: {},
                    onChangeIcon: {},
                    onResetIcon: {},
                    onAddTab: {},
                    onAlphabetize: {},
                    onDelete: {}
                )
            )
        )

        XCTAssertEqual(
            itemTitles(for: builder.buildMenu()),
            [
                "Rename Folder",
                "Change Folder Icon…",
                "Add Tab to Folder",
                "<separator>",
                "Alphabetize Tabs",
                "<separator>",
                "Delete Folder",
            ]
        )
    }

    func testFolderHeaderContextMenuWithCustomIconIncludesResetInExpectedPosition() {
        let builder = makeBuilder(
            entries: makeFolderHeaderContextMenuEntries(
                hasCustomIcon: true,
                callbacks: .init(
                    onRename: {},
                    onChangeIcon: {},
                    onResetIcon: {},
                    onAddTab: {},
                    onAlphabetize: {},
                    onDelete: {}
                )
            )
        )

        XCTAssertEqual(
            itemTitles(for: builder.buildMenu()),
            [
                "Rename Folder",
                "Change Folder Icon…",
                "Reset Folder Icon",
                "Add Tab to Folder",
                "<separator>",
                "Alphabetize Tabs",
                "<separator>",
                "Delete Folder",
            ]
        )
    }

    func testFolderHeaderContextMenuAlwaysIncludesChangeFolderIconItem() {
        XCTAssertTrue(
            itemTitles(
                for: makeBuilder(
                    entries: makeFolderHeaderContextMenuEntries(
                        hasCustomIcon: false,
                        callbacks: .init(
                            onRename: {},
                            onChangeIcon: {},
                            onResetIcon: {},
                            onAddTab: {},
                            onAlphabetize: {},
                            onDelete: {}
                        )
                    )
                ).buildMenu()
            ).contains("Change Folder Icon…")
        )
        XCTAssertTrue(
            itemTitles(
                for: makeBuilder(
                    entries: makeFolderHeaderContextMenuEntries(
                        hasCustomIcon: true,
                        callbacks: .init(
                            onRename: {},
                            onChangeIcon: {},
                            onResetIcon: {},
                            onAddTab: {},
                            onAlphabetize: {},
                            onDelete: {}
                        )
                    )
                ).buildMenu()
            ).contains("Change Folder Icon…")
        )
    }

    func testRegularTabContextMenuMergesBothActionSurfacesWithoutDuplicateSplitItems() throws {
        let menu = makeBuilder(
            entries: makeRegularTabContextMenuEntries(
                folders: [SidebarContextMenuChoice(id: UUID(), title: "Folder")],
                spaces: [
                    SidebarContextMenuChoice(id: UUID(), title: "Space A", isSelected: true),
                    SidebarContextMenuChoice(id: UUID(), title: "Space B"),
                ],
                showsAddToFavorites: true,
                canMoveUp: false,
                canMoveDown: true,
                showsCloseAllBelow: true,
                callbacks: .init(
                    onAddToFolder: { _ in },
                    onAddToFavorites: {},
                    onCopyLink: {},
                    onShare: {},
                    onRename: {},
                    onSplitRight: {},
                    onSplitLeft: {},
                    onDuplicate: {},
                    onMoveToSpace: { _ in },
                    onMoveUp: {},
                    onMoveDown: {},
                    onPinToSpace: {},
                    onPinGlobally: {},
                    onCloseAllBelow: {},
                    onClose: {}
                )
            )
        ).buildMenu()

        XCTAssertEqual(
            itemTitles(for: menu),
            [
                "Add to Folder",
                "Add to Favorites",
                "<separator>",
                "Copy Link",
                "Share",
                "Rename",
                "<separator>",
                "Open in Split",
                "Duplicate",
                "Move to Space",
                "Move Up",
                "Move Down",
                "Pin to Space",
                "Pin Globally",
                "<separator>",
                "Close All Below",
                "Close",
            ]
        )

        let splitItem = try XCTUnwrap(menu.items.first(where: { $0.title == "Open in Split" }))
        XCTAssertEqual(
            splitItem.submenu?.items.map(\.title),
            ["Right", "Left"]
        )
    }

    func testLauncherContextMenusPreserveContainerSpecificDifferences() {
        let spacePinnedMenu = makeBuilder(
            entries: makeSpacePinnedLauncherContextMenuEntries(
                hasRuntimeResetActions: true,
                showsCloseCurrentPage: true,
                callbacks: .init(
                    onOpen: {},
                    onSplitRight: {},
                    onSplitLeft: {},
                    onDuplicate: {},
                    onResetToLaunchURL: {},
                    onReplaceLauncherURLWithCurrent: {},
                    onEditIcon: {},
                    onEditLink: {},
                    onUnpin: {},
                    onMoveToRegularTabs: {},
                    onPinGlobally: {},
                    onCloseCurrentPage: {}
                )
            )
        ).buildMenu()
        let folderMenu = makeBuilder(
            entries: makeFolderLauncherContextMenuEntries(
                hasRuntimeResetActions: true,
                showsCloseCurrentPage: true,
                callbacks: .init(
                    onOpen: {},
                    onSplitRight: {},
                    onSplitLeft: {},
                    onDuplicate: {},
                    onResetToLaunchURL: {},
                    onReplaceLauncherURLWithCurrent: {},
                    onEditIcon: {},
                    onEditLink: {},
                    onUnpin: {},
                    onMoveToRegularTabs: {},
                    onPinGlobally: nil,
                    onCloseCurrentPage: {}
                )
            )
        ).buildMenu()

        XCTAssertTrue(itemTitles(for: spacePinnedMenu).contains("Pin Globally"))
        XCTAssertFalse(itemTitles(for: folderMenu).contains("Pin Globally"))
        XCTAssertFalse(itemTitles(for: spacePinnedMenu).contains("Duplicate Tab"))
        XCTAssertTrue(itemTitles(for: folderMenu).contains("Duplicate Tab"))
        XCTAssertTrue(itemTitles(for: spacePinnedMenu).contains("Edit Icon"))
        XCTAssertTrue(itemTitles(for: folderMenu).contains("Edit Icon"))
    }

    func testEssentialsContextMenuUsesExpectedOrder() {
        let menu = makeBuilder(
            entries: makeEssentialsContextMenuEntries(
                showsCloseCurrentPage: true,
                callbacks: .init(
                    onOpen: {},
                    onSplitRight: {},
                    onSplitLeft: {},
                    onCloseCurrentPage: {},
                    onRemoveFromEssentials: {},
                    onMoveToRegularTabs: {}
                )
            )
        ).buildMenu()

        XCTAssertEqual(
            itemTitles(for: menu),
            [
                "Open",
                "Open in Split (Right)",
                "Open in Split (Left)",
                "<separator>",
                "Close current page",
                "<separator>",
                "Remove from Essentials",
                "Move to Regular Tabs",
            ]
        )
    }

    func testSpaceContextMenuMatchesCurrentActionSetAndOrder() {
        let profileA = UUID()
        let profileB = UUID()
        let menu = makeBuilder(
            entries: makeSpaceContextMenuEntries(
                profiles: [
                    SidebarContextMenuChoice(id: profileA, title: "Default", isSelected: true),
                    SidebarContextMenuChoice(id: profileB, title: "Work"),
                ],
                canRename: true,
                canChangeIcon: true,
                canDelete: true,
                callbacks: .init(
                    onSelectProfile: { _ in },
                    onRename: {},
                    onChangeIcon: {},
                    onChangeTheme: {},
                    onOpenSettings: {},
                    onDeleteSpace: {}
                )
            )
        ).buildMenu()

        XCTAssertEqual(
            itemTitles(for: menu),
            [
                "Profile",
                "<separator>",
                "Rename",
                "Change Icon",
                "Change Theme",
                "<separator>",
                "Space Settings",
                "Delete Space",
            ]
        )
        XCTAssertEqual(menu.items.first?.submenu?.items.map(\.title), ["Default", "Work"])
        XCTAssertEqual(menu.items.first?.submenu?.items.first?.state, .on)
    }

    func testSpaceListContextMenuMatchesCurrentActionSetAndOrder() {
        let menu = makeBuilder(
            entries: makeSpaceListContextMenuEntries(
                canDelete: true,
                callbacks: .init(
                    onOpenSettings: {},
                    onDeleteSpace: {}
                )
            )
        ).buildMenu()

        XCTAssertEqual(
            itemTitles(for: menu),
            [
                "Space Settings",
                "<separator>",
                "Delete Space",
            ]
        )
    }

    func testSidebarShellContextMenuMatchesCurrentActionSetAndOrder() {
        let menu = makeBuilder(
            entries: makeSidebarShellContextMenuEntries(
                hasSelectedTab: true,
                isCompactModeEnabled: true,
                callbacks: .init(
                    onCreateSpace: {},
                    onCreateFolder: {},
                    onNewSplit: {},
                    onNewTab: {},
                    onReloadSelectedTab: {},
                    onBookmarkSelectedTab: {},
                    onReopenClosedTab: {},
                    onToggleCompactMode: {},
                    onEditTheme: {},
                    onOpenLayout: {}
                )
            )
        ).buildMenu()

        XCTAssertEqual(
            itemTitles(for: menu),
            [
                "Create Space",
                "Create Folder",
                "New Split",
                "New Tab",
                "<separator>",
                "Reload Selected Tab",
                "Bookmark Selected Tab…",
                "Reopen Closed Tab",
                "<separator>",
                "Enable compact mode",
                "<separator>",
                "Edit Theme",
                "Sumi Layout…",
            ]
        )
        XCTAssertEqual(menu.items[9].state, .on)
    }

    func testSidebarContextMenuBuilderLifecycleCallbacksFire() {
        var events: [String] = []
        let builder = SidebarContextMenuBuilder(
            entries: [.action(.init(title: "Open", onAction: {}))],
            onMenuWillOpen: { events.append("open") },
            onMenuDidClose: { events.append("close") }
        )
        let menu = builder.buildMenu()

        builder.menuWillOpen(menu)
        builder.menuDidClose(menu)

        XCTAssertEqual(events, ["open", "close"])
    }

    func testSidebarContextMenuRoutingPolicyRightClickSurfaceInterceptsOnlyRightClick() {
        XCTAssertTrue(
            SidebarContextMenuRoutingPolicy.shouldIntercept(
                .rightMouseDown,
                triggers: .rightClick
            )
        )
        XCTAssertFalse(
            SidebarContextMenuRoutingPolicy.shouldIntercept(
                .leftMouseDown,
                triggers: .rightClick
            )
        )
    }

    func testSidebarContextMenuRoutingPolicyLeftClickSurfaceInterceptsOnlyLeftClick() {
        XCTAssertTrue(
            SidebarContextMenuRoutingPolicy.shouldIntercept(
                .leftMouseDown,
                triggers: .leftClick
            )
        )
        XCTAssertFalse(
            SidebarContextMenuRoutingPolicy.shouldIntercept(
                .rightMouseDown,
                triggers: .leftClick
            )
        )
    }

    func testSidebarContextMenuPresentationStyleUsesContextualEventForRightClick() {
        XCTAssertEqual(
            SidebarContextMenuRoutingPolicy.presentationStyle(for: .rightMouseDown),
            .contextualEvent
        )
    }

    func testSidebarContextMenuPresentationStyleUsesAnchoredPopupForLeftClick() {
        XCTAssertEqual(
            SidebarContextMenuRoutingPolicy.presentationStyle(for: .leftMouseDown),
            .anchoredPopup
        )
    }

    @MainActor
    func testSidebarContextMenuLeafHostRightClickOwnsMenuInteraction() {
        let view = SidebarInteractiveItemView(frame: NSRect(x: 0, y: 0, width: 80, height: 36))
        view.update(
            rootView: AnyView(Color.clear.frame(width: 80, height: 36)),
            configuration: SidebarAppKitItemConfiguration(
                menu: SidebarContextMenuLeafConfiguration(
                    isEnabled: true,
                    surfaceKind: .row,
                    triggers: .rightClick,
                    entries: { [.action(.init(title: "Open", onAction: {}))] },
                    onMenuVisibilityChanged: { _ in }
                )
            )
        )

        XCTAssertTrue(
            view.shouldCaptureInteraction(
                at: NSPoint(x: 12, y: 12),
                eventType: .rightMouseDown
            )
        )
        XCTAssertFalse(
            view.shouldCaptureInteraction(
                at: NSPoint(x: 12, y: 12),
                eventType: .leftMouseDown
            )
        )
    }

    @MainActor
    func testSidebarContextMenuLeafHostLeftClickMenuInterceptsOnlyLeftClick() {
        let view = SidebarInteractiveItemView(frame: NSRect(x: 0, y: 0, width: 40, height: 24))
        view.update(
            rootView: AnyView(Color.clear.frame(width: 40, height: 24)),
            configuration: SidebarAppKitItemConfiguration(
                menu: SidebarContextMenuLeafConfiguration(
                    isEnabled: true,
                    surfaceKind: .button,
                    triggers: .leftClick,
                    entries: { [.action(.init(title: "Configure", onAction: {}))] },
                    onMenuVisibilityChanged: { _ in }
                )
            )
        )

        XCTAssertTrue(
            view.shouldCaptureInteraction(
                at: NSPoint(x: 10, y: 10),
                eventType: .leftMouseDown
            )
        )
        XCTAssertFalse(
            view.shouldCaptureInteraction(
                at: NSPoint(x: 10, y: 10),
                eventType: .rightMouseDown
            )
        )
    }

    @MainActor
    func testSidebarContextMenuLeafHostDragSourceCapturesLeftMouseButRespectsExclusionZones() {
        let view = SidebarInteractiveItemView(frame: NSRect(x: 0, y: 0, width: 80, height: 36))
        view.update(
            rootView: AnyView(Color.clear.frame(width: 80, height: 36)),
            configuration: SidebarAppKitItemConfiguration(
                dragSource: SidebarDragSourceConfiguration(
                    item: SumiDragItem(tabId: UUID(), title: "Drag"),
                    sourceZone: .spaceRegular(UUID()),
                    previewKind: .row,
                    exclusionZones: [.trailingStrip(20)],
                    onActivate: {},
                    isEnabled: true
                )
            )
        )

        XCTAssertTrue(
            view.shouldCaptureInteraction(
                at: NSPoint(x: 12, y: 12),
                eventType: .leftMouseDown
            )
        )
        XCTAssertFalse(
            view.shouldCaptureInteraction(
                at: NSPoint(x: 72, y: 12),
                eventType: .leftMouseDown
            )
        )
        XCTAssertFalse(
            view.shouldCaptureInteraction(
                at: NSPoint(x: 12, y: 12),
                eventType: .rightMouseDown
            )
        )
    }

    @MainActor
    func testSidebarInteractiveItemDragCaptureResumesAfterContextMenuTrackingEndsWithoutRemount() {
        let state = SidebarInteractionState()
        let controller = makeSidebarContextMenuController(interactionState: state)
        let view = SidebarInteractiveItemView(frame: NSRect(x: 0, y: 0, width: 80, height: 36))
        view.contextMenuController = controller
        view.update(
            rootView: AnyView(Color.clear.frame(width: 80, height: 36)),
            configuration: SidebarAppKitItemConfiguration(
                dragSource: SidebarDragSourceConfiguration(
                    item: SumiDragItem(tabId: UUID(), title: "Launcher"),
                    sourceZone: .spacePinned(UUID()),
                    previewKind: .row,
                    isEnabled: true
                )
            )
        )

        XCTAssertTrue(
            view.shouldCaptureInteraction(
                at: NSPoint(x: 12, y: 12),
                eventType: .leftMouseDown
            )
        )

        let menuTokenID = state.beginContextMenuSessionForTesting()

        XCTAssertFalse(
            view.shouldCaptureInteraction(
                at: NSPoint(x: 12, y: 12),
                eventType: .leftMouseDown
            )
        )

        state.endContextMenuSessionForTesting(menuTokenID)

        XCTAssertTrue(
            view.shouldCaptureInteraction(
                at: NSPoint(x: 12, y: 12),
                eventType: .leftMouseDown
            )
        )
    }

    @MainActor
    func testShortcutLauncherDragConfigurationKeepsStableEnablementDuringContextMenuTracking() {
        let state = SidebarInteractionState()
        state.beginContextMenuSessionForTesting()

        let spaceId = UUID()
        let pin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: spaceId,
            index: 0,
            launchURL: URL(string: "https://example.com")!,
            title: "Example"
        )
        let configuration = makeShortcutSidebarDragSourceConfiguration(
            pin: pin,
            resolvedTitle: "Example",
            runtimeAffordance: .liveSelected,
            dragSourceZone: .spacePinned(spaceId),
            dragHasTrailingActionExclusion: true,
            dragIsEnabled: true
        )

        XCTAssertFalse(state.allowsSidebarDragSourceHitTesting)
        XCTAssertEqual(configuration?.item.tabId, pin.id)
        XCTAssertTrue(configuration?.isEnabled == true)
    }

    @MainActor
    func testSidebarInteractiveItemPrimaryOnlyCapturesLeftMouseButNotRightMouse() {
        var primaryActivations = 0
        let view = SidebarInteractiveItemView(frame: NSRect(x: 0, y: 0, width: 80, height: 36))
        view.update(
            rootView: AnyView(Color.clear.frame(width: 80, height: 36)),
            configuration: SidebarAppKitItemConfiguration(
                primaryAction: { primaryActivations += 1 }
            )
        )

        XCTAssertTrue(
            view.shouldCaptureInteraction(
                at: NSPoint(x: 12, y: 12),
                eventType: .leftMouseDown
            )
        )
        XCTAssertFalse(
            view.shouldCaptureInteraction(
                at: NSPoint(x: 12, y: 12),
                eventType: .rightMouseDown
            )
        )

        view.mouseDown(with: makeMouseEvent(type: .leftMouseDown, location: NSPoint(x: 12, y: 12)))
        view.mouseUp(with: makeMouseEvent(type: .leftMouseUp, location: NSPoint(x: 12, y: 12)))

        XCTAssertEqual(primaryActivations, 1)
    }

    @MainActor
    func testSidebarInteractiveItemPrimaryActionCapturesLeftMouseWhenDragSourceIsDisabled() {
        SidebarDragState.shared.resetInteractionState()
        var primaryActivations = 0
        var dragActivations = 0
        let view = SidebarInteractiveItemView(frame: NSRect(x: 0, y: 0, width: 80, height: 36))
        view.update(
            rootView: AnyView(Color.clear.frame(width: 80, height: 36)),
            configuration: SidebarAppKitItemConfiguration(
                dragSource: SidebarDragSourceConfiguration(
                    item: SumiDragItem(tabId: UUID(), title: "Drag"),
                    sourceZone: .spaceRegular(UUID()),
                    previewKind: .row,
                    exclusionZones: [.trailingStrip(20)],
                    onActivate: { dragActivations += 1 },
                    isEnabled: false
                ),
                primaryAction: { primaryActivations += 1 }
            )
        )

        XCTAssertTrue(
            view.shouldCaptureInteraction(
                at: NSPoint(x: 12, y: 12),
                eventType: .leftMouseDown
            )
        )
        XCTAssertFalse(
            view.shouldCaptureInteraction(
                at: NSPoint(x: 72, y: 12),
                eventType: .leftMouseDown
            )
        )

        view.mouseDown(with: makeMouseEvent(type: .leftMouseDown, location: NSPoint(x: 12, y: 12)))
        view.mouseDragged(with: makeMouseEvent(type: .leftMouseDragged, location: NSPoint(x: 52, y: 12)))
        view.mouseUp(with: makeMouseEvent(type: .leftMouseUp, location: NSPoint(x: 12, y: 12)))

        XCTAssertEqual(primaryActivations, 1)
        XCTAssertEqual(dragActivations, 0)
        XCTAssertFalse(SidebarDragState.shared.isDragging)
    }

    @MainActor
    func testSidebarInteractiveItemSmallMovementKeepsLeftClickAsPrimaryActivation() {
        SidebarDragState.shared.resetInteractionState()
        var primaryActivations = 0
        let view = SidebarInteractiveItemView(frame: NSRect(x: 0, y: 0, width: 80, height: 36))
        view.update(
            rootView: AnyView(Color.clear.frame(width: 80, height: 36)),
            configuration: SidebarAppKitItemConfiguration(
                dragSource: SidebarDragSourceConfiguration(
                    item: SumiDragItem(tabId: UUID(), title: "Drag"),
                    sourceZone: .spaceRegular(UUID()),
                    previewKind: .row,
                    onActivate: { XCTFail("Drag fallback activation should not run when primaryAction is explicit.") },
                    isEnabled: true
                ),
                primaryAction: { primaryActivations += 1 }
            )
        )

        view.mouseDown(with: makeMouseEvent(type: .leftMouseDown, location: NSPoint(x: 12, y: 12)))
        view.mouseDragged(with: makeMouseEvent(type: .leftMouseDragged, location: NSPoint(x: 13, y: 12)))
        view.mouseUp(with: makeMouseEvent(type: .leftMouseUp, location: NSPoint(x: 13, y: 12)))

        XCTAssertEqual(primaryActivations, 1)
        XCTAssertFalse(SidebarDragState.shared.isDragging)
    }

    @MainActor
    func testSidebarInteractiveItemDismantleClearsPartialPrimaryClickTracking() {
        var primaryActivations = 0
        let controller = makeSidebarContextMenuController(interactionState: SidebarInteractionState())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let view = SidebarInteractiveItemView(frame: NSRect(x: 0, y: 0, width: 80, height: 36))
        window.contentView?.addSubview(view)
        view.contextMenuController = controller
        view.update(
            rootView: AnyView(Color.clear.frame(width: 80, height: 36)),
            configuration: SidebarAppKitItemConfiguration(
                primaryAction: { primaryActivations += 1 }
            )
        )

        view.mouseDown(with: makeMouseEvent(type: .leftMouseDown, location: NSPoint(x: 12, y: 12)))
        XCTAssertTrue(controller.primaryMouseTrackingOwner(in: window) === view)
        view.prepareForDismantle()
        view.mouseUp(with: makeMouseEvent(type: .leftMouseUp, location: NSPoint(x: 12, y: 12)))

        XCTAssertEqual(primaryActivations, 0)
        XCTAssertNil(controller.primaryMouseTrackingOwner(in: window))
        XCTAssertFalse(
            view.shouldCaptureInteraction(
                at: NSPoint(x: 12, y: 12),
                eventType: .leftMouseDown
            )
        )
    }

    @MainActor
    func testSidebarContextMenuLeafHostMiddleClickOwnsOtherMouseUp() {
        let view = SidebarInteractiveItemView(frame: NSRect(x: 0, y: 0, width: 80, height: 36))
        view.update(
            rootView: AnyView(Color.clear.frame(width: 80, height: 36)),
            configuration: SidebarAppKitItemConfiguration(
                onMiddleClick: {}
            )
        )

        XCTAssertTrue(
            view.shouldCaptureInteraction(
                at: NSPoint(x: 12, y: 12),
                eventType: .otherMouseUp
            )
        )
        XCTAssertFalse(
            view.shouldCaptureInteraction(
                at: NSPoint(x: 12, y: 12),
                eventType: .leftMouseDown
            )
        )
    }

    @MainActor
    func testSidebarInteractiveItemDismantlePreparationDisarmsAndDetachesController() {
        let state = SidebarInteractionState()
        let controller = makeSidebarContextMenuController(interactionState: state)
        let view = SidebarInteractiveItemView(frame: NSRect(x: 0, y: 0, width: 80, height: 36))
        view.contextMenuController = controller
        view.update(
            rootView: AnyView(Color.clear.frame(width: 80, height: 36)),
            configuration: SidebarAppKitItemConfiguration(
                menu: SidebarContextMenuLeafConfiguration(
                    isEnabled: true,
                    surfaceKind: .row,
                    triggers: .rightClick,
                    entries: { [.action(.init(title: "Open", onAction: {}))] },
                    onMenuVisibilityChanged: { _ in }
                )
            )
        )

        XCTAssertTrue(
            view.shouldCaptureInteraction(
                at: NSPoint(x: 12, y: 12),
                eventType: .rightMouseDown
            )
        )

        view.prepareForDismantle()

        XCTAssertNil(view.contextMenuController)
        XCTAssertFalse(
            view.shouldCaptureInteraction(
                at: NSPoint(x: 12, y: 12),
                eventType: .rightMouseDown
            )
        )
    }

    func testSidebarInteractionStateTracksMenuLifecycle() {
        let state = SidebarInteractionState()

        XCTAssertEqual(state.activeKindsDescription, "none")
        XCTAssertFalse(state.isContextMenuPresented)

        let menuTokenID = state.beginContextMenuSessionForTesting()

        XCTAssertTrue(state.isContextMenuPresented)
        XCTAssertTrue(state.freezesSidebarHoverState)
        XCTAssertFalse(state.allowsSidebarSwipeCapture)

        state.endContextMenuSessionForTesting(menuTokenID)

        XCTAssertEqual(state.activeKindsDescription, "none")
        XCTAssertFalse(state.isContextMenuPresented)
    }

    func testSidebarInteractionStateDragStartDoesNotBlockDragHitTesting() {
        let state = SidebarInteractionState()

        XCTAssertTrue(SidebarTransientUIKind.drag.pinsCollapsedSidebar)
        XCTAssertFalse(SidebarTransientUIKind.drag.blocksSidebarDragSources)

        state.syncSidebarItemDrag(true)

        XCTAssertEqual(state.activeKindsDescription, "drag")
        XCTAssertTrue(state.allowsSidebarDragSourceHitTesting)
        XCTAssertTrue(state.freezesSidebarHoverState)

        state.syncSidebarItemDrag(false)
    }

    func testSidebarInteractionStatePreservesMenuTrackingAgainstSidebarDragSync() {
        let state = SidebarInteractionState()

        let menuTokenID = state.beginContextMenuSessionForTesting()
        state.syncSidebarItemDrag(true)

        XCTAssertTrue(state.isContextMenuPresented)
        XCTAssertFalse(state.allowsSidebarDragSourceHitTesting)

        state.endContextMenuSessionForTesting(menuTokenID)
        state.syncSidebarItemDrag(true)

        XCTAssertEqual(state.activeKindsDescription, "drag")
        XCTAssertTrue(state.allowsSidebarDragSourceHitTesting)

        state.syncSidebarItemDrag(false)

        XCTAssertEqual(state.activeKindsDescription, "none")
        XCTAssertTrue(state.allowsSidebarDragSourceHitTesting)
    }

    @MainActor
    func testSidebarContextMenuControllerStartsMenuTrackingBeforeVisibilityAndPreOpenCleanupRestoresDragCapture() {
        let state = SidebarInteractionState()
        let controller = makeSidebarContextMenuController(interactionState: state)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        var visibilityEvents: [Bool] = []

        let dragView = SidebarInteractiveItemView(frame: NSRect(x: 0, y: 0, width: 80, height: 36))
        dragView.contextMenuController = controller
        dragView.update(
            rootView: AnyView(Color.clear.frame(width: 80, height: 36)),
            configuration: SidebarAppKitItemConfiguration(
                dragSource: SidebarDragSourceConfiguration(
                    item: SumiDragItem(tabId: UUID(), title: "Drag"),
                    sourceZone: .spaceRegular(UUID()),
                    previewKind: .row,
                    isEnabled: true
                )
            )
        )
        window.contentView?.addSubview(dragView)

        XCTAssertTrue(
            dragView.shouldCaptureInteraction(
                at: NSPoint(x: 12, y: 12),
                eventType: .leftMouseDown
            )
        )

        let sessionID = controller.beginMenuSessionForTesting(
            ownerView: dragView,
            onMenuVisibilityChanged: { visibilityEvents.append($0) }
        )

        XCTAssertTrue(state.isContextMenuPresented)
        XCTAssertFalse(state.allowsSidebarDragSourceHitTesting)
        XCTAssertFalse(
            dragView.shouldCaptureInteraction(
                at: NSPoint(x: 12, y: 12),
                eventType: .leftMouseDown
            )
        )

        controller.finishMenuSessionForTesting(sessionID: sessionID)
        drainMainRunLoop()

        XCTAssertEqual(state.activeKindsDescription, "none")
        XCTAssertTrue(state.allowsSidebarDragSourceHitTesting)
        XCTAssertTrue(visibilityEvents.isEmpty)
        XCTAssertTrue(
            dragView.shouldCaptureInteraction(
                at: NSPoint(x: 12, y: 12),
                eventType: .leftMouseDown
            )
        )
    }

    @MainActor
    func testSidebarContextMenuControllerMenuCloseDoesNotRestoreDragCaptureBeforeEndTracking() {
        let state = SidebarInteractionState()
        let controller = makeSidebarContextMenuController(interactionState: state)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let menu = NSMenu()
        var visibilityEvents: [Bool] = []

        let dragView = SidebarInteractiveItemView(frame: NSRect(x: 0, y: 0, width: 80, height: 36))
        dragView.contextMenuController = controller
        dragView.update(
            rootView: AnyView(Color.clear.frame(width: 80, height: 36)),
            configuration: SidebarAppKitItemConfiguration(
                dragSource: SidebarDragSourceConfiguration(
                    item: SumiDragItem(tabId: UUID(), title: "Drag"),
                    sourceZone: .spaceRegular(UUID()),
                    previewKind: .row,
                    isEnabled: true
                )
            )
        )
        window.contentView?.addSubview(dragView)

        let sessionID = controller.beginMenuSessionForTesting(
            ownerView: dragView,
            menu: menu,
            onMenuVisibilityChanged: { visibilityEvents.append($0) }
        )
        controller.markMenuOpenedForTesting(sessionID: sessionID)

        XCTAssertTrue(state.isContextMenuPresented)
        XCTAssertFalse(state.allowsSidebarDragSourceHitTesting)
        XCTAssertFalse(
            dragView.shouldCaptureInteraction(
                at: NSPoint(x: 12, y: 12),
                eventType: .leftMouseDown
            )
        )

        controller.markMenuClosedForTesting(sessionID: sessionID)
        drainMainRunLoop()

        XCTAssertTrue(state.isContextMenuPresented)
        XCTAssertFalse(state.allowsSidebarDragSourceHitTesting)
        XCTAssertTrue(visibilityEvents.isEmpty)
        XCTAssertFalse(
            dragView.shouldCaptureInteraction(
                at: NSPoint(x: 12, y: 12),
                eventType: .leftMouseDown
            )
        )
    }

    @MainActor
    func testSidebarContextMenuControllerEndTrackingRestoresDragCaptureAndVisibilityCallbacks() {
        let state = SidebarInteractionState()
        let controller = makeSidebarContextMenuController(interactionState: state)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let menu = NSMenu()
        var visibilityEvents: [Bool] = []

        let dragView = SidebarInteractiveItemView(frame: NSRect(x: 0, y: 0, width: 80, height: 36))
        dragView.contextMenuController = controller
        dragView.update(
            rootView: AnyView(Color.clear.frame(width: 80, height: 36)),
            configuration: SidebarAppKitItemConfiguration(
                dragSource: SidebarDragSourceConfiguration(
                    item: SumiDragItem(tabId: UUID(), title: "Drag"),
                    sourceZone: .spaceRegular(UUID()),
                    previewKind: .row,
                    isEnabled: true
                )
            )
        )
        window.contentView?.addSubview(dragView)

        let sessionID = controller.beginMenuSessionForTesting(
            ownerView: dragView,
            menu: menu,
            onMenuVisibilityChanged: { visibilityEvents.append($0) }
        )
        controller.markMenuOpenedForTesting(sessionID: sessionID)
        controller.markMenuClosedForTesting(sessionID: sessionID)

        NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: menu)
        drainMainRunLoop()

        XCTAssertEqual(state.activeKindsDescription, "none")
        XCTAssertTrue(state.allowsSidebarDragSourceHitTesting)
        XCTAssertEqual(visibilityEvents, [true, false])
        XCTAssertTrue(
            dragView.shouldCaptureInteraction(
                at: NSPoint(x: 12, y: 12),
                eventType: .leftMouseDown
            )
        )
    }

    @MainActor
    func testSidebarContextMenuControllerForceCloseResetsMenuTrackingWithoutDelegateClose() {
        let state = SidebarInteractionState()
        let controller = makeSidebarContextMenuController(interactionState: state)
        var visibilityEvents: [Bool] = []
        let sessionID = controller.beginMenuSessionForTesting(
            onMenuVisibilityChanged: { visibilityEvents.append($0) }
        )

        XCTAssertTrue(state.isContextMenuPresented)
        controller.markMenuOpenedForTesting(sessionID: sessionID)
        XCTAssertTrue(state.isContextMenuPresented)

        controller.forceCloseActiveSessionForTesting()

        XCTAssertEqual(state.activeKindsDescription, "none")
        XCTAssertEqual(visibilityEvents, [])
        drainMainRunLoop()
        XCTAssertEqual(visibilityEvents, [true, false])
    }

    @MainActor
    func testSidebarContextMenuControllerDetachingActiveOwnerResetsMenuTracking() {
        let state = SidebarInteractionState()
        let controller = makeSidebarContextMenuController(interactionState: state)
        let ownerView = NSView(frame: .zero)
        var visibilityEvents: [Bool] = []
        let sessionID = controller.beginMenuSessionForTesting(
            ownerView: ownerView,
            onMenuVisibilityChanged: { visibilityEvents.append($0) }
        )

        XCTAssertTrue(state.isContextMenuPresented)
        controller.markMenuOpenedForTesting(sessionID: sessionID)
        XCTAssertTrue(state.isContextMenuPresented)

        controller.detachOwnerViewForTesting(ownerView)

        XCTAssertEqual(state.activeKindsDescription, "none")
        XCTAssertEqual(visibilityEvents, [])
        drainMainRunLoop()
        XCTAssertEqual(visibilityEvents, [true, false])
    }

    @MainActor
    func testSidebarContextMenuControllerWindowCloseResetsMenuTracking() {
        let state = SidebarInteractionState()
        let controller = makeSidebarContextMenuController(interactionState: state)
        let (window, ownerView) = makeWindowAndAttachedHostView()
        var visibilityEvents: [Bool] = []
        let sessionID = controller.beginMenuSessionForTesting(
            ownerView: ownerView,
            onMenuVisibilityChanged: { visibilityEvents.append($0) }
        )

        XCTAssertTrue(state.isContextMenuPresented)
        controller.markMenuOpenedForTesting(sessionID: sessionID)
        XCTAssertTrue(state.isContextMenuPresented)

        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
        drainMainRunLoop()

        XCTAssertEqual(state.activeKindsDescription, "none")
        XCTAssertEqual(visibilityEvents, [true, false])
    }

    @MainActor
    func testSidebarContextMenuControllerIgnoresLateEndTrackingFromPreviousSession() {
        let state = SidebarInteractionState()
        let controller = makeSidebarContextMenuController(interactionState: state)
        let ownerView = NSView(frame: .zero)
        let firstMenu = NSMenu()
        let secondMenu = NSMenu()
        var firstSessionEvents: [Bool] = []
        var secondSessionEvents: [Bool] = []

        let firstSessionID = controller.beginMenuSessionForTesting(
            ownerView: ownerView,
            menu: firstMenu,
            onMenuVisibilityChanged: { firstSessionEvents.append($0) }
        )
        controller.markMenuOpenedForTesting(sessionID: firstSessionID)
        controller.markMenuClosedForTesting(sessionID: firstSessionID)
        XCTAssertTrue(state.isContextMenuPresented)

        let secondSessionID = controller.beginMenuSessionForTesting(
            ownerView: ownerView,
            menu: secondMenu,
            onMenuVisibilityChanged: { secondSessionEvents.append($0) }
        )

        XCTAssertTrue(state.isContextMenuPresented)
        XCTAssertEqual(firstSessionEvents, [])
        drainMainRunLoop()
        XCTAssertEqual(firstSessionEvents, [true, false])

        controller.markMenuOpenedForTesting(sessionID: secondSessionID)
        XCTAssertTrue(state.isContextMenuPresented)

        NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: firstMenu)

        XCTAssertTrue(state.isContextMenuPresented)
        XCTAssertEqual(firstSessionEvents, [true, false])
        XCTAssertEqual(secondSessionEvents, [])

        controller.markMenuClosedForTesting(sessionID: secondSessionID)
        NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: secondMenu)

        drainMainRunLoop()
        XCTAssertEqual(state.activeKindsDescription, "none")
        XCTAssertEqual(secondSessionEvents, [true, false])
    }

    @MainActor
    func testSidebarInteractiveItemCanRestartDragAfterMenuEndTracking() {
        SidebarDragState.shared.resetInteractionState()

        let state = SidebarInteractionState()
        let controller = makeSidebarContextMenuController(interactionState: state)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let menu = NSMenu()
        let dragView = SidebarInteractiveItemView(frame: NSRect(x: 0, y: 0, width: 80, height: 36))
        dragView.contextMenuController = controller
        dragView.update(
            rootView: AnyView(Color.clear.frame(width: 80, height: 36)),
            configuration: SidebarAppKitItemConfiguration(
                dragSource: SidebarDragSourceConfiguration(
                    item: SumiDragItem(tabId: UUID(), title: "Drag"),
                    sourceZone: .spaceRegular(UUID()),
                    previewKind: .row,
                    isEnabled: true
                )
            )
        )
        window.contentView?.addSubview(dragView)

        let sessionID = controller.beginMenuSessionForTesting(
            ownerView: dragView,
            menu: menu
        )
        controller.markMenuOpenedForTesting(sessionID: sessionID)
        controller.markMenuClosedForTesting(sessionID: sessionID)

        NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: menu)
        drainMainRunLoop()

        dragView.mouseDown(with: makeMouseEvent(type: .leftMouseDown, location: NSPoint(x: 12, y: 12)))
        dragView.mouseDragged(with: makeMouseEvent(type: .leftMouseDragged, location: NSPoint(x: 52, y: 12)))

        XCTAssertTrue(SidebarDragState.shared.isDragging)
        XCTAssertTrue(SidebarDragState.shared.isInternalDragSession)
        XCTAssertNotNil(SidebarDragState.shared.activeDragItemId)

        SidebarDragState.shared.resetInteractionState()
        dragView.mouseUp(with: makeMouseEvent(type: .leftMouseUp, location: NSPoint(x: 52, y: 12)))
    }

    @MainActor
    func testSidebarInteractiveItemDismantlePreservesActiveInternalDragPreviewState() {
        SidebarDragState.shared.resetInteractionState()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let dragItemID = UUID()
        let dragView = SidebarInteractiveItemView(frame: NSRect(x: 0, y: 0, width: 80, height: 36))
        dragView.update(
            rootView: AnyView(Color.clear.frame(width: 80, height: 36)),
            configuration: SidebarAppKitItemConfiguration(
                dragSource: SidebarDragSourceConfiguration(
                    item: SumiDragItem(tabId: dragItemID, title: "Essential"),
                    sourceZone: .essentials,
                    previewKind: .essentialsTile,
                    isEnabled: true
                )
            )
        )
        window.contentView?.addSubview(dragView)

        dragView.mouseDown(with: makeMouseEvent(type: .leftMouseDown, location: NSPoint(x: 12, y: 12)))
        dragView.mouseDragged(with: makeMouseEvent(type: .leftMouseDragged, location: NSPoint(x: 52, y: 12)))

        XCTAssertTrue(SidebarDragState.shared.isDragging)
        XCTAssertTrue(SidebarDragState.shared.isInternalDragSession)
        XCTAssertEqual(SidebarDragState.shared.activeDragItemId, dragItemID)
        XCTAssertEqual(SidebarDragState.shared.previewKind, .essentialsTile)
        XCTAssertNotNil(SidebarDragState.shared.previewModel)
        XCTAssertNotNil(SidebarDragState.shared.previewAssets[.essentialsTile])

        dragView.prepareForDismantle()

        XCTAssertTrue(SidebarDragState.shared.isDragging)
        XCTAssertTrue(SidebarDragState.shared.isInternalDragSession)
        XCTAssertEqual(SidebarDragState.shared.activeDragItemId, dragItemID)
        XCTAssertEqual(SidebarDragState.shared.previewKind, .essentialsTile)
        XCTAssertNotNil(SidebarDragState.shared.previewModel)
        XCTAssertNotNil(SidebarDragState.shared.previewAssets[.essentialsTile])
        XCTAssertNil(dragView.contextMenuController)
        XCTAssertFalse(
            dragView.shouldCaptureInteraction(
                at: NSPoint(x: 12, y: 12),
                eventType: .leftMouseDown
            )
        )

        SidebarDragState.shared.resetInteractionState()
    }

    @MainActor
    func testSidebarContextMenuControllerRecoverInteractiveOwnersMatchesRemountedSourceOwnerByDragKey() {
        let state = SidebarInteractionState()
        let controller = makeSidebarContextMenuController(interactionState: state)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let itemID = UUID()
        let sourceZone = DropZoneID.spaceRegular(UUID())

        let originalOwner = SidebarInteractiveItemView(frame: NSRect(x: 0, y: 0, width: 80, height: 36))
        originalOwner.contextMenuController = controller
        originalOwner.update(
            rootView: AnyView(Color.clear.frame(width: 80, height: 36)),
            configuration: SidebarAppKitItemConfiguration(
                dragSource: SidebarDragSourceConfiguration(
                    item: SumiDragItem(tabId: itemID, title: "Drag"),
                    sourceZone: sourceZone,
                    previewKind: .row,
                    isEnabled: true
                )
            )
        )
        window.contentView?.addSubview(originalOwner)

        let source = SidebarTransientPresentationSource(
            windowID: UUID(),
            window: window,
            originOwnerView: originalOwner,
            coordinator: nil
        )

        originalOwner.removeFromSuperview()

        let replacementOwner = SidebarInteractiveItemView(frame: NSRect(x: 0, y: 0, width: 80, height: 36))
        replacementOwner.contextMenuController = controller
        replacementOwner.update(
            rootView: AnyView(Color.clear.frame(width: 80, height: 36)),
            configuration: SidebarAppKitItemConfiguration(
                dragSource: SidebarDragSourceConfiguration(
                    item: SumiDragItem(tabId: itemID, title: "Drag"),
                    sourceZone: sourceZone,
                    previewKind: .row,
                    isEnabled: true
                )
            )
        )
        window.contentView?.addSubview(replacementOwner)

        let result = controller.recoverInteractiveOwners(in: window, source: source)

        XCTAssertEqual(result.recoveredOwnerCount, 1)
        XCTAssertTrue(result.sourceOwnerResolved)
        XCTAssertEqual(result.resolutionReason, "dragKey")
        XCTAssertEqual(result.resolvedOwnerDescription, replacementOwner.recoveryDebugDescription)
    }

    @MainActor
    func testSidebarContextMenuControllerRecoverInteractiveOwnersDoesNotTreatUnrelatedOwnerAsSourceRecovery() {
        let state = SidebarInteractionState()
        let controller = makeSidebarContextMenuController(interactionState: state)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let sourceZone = DropZoneID.spaceRegular(UUID())

        let originalOwner = SidebarInteractiveItemView(frame: NSRect(x: 0, y: 0, width: 80, height: 36))
        originalOwner.contextMenuController = controller
        originalOwner.update(
            rootView: AnyView(Color.clear.frame(width: 80, height: 36)),
            configuration: SidebarAppKitItemConfiguration(
                dragSource: SidebarDragSourceConfiguration(
                    item: SumiDragItem(tabId: UUID(), title: "Drag"),
                    sourceZone: sourceZone,
                    previewKind: .row,
                    isEnabled: true
                )
            )
        )
        window.contentView?.addSubview(originalOwner)

        let source = SidebarTransientPresentationSource(
            windowID: UUID(),
            window: window,
            originOwnerView: originalOwner,
            coordinator: nil
        )

        originalOwner.removeFromSuperview()

        let unrelatedOwner = SidebarInteractiveItemView(frame: NSRect(x: 0, y: 0, width: 80, height: 36))
        unrelatedOwner.contextMenuController = controller
        unrelatedOwner.update(
            rootView: AnyView(Color.clear.frame(width: 80, height: 36)),
            configuration: SidebarAppKitItemConfiguration(
                dragSource: SidebarDragSourceConfiguration(
                    item: SumiDragItem(tabId: UUID(), title: "Other"),
                    sourceZone: sourceZone,
                    previewKind: .row,
                    isEnabled: true
                )
            )
        )
        window.contentView?.addSubview(unrelatedOwner)

        let result = controller.recoverInteractiveOwners(in: window, source: source)

        XCTAssertEqual(result.recoveredOwnerCount, 1)
        XCTAssertFalse(result.sourceOwnerResolved)
        XCTAssertNil(result.resolutionReason)
        XCTAssertNil(result.resolvedOwnerDescription)
    }

    @MainActor
    func testSidebarContextMenuControllerFinishSessionIsIdempotentAfterForcedClose() {
        let state = SidebarInteractionState()
        let controller = makeSidebarContextMenuController(interactionState: state)
        var visibilityEvents: [Bool] = []
        let sessionID = controller.beginMenuSessionForTesting(
            onMenuVisibilityChanged: { visibilityEvents.append($0) }
        )

        controller.markMenuOpenedForTesting(sessionID: sessionID)
        controller.finishMenuSessionForTesting(sessionID: sessionID)
        controller.finishMenuSessionForTesting(sessionID: sessionID)

        XCTAssertEqual(state.activeKindsDescription, "none")
        XCTAssertEqual(visibilityEvents, [])
        drainMainRunLoop()
        XCTAssertEqual(visibilityEvents, [true, false])
    }

    @MainActor
    func testSidebarContextMenuControllerDismissRecoveryUsesWindowAndOwnerAnchor() {
        let state = SidebarInteractionState()
        let controller = makeSidebarContextMenuController(interactionState: state)
        let spy = SidebarContextMenuRecoverySpy()
        controller.sidebarRecoveryCoordinator = spy

        let (window, ownerView) = makeWindowAndAttachedHostView()
        controller.runPointerRecoveryForTesting(aroundOwnerView: ownerView)

        XCTAssertEqual(spy.recoveredWindows.count, 1)
        XCTAssertTrue(spy.recoveredWindows.first === window)
        XCTAssertEqual(spy.recoveredAnchors.count, 1)
        XCTAssertTrue(spy.recoveredAnchors.first === ownerView)
        XCTAssertEqual(spy.recoveryOrder, ["window", "anchor"])
    }

    @MainActor
    func testSidebarContextMenuControllerDismissRecoveryIsRepeatableAcrossCycles() {
        let state = SidebarInteractionState()
        let controller = makeSidebarContextMenuController(interactionState: state)
        let spy = SidebarContextMenuRecoverySpy()
        controller.sidebarRecoveryCoordinator = spy

        let (window, ownerView) = makeWindowAndAttachedHostView()
        controller.runPointerRecoveryForTesting(aroundOwnerView: ownerView)
        controller.runPointerRecoveryForTesting(aroundOwnerView: ownerView)

        XCTAssertEqual(spy.recoveredWindows.count, 2)
        XCTAssertTrue(spy.recoveredWindows.allSatisfy { $0 === window })
        XCTAssertEqual(spy.recoveredAnchors.count, 2)
        XCTAssertTrue(spy.recoveredAnchors.allSatisfy { $0 === ownerView })
        XCTAssertEqual(spy.recoveryOrder, ["window", "anchor", "window", "anchor"])
    }

    func testHoverSidebarVisibilityPolicyPinsOverlayWhileContextMenuPresented() {
        XCTAssertTrue(
            HoverSidebarVisibilityPolicy.shouldShowOverlay(
                mouse: CGPoint(x: -400, y: -400),
                windowFrame: CGRect(x: 100, y: 100, width: 1200, height: 800),
                overlayWidth: 280,
                isOverlayVisible: false,
                contextMenuPresented: true,
                triggerWidth: 6,
                overshootSlack: 12,
                keepOpenHysteresis: 52,
                verticalSlack: 24
            )
        )
    }

    @MainActor
    func testSidebarContextMenuControllerBackgroundMenuUsesConfiguredVisibilityCallback() {
        let state = SidebarInteractionState()
        let controller = makeSidebarContextMenuController(interactionState: state)
        var visibilityEvents: [Bool] = []

        controller.configureBackgroundMenuForTesting(
            entriesProvider: { [.action(.init(title: "Open", onAction: {}))] },
            onMenuVisibilityChanged: { visibilityEvents.append($0) }
        )

        let sessionID = controller.beginMenuSessionForTesting(
            onMenuVisibilityChanged: { visibilityEvents.append($0) }
        )
        controller.markMenuOpenedForTesting(sessionID: sessionID)
        controller.finishMenuSessionForTesting(sessionID: sessionID)

        XCTAssertEqual(visibilityEvents, [])
        drainMainRunLoop()
        XCTAssertEqual(visibilityEvents, [true, false])
    }

    private func makeBuilder(entries: [SidebarContextMenuEntry]) -> SidebarContextMenuBuilder {
        SidebarContextMenuBuilder(entries: entries)
    }

    private func itemTitle(for entry: SidebarContextMenuEntry) -> String {
        switch entry {
        case .action(let action):
            action.title
        case .submenu(let title, _, _):
            title
        case .separator:
            "<separator>"
        }
    }

    private func itemTitles(for menu: NSMenu) -> [String] {
        menu.items.map { item in
            item.isSeparatorItem ? "<separator>" : item.title
        }
    }

    @MainActor
    private func makeWindowAndAttachedHostView() -> (NSWindow, NSView) {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        let hostView = NSView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        window.contentView?.addSubview(hostView)
        return (window, hostView)
    }

    @MainActor
    private func drainMainRunLoop() {
        let until = Date().addingTimeInterval(0.05)
        RunLoop.main.run(until: until)
    }

    private static func mouseEvent(
        type: NSEvent.EventType,
        modifierFlags: NSEvent.ModifierFlags = []
    ) -> NSEvent {
        guard let event = NSEvent.mouseEvent(
            with: type,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ) else {
            fatalError("Failed to create mouse event for test.")
        }
        return event
    }

    private func makeMouseEvent(
        type: NSEvent.EventType,
        location: NSPoint
    ) -> NSEvent {
        guard let event = NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ) else {
            fatalError("Failed to create mouse event for test.")
        }
        return event
    }
}

@MainActor
private final class SidebarContextMenuRecoverySpy: SidebarHostRecoveryHandling {
    private(set) var recoveredWindows: [NSWindow] = []
    private(set) var recoveredAnchors: [NSView] = []
    private(set) var recoveryOrder: [String] = []

    func sync(anchor: NSView, window: NSWindow?) {}

    func unregister(anchor: NSView) {}

    func recover(in window: NSWindow?) {
        if let window {
            recoveredWindows.append(window)
            recoveryOrder.append("window")
        }
    }

    func recover(anchor: NSView?) {
        if let anchor {
            recoveredAnchors.append(anchor)
            recoveryOrder.append("anchor")
        }
    }
}

private extension DragOperation {
    @MainActor
    init(
        payload: DragOperation.Payload,
        fromContainer: TabDragManager.DragContainer,
        toContainer: TabDragManager.DragContainer,
        toIndex: Int
    ) {
        let sourceItemId: UUID
        let sourceItemKind: SumiDragItemKind
        let sourceProfileId: UUID?
        let payloadSpaceId: UUID?

        switch payload {
        case .tab(let tab):
            sourceItemId = tab.shortcutPinId ?? tab.id
            sourceItemKind = .tab
            sourceProfileId = tab.profileId
            payloadSpaceId = tab.spaceId
        case .pin(let pin):
            sourceItemId = pin.id
            sourceItemKind = .tab
            sourceProfileId = pin.profileId
            payloadSpaceId = pin.spaceId
        case .folder(let folder):
            sourceItemId = folder.id
            sourceItemKind = .folder
            sourceProfileId = nil
            payloadSpaceId = folder.spaceId
        }

        let scopedSpaceId = fromContainer.spaceIdForSidebarTestScope
            ?? toContainer.spaceIdForSidebarTestScope
            ?? payloadSpaceId
            ?? UUID()
        self.init(
            payload: payload,
            scope: SidebarDragScope(
                spaceId: scopedSpaceId,
                profileId: sourceProfileId,
                sourceContainer: fromContainer,
                sourceItemId: sourceItemId,
                sourceItemKind: sourceItemKind
            ),
            fromContainer: fromContainer,
            toContainer: toContainer,
            toIndex: toIndex
        )
    }
}

private extension TabDragManager.DragContainer {
    var spaceIdForSidebarTestScope: UUID? {
        switch self {
        case .spacePinned(let spaceId),
             .spaceRegular(let spaceId):
            return spaceId
        case .essentials,
             .folder,
             .none:
            return nil
        }
    }
}

@MainActor
final class SidebarDragOperationParityTests: XCTestCase {
    func testRegularToFolderCreatesFolderChildLauncherAndKeepsClosedFolderClosed() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.createSpace(name: "Workspace")
        let folder = tabManager.createFolder(for: space.id, name: "Folder")
        folder.isOpen = false
        let tab = tabManager.createNewTab(url: "https://example.com/a", in: space)

        tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .tab(tab),
                fromContainer: .spaceRegular(space.id),
                toContainer: .folder(folder.id),
                toIndex: 0
            )
        )

        let folderPins = tabManager.spacePinnedPins(for: space.id)
        XCTAssertEqual(folderPins.count, 1)
        XCTAssertEqual(folderPins.first?.folderId, folder.id)
        XCTAssertFalse(folder.isOpen)
        XCTAssertTrue(tabManager.tabsBySpace[space.id]?.isEmpty ?? false)
    }

    func testSpacePinnedLauncherMovedIntoClosedFolderKeepsFolderClosed() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.createSpace(name: "Workspace")
        let folder = tabManager.createFolder(for: space.id, name: "Folder")
        folder.isOpen = false
        let pin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: space.id,
            index: 0,
            launchURL: URL(string: "https://example.com/launcher")!,
            title: "Launcher"
        )
        tabManager.setSpacePinnedShortcuts([pin], for: space.id)

        tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .tab(tabManager.dragProxyTab(for: pin)),
                fromContainer: .spacePinned(space.id),
                toContainer: .folder(folder.id),
                toIndex: 0
            )
        )

        let movedPin = try XCTUnwrap(tabManager.shortcutPin(by: pin.id))
        XCTAssertEqual(movedPin.folderId, folder.id)
        XCTAssertFalse(folder.isOpen)
        XCTAssertEqual(tabManager.folderPinnedPins(for: folder.id, in: space.id).map(\.id), [pin.id])
    }

    func testActiveLiveLauncherMovedIntoClosedFolderKeepsFolderClosedAndLiveBinding() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.createSpace(name: "Workspace")
        let folder = tabManager.createFolder(for: space.id, name: "Folder")
        folder.isOpen = false
        let pin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: space.id,
            index: 0,
            launchURL: URL(string: "https://example.com/live")!,
            title: "Live"
        )
        tabManager.setSpacePinnedShortcuts([pin], for: space.id)

        let windowId = UUID()
        let liveTab = tabManager.activateShortcutPin(pin, in: windowId, currentSpaceId: space.id)
        XCTAssertNil(liveTab.folderId)

        tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .tab(tabManager.dragProxyTab(for: pin)),
                fromContainer: .spacePinned(space.id),
                toContainer: .folder(folder.id),
                toIndex: 0
            )
        )

        let movedPin = try XCTUnwrap(tabManager.shortcutPin(by: pin.id))
        let movedLiveTab = try XCTUnwrap(tabManager.shortcutLiveTab(for: pin.id, in: windowId))
        XCTAssertEqual(movedPin.folderId, folder.id)
        XCTAssertEqual(movedLiveTab.folderId, folder.id)
        XCTAssertFalse(folder.isOpen)
    }

    func testFolderLauncherMoveToTopLevelPinnedUpdatesLiveInstanceFolderBinding() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.createSpace(name: "Workspace")
        let folder = tabManager.createFolder(for: space.id, name: "Folder")
        let tab = tabManager.createNewTab(url: "https://example.com/folder", in: space)

        tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .tab(tab),
                fromContainer: .spaceRegular(space.id),
                toContainer: .folder(folder.id),
                toIndex: 0
            )
        )

        let folderPin = try XCTUnwrap(tabManager.spacePinnedPins(for: space.id).first)
        let windowId = UUID()
        let liveTab = tabManager.activateShortcutPin(folderPin, in: windowId, currentSpaceId: space.id)
        XCTAssertEqual(liveTab.folderId, folder.id)

        tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .tab(tabManager.dragProxyTab(for: folderPin)),
                fromContainer: .folder(folder.id),
                toContainer: .spacePinned(space.id),
                toIndex: 0
            )
        )

        let updatedPin = try XCTUnwrap(tabManager.shortcutPin(by: folderPin.id))
        XCTAssertNil(updatedPin.folderId)
        XCTAssertNil(tabManager.shortcutLiveTab(for: folderPin.id, in: windowId)?.folderId)
    }

    func testPinnedToRegularTailMovesLauncherOutOfPinnedContainer() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.createSpace(name: "Workspace")
        let firstRegular = tabManager.createNewTab(url: "https://example.com/first", in: space)
        let secondRegular = tabManager.createNewTab(url: "https://example.com/second", in: space)

        tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .tab(firstRegular),
                fromContainer: .spaceRegular(space.id),
                toContainer: .spacePinned(space.id),
                toIndex: 0
            )
        )

        let pinned = try XCTUnwrap(tabManager.spacePinnedPins(for: space.id).first)
        let windowId = UUID()
        _ = tabManager.activateShortcutPin(pinned, in: windowId, currentSpaceId: space.id)

        tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .tab(tabManager.dragProxyTab(for: pinned)),
                fromContainer: .spacePinned(space.id),
                toContainer: .spaceRegular(space.id),
                toIndex: 1
            )
        )

        XCTAssertTrue(tabManager.spacePinnedPins(for: space.id).isEmpty)
        let urls = (tabManager.tabsBySpace[space.id] ?? []).map(\.url.absoluteString)
        XCTAssertEqual(urls, [
            secondRegular.url.absoluteString,
            pinned.launchURL.absoluteString,
        ])
        XCTAssertNil(tabManager.shortcutLiveTab(for: pinned.id, in: windowId))
        let movedTab = try XCTUnwrap(
            tabManager.tabsBySpace[space.id]?.first(where: { $0.url == pinned.launchURL })
        )
        XCTAssertEqual(movedTab.spaceId, space.id)
        XCTAssertFalse(movedTab.isShortcutLiveInstance)
    }

    func testEssentialsToRegularMovesOutOfProfilePinnedCollection() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.createSpace(name: "Workspace")
        let profileId = UUID()
        let pin = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: profileId,
            index: 0,
            launchURL: URL(string: "https://example.com/essential")!,
            title: "Essential"
        )
        tabManager.setPinnedTabs([pin], for: profileId)

        tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .tab(tabManager.dragProxyTab(for: pin)),
                fromContainer: .essentials,
                toContainer: .spaceRegular(space.id),
                toIndex: 0
            )
        )

        XCTAssertTrue(tabManager.essentialPins(for: profileId).isEmpty)
        XCTAssertEqual(tabManager.tabsBySpace[space.id]?.first?.url.absoluteString, pin.launchURL.absoluteString)
    }

    func testSplitDropDragResolutionReturnsShortcutProxyForLauncherPayload() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.createSpace(name: "Workspace")
        let pin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: space.id,
            index: 0,
            launchURL: URL(string: "https://example.com/launcher")!,
            title: "Launcher"
        )
        tabManager.setSpacePinnedShortcuts([pin], for: space.id)

        let resolved = try XCTUnwrap(tabManager.resolveDragTab(for: pin.id))
        XCTAssertEqual(resolved.id, pin.id)
        XCTAssertEqual(resolved.shortcutPinId, pin.id)
        XCTAssertEqual(resolved.url, pin.launchURL)
        XCTAssertEqual(resolved.spaceId, space.id)
        XCTAssertTrue(resolved.isShortcutLiveInstance)
    }

    func testFolderDragItemResolvesToFolderPayload() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.createSpace(name: "Workspace")
        let folder = tabManager.createFolder(for: space.id, name: "Folder")
        let item = SumiDragItem.folder(folderId: folder.id, title: folder.name)

        let payload = try XCTUnwrap(tabManager.resolveSidebarDragPayload(for: item))
        guard case .folder(let resolvedFolder) = payload else {
            XCTFail("Expected folder payload")
            return
        }

        XCTAssertEqual(resolvedFolder.id, folder.id)
    }

    func testFolderDragReordersTopLevelPinnedFolders() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.createSpace(name: "Workspace")
        let first = tabManager.createFolder(for: space.id, name: "First")
        let second = tabManager.createFolder(for: space.id, name: "Second")

        tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .folder(first),
                fromContainer: .spacePinned(space.id),
                toContainer: .spacePinned(space.id),
                toIndex: 2
            )
        )

        let reordered = tabManager.topLevelSpacePinnedItems(for: space.id)
        XCTAssertEqual(reordered.map(\.id), [second.id, first.id])
        XCTAssertEqual(tabManager.folders(for: space.id).map(\.index), [0, 1])
    }

    func testFolderDragReordersWithinMixedTopLevelPinnedItems() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.createSpace(name: "Workspace")
        let firstPin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: space.id,
            index: 0,
            launchURL: URL(string: "https://example.com/first")!,
            title: "First"
        )
        let secondPin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: space.id,
            index: 2,
            launchURL: URL(string: "https://example.com/second")!,
            title: "Second"
        )
        let folder = tabManager.createFolder(for: space.id, name: "Folder")
        folder.index = 1
        tabManager.setFolders([folder], for: space.id)
        tabManager.setSpacePinnedShortcuts([firstPin, secondPin], for: space.id)

        XCTAssertEqual(tabManager.topLevelSpacePinnedItems(for: space.id).map(\.id), [
            firstPin.id,
            folder.id,
            secondPin.id,
        ])

        tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .folder(folder),
                fromContainer: .spacePinned(space.id),
                toContainer: .spacePinned(space.id),
                toIndex: 3
            )
        )

        XCTAssertEqual(tabManager.topLevelSpacePinnedItems(for: space.id).map(\.id), [
            firstPin.id,
            secondPin.id,
            folder.id,
        ])
        XCTAssertEqual(tabManager.spacePinnedPins(for: space.id).map(\.index), [0, 1])
        XCTAssertEqual(tabManager.folders(for: space.id).map(\.index), [2])
    }

    func testFolderDragIntoFolderIsIgnored() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.createSpace(name: "Workspace")
        let first = tabManager.createFolder(for: space.id, name: "First")
        let second = tabManager.createFolder(for: space.id, name: "Second")

        let accepted = tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .folder(first),
                fromContainer: .spacePinned(space.id),
                toContainer: .folder(second.id),
                toIndex: 0
            )
        )

        XCTAssertFalse(accepted)
        let unchanged = tabManager.topLevelSpacePinnedItems(for: space.id)
        XCTAssertEqual(unchanged.map(\.id), [first.id, second.id])
        XCTAssertTrue(tabManager.folderPinnedPins(for: second.id, in: space.id).isEmpty)
    }

    func testSameContainerReorderForTopLevelPinnedUpdatesIndices() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.createSpace(name: "Workspace")
        let first = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: space.id,
            index: 0,
            launchURL: URL(string: "https://example.com/one")!,
            title: "One"
        )
        let second = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: space.id,
            index: 1,
            launchURL: URL(string: "https://example.com/two")!,
            title: "Two"
        )
        tabManager.setSpacePinnedShortcuts([first, second], for: space.id)

        tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .tab(tabManager.dragProxyTab(for: first)),
                fromContainer: .spacePinned(space.id),
                toContainer: .spacePinned(space.id),
                toIndex: 1
            )
        )

        let reordered = tabManager.spacePinnedPins(for: space.id)
        XCTAssertEqual(reordered.map(\.id), [second.id, first.id])
        XCTAssertEqual(reordered.map(\.index), [0, 1])
    }

    func testSameContainerReorderForEssentialsUpdatesIndices() throws {
        let tabManager = try makeInMemoryTabManager()
        let profileId = UUID()
        let first = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: profileId,
            index: 0,
            launchURL: URL(string: "https://example.com/essential-one")!,
            title: "One"
        )
        let second = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: profileId,
            index: 1,
            launchURL: URL(string: "https://example.com/essential-two")!,
            title: "Two"
        )
        tabManager.setPinnedTabs([first, second], for: profileId)

        tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .tab(tabManager.dragProxyTab(for: first)),
                fromContainer: .essentials,
                toContainer: .essentials,
                toIndex: 1
            )
        )

        let reordered = tabManager.essentialPins(for: profileId)
        XCTAssertEqual(reordered.map(\.id), [second.id, first.id])
        XCTAssertEqual(reordered.map(\.index), [0, 1])
    }

    func testEssentialsToSecondarySpacePinnedMovesLauncherOutOfProfilePinnedCollection() throws {
        let tabManager = try makeInMemoryTabManager()
        let sourceProfileId = UUID()
        let targetSpace = tabManager.createSpace(name: "Secondary")
        let pin = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: sourceProfileId,
            index: 0,
            launchURL: URL(string: "https://example.com/essential-secondary-pinned")!,
            title: "Essential"
        )
        tabManager.setPinnedTabs([pin], for: sourceProfileId)

        tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .tab(tabManager.dragProxyTab(for: pin)),
                fromContainer: .essentials,
                toContainer: .spacePinned(targetSpace.id),
                toIndex: 0
            )
        )

        XCTAssertTrue(tabManager.essentialPins(for: sourceProfileId).isEmpty)
        XCTAssertEqual(tabManager.spacePinnedPins(for: targetSpace.id).map(\.launchURL), [pin.launchURL])
    }

    func testEssentialsToSecondaryRegularMovesLauncherOutOfProfilePinnedCollection() throws {
        let tabManager = try makeInMemoryTabManager()
        let sourceProfileId = UUID()
        let targetSpace = tabManager.createSpace(name: "Secondary")
        let pin = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: sourceProfileId,
            index: 0,
            launchURL: URL(string: "https://example.com/essential-secondary-regular")!,
            title: "Essential"
        )
        tabManager.setPinnedTabs([pin], for: sourceProfileId)

        tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .tab(tabManager.dragProxyTab(for: pin)),
                fromContainer: .essentials,
                toContainer: .spaceRegular(targetSpace.id),
                toIndex: 0
            )
        )

        XCTAssertTrue(tabManager.essentialPins(for: sourceProfileId).isEmpty)
        XCTAssertEqual(tabManager.tabsBySpace[targetSpace.id]?.map(\.url), [pin.launchURL])
    }

    func testSameContainerReorderForFolderChildrenUpdatesIndicesAndFolderBinding() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.createSpace(name: "Workspace")
        let folder = tabManager.createFolder(for: space.id, name: "Folder")
        let first = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: space.id,
            index: 0,
            folderId: folder.id,
            launchURL: URL(string: "https://example.com/folder-one")!,
            title: "One"
        )
        let second = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: space.id,
            index: 1,
            folderId: folder.id,
            launchURL: URL(string: "https://example.com/folder-two")!,
            title: "Two"
        )
        tabManager.setSpacePinnedShortcuts([first, second], for: space.id)

        tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .tab(tabManager.dragProxyTab(for: first)),
                fromContainer: .folder(folder.id),
                toContainer: .folder(folder.id),
                toIndex: 1
            )
        )

        let reordered = tabManager.folderPinnedPins(for: folder.id, in: space.id)
        XCTAssertEqual(reordered.map(\.id), [second.id, first.id])
        XCTAssertEqual(reordered.map(\.folderId), [folder.id, folder.id])
        XCTAssertEqual(reordered.map(\.index), [0, 1])
    }

    func testSameContainerReorderForRegularTabsUpdatesIndices() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.createSpace(name: "Workspace")
        let first = tabManager.createNewTab(url: "https://example.com/one", in: space)
        let second = tabManager.createNewTab(url: "https://example.com/two", in: space)
        let third = tabManager.createNewTab(url: "https://example.com/three", in: space)

        tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .tab(first),
                fromContainer: .spaceRegular(space.id),
                toContainer: .spaceRegular(space.id),
                toIndex: 3
            )
        )

        let reordered = tabManager.tabsBySpace[space.id] ?? []
        XCTAssertEqual(reordered.map(\.id), [second.id, third.id, first.id])
        XCTAssertEqual(reordered.map(\.index), [0, 1, 2])
    }

    func testCrossSpaceSidebarOperationIsRejectedWithoutMutation() throws {
        let tabManager = try makeInMemoryTabManager()
        let sourceSpace = tabManager.createSpace(name: "Source")
        let targetSpace = tabManager.createSpace(name: "Target")
        let tab = tabManager.createNewTab(url: "https://example.com/cross-space", in: sourceSpace)

        let accepted = tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .tab(tab),
                fromContainer: .spaceRegular(sourceSpace.id),
                toContainer: .spaceRegular(targetSpace.id),
                toIndex: 0
            )
        )

        XCTAssertFalse(accepted)
        XCTAssertEqual(tabManager.tabsBySpace[sourceSpace.id]?.map(\.id), [tab.id])
        XCTAssertTrue(tabManager.tabsBySpace[targetSpace.id]?.isEmpty ?? true)
    }

    func testCrossProfileSidebarOperationIsRejectedWithoutMutation() throws {
        let tabManager = try makeInMemoryTabManager()
        let sourceProfileId = UUID()
        let otherProfileId = UUID()
        let sourceSpace = tabManager.createSpace(name: "Source", profileId: sourceProfileId)
        let tab = tabManager.createNewTab(url: "https://example.com/cross-profile", in: sourceSpace)

        let accepted = tabManager.performSidebarDragOperation(
            DragOperation(
                payload: .tab(tab),
                scope: SidebarDragScope(
                    spaceId: sourceSpace.id,
                    profileId: otherProfileId,
                    sourceContainer: .spaceRegular(sourceSpace.id),
                    sourceItemId: tab.id,
                    sourceItemKind: .tab
                ),
                fromContainer: .spaceRegular(sourceSpace.id),
                toContainer: .essentials,
                toIndex: 0
            )
        )

        XCTAssertFalse(accepted)
        XCTAssertEqual(tabManager.tabsBySpace[sourceSpace.id]?.map(\.id), [tab.id])
        XCTAssertTrue(tabManager.essentialPins(for: sourceProfileId).isEmpty)
        XCTAssertTrue(tabManager.essentialPins(for: otherProfileId).isEmpty)
    }

    func testSpaceReorderSourcesDoNotUseSidebarDragAndDropPipeline() throws {
        let scannedPaths = [
            "Navigation/Sidebar/SpacesList/SpacesList.swift",
            "Navigation/Sidebar/SpacesList/SpacesListItem.swift",
            "Navigation/Sidebar/SpacesList/SpaceReorderDragState.swift",
            "Navigation/Sidebar/SidebarBottomBar.swift",
            "Sumi/Managers/TabManager/TabManager+SpaceLifecycle.swift"
        ]
        let forbiddenTokens = [
            "SidebarDragState",
            "SidebarGlobalDragOverlay",
            "SumiDragItem"
        ]

        for path in scannedPaths {
            let source = try String(
                contentsOf: Self.repoRoot.appendingPathComponent(path),
                encoding: .utf8
            )
            for token in forbiddenTokens {
                XCTAssertFalse(source.contains(token), "\(path) must not reference \(token)")
            }
        }
    }

    private func makeInMemoryTabManager() throws -> TabManager {
        let container = try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return TabManager(context: container.mainContext, loadPersistedState: false)
    }

    private static var repoRoot: URL {
        var url = URL(fileURLWithPath: #filePath)
        url.deleteLastPathComponent()
        url.deleteLastPathComponent()
        return url
    }

    private func makeMouseEvent(
        type: NSEvent.EventType,
        location: NSPoint
    ) -> NSEvent {
        guard let event = NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ) else {
            fatalError("Failed to create mouse event for test.")
        }
        return event
    }
}

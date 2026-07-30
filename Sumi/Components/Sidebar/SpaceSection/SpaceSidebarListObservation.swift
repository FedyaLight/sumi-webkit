import Combine
import SumiDomain
import SwiftUI

enum SpaceSidebarListElementID: Hashable {
    case pinnedTop
    case folderHeader(UUID)
    case folderBodyTop(UUID)
    case folderBodyBottom(UUID)
    case shortcut(UUID)
    case liveItem(UUID, String)
    case splitGroup(UUID)
    case boundary
    case regularRunStart
    case regularTab(UUID)
    case regularRunEnd
    case newTabGap
    case newTab

    /// The dragged item behind a row that can move between the pinned and
    /// regular sections, and therefore lend or adopt a presentation identity.
    var transferableItemID: UUID? {
        switch self {
        case .shortcut(let itemID), .regularTab(let itemID):
            return itemID
        default:
            return nil
        }
    }
}

enum SpaceSidebarListElementPayload {
    struct Boundary {
        let layout: SpaceTabSectionBoundaryLayout
        let hasPersistedTabs: Bool
    }

    struct Folder {
        let model: TabFolder
        let presentation: SidebarFolderPresentationCell
        let parentFolderID: UUID?
        let containerIndex: Int
        let nestingDepth: Int
        let projection: SidebarFolderViewProjection
        let contentProjection: SidebarFolderContentProjection
        let orderedDescendantItemIDs: [UUID]
    }

    struct TopLevelShortcut {
        let pin: ShortcutPin
        let liveTab: Tab?
        let runtimeAffordance: SumiLauncherRuntimeAffordanceState
        let index: Int
    }

    struct FolderShortcut {
        let pin: ShortcutPin
        let folder: TabFolder
        let index: Int
        let nestingDepth: Int
        let projection: SidebarFolderViewProjection
    }

    struct TopLevelSplitGroup {
        let group: SplitGroup
        let items: [SplitGroupSidebarItem]
        let index: Int
    }

    struct FolderSplitGroup {
        let group: SplitGroup
        let items: [SplitGroupSidebarItem]
        let folder: TabFolder
        let index: Int
        let nestingDepth: Int
    }

    struct LiveItem {
        let item: SumiLiveFolderItem
        let folder: TabFolder
        let index: Int
        let nestingDepth: Int
        let isSelected: Bool
    }

    struct RegularSplitGroup {
        let group: SplitGroup
        let tabByID: [UUID: Tab]
    }

    case pinnedTop
    case folderBodyTop
    case folderBodyBottom
    case folder(Folder)
    case topLevelShortcut(TopLevelShortcut)
    case folderShortcut(FolderShortcut)
    case collapsedNestedSticky(UUID)
    case topLevelSplitGroup(TopLevelSplitGroup)
    case folderSplitGroup(FolderSplitGroup)
    case liveItem(LiveItem)
    case boundary(Boundary)
    case regularRunStart
    case regularTab(Tab)
    case regularSplitGroup(RegularSplitGroup)
    case regularRunEnd
    case newTabGap
    case newTab
}

struct SpaceSidebarDragSnapshots {
    let pinned: SpacePinnedDragSnapshot
    let regular: SpaceRegularDragSnapshot
}

struct SpaceSidebarDragSnapshotReader<Content: View>: View {
    let spaceID: UUID
    @ObservedObject var listPresentation: SidebarListDragPresentation
    @ViewBuilder let content: (SpaceSidebarDragSnapshots) -> Content

    @EnvironmentObject private var dragGeometry: SidebarDragGeometryModule

    var body: some View {
        let generation = dragGeometry.sidebarGeometryGeneration
        content(
            SpaceSidebarDragSnapshots(
                pinned: SpacePinnedDragSnapshot(
                    frame: listPresentation.frame,
                    geometryGeneration: generation,
                    spaceID: spaceID
                ),
                regular: SpaceRegularDragSnapshot(
                    frame: listPresentation.frame,
                    geometryGeneration: generation
                )
            )
        )
    }
}

/// A single demand-scoped subscription fan-in for the live folders whose
/// headers are currently reachable in the flattened scene.
@MainActor
final class SpaceSidebarLiveFolderRevision: ObservableObject {
    @Published private(set) var snapshots: [UUID: SidebarLiveFolderSnapshot] = [:]

    private let manager: SumiLiveFolderManager
    private var folderIDs: [UUID] = []
    private var isActive = false
    private var cancellable: AnyCancellable?

    init(manager: SumiLiveFolderManager) {
        self.manager = manager
    }

    func reconcile(folderIDs: [UUID], isActive: Bool) {
        let normalizedIDs = Array(Set(folderIDs)).sorted {
            $0.uuidString < $1.uuidString
        }
        guard normalizedIDs != self.folderIDs || isActive != self.isActive
        else { return }

        self.folderIDs = normalizedIDs
        self.isActive = isActive
        cancellable?.cancel()
        cancellable = nil

        let nextSnapshots = Dictionary(
            uniqueKeysWithValues: normalizedIDs.map { folderID in
                (folderID, snapshot(for: folderID))
            }
        )
        if nextSnapshots != snapshots {
            snapshots = nextSnapshots
        }

        guard isActive, !normalizedIDs.isEmpty else { return }
        cancellable = Publishers.MergeMany(
            normalizedIDs.map { folderID in
                manager.contentChanges(for: folderID)
                    .map { folderID }
            }
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] folderID in
            self?.refresh(folderID: folderID)
        }
    }

    private func refresh(folderID: UUID) {
        guard snapshots.keys.contains(folderID) else { return }
        let next = snapshot(for: folderID)
        guard snapshots[folderID] != next else { return }
        snapshots[folderID] = next
    }

    private func snapshot(for folderID: UUID) -> SidebarLiveFolderSnapshot {
        let source = manager.source(for: folderID)
        return SidebarLiveFolderSnapshot(
            source: source,
            items: source == nil
                ? []
                : manager.visibleItems(for: folderID)
        )
    }

    isolated deinit {
        cancellable?.cancel()
    }
}

struct SpaceSidebarLiveFolderReader<Content: View>: View {
    let folderIDs: [UUID]
    let isActive: Bool
    @ViewBuilder let content: ([UUID: SidebarLiveFolderSnapshot]) -> Content

    @StateObject private var revision: SpaceSidebarLiveFolderRevision

    init(
        manager: SumiLiveFolderManager,
        folderIDs: [UUID],
        isActive: Bool,
        @ViewBuilder content: @escaping (
            [UUID: SidebarLiveFolderSnapshot]
        ) -> Content
    ) {
        self.folderIDs = folderIDs
        self.isActive = isActive
        self.content = content
        _revision = StateObject(
            wrappedValue: SpaceSidebarLiveFolderRevision(manager: manager)
        )
    }

    var body: some View {
        content(revision.snapshots)
            .onAppear {
                revision.reconcile(folderIDs: folderIDs, isActive: isActive)
            }
            .onChange(of: folderIDs) { _, folderIDs in
                revision.reconcile(folderIDs: folderIDs, isActive: isActive)
            }
            .onChange(of: isActive) { _, isActive in
                revision.reconcile(folderIDs: folderIDs, isActive: isActive)
            }
            .onDisappear {
                revision.reconcile(folderIDs: [], isActive: false)
            }
    }
}

/// The entire scroll-content Interface for one Space. Pinned content, every
/// recursive folder row, the section boundary, regular tabs, and New Tab all
/// share one lazy presentation surface.

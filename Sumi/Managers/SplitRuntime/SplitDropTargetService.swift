import CoreGraphics
import Foundation
import SumiDomain

/// Resolves pointer geometry into a durable member target. It owns only the
/// bounded layout cache used while a full-group drag is active.
@MainActor
final class SplitDropTargetService {
    private let splitGroups: SplitGroupStore
    private let windowState: (UUID) -> BrowserWindowState?
    private let currentTab: (BrowserWindowState) -> Tab?
    private let query: WindowSplitQuery
    private let memberResolver: SplitRuntimeMemberResolver
    private let groupedResolver = SplitGroupedDropTargetResolver()
    private var fullGroupLayouts = SplitFullGroupLayoutCatalog()

    init(
        splitGroups: SplitGroupStore,
        windowState: @escaping (UUID) -> BrowserWindowState?,
        currentTab: @escaping (BrowserWindowState) -> Tab?,
        query: WindowSplitQuery,
        memberResolver: SplitRuntimeMemberResolver
    ) {
        self.splitGroups = splitGroups
        self.windowState = windowState
        self.currentTab = currentTab
        self.query = query
        self.memberResolver = memberResolver
    }

    func target(
        at location: CGPoint,
        in bounds: CGRect,
        windowID: UUID,
        draggedMemberID: SplitMemberID?,
        draggedLookupID: UUID?
    ) -> SplitDropTarget? {
        guard bounds.width > 0,
              bounds.height > 0,
              bounds.contains(location),
              let windowState = windowState(windowID) else {
            return nil
        }
        let draggedMember = draggedMemberID.flatMap {
            previewMember(for: $0, in: windowState)
        } ?? draggedLookupID.flatMap {
            guard let memberID = memberResolver.memberID(forLookupID: $0) else {
                return nil
            }
            return previewMember(for: memberID, in: windowState)
        }

        if let group = query.group(in: windowID) {
            return groupedResolver.target(
                in: group,
                at: location,
                bounds: bounds,
                draggedMember: draggedMember,
                fullGroupLayouts: &fullGroupLayouts
            )
        }

        guard let current = currentTab(windowState),
              current.representsSumiNativeSurface == false,
              let currentMemberID = memberResolver.memberID(for: current),
              let currentMember = memberResolver.makeMember(
                  for: currentMemberID,
                  windowState: windowState
              ) else {
            return nil
        }
        return SplitFirstDropTargetResolver.target(
            currentMember: currentMember,
            at: location,
            bounds: bounds,
            draggedMember: draggedMember
        )
    }

    func clearCachedLayouts() {
        fullGroupLayouts.removeAll(keepingCapacity: true)
    }

    private func previewMember(
        for memberID: SplitMemberID,
        in windowState: BrowserWindowState
    ) -> SplitMember? {
        splitGroups.group(containing: memberID)?
            .member(for: memberID)
            ?? memberResolver.makeMember(
                for: memberID,
                windowState: windowState
            )
    }
}

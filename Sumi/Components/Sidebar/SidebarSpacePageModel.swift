//
//  SidebarSpacePageModel.swift
//  Sumi
//
//

import Combine
import Foundation

/// Page-scoped observation hub for sidebar structural managers.
///
/// Forwards `objectWillChange` from tab / profile / live-folder / split managers
/// so `SpacesSideBarView` can observe one model instead of four.
@MainActor
final class SidebarSpacePageModel: ObservableObject {
    @Published var structuralRevision: UInt = 0

    let tabManager: TabManager
    let profileManager: ProfileManager
    let liveFolderManager: SumiLiveFolderManager
    let splitManager: SplitViewManager

    private let tabStructuralRevision: () -> UInt
    private var cancellables = Set<AnyCancellable>()

    init(browserContext: SidebarBrowserContext) {
        tabManager = browserContext.tabManager
        profileManager = browserContext.profileManager
        liveFolderManager = browserContext.liveFolderManager
        splitManager = browserContext.splitManager
        tabStructuralRevision = browserContext.tabStructuralRevision
        structuralRevision = tabStructuralRevision()

        forwardObjectWillChange(from: tabManager)
        forwardObjectWillChange(from: profileManager)
        forwardObjectWillChange(from: liveFolderManager)
        forwardObjectWillChange(from: splitManager)
    }

    func bump() {
        structuralRevision &+= 1
    }

    func refreshStructuralRevision() {
        structuralRevision = tabStructuralRevision()
    }

    func availableSpaces(isIncognito: Bool, ephemeralSpaces: [Space]) -> [Space] {
        isIncognito ? ephemeralSpaces : tabManager.spaceStateOwner.spaces
    }

    private func forwardObjectWillChange<T: ObservableObject>(from source: T) {
        source.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
}

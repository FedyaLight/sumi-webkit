import Combine
import Foundation

/// Page-scoped subscriptions for the mounted sidebar.
///
/// The publisher values are deliberately narrow: structural inventory,
/// profiles, and live-folder content each invalidate only their consumers.
/// Constructing the production streams installs no observers while the page
/// is unmounted.
@MainActor
final class SidebarSpacePageModel: ObservableObject {
    @Published private(set) var structuralRevision: UInt
    @Published private(set) var profiles: [Profile]
    @Published private(set) var profileRuntimeRevision: UInt = 0
    @Published private(set) var liveFolderRevision: UInt = 0

    let profileManager: ProfileManager
    let liveFolderManager: SumiLiveFolderManager
    private let spaceLifecycle: SidebarSpaceLifecycle
    private let updateStreams: SidebarUpdateStreams
    private var cancellables = Set<AnyCancellable>()

    init(
        browserContext: SidebarBrowserContext,
        spaceLifecycle: SidebarSpaceLifecycle,
        updateStreams: SidebarUpdateStreams
    ) {
        profileManager = browserContext.profileManager
        liveFolderManager = browserContext.liveFolderManager
        self.spaceLifecycle = spaceLifecycle
        self.updateStreams = updateStreams
        structuralRevision = 0
        profiles = browserContext.profileManager.profiles
    }

    func setActive(_ isActive: Bool) {
        if !isActive {
            cancellables.removeAll()
            return
        }
        guard cancellables.isEmpty else { return }

        updateStreams.inventoryRevision
            .receive(on: RunLoop.main)
            .sink { [weak self] revision in
                self?.structuralRevision = revision
            }
            .store(in: &cancellables)

        updateStreams.profiles
            .receive(on: RunLoop.main)
            .sink { [weak self] profiles in
                self?.profiles = profiles
            }
            .store(in: &cancellables)

        updateStreams.profileRuntimeChanged
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.profileRuntimeRevision &+= 1
            }
            .store(in: &cancellables)

        updateStreams.liveFoldersChanged
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.liveFolderRevision &+= 1
            }
            .store(in: &cancellables)
    }

    func availableSpaces(isIncognito: Bool, ephemeralSpaces: [Space]) -> [Space] {
        spaceLifecycle.availableSpaces(
            isIncognito: isIncognito,
            ephemeralSpaces: ephemeralSpaces
        )
    }
}

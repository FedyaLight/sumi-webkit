import Combine

/// Owns the browser process's selected profile publication. Consumers that
/// only need this state retain this authority instead of resolving it through
/// the complete `BrowserManager` graph.
@MainActor
final class BrowserCurrentProfileAuthority {
    @Published private(set) var currentProfile: Profile?
    @Published private(set) var isTransitioning = false

    init(_ currentProfile: Profile?) {
        self.currentProfile = currentProfile
    }

    fileprivate func setCurrentProfile(_ profile: Profile?) {
        currentProfile = profile
    }

    fileprivate func setTransitioning(_ isTransitioning: Bool) {
        self.isTransitioning = isTransitioning
    }
}

extension BrowserManager {
    var currentProfile: Profile? {
        get { currentProfileAuthority.currentProfile }
        set {
            objectWillChange.send()
            currentProfileAuthority.setCurrentProfile(newValue)
        }
    }

    var isTransitioningProfile: Bool {
        get { currentProfileAuthority.isTransitioning }
        set {
            currentProfileAuthority.setTransitioning(newValue)
        }
    }
}

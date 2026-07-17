import Foundation

@MainActor
final class BrowserProfileAdoptionService {
    private let currentProfile: BrowserCurrentProfileAuthority
    private let profiles: ProfileManager
    private let transitions: BrowserProfileSwitchTransitionOwner

    init(
        currentProfile: BrowserCurrentProfileAuthority,
        profiles: ProfileManager,
        transitions: BrowserProfileSwitchTransitionOwner
    ) {
        self.currentProfile = currentProfile
        self.profiles = profiles
        self.transitions = transitions
    }

    func adoptProfileIfNeeded(
        for windowState: BrowserWindowState,
        context: BrowserProfileSwitchContext
    ) {
        guard let targetProfileID = windowState.currentProfileId else { return }
        guard currentProfile.currentProfile?.id != targetProfileID else { return }
        guard let targetProfile = profiles.profiles.first(where: {
            $0.id == targetProfileID
        }) else {
            let fallbackID = currentProfile.currentProfile?.id
                ?? profiles.profiles.first?.id
            windowState.currentProfileId = fallbackID
            RuntimeDiagnostics.emit(
                "Window \(windowState.id) referenced missing profile \(targetProfileID); reset currentProfileId to \(fallbackID?.uuidString ?? "nil")."
            )
            return
        }

        Task { [weak transitions, weak windowState] in
            guard let transitions, let windowState else { return }
            await transitions.switchToProfile(
                targetProfile,
                context: context,
                in: windowState
            )
        }
    }
}

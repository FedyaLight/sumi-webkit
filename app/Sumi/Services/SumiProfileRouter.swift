import Foundation

@MainActor
protocol SumiProfileRoutingSupport: AnyObject {
    var currentProfile: Profile? { get }
    var isSwitchingProfile: Bool { get }
    var profileManager: ProfileManager { get }
    var windowRegistry: WindowRegistry? { get }

    func switchToProfile(
        _ profile: Profile,
        context: BrowserManager.ProfileSwitchContext,
        in windowState: BrowserWindowState?
    ) async
}

@MainActor
final class SumiProfileRouter {
    func activeProfileId(
        for space: Space?,
        currentProfile: Profile?
    ) -> UUID? {
        space?.profileId ?? currentProfile?.id
    }

    func adoptProfileIfNeeded(
        for windowState: BrowserWindowState,
        context: BrowserManager.ProfileSwitchContext,
        support: SumiProfileRoutingSupport
    ) {
        guard let targetProfileId = windowState.currentProfileId else { return }
        guard !support.isSwitchingProfile else { return }
        guard support.currentProfile?.id != targetProfileId else { return }
        guard let targetProfile = support.profileManager.profiles.first(where: { $0.id == targetProfileId })
        else {
            let fallbackId = support.currentProfile?.id ?? support.profileManager.profiles.first?.id
            windowState.currentProfileId = fallbackId
            RuntimeDiagnostics.emit(
                "⚠️ [SumiProfileRouter] Window \(windowState.id) referenced missing profile \(targetProfileId); reset currentProfileId to \(fallbackId?.uuidString ?? "nil")."
            )
            return
        }

        Task { [weak support] in
            await support?.switchToProfile(
                targetProfile,
                context: context,
                in: windowState
            )
            await MainActor.run {
                if let activeId = support?.windowRegistry?.activeWindow?.id,
                   activeId == windowState.id
                {
                    support?.windowRegistry?.activeWindow?.currentProfileId = targetProfileId
                }
            }
        }
    }
}

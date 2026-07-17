import Foundation
import SwiftUI

@MainActor
final class BrowserProfileSwitchApplication {
    private let identity: BrowserProfileSwitchIdentityPublication
    private let dataScope: BrowserProfileDataScopeTransition
    private let tabSelection: BrowserProfileTabSelectionTransition

    init(
        identity: BrowserProfileSwitchIdentityPublication,
        dataScope: BrowserProfileDataScopeTransition,
        tabSelection: BrowserProfileTabSelectionTransition
    ) {
        self.identity = identity
        self.dataScope = dataScope
        self.tabSelection = tabSelection
    }

    func apply(
        _ profile: Profile,
        transition: BrowserProfileSwitchAdmission.PreparedTransition,
        isAnimated: Bool
    ) {
        RuntimeDiagnostics.emit {
            "🔀 [BrowserManager] Switching to profile: \(profile.name) (\(profile.id.uuidString)) from: \(identity.currentProfileName())"
        }
        let updates = {
            self.identity.publish(
                profile,
                to: transition.targetWindow,
                isAnimated: isAnimated
            )
            self.dataScope.transition(
                to: profile,
                mutationLease: transition.mutationLease
            )
            self.tabSelection.transition(in: transition.targetWindow)
        }
        if isAnimated {
            withAnimation(.easeInOut(duration: 0.35), updates)
        } else {
            updates()
        }
    }

    func finishAnimationAfterDelay() {
        let identity = identity
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            identity.finishAnimatedTransition()
        }
    }
}

//
//  BrowserProfileLifecycleBundle.swift
//  Sumi
//
//  Phase 5A capability bag: profile switch + startup policy.
//

import Foundation

/// Groups profile-switch transition and startup policy owners.
@MainActor
final class BrowserProfileLifecycleBundle {
    let profileSwitchTransitionOwner: BrowserProfileSwitchTransitionOwner
    let startupPolicyOwner: BrowserStartupPolicyOwner

    init(browserManager: BrowserManager) {
        self.profileSwitchTransitionOwner = BrowserProfileSwitchTransitionOwner(
            host: browserManager,
            dependencies: .live(browserManager: browserManager)
        )
        self.startupPolicyOwner = BrowserStartupPolicyOwner(
            dependencies: .live(browserManager: browserManager)
        )
    }
}

import Foundation

struct SumiPermissionAntiAbusePolicy: Sendable {
    func suppression(
        for key: SumiPermissionKey,
        events: [SumiPermissionAntiAbuseEvent],
        now: Date
    ) -> SumiPermissionPromptSuppression? {
        let scopedEvents = relevantEvents(events, for: key)

        if let deny = scopedEvents
            .filter({ $0.type == .userDenied })
            .max(by: { $0.createdAt < $1.createdAt })
        {
            let cooldown = SumiPermissionPromptCooldown(
                startedAt: deny.createdAt,
                duration: SumiPermissionPromptCooldown.explicitDenyCooldown
            )
            if cooldown.contains(now) {
                return SumiPermissionPromptSuppression(
                    kind: .cooldown,
                    trigger: .explicitDeny,
                    key: key,
                    until: cooldown.expiresAt,
                    reason: "explicit-deny-cooldown"
                )
            }
        }

        let dismissals = scopedEvents
            .filter { $0.type == .userDismissed }
            .sorted { $0.createdAt < $1.createdAt }
        guard let latestDismissal = dismissals.last else { return nil }

        let embargoStart = now.addingTimeInterval(-SumiPermissionPromptCooldown.embargoWindow)
        let dismissalsInEmbargoWindow = dismissals.filter { $0.createdAt >= embargoStart }
        if dismissalsInEmbargoWindow.count >= 3 {
            let cooldown = SumiPermissionPromptCooldown(
                startedAt: latestDismissal.createdAt,
                duration: SumiPermissionPromptCooldown.thirdDismissEmbargo
            )
            if cooldown.contains(now) {
                return SumiPermissionPromptSuppression(
                    kind: .embargo,
                    trigger: .dismissal,
                    key: key,
                    until: cooldown.expiresAt,
                    reason: "repeated-dismissal-embargo"
                )
            }
        }

        let secondDismissStart = now.addingTimeInterval(-SumiPermissionPromptCooldown.secondDismissWindow)
        let dismissalsInSecondWindow = dismissals.filter { $0.createdAt >= secondDismissStart }
        if dismissalsInSecondWindow.count >= 2 {
            let cooldown = SumiPermissionPromptCooldown(
                startedAt: latestDismissal.createdAt,
                duration: SumiPermissionPromptCooldown.secondDismissCooldown
            )
            if cooldown.contains(now) {
                return SumiPermissionPromptSuppression(
                    kind: .cooldown,
                    trigger: .dismissal,
                    key: key,
                    until: cooldown.expiresAt,
                    reason: "repeated-dismissal-cooldown"
                )
            }
        }

        let cooldown = SumiPermissionPromptCooldown(
            startedAt: latestDismissal.createdAt,
            duration: SumiPermissionPromptCooldown.firstDismissCooldown
        )
        guard cooldown.contains(now) else { return nil }
        return SumiPermissionPromptSuppression(
            kind: .cooldown,
            trigger: .dismissal,
            key: key,
            until: cooldown.expiresAt,
            reason: "dismissal-cooldown"
        )
    }

    func systemBlockedSuppression(
        for key: SumiPermissionKey,
        events: [SumiPermissionAntiAbuseEvent],
        now: Date
    ) -> SumiPermissionPromptSuppression? {
        let scopedEvents = relevantEvents(events, for: key)
        guard let latest = scopedEvents
            .filter({ $0.type == .systemBlocked })
            .max(by: { $0.createdAt < $1.createdAt })
        else {
            return nil
        }

        let cooldown = SumiPermissionPromptCooldown(
            startedAt: latest.createdAt,
            duration: SumiPermissionPromptCooldown.systemBlockedCooldown
        )
        guard cooldown.contains(now) else { return nil }
        return SumiPermissionPromptSuppression(
            kind: .cooldown,
            trigger: .systemBlocked,
            key: key,
            until: cooldown.expiresAt,
            reason: "system-blocked-cooldown"
        )
    }

    private func relevantEvents(
        _ events: [SumiPermissionAntiAbuseEvent],
        for key: SumiPermissionKey
    ) -> [SumiPermissionAntiAbuseEvent] {
        let matching = events
            .filter {
                $0.key.persistentIdentity == key.persistentIdentity
                    && $0.key.isEphemeralProfile == key.isEphemeralProfile
            }
            .sorted { $0.createdAt < $1.createdAt }
        guard let latestAllow = matching
            .filter({ $0.type == .userAllowed })
            .max(by: { $0.createdAt < $1.createdAt })
        else {
            return matching
        }
        return matching.filter { $0.createdAt > latestAllow.createdAt }
    }
}

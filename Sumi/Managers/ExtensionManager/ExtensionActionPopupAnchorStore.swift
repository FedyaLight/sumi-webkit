import Foundation

@available(macOS 15.5, *)
@MainActor
final class ExtensionActionPopupAnchorStore {
    static let defaultSessionTTL: TimeInterval = 30
    static let defaultPendingLimit = 16

    private let sessionTTL: TimeInterval
    private let pendingLimit: Int
    private var pendingAnchorsBySessionToken: [UUID: ExtensionActionPopupAnchor] = [:]
    private var latestSessionByExtensionID: [String: UUID] = [:]

    init(
        sessionTTL: TimeInterval = ExtensionActionPopupAnchorStore.defaultSessionTTL,
        pendingLimit: Int = ExtensionActionPopupAnchorStore.defaultPendingLimit
    ) {
        self.sessionTTL = sessionTTL
        self.pendingLimit = pendingLimit
    }

    var pendingCount: Int {
        pendingAnchorsBySessionToken.count
    }

    func latestSessionToken(
        for extensionId: String,
        now: Date = Date()
    ) -> UUID? {
        pruneExpiredAnchors(now: now)
        return latestSessionByExtensionID[extensionId]
    }

    func contains(sessionToken: UUID) -> Bool {
        pendingAnchorsBySessionToken[sessionToken] != nil
    }

    func store(
        _ anchor: ExtensionActionPopupAnchor,
        now: Date = Date()
    ) {
        pruneExpiredAnchors(now: now)
        pendingAnchorsBySessionToken[anchor.sessionToken] = anchor
        latestSessionByExtensionID[anchor.extensionID] = anchor.sessionToken
        enforcePendingLimit()
    }

    func latestAnchor(
        for extensionId: String,
        now: Date = Date()
    ) -> ExtensionActionPopupAnchor? {
        pruneExpiredAnchors(now: now)
        guard let sessionToken = latestSessionByExtensionID[extensionId] else {
            return nil
        }
        return pendingAnchorsBySessionToken[sessionToken]
    }

    func consume(sessionToken: UUID?) {
        guard let sessionToken else { return }
        removeAnchor(sessionToken: sessionToken)
    }

    func clearAnchors(notMatching profileId: UUID) {
        let staleTokens = pendingAnchorsBySessionToken.compactMap { token, anchor in
            anchor.profileID == profileId ? nil : token
        }
        for token in staleTokens {
            removeAnchor(sessionToken: token)
        }
    }

    private func pruneExpiredAnchors(now: Date) {
        let expiredTokens = pendingAnchorsBySessionToken.compactMap { token, anchor -> UUID? in
            now.timeIntervalSince(anchor.capturedAt) > sessionTTL ? token : nil
        }
        for token in expiredTokens {
            removeAnchor(sessionToken: token)
        }
    }

    private func removeAnchor(sessionToken: UUID) {
        guard let anchor = pendingAnchorsBySessionToken.removeValue(forKey: sessionToken) else {
            return
        }
        if latestSessionByExtensionID[anchor.extensionID] == sessionToken {
            latestSessionByExtensionID.removeValue(forKey: anchor.extensionID)
        }
    }

    private func enforcePendingLimit() {
        guard pendingAnchorsBySessionToken.count > pendingLimit else {
            return
        }

        let sortedTokens = pendingAnchorsBySessionToken.values
            .sorted { $0.capturedAt < $1.capturedAt }
            .map(\.sessionToken)

        let overflow = pendingAnchorsBySessionToken.count - pendingLimit
        for token in sortedTokens.prefix(overflow) {
            removeAnchor(sessionToken: token)
        }
    }
}

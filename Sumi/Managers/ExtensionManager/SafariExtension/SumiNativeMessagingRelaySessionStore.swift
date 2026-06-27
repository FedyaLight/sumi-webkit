//
//  SumiNativeMessagingRelaySessionStore.swift
//  Sumi
//
//  Cross-session bookkeeping for Sumi's Safari native messaging relay.
//

import Foundation

@MainActor
final class SumiNativeMessagingRelaySessionStore {
    private let adapterRegistry: SumiNativeMessagingAdapterRegistry
    private var trackedPortSessions: [ObjectIdentifier: SumiNativeMessagingPortSession] = [:]
    private var disconnectingAdapterPortSessionIDs: Set<ObjectIdentifier> = []
    private var pendingOneShotRelays: [ObjectIdentifier: PendingOneShotRelay] = [:]

    private struct PendingOneShotRelay {
        let extensionId: String
        let profileId: UUID?
        let coordinator: SumiNativeMessagingOnceReplyCoordinator
    }

    init(adapterRegistry: SumiNativeMessagingAdapterRegistry) {
        self.adapterRegistry = adapterRegistry
    }

    func trackPortSession(_ session: SumiNativeMessagingPortSession) {
        trackedPortSessions[ObjectIdentifier(session)] = session
    }

    func trackPendingOneShot(
        _ coordinator: SumiNativeMessagingOnceReplyCoordinator,
        extensionId: String,
        profileId: UUID?
    ) {
        pendingOneShotRelays[ObjectIdentifier(coordinator)] = PendingOneShotRelay(
            extensionId: extensionId,
            profileId: profileId,
            coordinator: coordinator
        )
    }

    func untrackPendingOneShot(_ coordinator: SumiNativeMessagingOnceReplyCoordinator) {
        pendingOneShotRelays.removeValue(forKey: ObjectIdentifier(coordinator))
    }

    func cancelPendingOneShotRelays(
        forExtensionId extensionId: String,
        profileId: UUID?
    ) {
        for (key, pending) in pendingOneShotRelays {
            guard pending.extensionId == extensionId else { continue }
            if let profileId, pending.profileId != profileId { continue }
            pending.coordinator.cancel()
            pendingOneShotRelays.removeValue(forKey: key)
        }
    }

    func disconnectTrackedPortSessions(
        forExtensionId extensionId: String,
        profileId: UUID?
    ) {
        let sessions = trackedPortSessions.values.filter { session in
            guard session.extensionId == extensionId else { return false }
            if let profileId, session.profileId != profileId { return false }
            return true
        }

        for session in sessions {
            teardownPortSession(session)
        }
    }

    func disconnectAllTrackedPortSessions() {
        let sessions = Array(trackedPortSessions.values)
        sessions.forEach { teardownPortSession($0) }
    }

    func teardownPortSession(_ session: SumiNativeMessagingPortSession) {
        disconnectAdapterPortIfNeeded(for: session)
        session.disconnect()
    }

    func finalizePortSession(
        _ session: SumiNativeMessagingPortSession,
        unregisterHandler: (SumiNativeMessagingPortSession) -> Void
    ) {
        let key = ObjectIdentifier(session)
        let wasTracked = trackedPortSessions.removeValue(forKey: key) != nil
        disconnectAdapterPortIfNeeded(for: session)
        unregisterHandler(session)
        disconnectingAdapterPortSessionIDs.remove(key)
        if wasTracked {
            SumiNativeMessagingRuntimeCounters.recordPortClosed()
        }
    }

    private func disconnectAdapterPortIfNeeded(for session: SumiNativeMessagingPortSession) {
        let key = ObjectIdentifier(session)
        guard disconnectingAdapterPortSessionIDs.insert(key).inserted else { return }
        if let adapter = adapterRegistry.adapter(
            forHostBundleIdentifier: session.resolvedHostBundleIdentifier
        ) {
            adapter.disconnectPort(session: session)
        }
    }
}

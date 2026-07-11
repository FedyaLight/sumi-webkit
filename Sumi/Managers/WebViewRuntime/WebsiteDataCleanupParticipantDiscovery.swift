import Foundation
import SumiWebRuntime
import WebKit

/// Repeatedly discovers profile-owned WebViews until both repository mutation
/// generation and the concrete participant set reach a fixed point. It also
/// owns the bounded wait for in-flight ownership transitions.
@MainActor
final class WebsiteDataCleanupParticipantDiscovery {
    typealias RetiringResidenceBarrier = @MainActor () async -> Bool
    typealias RuntimeMutationGeneration = @MainActor () -> UInt64
    typealias RuntimeTabProvider = @MainActor () -> [Tab]?

    @MainActor
    private final class BoundedBarrierWait: @unchecked Sendable {
        var continuation: CheckedContinuation<Bool, Never>?
        var barrierJob: Task<Void, Never>?
        var timeoutJob: Task<Void, Never>?
        var isCompleted = false

        func complete(_ result: Bool) {
            guard isCompleted == false else { return }
            isCompleted = true
            barrierJob?.cancel()
            timeoutJob?.cancel()
            continuation?.resume(returning: result)
            continuation = nil
        }
    }

    private let navigationBarrier: WebsiteDataCleanupNavigationBarrier
    private let runtimeTabs: RuntimeTabProvider
    private let liveWebViews: @MainActor (Tab) -> [WKWebView]
    private let waitForRetiringResidenceBarrier: RetiringResidenceBarrier
    private let runtimeMutationGeneration: RuntimeMutationGeneration
    private let residenceBarrierTimeout: Duration

    init(
        navigationBarrier: WebsiteDataCleanupNavigationBarrier,
        runtimeTabs: @escaping RuntimeTabProvider,
        liveWebViews: @escaping @MainActor (Tab) -> [WKWebView],
        waitForRetiringResidenceBarrier: @escaping RetiringResidenceBarrier,
        runtimeMutationGeneration: @escaping RuntimeMutationGeneration,
        residenceBarrierTimeout: Duration
    ) {
        self.navigationBarrier = navigationBarrier
        self.runtimeTabs = runtimeTabs
        self.liveWebViews = liveWebViews
        self.waitForRetiringResidenceBarrier = waitForRetiringResidenceBarrier
        self.runtimeMutationGeneration = runtimeMutationGeneration
        self.residenceBarrierTimeout = residenceBarrierTimeout
    }

    func waitForOwnershipSettlement() async -> Bool {
        let wait = BoundedBarrierWait()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                wait.continuation = continuation
                wait.barrierJob = Task { @MainActor [waitForRetiringResidenceBarrier] in
                    wait.complete(await waitForRetiringResidenceBarrier())
                }
                wait.timeoutJob = Task { @MainActor [residenceBarrierTimeout] in
                    do {
                        try await Task.sleep(for: residenceBarrierTimeout)
                        wait.complete(false)
                    } catch {
                        // The winning branch cancels this timeout.
                    }
                }
            }
        } onCancel: {
            Task { @MainActor in
                wait.complete(false)
            }
        }
    }

    func settleParticipants(
        profileIDs: Set<UUID>,
        session: WebsiteDataCleanupNavigationBarrier.Session,
        canContinue: @escaping @MainActor () -> Bool
    ) async -> Bool {
        while true {
            let discoveryGeneration = runtimeMutationGeneration()
            guard let discoveredParticipants = discoverParticipants(
                profileIDs: profileIDs,
                session: session
            ) else {
                navigationBarrier.invalidate(session)
                return false
            }

            for participant in discoveredParticipants {
                guard await navigationBarrier.prepare(participant) else {
                    navigationBarrier.invalidate(session)
                    return false
                }
            }

            guard navigationBarrier.isValid(session), canContinue() else {
                return false
            }

            // An ownership transition admitted before the mutation gate closed
            // may publish a new residence after the first discovery pass.
            guard await waitForOwnershipSettlement() else {
                return false
            }

            let generationIsStable = runtimeMutationGeneration()
                == discoveryGeneration
            guard let hasUndiscoveredParticipants = hasUndiscoveredParticipants(
                profileIDs: profileIDs,
                session: session
            ) else {
                navigationBarrier.invalidate(session)
                return false
            }
            if generationIsStable && hasUndiscoveredParticipants == false {
                return true
            }
        }
    }

    private func discoverParticipants(
        profileIDs: Set<UUID>,
        session: WebsiteDataCleanupNavigationBarrier.Session
    ) -> [WebsiteDataCleanupNavigationBarrier.Participant]? {
        guard let eligibleTabs = eligibleTabs(profileIDs: profileIDs) else {
            return nil
        }

        var discovered: [WebsiteDataCleanupNavigationBarrier.Participant] = []
        for tab in eligibleTabs {
            for webView in liveWebViews(tab) {
                if navigationBarrier.contains(webView, in: session) {
                    continue
                }
                guard let participant = navigationBarrier.register(
                    tab: tab,
                    webView: webView,
                    in: session
                ) else {
                    return nil
                }
                discovered.append(participant)
            }
        }
        return discovered
    }

    private func hasUndiscoveredParticipants(
        profileIDs: Set<UUID>,
        session: WebsiteDataCleanupNavigationBarrier.Session
    ) -> Bool? {
        guard let eligibleTabs = eligibleTabs(profileIDs: profileIDs) else {
            return nil
        }
        for tab in eligibleTabs {
            if liveWebViews(tab).contains(where: {
                navigationBarrier.contains($0, in: session) == false
            }) {
                return true
            }
        }
        return false
    }

    private func eligibleTabs(profileIDs: Set<UUID>) -> [Tab]? {
        var seenTabIDs = Set<UUID>()
        guard let tabs = runtimeTabs() else { return nil }
        return tabs.filter { tab in
            seenTabIDs.insert(tab.id).inserted
                && isTabEligible(tab, profileIDs: profileIDs)
        }
    }

    private func isTabEligible(_ tab: Tab, profileIDs: Set<UUID>) -> Bool {
        guard let profileID = tab.resolveProfile()?.id ?? tab.profileId else {
            return false
        }
        return profileIDs.contains(profileID)
            && tab.representsSumiNativeSurface == false
    }
}

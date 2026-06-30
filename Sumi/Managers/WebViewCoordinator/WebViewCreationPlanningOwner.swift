//
//  WebViewCreationPlanningOwner.swift
//  Sumi
//
//  Owns normal-tab WebView materialization planning and initial-document warmup gating.
//

import Foundation
import WebKit

enum InitialDocumentWarmupDeferral {
    case waitForInFlight
    case start(profileId: UUID, windowId: UUID)
}

struct InitialDocumentWarmupRuntime {
    let needsInitialDocumentExtensionContextLoad: @MainActor (UUID) -> Bool
    let ensureInitialDocumentExtensionContextsLoaded: @MainActor (UUID) async -> Void
    let refreshCompositorForWindow: @MainActor (UUID) -> Void
}

@MainActor
private struct InitialDocumentWarmupGate {
    private var inFlightProfileIds: Set<UUID> = []
    private var attemptedProfileIds: Set<UUID> = []

    mutating func deferralIfNeeded(
        for tab: Tab,
        in windowId: UUID,
        runtime: InitialDocumentWarmupRuntime?
    ) -> InitialDocumentWarmupDeferral? {
        guard tab.isEphemeral == false,
              Self.isWarmupURL(tab.url),
              let profileId = tab.resolveProfile()?.id ?? tab.profileId,
              let runtime
        else {
            return nil
        }

        if inFlightProfileIds.contains(profileId) {
            return .waitForInFlight
        }

        guard attemptedProfileIds.contains(profileId) == false,
              runtime.needsInitialDocumentExtensionContextLoad(profileId)
        else {
            return nil
        }

        attemptedProfileIds.insert(profileId)
        inFlightProfileIds.insert(profileId)
        return .start(
            profileId: profileId,
            windowId: windowId
        )
    }

    mutating func finish(profileId: UUID) {
        inFlightProfileIds.remove(profileId)
    }

    private static func isWarmupURL(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return scheme == "http" || scheme == "https"
    }
}

enum NormalTabWebViewCreationPlan {
    case useExisting(WKWebView)
    case adoptExistingPrimary(WKWebView)
    case deferForInitialDocumentWarmup(InitialDocumentWarmupDeferral)
    case createPrimary
    case createClone(primaryWindowId: UUID)
}

@MainActor
final class WebViewCreationPlanningOwner {
    private var initialDocumentWarmupGate = InitialDocumentWarmupGate()

    func creationPlan(
        for tab: Tab,
        in windowId: UUID,
        initialDocumentWarmupRuntime: InitialDocumentWarmupRuntime?,
        existingWebView: WKWebView?,
        windowWebViews: [UUID: WKWebView]
    ) -> NormalTabWebViewCreationPlan {
        if let existingWebView {
            return .useExisting(existingWebView)
        }

        if let adoptableWebView = adoptableExistingPrimaryWebView(
            for: tab,
            in: windowId,
            hasTrackedWebViews: windowWebViews.isEmpty == false
        ) {
            return .adoptExistingPrimary(adoptableWebView)
        }

        if let deferral = initialDocumentWarmupGate.deferralIfNeeded(
            for: tab,
            in: windowId,
            runtime: initialDocumentWarmupRuntime
        ) {
            return .deferForInitialDocumentWarmup(deferral)
        }

        let otherWindowIds = windowWebViews.keys.filter { $0 != windowId }
        guard otherWindowIds.isEmpty == false else {
            return .createPrimary
        }

        guard let primaryWindowId = Self.primaryWindowIdForClone(
            preferredPrimaryWindowId: tab.primaryWindowId,
            otherWindowIds: otherWindowIds
        ) else {
            return .createPrimary
        }

        return .createClone(primaryWindowId: primaryWindowId)
    }

    func startInitialDocumentWarmupIfNeeded(
        _ deferral: InitialDocumentWarmupDeferral,
        runtime: InitialDocumentWarmupRuntime?
    ) {
        guard case let .start(profileId, windowId) = deferral else {
            return
        }
        guard let runtime else {
            assertionFailure("Initial document warmup start requires a runtime")
            return
        }

        Task { @MainActor [weak self] in
            await runtime.ensureInitialDocumentExtensionContextsLoaded(profileId)
            guard let self else { return }
            self.initialDocumentWarmupGate.finish(profileId: profileId)
            runtime.refreshCompositorForWindow(windowId)
        }
    }

    static func primaryWindowIdForClone<S: Sequence>(
        preferredPrimaryWindowId: UUID?,
        otherWindowIds: S
    ) -> UUID? where S.Element == UUID {
        let candidates = Array(otherWindowIds)
        if let preferredPrimaryWindowId,
           candidates.contains(preferredPrimaryWindowId) {
            return preferredPrimaryWindowId
        }

        return candidates.min { $0.uuidString < $1.uuidString }
    }

    private func adoptableExistingPrimaryWebView(
        for tab: Tab,
        in windowId: UUID,
        hasTrackedWebViews: Bool
    ) -> WKWebView? {
        guard let existingWebView = tab.existingWebView else { return nil }
        guard hasTrackedWebViews == false else { return nil }
        guard tab.primaryWindowId == nil || tab.primaryWindowId == windowId else { return nil }
        return existingWebView
    }
}

//
//  WebViewCreationPlanningOwner.swift
//  SumiWebRuntime
//
//  Owns normal-tab WebView materialization planning and initial-document warmup gating.
//

import Foundation
import WebKit

public enum InitialDocumentWarmupDeferral {
    case waitForInFlight
    case start(profileId: UUID, windowId: UUID)
}

public struct InitialDocumentWarmupRuntime {
    public let needsInitialDocumentExtensionContextLoad: @MainActor (UUID) -> Bool
    public let ensureInitialExtensionContextsLoaded: @MainActor (UUID) async -> Void
    public let refreshCompositorForWindow: @MainActor (UUID) -> Void

    public init(
        needsInitialDocumentExtensionContextLoad: @escaping @MainActor (UUID) -> Bool,
        ensureInitialExtensionContextsLoaded: @escaping @MainActor (UUID) async -> Void,
        refreshCompositorForWindow: @escaping @MainActor (UUID) -> Void
    ) {
        self.needsInitialDocumentExtensionContextLoad = needsInitialDocumentExtensionContextLoad
        self.ensureInitialExtensionContextsLoaded = ensureInitialExtensionContextsLoaded
        self.refreshCompositorForWindow = refreshCompositorForWindow
    }
}

@MainActor
private struct InitialDocumentWarmupGate {
    private var inFlightProfileIds: Set<UUID> = []
    private var attemptedProfileIds: Set<UUID> = []

    mutating func deferralIfNeeded(
        for tab: any WebRuntimeTabHandle,
        in windowId: UUID,
        runtime: InitialDocumentWarmupRuntime?
    ) -> InitialDocumentWarmupDeferral? {
        guard tab.isEphemeral == false,
              Self.isWarmupURL(tab.url),
              let profileId = tab.resolvedProfileId,
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

public enum NormalTabWebViewCreationPlan {
    case useExisting(WKWebView)
    case adoptExistingPrimary(WKWebView)
    case deferForInitialDocumentWarmup(InitialDocumentWarmupDeferral)
    case createPrimary
    case createClone(primaryWindowId: UUID)
}

@MainActor
public final class WebViewCreationPlanningOwner {
    private var initialDocumentWarmupGate = InitialDocumentWarmupGate()

    public init() {}

    public func creationPlan(
        for tab: any WebRuntimeTabHandle,
        in windowId: UUID,
        initialDocumentWarmupRuntime: InitialDocumentWarmupRuntime?,
        existingWebView: WKWebView?,
        windowWebViews: [UUID: WKWebView],
        sessionStore: TabWebViewSessionStore? = nil
    ) -> NormalTabWebViewCreationPlan {
        if let existingWebView {
            return .useExisting(existingWebView)
        }

        if let adoptableWebView = adoptableExistingPrimaryWebView(
            for: tab,
            sessionStore: sessionStore,
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

        guard let primaryWindowId = Self.primaryWindowIdForClone(otherWindowIds: otherWindowIds) else {
            return .createPrimary
        }

        return .createClone(primaryWindowId: primaryWindowId)
    }

    public func startInitialDocumentWarmupIfNeeded(
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
            await runtime.ensureInitialExtensionContextsLoaded(profileId)
            guard let self else { return }
            self.initialDocumentWarmupGate.finish(profileId: profileId)
            runtime.refreshCompositorForWindow(windowId)
        }
    }

    public static func primaryWindowIdForClone<S: Sequence>(
        otherWindowIds: S
    ) -> UUID? where S.Element == UUID {
        let candidates = Array(otherWindowIds)
        return candidates.min { $0.uuidString < $1.uuidString }
    }

    private func adoptableExistingPrimaryWebView(
        for tab: any WebRuntimeTabHandle,
        sessionStore: TabWebViewSessionStore?,
        hasTrackedWebViews: Bool
    ) -> WKWebView? {
        guard hasTrackedWebViews == false else { return nil }
        let session: TabWebViewSession
        if let sessionStore {
            sessionStore.promoteLocalSessionIfNeeded(
                tabId: tab.id,
                localSession: tab.localSession
            )
            session = sessionStore.session(for: tab.id)
        } else {
            // Pre-runtime / tests without a store: Tab-local session notes.
            session = tab.localSession
        }
        // Adopt windowed primary hint or untracked — never parked staging.
        if session.primaryWindowId != nil, let primary = session.primaryWebView {
            return primary
        }
        return session.untrackedWebView
    }
}

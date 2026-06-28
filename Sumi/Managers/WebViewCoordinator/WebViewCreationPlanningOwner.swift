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
    case start(profileId: UUID, browserManager: BrowserManager, windowId: UUID)
}

@MainActor
private struct InitialDocumentWarmupGate {
    private var inFlightProfileIds: Set<UUID> = []
    private var attemptedProfileIds: Set<UUID> = []

    mutating func deferralIfNeeded(
        for tab: Tab,
        in windowId: UUID,
        browserManager coordinatorBrowserManager: BrowserManager?
    ) -> InitialDocumentWarmupDeferral? {
        guard tab.isEphemeral == false,
              Self.isWarmupURL(tab.url),
              let profileId = tab.resolveProfile()?.id ?? tab.profileId,
              let browserManager = tab.browserManager ?? coordinatorBrowserManager
        else {
            return nil
        }

        if inFlightProfileIds.contains(profileId) {
            return .waitForInFlight
        }

        guard attemptedProfileIds.contains(profileId) == false,
              browserManager.extensionsModule
                .needsInitialDocumentExtensionContextLoadIfNeeded(profileId: profileId)
        else {
            return nil
        }

        attemptedProfileIds.insert(profileId)
        inFlightProfileIds.insert(profileId)
        return .start(
            profileId: profileId,
            browserManager: browserManager,
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
        browserManager coordinatorBrowserManager: BrowserManager?,
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
            browserManager: coordinatorBrowserManager
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
        _ deferral: InitialDocumentWarmupDeferral
    ) {
        guard case let .start(profileId, browserManager, windowId) = deferral else {
            return
        }
        Task { @MainActor [weak self, weak browserManager] in
            await browserManager?.extensionsModule
                .ensureInitialDocumentExtensionContextsLoadedIfNeeded(
                    profileId: profileId
                )
            guard let self else { return }
            self.initialDocumentWarmupGate.finish(profileId: profileId)

            guard let browserManager,
                  let windowState = browserManager.windowRegistry?.windows[windowId]
            else { return }
            browserManager.refreshCompositor(for: windowState)
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

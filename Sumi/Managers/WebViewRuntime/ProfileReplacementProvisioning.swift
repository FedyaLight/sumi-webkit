import Foundation
import SumiDomain
import WebKit
import SumiWebRuntime

/// Constructs target-profile WebViews without mutating repository placement
/// or the Tab's committed profile. Failed construction destroys only the
/// provisional generation and restores configuration-policy snapshots.
@MainActor
struct ProfileReplacementProvisioning {
    func prepare(
        tabs: [Tab],
        liveSnapshots: [UUID: WebViewSessionSnapshot],
        targetProfile: Profile,
        reason: String
    ) -> [PreparedWebViewReplacement]? {
        var prepared: [PreparedWebViewReplacement] = []
        for tab in tabs {
            guard let snapshot = liveSnapshots[tab.id] else { continue }
            let navigationIntent = tab.currentMainFrameNavigationIntent()
            let protection =
                tab.reloadPolicyStateOwner.protectionAppliedAttachmentState
            let safari = tab.reloadPolicyStateOwner
                .safariContentBlockerAppliedAttachmentState

            guard let replacement = prepare(
                tab: tab,
                snapshot: snapshot,
                targetProfile: targetProfile,
                targetURL: navigationIntent.targetURL,
                semanticRevision: navigationIntent.revision,
                protection: protection,
                safari: safari,
                reason: reason
            ) else {
                discard(prepared)
                return nil
            }
            prepared.append(replacement)
        }
        return prepared
    }

    func discard(_ prepared: [PreparedWebViewReplacement]) {
        for replacement in prepared {
            replacement.replacements.forEach(
                replacement.tab.cleanupCloneWebView
            )
            restoreReloadPolicy(replacement)
        }
    }

    func restoreReloadPolicy(
        _ prepared: [PreparedWebViewReplacement]
    ) {
        prepared.forEach(restoreReloadPolicy)
    }

    private func prepare(
        tab: Tab,
        snapshot: WebViewSessionSnapshot,
        targetProfile: Profile,
        targetURL: URL,
        semanticRevision: UInt64,
        protection: SumiProtectionAttachmentState?,
        safari: SumiSafariContentBlockerAttachmentState?,
        reason: String
    ) -> PreparedWebViewReplacement? {
        let placement: WebViewReplacementPlacement
        let replacements: [WKWebView]
        let tracked: [WKWebView]
        let bindings: [WKWebView]

        if snapshot.windowWebViews.isEmpty == false {
            var byWindowID: [UUID: WKWebView] = [:]
            for windowID in snapshot.windowWebViews.keys.sorted(by: uuidOrder) {
                guard let webView = tab.makeNormalTabWebView(
                    reason: "\(reason).tracked",
                    explicitProfile: targetProfile,
                    prepareExtensionRuntime: false
                ) else {
                    byWindowID.values.forEach(tab.cleanupCloneWebView)
                    restoreReloadPolicy(tab, protection, safari)
                    return nil
                }
                byWindowID[windowID] = webView
            }
            guard let primaryWindowID = snapshot.primaryWindowID,
                  byWindowID[primaryWindowID] != nil else {
                byWindowID.values.forEach(tab.cleanupCloneWebView)
                restoreReloadPolicy(tab, protection, safari)
                return nil
            }
            replacements = Array(byWindowID.values)
            tracked = replacements
            bindings = replacements
            placement = .windowSet(
                webViewsByWindowID: byWindowID,
                primaryWindowID: primaryWindowID
            )
        } else {
            guard let webView = tab.makeNormalTabWebView(
                reason: "\(reason).detached",
                explicitProfile: targetProfile,
                prepareExtensionRuntime: false
            ) else {
                restoreReloadPolicy(tab, protection, safari)
                return nil
            }
            let residence: WebViewDetachedReplacementResidence =
                snapshot.untrackedWebView == nil ? .parked : .untracked
            replacements = [webView]
            tracked = []
            bindings = residence == .untracked ? [webView] : []
            placement = .detached(webView: webView, residence: residence)
        }

        return PreparedWebViewReplacement(
            tab: tab,
            snapshot: snapshot,
            placement: placement,
            replacements: replacements,
            trackedReplacements: tracked,
            bindingReplacements: bindings,
            targetURL: targetURL,
            semanticRevision: semanticRevision,
            profileID: targetProfile.id,
            requiresExtensionRuntimePreparation: true,
            previousProtectionState: protection,
            previousSafariContentBlockerState: safari
        )
    }

    private func restoreReloadPolicy(_ replacement: PreparedWebViewReplacement) {
        restoreReloadPolicy(
            replacement.tab,
            replacement.previousProtectionState,
            replacement.previousSafariContentBlockerState
        )
    }

    private func restoreReloadPolicy(
        _ tab: Tab,
        _ protection: SumiProtectionAttachmentState?,
        _ safari: SumiSafariContentBlockerAttachmentState?
    ) {
        tab.reloadPolicyStateOwner.noteContentBlockingWebViewRebuildFailed(
            restoringProtectionState: protection,
            restoringSafariContentBlockerState: safari
        )
    }

    private func uuidOrder(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
    }
}

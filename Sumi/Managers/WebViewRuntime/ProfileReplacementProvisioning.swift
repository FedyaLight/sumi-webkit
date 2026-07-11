import Foundation
import WebKit
import SumiWebRuntime

/// Constructs target-profile WebViews without mutating repository placement
/// or the Tab's committed profile. Failed construction destroys only the
/// provisional generation and cancels its uncommitted policy receipts.
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
            guard let replacement = prepare(
                tab: tab,
                snapshot: snapshot,
                targetProfile: targetProfile,
                targetURL: navigationIntent.targetURL,
                semanticRevision: navigationIntent.revision,
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
        }
    }

    private func prepare(
        tab: Tab,
        snapshot: WebViewSessionSnapshot,
        targetProfile: Profile,
        targetURL: URL,
        semanticRevision: UInt64,
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
                    return nil
                }
                byWindowID[windowID] = webView
            }
            guard let primaryWindowID = snapshot.primaryWindowID,
                  byWindowID[primaryWindowID] != nil else {
                byWindowID.values.forEach(tab.cleanupCloneWebView)
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
                return nil
            }
            let residence: WebViewDetachedReplacementResidence =
                snapshot.untrackedWebView == nil ? .parked : .untracked
            replacements = [webView]
            tracked = []
            bindings = residence == .untracked ? [webView] : []
            placement = .detached(webView: webView, residence: residence)
        }

        guard let configurationPolicyChangeSet =
            tab.preparedConfigurationPolicyChangeSet(
                for: replacements
            ) else {
            replacements.forEach(tab.cleanupCloneWebView)
            return nil
        }

        guard let preparedReplacement = PreparedWebViewReplacement(
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
            configurationPolicyChangeSet: configurationPolicyChangeSet
        ) else {
            configurationPolicyChangeSet.cancel()
            replacements.forEach(tab.cleanupCloneWebView)
            return nil
        }
        return preparedReplacement
    }

    private func uuidOrder(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
    }
}

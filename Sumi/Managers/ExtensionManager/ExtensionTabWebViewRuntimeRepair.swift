import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
protocol ExtensionControllerRuntimeRebuildQuery: AnyObject {
    func webViewNeedsExtensionRuntimeRebuild(
        _ webView: WKWebView,
        for tab: Tab
    ) -> Bool
}

/// Read-only controller/WebView mismatch classification. It cannot provision,
/// bind, scan profiles, or rebuild WebViews.
@available(macOS 15.5, *)
@MainActor
final class ExtensionWebViewControllerMismatchQuery:
    ExtensionControllerRuntimeRebuildQuery {
    private weak var tabs: (any ExtensionTabQuery)?
    private weak var profiles: (any ExtensionTabProfileResolving)?
    private weak var profileRuntime: ExtensionProfileRuntime?

    init(
        tabs: any ExtensionTabQuery,
        profiles: any ExtensionTabProfileResolving,
        profileRuntime: ExtensionProfileRuntime
    ) {
        self.tabs = tabs
        self.profiles = profiles
        self.profileRuntime = profileRuntime
    }

    func webViewNeedsExtensionRuntimeRebuild(
        _ webView: WKWebView,
        for tab: Tab
    ) -> Bool {
        guard tabs?.extensionTab(for: tab.id) === tab,
              (webView as? FocusableWKWebView)?.owningTab === tab,
              let profileID = profiles?.profileID(for: tab)
        else { return false }
        let current = webView.configuration.webExtensionController
        if let current,
           let currentProfileID = profileRuntime?.profileId(for: current),
           currentProfileID != profileID {
            return true
        }
        return ExtensionRuntimeWebViewBindingPolicy.needsRuntimeRebuild(
            currentController: current,
            expectedController: profileRuntime?.controller(for: profileID)
        )
    }
}

@available(macOS 15.5, *)
@MainActor
protocol ExtensionTabWebViewRuntimeRepairing: AnyObject {
    @discardableResult
    func repair(
        _ tab: Tab,
        reason: String,
        allowWhenExtensionsNotLoaded: Bool
    ) -> ExtensionTabWebViewRuntimeRepairOutcome
}

@available(macOS 15.5, *)
enum ExtensionTabWebViewRuntimeRepairOutcome: Equatable {
    case notApplicable
    case publicationInvalidated(ExtensionTabWebViewRebuildSubmissionOutcome)
    case publicationSuperseded(ExtensionTabWebViewRebuildSubmissionOutcome)
}

/// Reconciles controller binding for one exact canonical Tab. Destructive
/// rebuild is admitted only after all exact identity proofs still hold.
@available(macOS 15.5, *)
@MainActor
final class ExtensionTabWebViewRuntimeRepair:
    ExtensionTabWebViewRuntimeRepairing {
    private weak var runtimeSession: ExtensionRuntimeSession?
    private weak var tabs: (any ExtensionTabQuery)?
    private weak var profiles: (any ExtensionTabProfileResolving)?
    private weak var profileRuntime: ExtensionProfileRuntime?
    private weak var webViews: ExtensionExactTabWebViewQuery?
    private weak var admission: (any ExtensionWebViewControllerAdmitting)?
    private weak var mismatch: (any ExtensionControllerRuntimeRebuildQuery)?
    private weak var rebuilder: (any ExtensionTabWebViewRebuilding)?
    private let diagnostics: ExtensionRuntimeDiagnostics

    init(
        runtimeSession: ExtensionRuntimeSession,
        tabs: any ExtensionTabQuery,
        profiles: any ExtensionTabProfileResolving,
        profileRuntime: ExtensionProfileRuntime,
        webViews: ExtensionExactTabWebViewQuery,
        admission: any ExtensionWebViewControllerAdmitting,
        mismatch: any ExtensionControllerRuntimeRebuildQuery,
        rebuilder: any ExtensionTabWebViewRebuilding,
        diagnostics: ExtensionRuntimeDiagnostics
    ) {
        self.runtimeSession = runtimeSession
        self.tabs = tabs
        self.profiles = profiles
        self.profileRuntime = profileRuntime
        self.webViews = webViews
        self.admission = admission
        self.mismatch = mismatch
        self.rebuilder = rebuilder
        self.diagnostics = diagnostics
    }

    @discardableResult
    func repair(
        _ tab: Tab,
        reason: String,
        allowWhenExtensionsNotLoaded: Bool = false
    ) -> ExtensionTabWebViewRuntimeRepairOutcome {
        guard isCurrent(tab),
              runtimeSession?.extensionsLoaded == true
                || allowWhenExtensionsNotLoaded,
              let profileID = profiles?.profileID(for: tab),
              let controller = profileRuntime?.controller(for: profileID)
        else { return .notApplicable }

        var requiresRebuild = false
        for webView in webViews?.currentLiveWebViews(for: tab) ?? [] {
            guard isCurrent(tab),
                  profiles?.profileID(for: tab) == profileID,
                  profileRuntime?.controller(for: profileID) === controller
            else { return .notApplicable }
            let outcome = admission?.admit(
                controller,
                profileID: profileID,
                to: webView,
                for: tab
            ) ?? .rejected
            diagnostics.trace(
                "controllerRepair outcome=\(String(describing: outcome)) tab=\(tab.id.uuidString.prefix(8))"
            )
            guard outcome != .rejected else { return .notApplicable }
            if outcome == .requiresRebuild {
                requiresRebuild = true
                break
            }
            if mismatch?.webViewNeedsExtensionRuntimeRebuild(
                    webView,
                    for: tab
                ) == true {
                requiresRebuild = true
                break
            }
        }

        guard requiresRebuild,
              isCurrent(tab),
              profiles?.profileID(for: tab) == profileID,
              profileRuntime?.controller(for: profileID) === controller
        else { return .notApplicable }
        SafariExtensionPermissionLifecycleDiagnostics.logReloadRebuild(
            SafariExtensionReloadRebuildSnapshot(
                triggerReason: reason,
                profileBucket: SafariExtensionPermissionLifecycleDiagnostics
                    .bucket(profileID),
                tabBucket: SafariExtensionPermissionLifecycleDiagnostics
                    .bucket(tab.id),
                host: SafariExtensionPermissionLifecycleDiagnostics.host(
                    from: tab.url
                ),
                userActionCaused: false,
                action: .destructiveRebuild
            )
        )
        guard let rebuilder else { return .notApplicable }
        tab.extensionPageRuntimeOwner
            .resetDocumentBindingForContentScriptRebind()
        let publicationInvalidation = tab.extensionPageRuntimeOwner
            .openPublicationInvalidationWitness()
        guard isCurrent(tab) else { return .notApplicable }
        let submission = rebuilder.rebuildExtensionLiveWebViews(
            for: tab,
            reason: reason
        )
        diagnostics.trace(
            "controllerRepair rebuild=\(String(describing: submission)) tab=\(tab.id.uuidString.prefix(8))"
        )
        guard isCurrent(tab),
              profiles?.profileID(for: tab) == profileID,
              profileRuntime?.controller(for: profileID) === controller
        else { return .notApplicable }
        guard tab.extensionPageRuntimeOwner.invalidateOpenPublication(
            ifCurrent: publicationInvalidation
        ) else {
            return .publicationSuperseded(submission)
        }
        return .publicationInvalidated(submission)
    }

    private func isCurrent(_ tab: Tab) -> Bool {
        tab.isEphemeral == false
            && tabs?.extensionTab(for: tab.id) === tab
    }
}

/// Fans an explicit profile reconciliation out to exact canonical Tabs.
@available(macOS 15.5, *)
@MainActor
final class ExtensionProfileWebViewRuntimeReconciler {
    private weak var inventory: (any ExtensionTabInventory)?
    private weak var tabs: (any ExtensionTabQuery)?
    private weak var profiles: (any ExtensionTabProfileResolving)?
    private weak var profileRuntime: ExtensionProfileRuntime?
    private weak var repair: (any ExtensionTabWebViewRuntimeRepairing)?
    #if DEBUG
        private(set) var reconciliationRequestCount = 0
    #endif

    init(
        inventory: any ExtensionTabInventory,
        tabs: any ExtensionTabQuery,
        profiles: any ExtensionTabProfileResolving,
        profileRuntime: ExtensionProfileRuntime,
        repair: any ExtensionTabWebViewRuntimeRepairing
    ) {
        self.inventory = inventory
        self.tabs = tabs
        self.profiles = profiles
        self.profileRuntime = profileRuntime
        self.repair = repair
    }

    func reconcile(
        profileID: UUID,
        allowWhenExtensionsNotLoaded: Bool = false,
        reason: String
    ) {
        #if DEBUG
            reconciliationRequestCount += 1
        #endif
        guard profileRuntime?.controller(for: profileID) != nil else { return }
        for tab in inventory?.allExtensionTabs ?? []
            where tabs?.extensionTab(for: tab.id) === tab
                && tab.isEphemeral == false
                && profiles?.profileID(for: tab) == profileID {
            repair?.repair(
                tab,
                reason: reason,
                allowWhenExtensionsNotLoaded: allowWhenExtensionsNotLoaded
            )
        }
    }
}

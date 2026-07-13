import Foundation
import WebKit

/// A short-lived exact-Tab plan captured before extension runtime shutdown.
/// Execution rejects a same-UUID replacement before mutating or rebuilding it.
@available(macOS 15.5, *)
@MainActor
struct ExtensionRuntimeTabRebuildPlan {
    enum Outcome: Equatable {
        case committed
        case deferred
        case noLiveWindows
        case failed
        case staleTab
        case browserUnavailable
    }

    struct Execution: Equatable {
        let tabID: UUID
        let tabIdentity: ObjectIdentifier
        let outcome: Outcome
    }

    private struct Candidate {
        let tab: Tab
    }

    private let candidates: [Candidate]

    static let empty = ExtensionRuntimeTabRebuildPlan(candidates: [])

    static func capture(
        hasLoadedUserRuntime: Bool,
        controllers: [WKWebExtensionController],
        tabs: [Tab],
        liveWebViews: (Tab) -> [WKWebView]
    ) -> ExtensionRuntimeTabRebuildPlan {
        guard hasLoadedUserRuntime else { return .empty }

        var seen = Set<ObjectIdentifier>()
        let candidates = tabs.compactMap { tab -> Candidate? in
            guard seen.insert(ObjectIdentifier(tab)).inserted else {
                return nil
            }

            if tab.webExtensionContextOverride != nil
                || tab.webViewConfigurationOverride?.webExtensionController
                    != nil {
                return Candidate(tab: tab)
            }

            let webViews = liveWebViews(tab)
            if tab.isEphemeral == false, webViews.isEmpty == false {
                return Candidate(tab: tab)
            }

            let hasAttachedController = webViews.contains { webView in
                guard let controller =
                    webView.configuration.webExtensionController
                else {
                    return false
                }
                return controllers.isEmpty
                    || controllers.contains { $0 === controller }
            }
            return hasAttachedController ? Candidate(tab: tab) : nil
        }
        return ExtensionRuntimeTabRebuildPlan(candidates: candidates)
    }

    func execute(
        canonicalTabs: (any ExtensionTabQuery)?,
        runtime: ExtensionManagerRuntime,
        trace: (Tab, Outcome) -> Void
    ) -> [Execution] {
        candidates.map { candidate in
            let tab = candidate.tab
            let identity = ObjectIdentifier(tab)
            guard canonicalTabs?.extensionTab(for: tab.id) === tab else {
                trace(tab, .staleTab)
                return Execution(
                    tabID: tab.id,
                    tabIdentity: identity,
                    outcome: .staleTab
                )
            }
            guard runtime.browserRuntimeAvailable() else {
                trace(tab, .browserUnavailable)
                return Execution(
                    tabID: tab.id,
                    tabIdentity: identity,
                    outcome: .browserUnavailable
                )
            }

            tab.webExtensionContextOverride = nil
            tab.webViewConfigurationOverride = nil
            tab.extensionPageRuntimeOwner
                .resetDocumentBindingForContentScriptRebind()
            tab.extensionPageRuntimeOwner.clearOpenNotificationGeneration()

            guard canonicalTabs?.extensionTab(for: tab.id) === tab else {
                trace(tab, .staleTab)
                return Execution(
                    tabID: tab.id,
                    tabIdentity: identity,
                    outcome: .staleTab
                )
            }

            let outcome = Outcome(runtime.rebuildLiveWebViews(tab))
            trace(tab, outcome)
            return Execution(
                tabID: tab.id,
                tabIdentity: identity,
                outcome: outcome
            )
        }
    }
}

@available(macOS 15.5, *)
private extension ExtensionRuntimeTabRebuildPlan.Outcome {
    init(_ submission: ExtensionTabWebViewRebuildSubmissionOutcome) {
        switch submission {
        case .committed:
            self = .committed
        case .deferred:
            self = .deferred
        case .noLiveWindows:
            self = .noLiveWindows
        case .failed:
            self = .failed
        }
    }
}

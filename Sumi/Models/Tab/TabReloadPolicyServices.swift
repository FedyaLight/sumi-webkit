import Foundation
import SumiDomain
import WebKit

@MainActor
enum AttachedRuleListSnapshot {
    case deriveFromDiagnostics
    case identifiers([String])
}

@MainActor
struct ReloadProtectionDiagnosticsContext {
    let currentURL: URL
    let appliedState: SumiProtectionAttachmentState?
    let reloadRequired: Bool
    let reloadRequiredReason: String?
    let didManualReloadRebuildWebView: Bool
    let appliedAfterManualReload: Bool
    let actualAttachedRuleLists: AttachedRuleListSnapshot
    let contentBlockingAssetSummary:
        SumiNormalTabContentBlockingAssetSummary?
    let webViewRebuildDuration: TimeInterval?
    let urlHubSummaryDuration: TimeInterval?
}

@MainActor
protocol SafariContentBlockerPolicyReading {
    func attachmentState(
        for url: URL?
    ) -> SumiSafariContentBlockerAttachmentState
}

@MainActor
protocol ProtectionPolicyReading {
    func attachmentState(for url: URL?) -> SumiProtectionAttachmentState
    func surfaceHost(for url: URL?) -> String?
    func diagnostics(
        _ context: ReloadProtectionDiagnosticsContext
    ) -> SumiProtectionCurrentTabDiagnostics?
}

@MainActor
protocol AutoplayPolicyReading {
    func policy(for url: URL?, profile: Profile?) -> SumiAutoplayPolicy
    func evaluateChange(
        _ requestedState: SumiRuntimeAutoplayState,
        for webView: WKWebView
    ) -> SumiRuntimePermissionOperationResult
}

@MainActor
struct InactiveSafariContentBlockerPolicy:
    SafariContentBlockerPolicyReading {
    func attachmentState(
        for url: URL?
    ) -> SumiSafariContentBlockerAttachmentState {
        .disabled(siteHost: nil)
    }
}

@MainActor
struct InactiveProtectionPolicy: ProtectionPolicyReading {
    func attachmentState(
        for url: URL?
    ) -> SumiProtectionAttachmentState {
        .disabled(siteHost: nil)
    }

    func surfaceHost(for url: URL?) -> String? { nil }

    func diagnostics(
        _ context: ReloadProtectionDiagnosticsContext
    ) -> SumiProtectionCurrentTabDiagnostics? {
        nil
    }
}

@MainActor
struct InactiveAutoplayPolicy: AutoplayPolicyReading {
    func policy(
        for url: URL?,
        profile: Profile?
    ) -> SumiAutoplayPolicy {
        .default
    }

    func evaluateChange(
        _ requestedState: SumiRuntimeAutoplayState,
        for webView: WKWebView
    ) -> SumiRuntimePermissionOperationResult {
        .noOp
    }
}

/// Three exact read capabilities used by reload state. It has no closures,
/// mutable state, rebuild commands, or browser-root access.
@MainActor
struct TabReloadPolicies {
    let safariContentBlockers: any SafariContentBlockerPolicyReading
    let protection: any ProtectionPolicyReading
    let autoplay: any AutoplayPolicyReading

    static let inactive = Self(
        safariContentBlockers: InactiveSafariContentBlockerPolicy(),
        protection: InactiveProtectionPolicy(),
        autoplay: InactiveAutoplayPolicy()
    )
}

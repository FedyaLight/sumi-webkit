import Foundation
import WebKit

@MainActor
struct CreatedWebViewPreparationOptions {
    let enableVisitedLinkRecording: Bool
    let applyNavigationPreferences: Bool
    let installFaviconRuntime: Bool
    let prepareExtensionRuntime: Bool

    static let normal = Self()

    static func auxiliary(prepareExtensionRuntime: Bool) -> Self {
        Self(
            installFaviconRuntime: false,
            prepareExtensionRuntime: prepareExtensionRuntime
        )
    }

    static let auxiliaryOverride = Self(
        enableVisitedLinkRecording: false,
        applyNavigationPreferences: false
    )

    init(
        enableVisitedLinkRecording: Bool = true,
        applyNavigationPreferences: Bool = true,
        installFaviconRuntime: Bool = true,
        prepareExtensionRuntime: Bool = true
    ) {
        self.enableVisitedLinkRecording = enableVisitedLinkRecording
        self.applyNavigationPreferences = applyNavigationPreferences
        self.installFaviconRuntime = installFaviconRuntime
        self.prepareExtensionRuntime = prepareExtensionRuntime
    }
}

/// Immutable values that identify one synchronous normal-WebView setup attempt.
/// Live WebView residence is intentionally excluded and must be re-read from
/// `TabNormalWebViewResidenceStage` after every re-entrant effect.
@MainActor
struct TabNormalWebViewSetupRequest {
    let tabID: UUID
    let targetURL: URL
    let isPopupHost: Bool
    let resolvedProfile: Profile?
}

/// Admission and suspension lifecycle used only by the setup orchestrator.
@MainActor
struct TabNormalWebViewCreationAdmissionStage {
    let deferUntilProfileAvailable: () -> Bool
    let beginSuspendedRestore: () -> Void
    let deferMaterialization: (@MainActor @Sendable @escaping () -> Void) -> Bool
    let replaySetup: @MainActor @Sendable (Bool) -> Void
}

/// Canonical detached residence and rejected-candidate disposal.
@MainActor
struct TabNormalWebViewResidenceStage {
    let currentWebView: () -> WKWebView?
    let parkedWebView: () -> WKWebView?
    let clearParkedWebView: () -> Void
    let retireParkedWebView: (WKWebView, String) -> Bool
    let cleanupRejectedWebView: (WKWebView) -> Void

    var hasCurrentWebView: Bool {
        currentWebView() != nil
    }

    var hasParkedWebView: Bool {
        parkedWebView() != nil
    }
}

/// Configuration policy used by reuse and creation, but not by residence or
/// document activation.
@MainActor
struct TabNormalWebViewConfigurationStage {
    let normalTabUserScripts: (URL?, UUID?) -> SumiNormalTabUserScripts
    let prepareNormalConfiguration: (
        URL,
        Profile,
        SumiNormalTabUserScripts
    ) -> PreparedNormalTabWebViewConfiguration
    let auxiliaryOverrideConfiguration: (Profile) -> WKWebViewConfiguration?
    let prepareForExtensionRuntime: (WKWebViewConfiguration, UUID?, String) -> Void
    let applyConfigurationOverride: (WKWebViewConfiguration, UUID?) -> Void
    let canReuse: (WKWebView, URL, Profile?) -> Bool
}

/// Physical WebKit preparation used by constructors and committed residence.
@MainActor
struct TabNormalWebViewPreparationStage {
    let prepareCreatedWebView: (
        FocusableWKWebView,
        URL?,
        String,
        CreatedWebViewPreparationOptions
    ) -> Void
    let prepareAssignedWebView: (WKWebView) -> Void
    let prepareReusedWebView: (WKWebView) -> Void
    let applyNavigationPreferences: (WKWebView) -> Void
}

/// Effects that may run only after a candidate has committed to canonical
/// residence. The setup service revalidates physical identity around them.
@MainActor
struct TabNormalWebViewInitialDocumentStage {
    let replaceNormalTabUserScripts: (WKUserContentController, URL?) async -> Void
    let loadExtensionOwnedInitialURL: (WKWebView, URL) -> Void
    let registerExtensionRuntime: (String) -> Void
    let scheduleRuntimeHandoff: (WKWebView?, URL, UUID?, String) -> Void
}

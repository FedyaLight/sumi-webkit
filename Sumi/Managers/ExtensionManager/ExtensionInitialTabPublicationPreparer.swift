import Foundation
import SumiWebRuntime
import WebKit

/// Silently captures the exact initial-Tab capability used by the surrounding
/// native window transaction. All mutation is complete before the receipt is
/// returned; no WebKit lifecycle callback is emitted here.
@available(macOS 15.5, *)
@MainActor
final class ExtensionInitialTabPublicationPreparer {
    private let runtimePublicationEvidence:
        ExtensionRuntimePublicationEvidenceIssuer
    private let profileRuntime: ExtensionProfileRuntime
    private let residenceAdmission: ExtensionInitialTabResidenceAdmission
    private let runtimeAdmission: ExtensionInitialTabRuntimeAdmission
    private let adapters: ExtensionCreatedTabAdapterPublication
    private let validator: ExtensionInitialTabPublicationValidator
    private let retirement: ExtensionInitialTabPublicationRetirement
    private let diagnostics: ExtensionRuntimeDiagnostics

    init(
        runtimePublicationEvidence: ExtensionRuntimePublicationEvidenceIssuer,
        profileRuntime: ExtensionProfileRuntime,
        residenceAdmission: ExtensionInitialTabResidenceAdmission,
        runtimeAdmission: ExtensionInitialTabRuntimeAdmission,
        adapters: ExtensionCreatedTabAdapterPublication,
        validator: ExtensionInitialTabPublicationValidator,
        retirement: ExtensionInitialTabPublicationRetirement,
        diagnostics: ExtensionRuntimeDiagnostics
    ) {
        self.runtimePublicationEvidence = runtimePublicationEvidence
        self.profileRuntime = profileRuntime
        self.residenceAdmission = residenceAdmission
        self.runtimeAdmission = runtimeAdmission
        self.adapters = adapters
        self.validator = validator
        self.retirement = retirement
        self.diagnostics = diagnostics
    }

    func prepare(
        window: BrowserWindowState,
        tab: Tab,
        webView: FocusableWKWebView,
        reason: String
    ) -> ExtensionInitialTabPublicationReceipt? {
        guard let residence = residenceAdmission.admit(
            window: window,
            tab: tab,
            webView: webView
        ), let controller = runtimeAdmission.admit(
            tab: tab,
            webView: webView,
            profileID: residence.profileID
        ) else { return nil }

        let dataStore = residence.profile.dataStore
        let runtimePublication = runtimePublicationEvidence.issue()
        let generation = runtimePublication.tabPublication
        let stateToken = tab.extensionPageRuntimeOwner
            .prepareForWindowPrepublication(generation: generation)
        guard let preparedAdapter = adapters.prepare(for: tab) else {
            _ = tab.extensionPageRuntimeOwner.rollbackWindowPrepublication(
                stateToken
            )
            return nil
        }

        let evidence = ExtensionInitialTabPublicationEvidence(
            window: window,
            tab: tab,
            webView: webView,
            profile: residence.profile,
            dataStore: dataStore,
            profileID: residence.profileID,
            runtimePublication: runtimePublication,
            contextBindingGeneration: profileRuntime
                .contextBindingGeneration(for: residence.profileID),
            controller: controller,
            adapter: preparedAdapter.adapter,
            createdAdapter: preparedAdapter.created,
            stateToken: stateToken,
            reason: reason
        )
        guard validator.preparedEvidenceIsCurrent(
            evidence,
            requiresPublishedWindow: false
        ) else {
            let restored = tab.extensionPageRuntimeOwner
                .rollbackWindowPrepublication(stateToken)
            if restored {
                retirement.removePreparedAdapter(evidence)
            }
            return nil
        }
        return ExtensionInitialTabPublicationReceipt(
            validator: validator,
            retirement: retirement,
            diagnostics: diagnostics,
            evidence: evidence
        )
    }
}

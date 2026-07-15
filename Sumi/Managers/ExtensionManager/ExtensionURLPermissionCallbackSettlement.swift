import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionURLPermissionCallbackSettlement {
    private let admission: ExtensionControllerCallbackAdmission
    private let decisions: ExtensionPermissionDecisionStore
    private let siteAccess: ExtensionSiteAccessPolicyCoordinator
    private let prompt: ExtensionPermissionPromptPresenter

    init(
        admission: ExtensionControllerCallbackAdmission,
        decisions: ExtensionPermissionDecisionStore,
        siteAccess: ExtensionSiteAccessPolicyCoordinator,
        prompt: ExtensionPermissionPromptPresenter
    ) {
        self.admission = admission
        self.decisions = decisions
        self.siteAccess = siteAccess
        self.prompt = prompt
    }

    func promptForPermissionToAccess(
        _ urls: Set<URL>,
        in tab: (any WKWebExtensionTab)?,
        evidence: ExtensionControllerCallbackEvidence,
        completionHandler: @escaping (Set<URL>, Date?) -> Void
    ) {
        let extensionContext = evidence.context
        var granted = Set<URL>()
        var unresolved = Set<URL>()

        for url in urls {
            guard admission.isCurrent(evidence) else {
                completionHandler([], nil)
                return
            }
            switch ExtensionPermissionPromptRouting.resolveURLPermissionBeforePrompt(
                url: url,
                in: extensionContext,
                tab: tab,
                extensionId: evidence.extensionID,
                profileId: evidence.profileID,
                siteAccess: siteAccess
            ) {
            case .alreadyGranted:
                Self.recordHostPermission(true, evidence, "promptAlreadyGranted")
                granted.insert(url)
            case .alreadyDenied:
                Self.recordHostPermission(false, evidence, "promptAlreadyDenied")
            case .configured(let access):
                let isAllowed = access == .allow
                guard setPermissionStatus(
                    isAllowed ? .grantedExplicitly : .deniedExplicitly,
                    for: url,
                    in: extensionContext,
                    includeHostPattern: true,
                    expirationDate: nil,
                    evidence: evidence,
                    siteAccess: siteAccess
                ) else {
                    completionHandler([], nil)
                    return
                }
                Self.recordHostPermission(
                    isAllowed,
                    evidence,
                    isAllowed ? "promptSiteAccessAllowed" : "promptSiteAccessDenied"
                )
                if isAllowed { granted.insert(url) }
            case .unresolved:
                unresolved.insert(url)
            }
        }

        guard unresolved.isEmpty == false else {
            guard admission.isCurrent(evidence) else {
                completionHandler([], nil)
                return
            }
            completionHandler(granted, nil)
            return
        }

        Task { @MainActor [weak self, admission = self.admission] in
            guard let self, admission.isCurrent(evidence) else {
                completionHandler([], nil)
                return
            }
            let promptPatterns = unresolved.compactMap {
                self.siteAccess.hostMatchPatternString(for: $0)
            }
            let decision = await self.prompt.promptForDecision(
                extensionContext: extensionContext,
                targets: unresolved.map(Self.permissionTarget(for:)),
                reason: "promptForPermissionToAccess",
                dedupeKey: self.decisions.permissionPromptDedupeKey(
                    profileID: evidence.profileID,
                    extensionID: evidence.extensionID,
                    targets: promptPatterns.isEmpty
                        ? unresolved.map(Self.permissionTarget(for:))
                        : promptPatterns
                ),
                extensionIdentifier: evidence.extensionID
            )
            let settlement = Self.settlement(for: decision)

            for url in unresolved {
                guard self.setPermissionStatus(
                    settlement.status,
                    for: url,
                    in: extensionContext,
                    includeHostPattern: true,
                    expirationDate: settlement.expirationDate,
                    evidence: evidence,
                    siteAccess: self.siteAccess
                ) else {
                    completionHandler([], nil)
                    return
                }
                if let pattern = self.siteAccess.hostMatchPatternString(for: url) {
                    self.decisions.persistExtensionPermissionDecision(
                        extensionId: evidence.extensionID,
                        profileId: evidence.profileID,
                        targetKind: .matchPattern,
                        target: pattern,
                        state: settlement.storedState,
                        expiresAt: settlement.expirationDate
                    )
                }
                guard admission.isCurrent(evidence) else {
                    completionHandler([], nil)
                    return
                }
                if let pattern = self.siteAccess.hostMatchPatternString(for: url) {
                    self.siteAccess.setConfiguredSiteAccess(
                        settlement.storedState == .allowed ? .allow : .deny,
                        extensionId: evidence.extensionID,
                        profileId: evidence.profileID,
                        matchPatternString: pattern,
                        expiresAt: settlement.expirationDate
                    )
                }
                guard admission.isCurrent(evidence) else {
                    completionHandler([], nil)
                    return
                }
                Self.recordHostPermission(
                    settlement.storedState == .allowed,
                    evidence,
                    settlement.storedState == .allowed ? "promptAllowed" : "promptDenied"
                )
            }
            guard admission.isCurrent(evidence) else {
                completionHandler([], nil)
                return
            }
            switch settlement.storedState {
            case .allowed:
                completionHandler(granted.union(unresolved), settlement.expirationDate)
            case .denied:
                completionHandler(granted, nil)
            }
        }
    }

    private func setPermissionStatus(
        _ status: WKWebExtensionContext.PermissionStatus,
        for url: URL,
        in extensionContext: WKWebExtensionContext,
        includeHostPattern: Bool,
        expirationDate: Date?,
        evidence: ExtensionControllerCallbackEvidence,
        siteAccess: ExtensionSiteAccessPolicyCoordinator
    ) -> Bool {
        guard admission.isCurrent(evidence) else { return false }
        if includeHostPattern,
           let pattern = siteAccess.hostMatchPatternString(for: url),
           let matchPattern = SafariExtensionMatchPatternDiagnostics.make(
               pattern,
               purpose: "urlPermissionCallbackSettlement.hostPattern"
           ) {
            extensionContext.setPermissionStatus(
                status,
                for: matchPattern,
                expirationDate: expirationDate
            )
            guard admission.isCurrent(evidence) else { return false }
        }
        extensionContext.setPermissionStatus(
            status,
            for: url,
            expirationDate: expirationDate
        )
        return admission.isCurrent(evidence)
    }

    private static func recordHostPermission(
        _ granted: Bool,
        _ evidence: ExtensionControllerCallbackEvidence,
        _ reason: String
    ) {
        SafariExtensionAutofillFillDiagnostics.recordHostPermission(
            granted: granted,
            extensionId: evidence.extensionID,
            reason: reason
        )
    }

    private struct Settlement {
        let status: WKWebExtensionContext.PermissionStatus
        let storedState: ExtensionManager.ExtensionStoredPermissionState
        let expirationDate: Date?
    }

    private static func settlement(
        for decision: ExtensionManager.ExtensionPermissionPromptDecision
    ) -> Settlement {
        switch decision {
        case .allow(let expirationDate):
            Settlement(
                status: .grantedExplicitly,
                storedState: .allowed,
                expirationDate: expirationDate
            )
        case .deny:
            Settlement(
                status: .deniedExplicitly,
                storedState: .denied,
                expirationDate: nil
            )
        }
    }

    nonisolated private static func permissionTarget(for url: URL) -> String {
        if let host = url.host, host.isEmpty == false { return host }
        if let scheme = url.scheme, scheme.isEmpty == false { return "\(scheme):" }
        return "this site"
    }
}

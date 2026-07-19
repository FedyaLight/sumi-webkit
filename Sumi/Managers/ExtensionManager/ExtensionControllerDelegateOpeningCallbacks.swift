import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionControllerDelegateOpeningCallbacks {
    private let bootstrapChromeAdmission: ExtensionBootstrapChromeAdmission
    private let installedExtensions: InstalledExtensionCollection
    private let handler: ExtensionControllerOpeningCallbackHandler

    init(
        bootstrapChromeAdmission: ExtensionBootstrapChromeAdmission,
        installedExtensions: InstalledExtensionCollection,
        handler: ExtensionControllerOpeningCallbackHandler
    ) {
        self.bootstrapChromeAdmission = bootstrapChromeAdmission
        self.installedExtensions = installedExtensions
        self.handler = handler
    }

    func openNewTab(
        configuration: WKWebExtension.TabConfiguration,
        evidence: ExtensionControllerCallbackEvidence,
        routes: ExtensionControllerDelegateBrowserRoutes,
        urlPermissions: ExtensionURLPermissionCallbackSettlement,
        completionHandler: @escaping ((any WKWebExtensionTab)?, (any Error)?) -> Void
    ) {
        guard admitsChrome(evidence: evidence, windows: routes.windows) else {
            completionHandler(nil, bootstrapSuppressionError())
            return
        }
        settleBootstrapPermissionsIfNeeded(
            for: configuration.url.map { [$0] } ?? [],
            evidence: evidence,
            urlPermissions: urlPermissions
        ) { [handler] in
            handler.openNewTab(
                configuration: configuration,
                evidence: evidence,
                runtime: routes.opening.tabOpeningCallback,
                completionHandler: completionHandler
            )
        }
    }

    func openNewWindow(
        configuration: WKWebExtension.WindowConfiguration,
        evidence: ExtensionControllerCallbackEvidence,
        routes: ExtensionControllerDelegateBrowserRoutes,
        urlPermissions: ExtensionURLPermissionCallbackSettlement,
        completionHandler: @escaping ((any WKWebExtensionWindow)?, (any Error)?) -> Void
    ) {
        guard admitsChrome(evidence: evidence, windows: routes.windows) else {
            completionHandler(nil, bootstrapSuppressionError())
            return
        }
        settleBootstrapPermissionsIfNeeded(
            for: configuration.tabURLs,
            evidence: evidence,
            urlPermissions: urlPermissions
        ) { [handler] in
            handler.openNewWindow(
                request: ExtensionWindowOpeningRequest(configuration: configuration),
                evidence: evidence,
                runtime: routes.opening,
                completionHandler: completionHandler
            )
        }
    }

    private func settleBootstrapPermissionsIfNeeded(
        for urls: [URL],
        evidence: ExtensionControllerCallbackEvidence,
        urlPermissions: ExtensionURLPermissionCallbackSettlement,
        completion: @escaping @MainActor () -> Void
    ) {
        guard bootstrapChromeAdmission.isActiveGlobalBootstrapOwner(
            evidence: evidence
        ), let manifest = installedExtensions.records.first(where: {
            $0.id == evidence.extensionID
        })?.manifest
        else {
            completion()
            return
        }

        let targets = ExtensionBootstrapPermissionTargetPolicy
            .earlyPromptTargets(in: urls, manifest: manifest)
        guard targets.isEmpty == false else {
            completion()
            return
        }

        // Bootstrap tabs and windows may immediately require an
        // externally-connectable content script. Settle declared access before
        // publishing them, while preserving normal behavior after denial.
        urlPermissions.promptForPermissionToAccess(
            targets,
            in: nil,
            evidence: evidence
        ) { _, _ in
            completion()
        }
    }

    private func admitsChrome(
        evidence: ExtensionControllerCallbackEvidence,
        windows: ExtensionWindowVisibilityResolver
    ) -> Bool {
        bootstrapChromeAdmission.admitsChrome(
            evidence: evidence,
            hasUserGesture: windows.openWindows(for: evidence.context).contains { window in
                (window.tabs?(for: evidence.context) ?? []).contains {
                    evidence.context.hasActiveUserGesture(in: $0)
                }
            }
        )
    }

    private func bootstrapSuppressionError() -> NSError {
        SumiWebExtensionCallbackErrorMapper.webExtensionCallbackError(
            from: ExtensionManagerCallbackError.bootstrapChromeSuppressed
        )
    }
}

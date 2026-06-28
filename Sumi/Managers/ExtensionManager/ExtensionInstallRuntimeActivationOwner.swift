//
//  ExtensionInstallRuntimeActivationOwner.swift
//  Sumi
//
//  Owns the post-load runtime activation steps shared by extension install flows.
//

import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionInstallRuntimeActivationOwner {
    enum Operation {
        case install
        case safariEnable

        var resyncReason: String {
            switch self {
            case .install:
                return "ExtensionManager.performInstallation.afterLoad"
            case .safariEnable:
                return "ExtensionManager.enableSafariAppExtension.afterLoad"
            }
        }
    }

    struct Request {
        let profileId: UUID
        let extensionContext: WKWebExtensionContext
        let installedExtensionId: String
        let operation: Operation
    }

    private let manager: ExtensionManager

    init(manager: ExtensionManager) {
        self.manager = manager
    }

    func activate(_ request: Request) async {
        // New install-time contexts must see existing tabs/windows before
        // `extensionsLoaded` flips, or MV3 onboarding (`tabs.create`) may race.
        manager.tabOpenNotificationGeneration &+= 1
        manager.updateWebViewsForProfile(
            request.profileId,
            allowWhenExtensionsNotLoaded: true
        )
        manager.resyncOpenTabsWithExtensionRuntimeAfterGenerationBump(
            reason: request.operation.resyncReason,
            allowWhenExtensionsNotLoaded: true
        )
        manager.registerExistingWindowStateIfAttached()

        let installedWebExtension = request.extensionContext.webExtension
        let installedDisplayName =
            installedWebExtension.displayName ?? request.installedExtensionId
        do {
            // Await background load so `runtime.onInstalled` can run in this install cycle.
            _ = try await manager.ensureBackgroundAvailableIfRequired(
                for: installedWebExtension,
                context: request.extensionContext,
                reason: .install
            )
        } catch {
            logBackgroundWakeFailure(
                error,
                operation: request.operation,
                installedDisplayName: installedDisplayName
            )
        }
        manager.markExtensionRuntimeReadyIfProfileContextsLoaded(for: request.profileId)
    }

    private func logBackgroundWakeFailure(
        _ error: any Error,
        operation: Operation,
        installedDisplayName: String
    ) {
        switch operation {
        case .install:
            ExtensionManager.logger.error(
                "Failed to wake background worker after install for \(installedDisplayName, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        case .safariEnable:
            ExtensionManager.logger.error(
                "Failed to wake background worker after Safari extension enable for \(installedDisplayName, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}

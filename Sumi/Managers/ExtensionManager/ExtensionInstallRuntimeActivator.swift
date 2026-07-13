//
//  ExtensionInstallRuntimeActivator.swift
//  Sumi
//
//  Performs post-load runtime activation shared by extension install flows.
//

import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionInstallRuntimeActivator {
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
        let loadedContext: ExtensionRuntimeContextLoader.LoadedContext
        let installedExtensionId: String
        let operation: Operation
    }

    private let manager: ExtensionManager
    private let authority: ExtensionLoadedContextAuthority

    init(manager: ExtensionManager) {
        self.manager = manager
        self.authority = manager.loadedContextAuthority
    }

    func activate(_ request: Request) async throws {
        try validate(request.loadedContext)
        // New install-time contexts must see existing tabs/windows before
        // `extensionsLoaded` flips, or MV3 onboarding (`tabs.create`) may race.
        manager.reloadRuntimePublications(
            reason: request.operation.resyncReason,
            allowWhenExtensionsNotLoaded: true,
            profileID: request.loadedContext.bindingReceipt.key.profileId
        )
        try validate(request.loadedContext)

        let installedWebExtension = request.loadedContext.context.webExtension
        let installedDisplayName =
            installedWebExtension.displayName ?? request.installedExtensionId
        do {
            // Await background load so `runtime.onInstalled` can run in this install cycle.
            _ = try await manager.ensureBackgroundAvailableIfRequired(
                for: installedWebExtension,
                context: request.loadedContext.context,
                reason: .install,
                isCurrent: { [weak self] in
                    self?.isCurrent(request.loadedContext) == true
                }
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            logBackgroundWakeFailure(
                error,
                operation: request.operation,
                installedDisplayName: installedDisplayName
            )
        }
        try validate(request.loadedContext)
        manager.markExtensionRuntimeReadyIfProfileContextsLoaded(
            for: request.loadedContext.bindingReceipt.key.profileId
        )
    }

    private func validate(
        _ loadedContext: ExtensionRuntimeContextLoader.LoadedContext
    ) throws {
        try authority.validate(loadedContext)
    }

    private func isCurrent(
        _ loadedContext: ExtensionRuntimeContextLoader.LoadedContext
    ) -> Bool {
        do {
            try authority.validate(loadedContext)
            return true
        } catch {
            return false
        }
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

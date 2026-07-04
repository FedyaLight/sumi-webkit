//
//  ExtensionActionPopupFailureDiagnosticsOwner.swift
//  Sumi
//
//  Owns classification of action-popup runtime failures and the diagnostic
//  lines emitted alongside blocked popup requests.
//

import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionActionPopupFailureDiagnosticsOwner {
    private enum ResourcesRootState {
        case available(URL)
        case resolutionFailed(Error)
    }

    struct Dependencies {
        let installedExtensions: @MainActor () -> [InstalledExtension]
        let controllerExists: @MainActor (UUID) -> Bool
        let extensionResourcesRoot: @MainActor (WebExtensionSourceKind, String, String) throws -> URL
        let lastExtensionLoadError: @MainActor (String, UUID) -> Error?
        let extensionSnapshot:
            @MainActor (String, UUID) -> ExtensionProfileRuntimeStateOwner.ExtensionSnapshot?
        let profileIdForContext: @MainActor (WKWebExtensionContext) -> UUID?
        let currentProfileId: @MainActor () -> UUID?
        let runtimeState: @MainActor () -> ExtensionManager.ExtensionRuntimeState
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func classifyActionPopupRuntimeFailure(
        extensionId: String,
        profileId: UUID,
        installedExtension: InstalledExtension? = nil
    ) -> ExtensionActionPopupRuntimeFailureBucket {
        let installed =
            installedExtension
            ?? dependencies.installedExtensions().first(where: { $0.id == extensionId })

        guard dependencies.controllerExists(profileId) else {
            return .profileRuntimeNotFound
        }

        guard let installed else {
            return .deletedImportRecordStale
        }

        let hasOriginalAppex =
            SafariAppExtensionResources.installedAppexBundleURL(
                sourceKind: installed.sourceKind,
                sourceBundlePath: installed.sourceBundlePath
            ) != nil
        if installed.sourceKind == .safariAppExtension,
           hasOriginalAppex == false {
            return .originalAppExtensionBundleMissing
        }
        let resourcesExist = resourcesExist(
            for: resourcesRootState(for: installed)
        )
        if resourcesExist == false {
            return .sourceResourcesMissing
        }

        if let loadError = dependencies.lastExtensionLoadError(extensionId, profileId) {
            let nsError = loadError as NSError
            if nsError.domain == WKWebExtension.errorDomain {
                return .webExtensionCreationFailed
            }
            if loadError is ExtensionError {
                return .manifestValidationPolicyWrongForSourceKind
            }
        }

        guard let snapshot = dependencies.extensionSnapshot(extensionId, profileId) else {
            return .profileRuntimeNotFound
        }
        let context = snapshot.context
        if let context,
           let currentProfileId = dependencies.currentProfileId(),
           currentProfileId != profileId,
           dependencies.profileIdForContext(context) != profileId {
            return .wrongProfileRuntimeLookup
        }

        if context == nil {
            if dependencies.lastExtensionLoadError(extensionId, profileId) != nil {
                return .webExtensionCreationFailed
            }
            return .profileContextNotCreated
        }

        if context?.isLoaded == false {
            return .profileContextNotLoaded
        }

        let runtimeState = dependencies.runtimeState()
        if runtimeState == .failed {
            return .globalRuntimeLoadFailed
        }

        if runtimeState != .ready {
            return .globalRuntimeUnavailable
        }

        return .enabledStateWithoutRuntime
    }

    func actionPopupRuntimeDiagnosticLines(
        extensionId: String,
        profileId: UUID,
        installedExtension: InstalledExtension,
        failureBucket: ExtensionActionPopupRuntimeFailureBucket,
        lastLoadError: Error? = nil
    ) -> [String] {
        guard let snapshot = dependencies.extensionSnapshot(extensionId, profileId) else {
            return ["failureBucket=\(failureBucket.rawValue)", "extensionId=\(extensionId)"]
        }
        let context = snapshot.context
        let hasOriginalAppex =
            SafariAppExtensionResources.installedAppexBundleURL(
                sourceKind: installedExtension.sourceKind,
                sourceBundlePath: installedExtension.sourceBundlePath
            ) != nil
        let resourcesRootState = resourcesRootState(for: installedExtension)
        let resourcesExist = resourcesExist(for: resourcesRootState)

        var lines = [
            "failureBucket=\(failureBucket.rawValue)",
            "extensionId=\(extensionId)",
            "displayName=\(installedExtension.name)",
            "profileId=\(profileId.uuidString)",
            "sourceKind=\(installedExtension.sourceKind.rawValue)",
            "hasOriginalAppex=\(hasOriginalAppex)",
            "sourceResourcesPresent=\(resourcesExist)",
            "controllerExists=\(snapshot.controllerExists)",
            "contextExists=\(snapshot.contextExists)",
            "contextLoaded=\(snapshot.contextLoaded)",
            "runtimeState=\(dependencies.runtimeState().rawValue)",
            "missingEnabledExtensionIDs=\(snapshot.missingEnabledExtensionIDs.joined(separator: ","))",
        ]

        if let lastLoadError {
            let nsError = lastLoadError as NSError
            lines.append("lastErrorDomain=\(nsError.domain)")
            lines.append("lastErrorCode=\(nsError.code)")
            lines.append("lastErrorDescription=\(nsError.localizedDescription)")
        } else if let recordedError = dependencies.lastExtensionLoadError(
            extensionId,
            profileId
        ) {
            let nsError = recordedError as NSError
            lines.append("lastErrorDomain=\(nsError.domain)")
            lines.append("lastErrorCode=\(nsError.code)")
            lines.append("lastErrorDescription=\(nsError.localizedDescription)")
        } else if let context, context.errors.isEmpty == false, let error = context.errors.first {
            let nsError = error as NSError
            lines.append("webKitErrorDomain=\(nsError.domain)")
            lines.append("webKitErrorCode=\(nsError.code)")
            lines.append("webKitErrorDescription=\(nsError.localizedDescription)")
        }

        if case .resolutionFailed(let error) = resourcesRootState {
            let nsError = error as NSError
            lines.append("sourceResourcesErrorDomain=\(nsError.domain)")
            lines.append("sourceResourcesErrorCode=\(nsError.code)")
            lines.append("sourceResourcesErrorDescription=\(nsError.localizedDescription)")
        }

        return lines
    }

    private func resourcesRootState(
        for installedExtension: InstalledExtension
    ) -> ResourcesRootState {
        do {
            let resourcesRoot = try dependencies.extensionResourcesRoot(
                installedExtension.sourceKind,
                installedExtension.packagePath,
                installedExtension.sourceBundlePath
            )
            return .available(resourcesRoot)
        } catch {
            return .resolutionFailed(error)
        }
    }

    private func resourcesExist(for state: ResourcesRootState) -> Bool {
        switch state {
        case .available(let resourcesRoot):
            return FileManager.default.fileExists(atPath: resourcesRoot.path)
        case .resolutionFailed:
            return false
        }
    }
}

@available(macOS 15.5, *)
extension ExtensionActionPopupFailureDiagnosticsOwner.Dependencies {
    @MainActor
    static func live(manager: ExtensionManager) -> Self {
        Self(
            installedExtensions: { [weak manager] in
                manager?.installedExtensions ?? []
            },
            controllerExists: { [weak manager] profileId in
                manager?.extensionControllersByProfile[profileId] != nil
            },
            extensionResourcesRoot: { [weak manager] sourceKind, packagePath, sourceBundlePath in
                guard let manager else {
                    throw ExtensionError.installationFailed("Extension manager is unavailable")
                }
                return try manager.extensionResourcesRoot(
                    sourceKind: sourceKind,
                    packagePath: packagePath,
                    sourceBundlePath: sourceBundlePath
                )
            },
            lastExtensionLoadError: { [weak manager] extensionId, profileId in
                manager?.lastExtensionLoadError(
                    extensionId: extensionId,
                    profileId: profileId
                )
            },
            extensionSnapshot: { [weak manager] extensionId, profileId in
                manager?.profileRuntimeStateOwner.extensionSnapshot(
                    extensionId: extensionId,
                    profileId: profileId
                )
            },
            profileIdForContext: { [weak manager] context in
                manager?.profileId(for: context)
            },
            currentProfileId: { [weak manager] in
                manager?.currentProfileId
            },
            runtimeState: { [weak manager] in
                manager?.runtimeState ?? .unavailable
            }
        )
    }
}

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    func classifyActionPopupRuntimeFailure(
        extensionId: String,
        profileId: UUID,
        installedExtension: InstalledExtension? = nil
    ) -> ExtensionActionPopupRuntimeFailureBucket {
        actionPopupFailureDiagnosticsOwner.classifyActionPopupRuntimeFailure(
            extensionId: extensionId,
            profileId: profileId,
            installedExtension: installedExtension
        )
    }

    func actionPopupRuntimeDiagnosticLines(
        extensionId: String,
        profileId: UUID,
        installedExtension: InstalledExtension,
        failureBucket: ExtensionActionPopupRuntimeFailureBucket,
        lastLoadError: Error? = nil
    ) -> [String] {
        actionPopupFailureDiagnosticsOwner.actionPopupRuntimeDiagnosticLines(
            extensionId: extensionId,
            profileId: profileId,
            installedExtension: installedExtension,
            failureBucket: failureBucket,
            lastLoadError: lastLoadError
        )
    }
}

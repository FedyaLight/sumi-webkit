//
//  ExtensionActionPopupFailureDiagnostics.swift
//  Sumi
//
//  Owns classification of action-popup runtime failures and the diagnostic
//  lines emitted alongside blocked popup requests.
//

import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionActionPopupFailureDiagnostics {
    private enum ResourcesRootState {
        case available(URL)
        case resolutionFailed(Error)
    }

    private let installedExtensions: @MainActor () -> [InstalledExtension]
    private let controllerExists: @MainActor (UUID) -> Bool
    private let extensionResourcesRoot: @MainActor (WebExtensionSourceKind, String, String) throws -> URL
    private let lastExtensionLoadError: @MainActor (String, UUID) -> Error?
    private let extensionSnapshot:
        @MainActor (String, UUID) -> ExtensionProfileRuntimeStateOwner.ExtensionSnapshot?
    private let profileIdForContext: @MainActor (WKWebExtensionContext) -> UUID?
    private let currentProfileId: @MainActor () -> UUID?
    private let runtimeState: @MainActor () -> ExtensionManager.ExtensionRuntimeState

    init(
        installedExtensions: @escaping @MainActor () -> [InstalledExtension],
        controllerExists: @escaping @MainActor (UUID) -> Bool,
        extensionResourcesRoot: @escaping @MainActor (WebExtensionSourceKind, String, String) throws -> URL,
        lastExtensionLoadError: @escaping @MainActor (String, UUID) -> Error?,
        extensionSnapshot:
            @escaping @MainActor (String, UUID) -> ExtensionProfileRuntimeStateOwner.ExtensionSnapshot?,
        profileIdForContext: @escaping @MainActor (WKWebExtensionContext) -> UUID?,
        currentProfileId: @escaping @MainActor () -> UUID?,
        runtimeState: @escaping @MainActor () -> ExtensionManager.ExtensionRuntimeState
    ) {
        self.installedExtensions = installedExtensions
        self.controllerExists = controllerExists
        self.extensionResourcesRoot = extensionResourcesRoot
        self.lastExtensionLoadError = lastExtensionLoadError
        self.extensionSnapshot = extensionSnapshot
        self.profileIdForContext = profileIdForContext
        self.currentProfileId = currentProfileId
        self.runtimeState = runtimeState
    }

    func classifyActionPopupRuntimeFailure(
        extensionId: String,
        profileId: UUID,
        installedExtension: InstalledExtension? = nil
    ) -> ExtensionActionPopupRuntimeFailureBucket {
        let installed =
            installedExtension
            ?? installedExtensions().first(where: { $0.id == extensionId })

        guard controllerExists(profileId) else {
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

        if let loadError = lastExtensionLoadError(extensionId, profileId) {
            let nsError = loadError as NSError
            if nsError.domain == WKWebExtension.errorDomain {
                return .webExtensionCreationFailed
            }
            if loadError is ExtensionError {
                return .manifestValidationPolicyWrongForSourceKind
            }
        }

        guard let snapshot = extensionSnapshot(extensionId, profileId) else {
            return .profileRuntimeNotFound
        }
        let context = snapshot.context
        if let context,
           let activeProfileId = currentProfileId(),
           activeProfileId != profileId,
           profileIdForContext(context) != profileId {
            return .wrongProfileRuntimeLookup
        }

        if context == nil {
            if lastExtensionLoadError(extensionId, profileId) != nil {
                return .webExtensionCreationFailed
            }
            return .profileContextNotCreated
        }

        if context?.isLoaded == false {
            return .profileContextNotLoaded
        }

        let currentRuntimeState = runtimeState()
        if currentRuntimeState == .failed {
            return .globalRuntimeLoadFailed
        }

        if currentRuntimeState != .ready {
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
        guard let snapshot = extensionSnapshot(extensionId, profileId) else {
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
            "runtimeState=\(runtimeState().rawValue)",
            "missingEnabledExtensionIDs=\(snapshot.missingEnabledExtensionIDs.joined(separator: ","))",
        ]

        if let lastLoadError {
            let nsError = lastLoadError as NSError
            lines.append("lastErrorDomain=\(nsError.domain)")
            lines.append("lastErrorCode=\(nsError.code)")
            lines.append("lastErrorDescription=\(nsError.localizedDescription)")
        } else if let recordedError = lastExtensionLoadError(
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
            let resourcesRoot = try extensionResourcesRoot(
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
extension ExtensionActionPopupFailureDiagnostics {
    convenience init(manager: ExtensionManager) {
        self.init(
            installedExtensions: { [weak manager] in
                manager?.installedExtensionCollection.records ?? []
            },
            controllerExists: { [weak manager] profileId in
                manager?.profileRuntime.controllersByProfile[profileId] != nil
            },
            extensionResourcesRoot: { [weak manager] sourceKind, packagePath, sourceBundlePath in
                guard let manager else {
                    throw ExtensionError.installationFailed(
                        "Extension manager is unavailable"
                    )
                }
                return try manager.extensionResourcesRoot(
                    sourceKind: sourceKind,
                    packagePath: packagePath,
                    sourceBundlePath: sourceBundlePath
                )
            },
            lastExtensionLoadError: { [weak manager] extensionId, profileId in
                manager?.runtimeCatalog.loadError(
                    extensionID: extensionId,
                    profileID: profileId
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
                manager?.profileRuntime.currentProfileId
            },
            runtimeState: { [weak manager] in
                manager?.runtimeLifecycle.state ?? .unavailable
            }
        )
    }
}

//
//  ExtensionActionBundle.swift
//  Sumi
//
//  V3 EM thin capability bag: action-adjacent popup / surface owners.
//

import Foundation
import WebKit

/// Groups action-adjacent ExtensionManager owners so EM no longer holds
/// separate peer `lazy var` Owners wired via `Dependencies.live`.
@available(macOS 15.5, *)
@MainActor
final class ExtensionActionBundle {
    let actionPopupAnchorResolutionOwner: ExtensionActionPopupAnchorResolutionOwner
    let actionPopupFailureDiagnosticsOwner: ExtensionActionPopupFailureDiagnosticsOwner
    let actionSurfacePublicationOwner: ExtensionActionSurfacePublicationOwner

    init(manager: ExtensionManager) {
        self.actionPopupAnchorResolutionOwner = ExtensionActionPopupAnchorResolutionOwner(
            actionAnchorStore: manager.actionAnchorStore,
            actionPopupAnchorStore: manager.actionPopupAnchorStore,
            browserBridgeContext: { [weak manager] in
                manager?.browserBridgeContext
            },
            fallbackProfileId: { [weak manager] in
                manager?.fallbackProfileId
            },
            resolvedProfileId: { [weak manager] windowState in
                manager?.resolvedProfileId(for: windowState)
            },
            windowMatchesProfile: { [weak manager] windowState, profileId in
                manager?.windowMatchesProfile(windowState, profileId: profileId) ?? false
            },
            trace: { [weak manager] message in
                manager?.extensionRuntimeTrace(message())
            }
        )
        self.actionPopupFailureDiagnosticsOwner = ExtensionActionPopupFailureDiagnosticsOwner(
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
        self.actionSurfacePublicationOwner = ExtensionActionSurfacePublicationOwner(
            extensionIDForContext: { [weak manager] context in
                manager?.extensionID(for: context)
            },
            setActionSurfaceState: { [weak manager] extensionId, state in
                manager?.actionStatesByExtensionID[extensionId] = state
            },
            removeActionSurfaceState: { [weak manager] extensionId in
                manager?.actionStatesByExtensionID.removeValue(forKey: extensionId)
            },
            currentExtensionTab: { [weak manager] in
                manager?.browserBridgeContext?.currentExtensionTabForActiveWindow()
            },
            stableAdapter: { [weak manager] tab in
                manager?.adapterResolutionOwner.stableAdapter(for: tab)
            },
            resolvedProfileId: { [weak manager] profileId in
                manager?.resolvedProfileId(explicitProfileId: profileId)
            },
            getExtensionContext: { [weak manager] extensionId, profileId in
                manager?.getExtensionContext(for: extensionId, profileId: profileId)
            },
            ensureBackgroundAvailableIfRequired: { [weak manager] webExtension, context, reason in
                _ = try await manager?.ensureBackgroundAvailableIfRequired(
                    for: webExtension,
                    context: context,
                    reason: reason
                )
            },
            reconcileOpenTabsAfterExtensionContextLoad: { [weak manager] reason in
                manager?.reconcileOpenTabsAfterExtensionContextLoad(reason: reason)
            }
        )
    }
}

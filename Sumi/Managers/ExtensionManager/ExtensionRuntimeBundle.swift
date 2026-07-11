//
//  ExtensionRuntimeBundle.swift
//  Sumi
//
//  V3 EM thin capability bag: runtime / window / site thin owners.
//

import Foundation
import WebKit

/// Groups runtime/window/site ExtensionManager owners so EM no longer holds
/// separate peer `lazy var` Owners wired via `Dependencies.live`.
@available(macOS 15.5, *)
@MainActor
final class ExtensionRuntimeBundle {
    let windowFocusResolutionOwner: ExtensionWindowFocusResolutionOwner
    let siteAccessPolicyCoordinator: ExtensionSiteAccessPolicyCoordinator
    let backgroundWakeCoordinator: ExtensionBackgroundWakeCoordinator
    let windowRequests: ExtensionWindowRequestRouter

    init(manager: ExtensionManager) {
        self.windowFocusResolutionOwner = ExtensionWindowFocusResolutionOwner(
            windowQuery: { [weak manager] in
                manager?.extensionWindowQuery
            },
            auxiliaryWindows: { [weak manager] in
                manager?.extensionAuxiliaryWindows
            },
            profileIdForContext: { [weak manager] context in
                manager?.profileId(for: context)
            },
            extensionIDForContext: { [weak manager] context in
                manager?.extensionID(for: context)
            },
            publishedWindowAdapter: { [weak manager] windowState, profileId in
                manager?.browserRuntimeBridgeOwner.publishedWindowAdapter(
                    for: windowState,
                    profileID: profileId
                )
            },
            miniWindowAdapters: { [weak manager] ownerExtensionID, profileID in
                manager?.browserRuntimeBridgeOwner
                    .windowPublications.publishedAuxiliaryWindowAdapters(
                        ownerExtensionID: ownerExtensionID,
                        profileID: profileID
                    ) ?? []
            }
        )
        self.siteAccessPolicyCoordinator = ExtensionSiteAccessPolicyCoordinator(
            siteAccessPolicyStore: manager.siteAccessPolicyStore,
            installCapabilityOwner: manager.installCapabilityOwner,
            installedExtensions: { [weak manager] in manager?.installedExtensionCollection.records ?? [] },
            loadedExtensionManifests: { [weak manager] in
                manager?.runtimeSession.loadedExtensionManifests ?? [:]
            },
            getExtensionContext: { [weak manager] extensionId, profileId in
                manager?.getExtensionContext(for: extensionId, profileId: profileId)
            },
            reconcileOpenTabsAfterExtensionContextLoad: { [weak manager] reason, profileId in
                manager?.reconcileOpenTabsAfterExtensionContextLoad(
                    reason: reason,
                    profileId: profileId
                )
            },
            postSiteAccessPoliciesDidChange: { [weak manager] in
                guard let manager else { return }
                NotificationCenter.default.post(
                    name: .sumiExtensionSiteAccessPoliciesDidChange,
                    object: manager
                )
            }
        )
        self.backgroundWakeCoordinator = ExtensionBackgroundWakeCoordinator(
            backgroundRuntimeStateOwner: manager.backgroundRuntimeStateOwner,
            nativeMessagingBackgroundWakeOwner: { [weak manager] in
                manager?.nativeMessagingBackgroundWakeOwner
            },
            contextIdentity: { [weak manager] extensionContext in
                manager?.contextIdentity(for: extensionContext)
            },
            resolvedProfileId: { [weak manager] explicitProfileId in
                manager?.resolvedProfileId(explicitProfileId: explicitProfileId)
            },
            recordRuntimeMetric: { [weak manager] extensionId, update in
                manager?.runtimeSession.recordRuntimeMetric(for: extensionId, update: update)
            },
            trace: { [weak manager] message in
                manager?.runtimeDiagnostics.trace(message)
            },
            logBackgroundWakeFailure: { [weak manager] error, extensionContext, reason, operation in
                manager?.logBackgroundWakeFailure(
                    error,
                    extensionContext: extensionContext,
                    reason: reason,
                    operation: operation
                )
            },
            debugBackgroundContentWake: { [weak manager] in
                #if DEBUG
                    manager?.testHooks.backgroundContentWake
                #else
                    nil
                #endif
            }
        )
        self.windowRequests = ExtensionWindowRequestRouter(
            profileRuntime: manager.profileRuntime,
            targetResolver: manager.requestedTabTargetResolver,
            loadResolver: manager.requestedTabLoadResolver,
            contextPreloader: manager.requestedTabContextPreloader,
            tabOpening: manager.requestedTabOpening,
            windowQuery: { [weak manager] in
                manager?.extensionWindowQuery
            },
            windowCreation: { [weak manager] in
                manager?.extensionRequestedWindowCreation
            },
            publishedWindow: { [weak manager] window, profileID in
                manager?.browserRuntimeBridgeOwner.publishedWindowAdapter(
                    for: window,
                    profileID: profileID
                )
            }
        )
    }
}

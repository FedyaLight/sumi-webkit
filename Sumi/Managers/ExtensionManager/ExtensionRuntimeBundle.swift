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
    let requestedWindowOpeningOwner: ExtensionRequestedWindowOpeningOwner

    init(manager: ExtensionManager) {
        self.windowFocusResolutionOwner = ExtensionWindowFocusResolutionOwner(
            windowQuery: { [weak manager] in
                manager?.extensionWindowQuery
            },
            tabQuery: { [weak manager] in
                manager?.extensionTabQuery
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
            windowMatchesProfile: { [weak manager] windowState, profileId in
                manager?.windowMatchesProfile(windowState, profileId: profileId) ?? false
            },
            windowAdapter: { [weak manager] windowId in
                manager?.adapterResolutionOwner.windowAdapter(for: windowId)
            },
            miniWindowAdapters: { [weak manager] in
                manager.map { Array($0.adapterStore.miniWindowAdapters.values) } ?? []
            },
            resolvedProfileIdForTab: { [weak manager] tab in
                manager?.resolvedProfileId(for: tab)
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
        self.requestedWindowOpeningOwner = ExtensionRequestedWindowOpeningOwner(
            windowQuery: { [weak manager] in
                manager?.extensionWindowQuery
            },
            requestedTabTargets: { [weak manager] in
                manager?.requestedTabTargetQuery
            },
            tabMutation: { [weak manager] in
                manager?.extensionTabMutation
            },
            profileIdForContext: { [weak manager] context in
                manager?.profileId(for: context)
            },
            windowMatchesProfile: { [weak manager] windowState, profileId in
                manager?.windowMatchesProfile(windowState, profileId: profileId) ?? false
            },
            extensionLoadURL: { [weak manager] url, controller in
                guard let manager else { return (nil, nil) }
                let load = manager.requestedTabLoadResolver.resolve(
                    url,
                    controller: controller
                )
                return (load.url, load.extensionContext)
            },
            prepareContentScriptContextsForInitialLoad: { [weak manager] loadURL, contextOverride, targetWindow, targetSpace, controller in
                guard let manager else { return }
                _ = await manager.requestedTabContextPreloader.prepare(
                    load: ExtensionRequestedTabLoad(
                        url: loadURL,
                        extensionContext: contextOverride
                    ),
                    targetWindow: targetWindow,
                    targetSpace: targetSpace,
                    controller: controller
                )
            },
            openExtensionRequestedTab: { [weak manager] url, shouldBeActive, shouldBePinned, requestedWindow, controller, extensionContext, reason in
                guard let manager else {
                    throw ExtensionManagerCallbackError.extensionManagerUnavailable.nsError()
                }
                return try manager.requestedTabOpening.open(
                    url: url,
                    shouldBeActive: shouldBeActive,
                    shouldBePinned: shouldBePinned,
                    requestedWindow: requestedWindow,
                    controller: controller,
                    extensionContext: extensionContext,
                    reason: reason
                )
            },
            windowAdapter: { [weak manager] windowId in
                manager?.adapterResolutionOwner.windowAdapter(for: windowId)
            },
            materializeNormalTabIfNeeded: { [weak manager] tab, isActive, targetWindow in
                guard let manager else { return }
                manager.requestedTabWebViewMaterializer
                    .materializeNormalTabIfNeeded(
                    tab,
                    isActive: isActive,
                    targetWindow: targetWindow
                )
            },
            registerCreatedTabWithExtensionRuntime: { [weak manager] tab, reason in
                guard let manager else { return }
                manager.extensionCreatedTabRegistrar.register(
                    tab, reason: reason
                )
            }
        )
    }
}

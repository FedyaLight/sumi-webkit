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
            browserBridgeContext: { [weak manager] in
                manager?.browserBridgeContext
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
            installedExtensions: { [weak manager] in manager?.installedExtensions ?? [] },
            loadedExtensionManifests: { [weak manager] in
                manager?.loadedExtensionManifests ?? [:]
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
                manager?.runtimeSessionOwner.recordRuntimeMetric(for: extensionId, update: update)
            },
            trace: { [weak manager] message in
                manager?.extensionRuntimeTrace(message)
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
            browserBridgeContext: { [weak manager] in
                manager?.browserBridgeContext
            },
            profileIdForContext: { [weak manager] context in
                manager?.profileId(for: context)
            },
            windowMatchesProfile: { [weak manager] windowState, profileId in
                manager?.windowMatchesProfile(windowState, profileId: profileId) ?? false
            },
            extensionLoadURL: { [weak manager] url, controller in
                manager?.requestedTabLifecycleOwner.loadURL(for: url, controller: controller) ?? (nil, nil)
            },
            prepareContentScriptContextsForInitialLoad: { [weak manager] loadURL, contextOverride, targetWindow, targetSpace, controller in
                _ = await manager?.prepareContentScriptContextsForExtensionRequestedInitialLoad(
                    loadURL: loadURL,
                    webExtensionContextOverride: contextOverride,
                    targetWindow: targetWindow,
                    targetSpace: targetSpace,
                    controller: controller
                )
            },
            openExtensionRequestedTab: { [weak manager] url, shouldBeActive, shouldBePinned, requestedWindow, controller, extensionContext, reason in
                guard let manager else {
                    throw ExtensionManagerCallbackError.extensionManagerUnavailable.nsError()
                }
                return try manager.openExtensionRequestedTab(
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
                manager?.materializeExtensionRequestedNormalTabIfNeeded(
                    tab,
                    isActive: isActive,
                    targetWindow: targetWindow
                )
            },
            registerCreatedTabWithExtensionRuntime: { [weak manager] tab, reason in
                manager?.registerExtensionCreatedTabWithExtensionRuntime(
                    tab,
                    reason: reason
                )
            }
        )
    }
}

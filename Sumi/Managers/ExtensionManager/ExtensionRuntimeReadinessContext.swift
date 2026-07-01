//
//  ExtensionRuntimeReadinessContext.swift
//  Sumi
//
//  Pure profile-runtime readiness decisions. ExtensionManager still owns WebKit
//  controller creation, context loading, and UI side effects.
//

import Foundation

struct ExtensionRuntimeReadinessContext: Equatable {
    let hasEnabledExtensionDemand: Bool
    let enabledExtensionIDs: Set<String>
    let loadedExtensionStatesByID: [String: Bool]
    let controllerExists: Bool
    let globalRuntimeReady: Bool

    var missingEnabledExtensionIDs: [String] {
        Array(enabledExtensionIDs.subtracting(loadedExtensionStatesByID.keys)).sorted()
    }

    var unloadedEnabledExtensionIDs: [String] {
        enabledExtensionIDs
            .filter { loadedExtensionStatesByID[$0] != true }
            .sorted()
    }

    var isProfileReady: Bool {
        hasEnabledExtensionDemand == false || unloadedEnabledExtensionIDs.isEmpty
    }

    func isExtensionReady(extensionID: String) -> Bool {
        loadedExtensionStatesByID[extensionID] == true
    }

    func canUseExistingRuntime(extensionID: String?) -> Bool {
        if let extensionID {
            return isExtensionReady(extensionID: extensionID)
        }
        return controllerExists && isProfileReady
    }

    func isReadyAfterRuntimeRequest(extensionID: String?) -> Bool {
        if let extensionID {
            return isExtensionReady(extensionID: extensionID)
        }
        return isProfileReady
    }

    func allowsReadyControllerFallback(extensionID: String?) -> Bool {
        extensionID == nil && controllerExists && globalRuntimeReady && isProfileReady
    }
}

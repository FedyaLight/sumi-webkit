//
//  ExtensionControllerProvisioningOwner.swift
//  Sumi
//
//  Adapts user-extension runtime roles to the browser-owned profile host and
//  binds the user-extension delegate to its shared controller.
//

import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
protocol ExtensionControllerProvisioning: AnyObject {
    func controllerIfAdmitted(
        for profileID: UUID,
        mutationLease: ProfileReferenceMutationLease?
    ) -> WKWebExtensionController?
}

@available(macOS 15.5, *)
@MainActor
protocol ExtensionWebViewConfigurationProvisioning: AnyObject {
    func controllerIfAdmitted(
        for profileId: UUID,
        mutationLease: ProfileReferenceMutationLease?
    ) -> WKWebExtensionController?
    func websiteDataStoreIfAdmitted(
        for profileId: UUID,
        mutationLease: ProfileReferenceMutationLease?
    ) -> WKWebsiteDataStore?
}

@available(macOS 15.5, *)
@MainActor
extension ExtensionControllerProvisioningOwner {
    func controllerIfAdmitted(
        for profileID: UUID
    ) -> WKWebExtensionController? {
        controllerIfAdmitted(for: profileID, mutationLease: nil)
    }

    func websiteDataStoreIfAdmitted(
        for profileID: UUID
    ) -> WKWebsiteDataStore? {
        websiteDataStoreIfAdmitted(for: profileID, mutationLease: nil)
    }
}

@available(macOS 15.5, *)
@MainActor
final class ExtensionControllerProvisioningOwner:
    ExtensionWebViewConfigurationProvisioning,
    ExtensionControllerProvisioning {
    struct Dependencies {
        let profileRuntime: ExtensionProfileRuntime
        let profileWebExtensionRuntime: SumiProfileWebExtensionRuntime
        let assignControllerDelegate: @MainActor (WKWebExtensionController) -> Void
        let controllerDelegateReadiness:
            ExtensionControllerDelegateReadiness
    }

    private let dependencies: Dependencies
    private var installedBindingsByProfile:
        [UUID: ExtensionControllerBindingSnapshot] = [:]

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    @discardableResult
    func controllerIfAdmitted(
        for profileId: UUID,
        mutationLease suppliedLease: ProfileReferenceMutationLease?
    ) -> WKWebExtensionController? {
        guard let controller = dependencies.profileWebExtensionRuntime
            .controllerIfAdmitted(
                for: profileId,
                mutationLease: suppliedLease
            ) else {
            return nil
        }
        if let binding = dependencies.profileRuntime
            .controllerBindingSnapshot(for: profileId),
           isInstalled(binding) == false {
            dependencies.assignControllerDelegate(controller)
            dependencies.controllerDelegateReadiness.controllerInstalled(binding)
            installedBindingsByProfile[profileId] = binding
        }
        return controller
    }

    func websiteDataStoreIfAdmitted(
        for profileId: UUID,
        mutationLease suppliedLease: ProfileReferenceMutationLease?
    ) -> WKWebsiteDataStore? {
        dependencies.profileWebExtensionRuntime.websiteDataStoreIfAdmitted(
            for: profileId,
            mutationLease: suppliedLease
        )
    }

    #if DEBUG
        func ensureExtensionController(
            for profileId: UUID
        ) -> WKWebExtensionController {
            guard let controller = controllerIfAdmitted(for: profileId) else {
                preconditionFailure("Test provisioned a blocked profile controller")
            }
            return controller
        }

        func websiteDataStore(for profileId: UUID) -> WKWebsiteDataStore {
            guard let store = websiteDataStoreIfAdmitted(for: profileId) else {
                preconditionFailure("Test requested a blocked profile data store")
            }
            return store
        }
    #endif

    func removeAllExtensionPageUserContentControllers() {
        dependencies.profileWebExtensionRuntime
            .removeAllExtensionPageUserContentControllers()
    }

    func releaseUserRuntime() {
        installedBindingsByProfile.removeAll()
        dependencies.profileWebExtensionRuntime.releaseUserRuntime()
    }

    func retireProfileController(
        profileID: UUID,
        fallbackProfileID: UUID
    ) {
        installedBindingsByProfile.removeValue(forKey: profileID)
        dependencies.profileWebExtensionRuntime.retireProfileController(
            profileID: profileID,
            fallbackProfileID: fallbackProfileID
        )
    }

    func containsProfileReference(to profileID: UUID) -> Bool {
        dependencies.profileWebExtensionRuntime
            .containsExtensionPageReference(to: profileID)
    }

    var hasExtensionPageUserContentControllers: Bool {
        dependencies.profileWebExtensionRuntime
            .hasExtensionPageUserContentControllers
    }

    private func isInstalled(
        _ binding: ExtensionControllerBindingSnapshot
    ) -> Bool {
        guard let installed = installedBindingsByProfile[binding.profileID]
        else { return false }
        return installed.revision == binding.revision
            && installed.controller === binding.controller
    }
}

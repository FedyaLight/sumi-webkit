import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
struct ExtensionOptionsWindowPresentationReceipt {
    let evidence: ExtensionControllerCallbackEvidence
    let profile: Profile
    let displayName: String
    let optionsURL: URL
    let packageURL: URL
    let extensionRoot: URL
    let configuration: WKWebViewConfiguration
    let visitedLinkStore: NSObject
    let installedRecordRevision: UInt64
}

@available(macOS 15.5, *)
@MainActor
struct ExtensionOptionsWindowCallbackRuntime {
    let admission: ExtensionControllerCallbackAdmission
    let installedExtensions: InstalledExtensionCollection
    let websiteDataMutationAdmissionIsBlocked:
        ExtensionManagerRuntime.WebsiteDataMutationAdmissionCheck
    let waitForWebsiteDataMutationAdmission:
        ExtensionManagerRuntime.WebsiteDataMutationAdmissionWaiter

    func isCurrent(
        _ receipt: ExtensionOptionsWindowPresentationReceipt
    ) -> Bool {
        let evidence = receipt.evidence
        return admission.isCurrent(evidence)
            && installedExtensions.recordRevision(for: evidence.extensionID)
                == receipt.installedRecordRevision
            && installedExtensions.records.contains {
                $0.id == evidence.extensionID
            }
            && receipt.profile.id == evidence.profileID
            && evidence.controller.configuration.defaultWebsiteDataStore
                === receipt.profile.dataStore
            && receipt.configuration.websiteDataStore
                === receipt.profile.dataStore
            && receipt.configuration.webExtensionController
                === evidence.controller
            && receipt.configuration.sumiVisitedLinkStoreObject
                === receipt.visitedLinkStore
            && evidence.controller.extensionContext(for: receipt.optionsURL)
                === evidence.context
            && FileManager.default.fileExists(
                atPath: receipt.packageURL.path
            )
    }
}

@available(macOS 15.5, *)
@MainActor
enum ExtensionOptionsWindowCallbackComposition {
    struct Invocation {
        let receipt: ExtensionOptionsWindowPresentationReceipt
        let runtime: ExtensionOptionsWindowCallbackRuntime
    }

    static func invocation(
        from manager: ExtensionManager,
        evidence: ExtensionControllerCallbackEvidence
    ) -> Invocation? {
        guard manager.controllerCallbackAdmission.isCurrent(evidence),
              let profile = manager.runtime.profile(evidence.profileID),
              profile.id == evidence.profileID,
              manager.profileRuntime.controller(for: evidence.profileID)
                === evidence.controller,
              evidence.controller.configuration.defaultWebsiteDataStore
                === profile.dataStore,
              let installedExtension = manager.installedExtensionCollection
                .records.first(where: { $0.id == evidence.extensionID }),
              let resolution = ExtensionOptionsPageResolver.resolve(
                  context: evidence.context,
                  controller: evidence.controller,
                  installedExtension: installedExtension
              )
        else {
            return nil
        }

        guard let configuration = evidence.context.webViewConfiguration,
              configuration.webExtensionController === evidence.controller,
              configuration.websiteDataStore === profile.dataStore
        else {
            return nil
        }
        configuration.sumiIsNormalTabWebViewConfiguration = false
        manager.browserConfiguration.applyVisitedLinkStore(
            to: configuration,
            for: profile
        )
        manager.webViewConfigurationPreparation
            .prepareWebViewConfigForExtensionRuntime(
                configuration,
                profileId: evidence.profileID,
                reason: "ExtensionOptionsWindowCallbackComposition"
            )
        guard configuration.webExtensionController === evidence.controller,
              configuration.websiteDataStore === profile.dataStore,
              let visitedLinkStore = configuration.sumiVisitedLinkStoreObject
        else {
            return nil
        }

        let runtime = manager.runtime
        let receipt = ExtensionOptionsWindowPresentationReceipt(
            evidence: evidence,
            profile: profile,
            displayName:
                evidence.context.webExtension.displayName ?? "Extension",
            optionsURL: resolution.presentationURL,
            packageURL: resolution.packageURL,
            extensionRoot: resolution.extensionRoot,
            configuration: configuration,
            visitedLinkStore: visitedLinkStore,
            installedRecordRevision: manager.installedExtensionCollection
                .recordRevision(for: evidence.extensionID)
        )
        let callbackRuntime = ExtensionOptionsWindowCallbackRuntime(
            admission: manager.controllerCallbackAdmission,
            installedExtensions: manager.installedExtensionCollection,
            websiteDataMutationAdmissionIsBlocked:
                runtime.websiteDataMutationAdmissionIsBlocked,
            waitForWebsiteDataMutationAdmission:
                runtime.waitForWebsiteDataMutationAdmission
        )
        guard callbackRuntime.isCurrent(receipt) else { return nil }
        return Invocation(receipt: receipt, runtime: callbackRuntime)
    }
}

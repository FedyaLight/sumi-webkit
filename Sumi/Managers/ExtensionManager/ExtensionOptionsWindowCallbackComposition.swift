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
    let websiteDataAdmission: ExtensionWebsiteDataMutationAdmission

    func isCurrent(
        _ receipt: ExtensionOptionsWindowPresentationReceipt
    ) -> Bool {
        let evidence = receipt.evidence
        return admission.isCurrent(evidence)
            && installedExtensions.recordRevision(for: evidence.extensionID)
                == receipt.installedRecordRevision
            && installedExtensions.records.contains {
                $0.id == evidence.extensionID && $0.isEnabled
            }
            && receipt.profile.id == evidence.profileID
            && receipt.configuration.websiteDataStore
                === evidence.controller.configuration.defaultWebsiteDataStore
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
}

@available(macOS 15.5, *)
@MainActor
final class ExtensionOptionsWindowCallbackComposer {
    private let admission: ExtensionControllerCallbackAdmission
    private let profiles: ExtensionBrowserProfileQuery
    private let profileRuntime: ExtensionProfileRuntime
    private let installedExtensions: InstalledExtensionCollection
    private let browserConfiguration: BrowserConfiguration
    private let configurationPreparation:
        ExtensionWebViewConfigurationPreparation
    private let websiteDataAdmission:
        ExtensionWebsiteDataMutationAdmission

    init(
        admission: ExtensionControllerCallbackAdmission,
        profiles: ExtensionBrowserProfileQuery,
        profileRuntime: ExtensionProfileRuntime,
        installedExtensions: InstalledExtensionCollection,
        browserConfiguration: BrowserConfiguration,
        configurationPreparation: ExtensionWebViewConfigurationPreparation,
        websiteDataAdmission: ExtensionWebsiteDataMutationAdmission
    ) {
        self.admission = admission
        self.profiles = profiles
        self.profileRuntime = profileRuntime
        self.installedExtensions = installedExtensions
        self.browserConfiguration = browserConfiguration
        self.configurationPreparation = configurationPreparation
        self.websiteDataAdmission = websiteDataAdmission
    }

    func invocation(
        evidence: ExtensionControllerCallbackEvidence
    ) -> ExtensionOptionsWindowCallbackComposition.Invocation? {
        guard admission.isCurrent(evidence),
              let profile = profiles.profile(evidence.profileID),
              profile.id == evidence.profileID,
              profileRuntime.controller(for: evidence.profileID)
                === evidence.controller,
              let installedExtension = installedExtensions
                .records.first(where: {
                    $0.id == evidence.extensionID && $0.isEnabled
                }),
              let resolution = ExtensionOptionsPageResolver.resolve(
                  context: evidence.context,
                  controller: evidence.controller,
                  installedExtension: installedExtension
              )
        else {
            return nil
        }

        guard let contextConfiguration = evidence.context.webViewConfiguration,
              contextConfiguration.webExtensionController === evidence.controller
        else {
            return nil
        }
        // WebKit binds extension URLs to this exact configuration; a copied or
        // rebuilt configuration does not retain that binding.
        let configuration = contextConfiguration
        configuration.sumiIsNormalTabWebViewConfiguration = false
        browserConfiguration.applyVisitedLinkStore(to: configuration, for: profile)
        guard configuration.webExtensionController === evidence.controller,
              let visitedLinkStore = configuration.sumiVisitedLinkStoreObject
        else {
            return nil
        }

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
            installedRecordRevision: installedExtensions
                .recordRevision(for: evidence.extensionID)
        )
        let callbackRuntime = ExtensionOptionsWindowCallbackRuntime(
            admission: admission,
            installedExtensions: installedExtensions,
            websiteDataAdmission: websiteDataAdmission
        )
        guard callbackRuntime.isCurrent(receipt) else { return nil }
        return ExtensionOptionsWindowCallbackComposition.Invocation(
            receipt: receipt,
            runtime: callbackRuntime
        )
    }
}

@available(macOS 15.5, *)
@MainActor
extension ExtensionOptionsWindowCallbackComposition {
    static func invocation(
        callbacks: ExtensionBrowserAttachmentAuthority.ControllerCallbacks,
        context: WKWebExtensionContext,
        controller: WKWebExtensionController
    ) -> Invocation? {
        callbacks.optionsInvocation(
            context: context,
            controller: controller
        )
    }

    #if DEBUG
        static func invocation(
            callbacks: ExtensionBrowserAttachmentAuthority.ControllerCallbacks,
            evidence: ExtensionControllerCallbackEvidence
        ) -> Invocation? {
            callbacks.optionsInvocation(evidence: evidence)
        }
    #endif
}

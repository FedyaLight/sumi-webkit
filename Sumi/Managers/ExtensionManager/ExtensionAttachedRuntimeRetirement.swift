import AppKit
import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
extension ExtensionBrowserAttachmentAuthority {
    /// Typed scoped/full retirement operations. No service-bearing resource
    /// aggregate is returned to the caller.
    @MainActor
    final class Retirement {
        struct BrowserEnvironment {
            let availability: ExtensionBrowserRuntimeAvailability
            let tabs: BrowserExtensionTabQueryAdapter
            let webViews: BrowserExtensionWebViewAdapter
            let auxiliaryWindows: BrowserExtensionAuxiliaryWindowAdapter
        }

        struct ActivityEnvironment {
            let deferredTabRegistration: ExtensionDeferredTabRegistration
            let publicationReconciler: ExtensionRuntimePublicationReconciler
        }

        struct Environment {
            let browser: BrowserEnvironment
            let activity: ActivityEnvironment
        }

        private let attachedEnvironment: @MainActor () -> Environment?
        private let retireAttachment: @MainActor () -> Void

        init(attachment: ExtensionBrowserAttachmentAuthority) {
            attachedEnvironment = { [weak attachment] in
                attachment?.retirementEnvironment()
            }
            retireAttachment = { [weak attachment] in
                attachment?.retireCurrentAttachment()
            }
        }

        func retire(
            using scopedRetirement: ExtensionScopedRuntimeRetirement,
            extensionID: String,
            cause: ExtensionScopedRuntimeRetirement.Cause,
            admission: ExtensionScopedRuntimeRetirement.Admission,
            nativeMessagingOwners: ExtensionDemandScopedNativeMessagingOwners
        ) -> ExtensionScopedRuntimeRetirement.Result {
            var wakes: ExtensionNativeMessagingBackgroundWakeOwner?
            nativeMessagingOwners.withLoadedWakeOwner { wakes = $0 }
            var relay: SumiNativeMessagingRelay?
            nativeMessagingOwners.withLoadedRelayOwner {
                relay = $0.loadedRelay
            }
            let auxiliaryWindows = attachedEnvironment()?.browser
                .auxiliaryWindows as (any ExtensionAuxiliaryWindowControl)?
            return scopedRetirement.retire(
                extensionID: extensionID,
                cause: cause,
                admission: admission,
                resources: .init(
                    auxiliaryWindows: auxiliaryWindows,
                    nativeMessagingWakes: wakes,
                    nativeMessagingRelay: relay
                )
            )
        }

        func shutDown(
            using shutdown: ExtensionRuntimeShutdown,
            reason: String,
            initialDocumentPreparation:
                ExtensionInitialDocumentRuntimePreparationOwner?,
            nativeMessagingOwners: ExtensionDemandScopedNativeMessagingOwners,
            admission: ExtensionRuntimeShutdown.Admission
        ) -> ExtensionRuntimeShutdown.Result {
            var wakes: ExtensionNativeMessagingBackgroundWakeOwner?
            nativeMessagingOwners.withLoadedWakeOwner { wakes = $0 }
            var relay: SumiNativeMessagingRelay?
            nativeMessagingOwners.withLoadedRelayOwner {
                relay = $0.loadedRelay
            }
            if let environment = attachedEnvironment() {
                let browser = environment.browser
                let activity = environment.activity
                return shutdown.shutDown(
                    reason: reason,
                    browserTabs: browser.tabs.allExtensionTabs,
                    liveWebViews: { [webViews = browser.webViews] tab in
                        webViews.extensionLiveWebViews(for: tab)
                    },
                    activityResources: .init(
                        initialDocumentPreparation:
                            initialDocumentPreparation,
                        deferredTabRegistration:
                            activity.deferredTabRegistration,
                        nativeMessagingWakes: wakes,
                        publicationReconciler:
                            activity.publicationReconciler,
                        auxiliaryWindows: browser.auxiliaryWindows,
                        nativeMessagingRelay: relay
                    ),
                    admission: admission
                )
            }
            return shutdown.shutDown(
                reason: reason,
                browserTabs: [],
                liveWebViews: { _ in [] },
                activityResources: .init(
                    initialDocumentPreparation: initialDocumentPreparation,
                    deferredTabRegistration: nil,
                    nativeMessagingWakes: wakes,
                    publicationReconciler: nil,
                    auxiliaryWindows: nil,
                    nativeMessagingRelay: relay
                ),
                admission: admission
            )
        }

        func executeRebuildPlan(
            _ plan: ExtensionRuntimeTabRebuildPlan,
            using shutdown: ExtensionRuntimeShutdown,
            reason: String
        ) -> [ExtensionRuntimeTabRebuildPlan.Execution] {
            let executions: [ExtensionRuntimeTabRebuildPlan.Execution]
            if let browser = attachedEnvironment()?.browser {
                executions = shutdown.executeRebuildPlan(
                    plan,
                    reason: reason,
                    browserAvailable: { browser.availability.isAvailable },
                    canonicalTab: { [tabs = browser.tabs] in
                        tabs.extensionTab(for: $0)
                    },
                    rebuildLiveWebViews: {
                        [webViews = browser.webViews] tab in
                        webViews.rebuildExtensionLiveWebViews(
                            for: tab,
                            reason: reason
                        )
                    }
                )
            } else {
                executions = shutdown.executeRebuildPlan(
                    plan,
                    reason: reason,
                    browserAvailable: { false },
                    canonicalTab: { _ in nil },
                    rebuildLiveWebViews: { _ in .failed }
                )
            }
            retireAttachment()
            return executions
        }
    }
}

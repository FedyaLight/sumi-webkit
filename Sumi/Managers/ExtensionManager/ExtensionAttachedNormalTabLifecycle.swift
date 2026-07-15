import AppKit
import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
extension ExtensionBrowserAttachmentAuthority {
    /// Attached normal-tab lifecycle commands. Every detached call is a
    /// fail-closed no-op; no underlying role can be retrieved.
    @MainActor
    final class NormalTabLifecycle {
        struct Environment {
            let liveWebViewPreparation: ExtensionLiveWebViewRuntimePreparation
            let tabRegistration: ExtensionNormalTabRegistration
            let tabRebind: ExtensionTabLifecycleRebindTransaction
            let tabProperties: ExtensionTabPropertyPublisher
            let deferredTabRegistration: ExtensionDeferredTabRegistration
        }

        private let attachedEnvironment: @MainActor () -> Environment?

        init(attachment: ExtensionBrowserAttachmentAuthority) {
            attachedEnvironment = { [weak attachment] in
                attachment?.normalTabLifecycleEnvironment()
            }
        }

        func prepareWebView(
            _ webView: WKWebView,
            currentURL: URL?,
            reason: String
        ) {
            attachedEnvironment()?.liveWebViewPreparation
                .prepareWebViewForExtensionRuntime(
                    webView,
                    currentURL: currentURL,
                    reason: reason
                )
        }

        func register(_ tab: Tab, reason: String) {
            attachedEnvironment()?.tabRegistration.register(
                tab,
                reason: reason
            )
        }

        func markEligibleAfterCommittedNavigation(
            _ tab: Tab,
            reason: String
        ) {
            attachedEnvironment()?.tabRegistration
                .markEligibleAfterCommittedNavigation(
                    tab,
                    reason: reason
                )
        }

        func reconcileOnUserGestureIfNeeded(_ tab: Tab, reason: String) {
            attachedEnvironment()?.tabRebind.reconcileOnUserGestureIfNeeded(
                    tab,
                    reason: reason
                )
        }

        func prepareBeforeCommittedMainFrameNavigation(
            _ tab: Tab,
            destinationURL: URL,
            reason: String
        ) {
            attachedEnvironment()?.tabRebind
                .prepareBeforeCommittedMainFrameNavigation(
                    tab,
                    destinationURL: destinationURL,
                    reason: reason
                )
        }

        func publishProperties(
            for tab: Tab,
            requested properties: WKWebExtension.TabChangedProperties
        ) {
            attachedEnvironment()?.tabProperties.publishChange(
                    for: tab,
                    requested: properties
                )
        }

        func scheduleDeferredRegistration(
            _ tab: Tab,
            profileID: UUID,
            extensionLoadRevision: ExtensionLoadRevision,
            reason: String
        ) -> Task<Void, Never> {
            attachedEnvironment()?.deferredTabRegistration
                .scheduleDeferredTabNotificationAfterContextLoad(
                    tab,
                    profileId: profileID,
                    extensionLoadRevision: extensionLoadRevision,
                    reason: reason
                ) ?? Task { @MainActor in }
        }

        func deferredRegistrationTask(
            for tabID: UUID
        ) -> Task<Void, Never>? {
            attachedEnvironment()?.deferredTabRegistration.task(for: tabID)
        }

        #if DEBUG
            func runtimeTasksForDrain() -> [Task<Void, Never>] {
                attachedEnvironment()?.deferredTabRegistration
                    .runtimeTasksForDrain() ?? []
            }
        #endif
    }
}

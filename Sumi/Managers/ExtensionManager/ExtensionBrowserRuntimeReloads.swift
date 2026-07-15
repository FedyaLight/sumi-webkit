import AppKit
import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
extension ExtensionBrowserAttachmentAuthority {
    /// Reload, handoff settlement, and profile reconciliation only.
    @MainActor
    final class Reloads {
        struct PublicationEnvironment {
            let reload: ExtensionRuntimeReloadTransaction
            let reconciler: ExtensionRuntimePublicationReconciler
            let tabActivation: ExtensionNormalTabActivationTransaction
            let auxiliaryWindows: BrowserExtensionAuxiliaryWindowAdapter
        }

        struct Environment {
            let publications: PublicationEnvironment
            let controllerReconciler: ExtensionProfileWebViewRuntimeReconciler
        }

        private let attachedEnvironment: @MainActor () -> Environment?
        private let runtimeLoadStatus: ExtensionRuntimeLoadStatusAuthority
        private let browserEvents: BrowserEvents

        init(
            attachment: ExtensionBrowserAttachmentAuthority,
            runtimeLoadStatus: ExtensionRuntimeLoadStatusAuthority,
            browserEvents: BrowserEvents
        ) {
            attachedEnvironment = { [weak attachment] in
                attachment?.reloadEnvironment()
            }
            self.runtimeLoadStatus = runtimeLoadStatus
            self.browserEvents = browserEvents
        }

        func reloadLoadedRuntime(
            reason: String,
            profileID: UUID? = nil
        ) {
            reload(
                reason: reason,
                publicationStage: .loadedRuntime,
                profileID: profileID
            )
        }

        func finalizeRuntimeLoad(
            reason: String,
            profileID: UUID? = nil
        ) {
            reload(
                reason: reason,
                publicationStage: .loadFinalization,
                profileID: profileID
            )
        }

        private func reload(
            reason: String,
            publicationStage: ExtensionRuntimePublicationStage,
            profileID: UUID?
        ) {
            guard let publications = attachedEnvironment()?.publications else {
                return
            }
            guard publicationStage.admits(runtimeLoadStatus) else { return }
            guard let commit = publications.reconciler.reload(
                ExtensionRuntimeReloadTransaction.Request(
                    reason: reason,
                    publicationStage: publicationStage,
                    requestedProfileID: profileID
                ),
                auxiliaryControl: publications.auxiliaryWindows
            ) else { return }
            settle(commit, publications: publications)
        }

        func settle(_ commit: ExtensionRuntimeReloadTransaction.Commit) {
            guard let publications = attachedEnvironment()?.publications else {
                return
            }
            settle(commit, publications: publications)
        }

        func reconcile(profileID: UUID, reason: String) {
            attachedEnvironment()?.controllerReconciler.reconcile(
                profileID: profileID,
                reason: reason
            )
        }

        private func settle(
            _ commit: ExtensionRuntimeReloadTransaction.Commit,
            publications: PublicationEnvironment
        ) {
            guard let activeWindow = commit.activeWindow,
                  commit.activeTab != nil
            else { return }
            _ = browserEvents.focus(activeWindow)
            guard let target = publications.reload.activationTarget(after: commit)
            else { return }
            publications.tabActivation.activate(target.tab, previous: nil)
        }
    }
}

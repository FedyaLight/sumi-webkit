import AppKit
import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
extension ExtensionBrowserAttachmentAuthority {
    /// Browser window/tab/auxiliary event publication only.
    @MainActor
    final class BrowserEvents {
        struct PublicationEnvironment {
            let gate: ExtensionRuntimePublicationGate
            let normalWindows: ExtensionNormalWindowLifecycle
            let auxiliaryWindows: ExtensionAuxiliaryWindowLifecycle
            let tabActivation: ExtensionNormalTabActivationTransaction
            let tabClosure: ExtensionNormalTabCloseTransaction
            let reconciler: ExtensionRuntimePublicationReconciler
        }

        struct BrowserEnvironment {
            let auxiliaryWindows: BrowserExtensionAuxiliaryWindowAdapter
            let windows: BrowserExtensionWindowQueryAdapter
        }

        struct Environment {
            let publications: PublicationEnvironment
            let browser: BrowserEnvironment
        }

        private let attachedEnvironment: @MainActor () -> Environment?
        private let runtimeLoadStatus: ExtensionRuntimeLoadStatusAuthority
        private let profileRuntime: ExtensionProfileRuntime
        private let extensionLoadRevisions: ExtensionLoadRevisionAuthority
        private let diagnostics: ExtensionRuntimeDiagnostics

        init(
            attachment: ExtensionBrowserAttachmentAuthority,
            runtimeLoadStatus: ExtensionRuntimeLoadStatusAuthority,
            profileRuntime: ExtensionProfileRuntime,
            extensionLoadRevisions: ExtensionLoadRevisionAuthority,
            diagnostics: ExtensionRuntimeDiagnostics
        ) {
            attachedEnvironment = { [weak attachment] in
                attachment?.browserEventEnvironment()
            }
            self.runtimeLoadStatus = runtimeLoadStatus
            self.profileRuntime = profileRuntime
            self.extensionLoadRevisions = extensionLoadRevisions
            self.diagnostics = diagnostics
        }

        func publishWindow(
            _ window: BrowserWindowState
        ) -> BrowserWindowExtensionPublicationOutcome {
            guard runtimeLoadStatus.extensionsLoaded else {
                return .notParticipating
            }
            guard let environment = attachedEnvironment() else {
                return .notParticipating
            }
            let publications = environment.publications
            guard publications.gate.admitStructuralBrowserEvent(),
                  let receipt = publications.normalWindows
                        .publication(for: window)
            else { return .suppressed }
            return .published(receipt)
        }

        func closeWindow(_ window: BrowserWindowState) {
            guard let publications = attachedEnvironment()?.publications,
                  publications.gate.admitStructuralBrowserEvent()
            else { return }
            publications.normalWindows.closed(window)
        }

        func activateTab(_ tab: Tab, previous: Tab?) {
            guard let publications = attachedEnvironment()?.publications,
                  publications.gate.acceptsBrowserEvents
            else { return }
            publications.tabActivation.activate(tab, previous: previous)
        }

        func closeTab(_ tab: Tab) {
            guard let publications = attachedEnvironment()?.publications else {
                return
            }
            switch publications.gate.exactTabCloseDisposition() {
            case .perform:
                publications.tabClosure.close(tab)
            case .deferUntilReloadHandoff:
                _ = publications.reconciler.deferTabClose(tab)
            case .reject:
                break
            }
        }

        @discardableResult
        func openAuxiliaryWindow(_ session: AuxiliaryWindowSession) -> Bool {
            guard let environment = attachedEnvironment(),
                  environment.publications.gate
                    .admitAuxiliaryBrowserEvent()
            else { return false }
            return environment.publications.auxiliaryWindows.opened(
                session,
                control: environment.browser.auxiliaryWindows
            )
        }

        func focusAuxiliaryWindow(_ session: AuxiliaryWindowSession) {
            guard let environment = attachedEnvironment(),
                  environment.publications.gate
                    .admitAuxiliaryBrowserEvent()
            else { return }
            environment.publications.auxiliaryWindows.focused(
                session,
                control: environment.browser.auxiliaryWindows
            )
        }

        func closeAuxiliaryWindow(_ session: AuxiliaryWindowSession) {
            guard let environment = attachedEnvironment(),
                  environment.publications.gate
                    .admitAuxiliaryBrowserEvent()
            else { return }
            environment.publications.auxiliaryWindows.closed(
                session,
                windowQuery: environment.browser.windows
            )
        }

        @discardableResult
        func focus(_ window: BrowserWindowState) -> Bool {
            guard let environment = attachedEnvironment(),
                  environment.publications.gate.acceptsBrowserEvents
            else { return false }
            let browser = environment.browser
                if let keyWindow = NSApp.keyWindow,
                   let session = browser.auxiliaryWindows
                    .auxiliaryWindowSession(for: keyWindow),
                   let receipt = browser.auxiliaryWindows
                    .auxiliaryWindowSessionReceipt(for: session) {
                    _ = browser.auxiliaryWindows
                        .focusAuxiliaryWindowSession(receipt)
                    return true
                }
            environment.publications.normalWindows.focused(window)
            return true
        }

        func publishExistingWindows() {
            guard let environment = attachedEnvironment(),
                  environment.publications.gate.acceptsBrowserEvents
            else { return }
            let windows = environment.browser.windows.allExtensionWindowStates
            diagnostics.trace(
                "registerExistingWindowState start generation=\(extensionLoadRevisions.issue().generation) windows=\(windows.count) controller=\(ExtensionRuntimeDiagnostics.objectDescription(profileRuntime.controllerForCurrentProfile()))"
            )
            for window in windows {
                _ = environment.publications.normalWindows.opened(window)
            }
            if let activeWindow = environment.browser.windows
                .activeExtensionWindowState {
                _ = focus(activeWindow)
            }
            diagnostics.trace(
                "registerExistingWindowState complete generation=\(extensionLoadRevisions.issue().generation) windows=\(windows.count)"
            )
        }
    }
}

import AppKit
import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
extension ExtensionBrowserAttachmentAuthority {
    /// Popup and action-invocation browser reads only; retained by action/UI.
    @MainActor
    final class ActionBrowserProjection:
        ExtensionActionPopupBrowserProjection,
        ExtensionActionInvocationBrowserProjection {
        struct BrowserEnvironment {
            let windows: BrowserExtensionWindowQueryAdapter
            let presentation: BrowserExtensionWindowPresentationAdapter
            let tabs: BrowserExtensionTabQueryAdapter
        }

        struct ControllerEnvironment {
            let profiles: ExtensionTabProfileResolution
            let webViews: ExtensionExactTabWebViewQuery
        }

        struct NormalTabEnvironment {
            let publishedTabs: ExtensionPublishedNormalTabQuery
            let registration: ExtensionNormalTabRegistration
        }

        struct Environment {
            let browser: BrowserEnvironment
            let controller: ControllerEnvironment
            let normalTabs: NormalTabEnvironment
            let adapters: ExtensionAdapterCatalog
            let profileQuery: ExtensionBrowserProfileQuery
        }

        private let attachedEnvironment: @MainActor () -> Environment?
        private let profileRuntime: ExtensionProfileRuntime

        init(
            attachment: ExtensionBrowserAttachmentAuthority,
            profileRuntime: ExtensionProfileRuntime
        ) {
            attachedEnvironment = { [weak attachment] in
                attachment?.actionBrowserEnvironment()
            }
            self.profileRuntime = profileRuntime
        }

        func action(
            for context: WKWebExtensionContext,
            preferredTab: Tab?
        ) -> WKWebExtension.Action? {
            guard let environment = attachedEnvironment() else {
                return context.action(for: nil)
            }
                let tab = preferredTab
                    ?? environment.browser.windows
                        .currentExtensionTabForActiveWindow()
            return context.action(
                for: tab.flatMap {
                    environment.adapters.stableAdapter(for: $0)
                }
            )
        }

        func popupWindowState(id: UUID) -> BrowserWindowState? {
            attachedEnvironment()?.browser.windows.extensionWindowState(for: id)
        }

        func popupActiveWindow() -> BrowserWindowState? {
            attachedEnvironment()?.browser.windows.activeExtensionWindowState
        }

        func popupWindow(containing tab: Tab) -> BrowserWindowState? {
            attachedEnvironment()?.browser.windows.extensionWindowState(
                containing: tab
            )
        }

        func popupAppKitWindow(for window: BrowserWindowState) -> NSWindow? {
            attachedEnvironment()?.browser.windows.appKitWindow(for: window)
        }

        func popupTab(id: UUID, in window: BrowserWindowState) -> Tab? {
            attachedEnvironment()?.browser.windows.extensionTab(
                withID: id,
                in: window
            )
        }

        func popupCurrentTab(in window: BrowserWindowState) -> Tab? {
            attachedEnvironment()?.browser.windows.currentExtensionTab(in: window)
        }

        func popupProfile(id: UUID) -> Profile? {
            attachedEnvironment()?.profileQuery.anyProfile(id)
                ?? profileRuntime.rememberedProfile(for: id)
        }

        func popupProfileID(for tab: Tab) -> UUID? {
            attachedEnvironment()?.controller.profiles.profileID(for: tab)
                ?? tab.profileId
                ?? tab.resolveProfile()?.id
                ?? profileRuntime.currentProfileId
        }

        func popupWindow(
            _ window: BrowserWindowState,
            matches profileID: UUID
        ) -> Bool {
            let resolved = window.isIncognito
                ? window.ephemeralProfile?.id
                : window.currentProfileId ?? profileRuntime.currentProfileId
            return resolved == profileID
        }

        func popupLiveWebView(for tab: Tab) -> WKWebView? {
            attachedEnvironment()?.controller.webViews.liveWebView(for: tab)
        }

        func popupFallbackAnchorView(windowID: UUID) -> NSView? {
            attachedEnvironment()?.browser.presentation
                .extensionURLHubFallbackAnchorView(for: windowID)
        }

        func popupAppearance(
            anchorWindow: NSWindow,
            fallback: NSAppearance
        ) -> NSAppearance? {
            attachedEnvironment()?.browser.presentation
                .extensionActionPopupAppearance(
                    forAnchorWindow: anchorWindow,
                    fallback: fallback
                )
        }

        func popupTabIsPublished(_ tab: Tab) -> Bool {
            attachedEnvironment()?.normalTabs.publishedTabs
                .containsPublishedTab(tab) ?? false
        }

        func actionInvocationTabs() -> [Tab] {
            attachedEnvironment()?.browser.tabs.allExtensionTabs ?? []
        }

        func actionInvocationProfileID(for tab: Tab) -> UUID? {
            popupProfileID(for: tab)
        }

        func actionInvocationPrimaryWindowID(for tab: Tab) -> UUID? {
            attachedEnvironment()?.browser.windows
                .preferredExtensionWindowState(containing: tab)?.id
        }

        func actionInvocationActiveWindowID() -> UUID? {
            attachedEnvironment()?.browser.windows.activeExtensionWindowState?.id
        }

        func actionInvocationStableAdapter(for tab: Tab) -> ExtensionTabAdapter? {
            attachedEnvironment()?.adapters.stableAdapter(for: tab)
        }

        func registerActionInvocationTab(_ tab: Tab, reason: String) {
            attachedEnvironment()?.normalTabs.registration.register(
                tab,
                reason: reason
            )
        }
    }
}

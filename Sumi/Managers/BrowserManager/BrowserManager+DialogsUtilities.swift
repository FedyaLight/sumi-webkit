//
//  BrowserManager+DialogsUtilities.swift
//  Sumi
//
//

import AppKit
import WebKit

@MainActor
extension BrowserManager {
    // MARK: - Native Modal Presentation

    func requestCollapsedSidebarOverlayDismissal() {
        nativeDialogPresentationOwner.requestCollapsedSidebarOverlayDismissal()
    }

    func showQuitDialog() {
        nativeDialogPresentationOwner.showQuitDialog()
    }

    func presentBrowsingDataSheet(windowState: BrowserWindowState? = nil) {
        nativeDialogPresentationOwner.presentBrowsingDataSheet(windowState: windowState)
    }

    @discardableResult
    func presentBasicAuthSheet(
        _ session: BasicAuthSheetSession,
        in windowState: BrowserWindowState?
    ) -> Bool {
        nativeDialogPresentationOwner.presentBasicAuthSheet(session, in: windowState)
    }

    func presentNoticeSheet(
        _ notice: BrowserNoticeSheetModel,
        source: SidebarTransientPresentationSource? = nil
    ) {
        nativeDialogPresentationOwner.presentNoticeSheet(notice, source: source)
    }

    func dismissNativeModalPresentation() {
        nativeDialogPresentationOwner.dismissNativeModalPresentation()
    }

    func nativeModalPresentationBindingDismissed(for windowID: UUID) {
        nativeDialogPresentationOwner.nativeModalPresentationBindingDismissed(for: windowID)
    }

    func isNativeModalPresented(in windowID: UUID?) -> Bool {
        nativeDialogPresentationOwner.isNativeModalPresented(in: windowID)
    }

    func isNativeModalPresented(in window: NSWindow?) -> Bool {
        nativeDialogPresentationOwner.isNativeModalPresented(in: window)
    }

    func presentSharingServicePicker(
        _ items: [Any],
        source: SidebarTransientPresentationSource
    ) {
        nativeDialogPresentationOwner.presentSharingServicePicker(items, source: source)
    }

    func cleanupAllTabs() {
        shutdownCleanupOwner.cleanupAllTabs()
    }

    // MARK: - Window-Aware Tab Operations for Commands

    func currentTabForActiveWindow() -> Tab? {
        activePageRoutingOwner.currentTabForActiveWindow()
    }

    func activePageTab(for windowState: BrowserWindowState) -> Tab? {
        activePageRoutingOwner.activePageTab(for: windowState)
    }

    func activePageTabForActiveWindow() -> Tab? {
        activePageRoutingOwner.activePageTabForActiveWindow()
    }

    func activePageWebView(for windowState: BrowserWindowState) -> WKWebView? {
        activePageRoutingOwner.activePageWebView(for: windowState)
    }

    func activePageWebViewForActiveWindow() -> WKWebView? {
        activePageRoutingOwner.activePageWebViewForActiveWindow()
    }

    func activePageURL(for windowState: BrowserWindowState) -> URL? {
        activePageRoutingOwner.activePageURL(for: windowState)
    }

    func activePageURLForActiveWindow() -> URL? {
        activePageRoutingOwner.activePageURLForActiveWindow()
    }

    func refreshCurrentTabInActiveWindow() {
        activePageRoutingOwner.refreshCurrentTabInActiveWindow()
    }

    func toggleMuteCurrentTabInActiveWindow() {
        activePageRoutingOwner.toggleMuteCurrentTabInActiveWindow()
    }

    func currentTabIsMuted() -> Bool {
        activePageRoutingOwner.currentTabIsMuted()
    }

    func currentTabHasAudioContent() -> Bool {
        activePageRoutingOwner.currentTabHasAudioContent()
    }

    // MARK: - URL Utilities

    func copyCurrentURL() {
        activePageRoutingOwner.copyCurrentURL()
    }

    // MARK: - Web Inspector

    func openWebInspector() {
        activePageRoutingOwner.openWebInspector()
    }

    func openWebInspector(for tab: Tab, in windowState: BrowserWindowState) {
        activePageRoutingOwner.openWebInspector(for: tab, in: windowState)
    }

    // MARK: - Profile Switch Toast

    func showProfileSwitchToast(to: Profile, in windowState: BrowserWindowState?) {
        guard let targetWindow = windowState ?? windowRegistry?.activeWindow else { return }
        presentToast(.init(kind: .profileSwitch(profileName: to.name)), in: targetWindow)
    }

    func presentToast(_ toast: BrowserToast, in windowState: BrowserWindowState? = nil) {
        guard sumiSettings?.showBrowserToasts != false else { return }
        guard let targetWindow = windowState ?? windowRegistry?.activeWindow else { return }
        targetWindow.presentToast(toast)
    }

    // MARK: - External URL Routing

    func presentExternalURL(_ url: URL) {
        activePageRoutingOwner.presentExternalURL(url)
    }

    @discardableResult
    func openDroppedURL(
        _ url: URL,
        in windowState: BrowserWindowState,
        at slot: DropZoneSlot
    ) -> Bool {
        activePageRoutingOwner.openDroppedURL(url, in: windowState, at: slot)
    }
}

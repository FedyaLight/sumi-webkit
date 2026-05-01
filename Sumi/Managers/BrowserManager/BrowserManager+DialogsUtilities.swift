//
//  BrowserManager+DialogsUtilities.swift
//  Sumi
//
//  Created by OpenAI Codex on 06/04/2026.
//

import AppKit
import SwiftUI

private final class SidebarSharingServicePickerRetainer {
    static let shared = SidebarSharingServicePickerRetainer()

    private var bridges: [ObjectIdentifier: SidebarSharingServicePickerBridge] = [:]

    func retain(_ bridge: SidebarSharingServicePickerBridge) {
        bridges[ObjectIdentifier(bridge)] = bridge
    }

    func release(_ bridge: SidebarSharingServicePickerBridge) {
        bridges.removeValue(forKey: ObjectIdentifier(bridge))
    }
}

@MainActor
private final class SidebarSharingServicePickerBridge: NSObject, @preconcurrency NSSharingServicePickerDelegate {
    private let token: SidebarTransientSessionToken
    private weak var coordinator: SidebarTransientSessionCoordinator?
    private var hasFinished = false

    init(
        token: SidebarTransientSessionToken,
        coordinator: SidebarTransientSessionCoordinator
    ) {
        self.token = token
        self.coordinator = coordinator
        super.init()
        SidebarSharingServicePickerRetainer.shared.retain(self)
    }

    func sharingServicePicker(
        _ sharingServicePicker: NSSharingServicePicker,
        didChoose service: NSSharingService?
    ) {
        finish()
    }

    func scheduleFallbackFinish() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.finish()
        }
    }

    private func finish() {
        guard !hasFinished else { return }
        hasFinished = true
        coordinator?.finishSession(
            token,
            reason: "SidebarSharingServicePickerBridge.finish"
        )
        SidebarSharingServicePickerRetainer.shared.release(self)
    }
}

@MainActor
extension BrowserManager {
    private func dialogPresentationWindow(
        for source: SidebarTransientPresentationSource? = nil
    ) -> NSWindow? {
        source?.window?.parent
            ?? source?.window
            ?? windowRegistry?.activeWindow?.window
            ?? NSApp.keyWindow
            ?? NSApp.mainWindow
    }

    // MARK: - Dialog Methods

    func showQuitDialog() {
        NSApplication.shared.terminate(nil)
    }

    func showDialog<Content: View>(_ dialog: Content) {
        dialogManager.showDialog(dialog, in: dialogPresentationWindow())
    }

    func showDialog<Content: View>(
        _ dialog: Content,
        source: SidebarTransientPresentationSource
    ) {
        dialogManager.showDialog(
            dialog,
            in: dialogPresentationWindow(for: source),
            source: source
        )
    }

    func closeDialog() {
        dialogManager.closeDialog()
    }

    func presentSharingServicePicker(
        _ items: [Any],
        source: SidebarTransientPresentationSource
    ) {
        guard let contentView = source.window?.contentView ?? dialogPresentationWindow(for: source)?.contentView else {
            return
        }

        let picker = NSSharingServicePicker(items: items)
        let bridge = source.coordinator.flatMap {
            SidebarSharingServicePickerBridge(
                token: $0.beginSession(
                    kind: .sharingPicker,
                    source: source,
                    path: "BrowserManager.presentSharingServicePicker"
                ),
                coordinator: $0
            )
        }
        picker.delegate = bridge

        let anchor = NSRect(
            x: contentView.bounds.midX,
            y: contentView.bounds.midY,
            width: 1,
            height: 1
        )
        picker.show(relativeTo: anchor, of: contentView, preferredEdge: .minY)
        bridge?.scheduleFallbackFinish()
    }

    func showExtensionInstallDialog() {
        extensionsModule.showExtensionInstallDialog()
    }

    func cleanupAllTabs() {
        RuntimeDiagnostics.emit("🔄 [BrowserManager] Cleaning up all tabs")
        extensionsModule.cancelNativeMessagingSessionsIfLoaded(
            reason: "BrowserManager.cleanupAllTabs"
        )
        let allTabs = tabManager.pinnedTabs + tabManager.tabs

        for tab in allTabs {
            RuntimeDiagnostics.emit("🔄 [BrowserManager] Cleaning up tab: \(tab.name)")
            tab.closeTab()
        }
    }

    // MARK: - Window-Aware Tab Operations for Commands

    func currentTabForActiveWindow() -> Tab? {
        if let activeWindow = windowRegistry?.activeWindow {
            return currentTab(for: activeWindow)
        }
        return tabManager.currentTab
    }

    func refreshCurrentTabInActiveWindow() {
        currentTabForActiveWindow()?.refresh()
    }

    func toggleMuteCurrentTabInActiveWindow() {
        currentTabForActiveWindow()?.toggleMute()
    }

    func currentTabIsMuted() -> Bool {
        currentTabForActiveWindow()?.audioState.isMuted ?? false
    }

    func currentTabHasAudioContent() -> Bool {
        currentTabForActiveWindow()?.audioState.isPlayingAudio ?? false
    }

    // MARK: - URL Utilities

    func copyCurrentURL() {
        if let url = currentTabForActiveWindow()?.url.absoluteString {
            RuntimeDiagnostics.emit("Attempting to copy URL: \(url)")

            DispatchQueue.main.async {
                NSPasteboard.general.clearContents()
                let success = NSPasteboard.general.setString(url, forType: .string)
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .drawCompleted)
                RuntimeDiagnostics.emit("Clipboard operation success: \(success)")
            }

            if let windowState = windowRegistry?.activeWindow {
                windowState.isShowingCopyURLToast = true

                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    windowState.isShowingCopyURLToast = false
                }
            }
        } else {
            RuntimeDiagnostics.emit("No URL found to copy")
        }
    }

    // MARK: - Web Inspector

    func openWebInspector() {
        guard let currentTab = currentTabForActiveWindow() else {
            RuntimeDiagnostics.emit("No current tab to inspect")
            return
        }

        if #available(macOS 13.3, *) {
            guard let webView = currentTab.ensureWebView() else {
                RuntimeDiagnostics.emit("No web view available to inspect")
                return
            }

            webView.isInspectable = true

            showWebInspectorAlert()
        } else {
            RuntimeDiagnostics.emit("Web inspector requires macOS 13.3 or later")
        }
    }

    // MARK: - Profile Switch Toast

    func showProfileSwitchToast(to: Profile, in windowState: BrowserWindowState?) {
        guard let targetWindow = windowState ?? windowRegistry?.activeWindow else { return }
        let toast = ProfileSwitchToast(toProfile: to)
        let windowId = targetWindow.id
        targetWindow.profileSwitchToast = toast
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            targetWindow.isShowingProfileSwitchToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.hideProfileSwitchToast(forWindowId: windowId)
        }
    }

    func hideProfileSwitchToast(for windowState: BrowserWindowState? = nil) {
        guard let window = windowState ?? windowRegistry?.activeWindow else { return }
        hideProfileSwitchToast(forWindowId: window.id)
    }

    // MARK: - External URL Routing

    func presentExternalURL(_ url: URL) {
        guard let windowState = windowRegistry?.activeWindow else { return }
        createNewTab(in: windowState, url: url.absoluteString)
    }

    private func showWebInspectorAlert() {
        let alert = NSAlert()
        alert.messageText = "Open Web Inspector"
        alert.informativeText = "To open the Web Inspector:\n\n1. Right-click on the page and select 'Inspect Element'\n\nOr enable the Develop menu in Safari Settings → Advanced, then use Develop → [Your App]"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func hideProfileSwitchToast(forWindowId windowId: UUID) {
        guard
            let window = windowRegistry?.windows[windowId]
                ?? (windowRegistry?.activeWindow?.id == windowId ? windowRegistry?.activeWindow : nil)
        else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
            window.isShowingProfileSwitchToast = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak window] in
            window?.profileSwitchToast = nil
        }
    }
}

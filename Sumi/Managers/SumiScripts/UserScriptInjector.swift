//
//  UserScriptInjector.swift
//  Sumi
//
//  Handles the actual injection of userscripts into WKWebView
//  via WKUserScript and WKUserContentController.
//
//  Manages injection timing, content-world isolation,
//  and CSP fallback for @inject-into auto scripts.
//

import Foundation
import WebKit

@MainActor
struct UserScriptInjectorRuntime {
    var downloadManager: () -> DownloadManager?
    var notificationPermissionBridge: () -> SumiNotificationPermissionBridge?
    var notificationTabContext: (UUID, WKWebView?) -> SumiWebNotificationTabContext?

    static let inactive = Self(
        downloadManager: { nil },
        notificationPermissionBridge: { nil },
        notificationTabContext: { _, _ in nil }
    )
}

@MainActor
final class UserScriptInjector {
    nonisolated static let userScriptMarker = "/* SUMI_USER_SCRIPT_RUNTIME */"

    @MainActor
    private var activeBridges: [UUID: [UUID: UserScriptGMBridge]] = [:]

    weak var tabHandler: SumiScriptsTabHandler?
    private var runtime = UserScriptInjectorRuntime.inactive

    func attach(runtime: UserScriptInjectorRuntime) {
        self.runtime = runtime
    }

    // MARK: - Public API

    func makeUserScripts(
        scripts: [SumiInstalledUserScript],
        webViewId: UUID,
        profileId: UUID?,
        isEphemeral: Bool
    ) -> [SumiUserScript] {
        activeBridges[webViewId] = [:]

        return scripts.map { script in
            switch script.fileType {
            case .javascript:
                let runtime = runtime
                let notificationContextProvider: @MainActor (WKWebView?) -> SumiWebNotificationTabContext? = { webView in
                    runtime.notificationTabContext(webViewId, webView)
                }
                let adapter = SumiInstalledUserScriptAdapter(
                    script: script,
                    profileId: profileId,
                    isEphemeral: isEphemeral,
                    tabHandler: tabHandler,
                    downloadManager: runtime.downloadManager(),
                    notificationPermissionBridge: runtime.notificationPermissionBridge(),
                    notificationTabContextProvider: notificationContextProvider
                )
                if let bridge = adapter.bridge {
                    activeBridges[webViewId]?[script.id] = bridge
                }
                return adapter
            case .css:
                return SumiInstalledUserStyleAdapter(script: script)
            }
        }
    }

    func cleanupBridges(for webViewId: UUID) {
        activeBridges.removeValue(forKey: webViewId)
    }

    func cleanupBridges(for webViewId: UUID, from controller: WKUserContentController) {
        _ = controller
        cleanupBridges(for: webViewId)
    }

    func executeMenuCommand(script: SumiInstalledUserScript, commandId: String, webView: WKWebView?) {
        guard let webView,
              let bridge = findBridge(for: script)
        else { return }
        bridge.resolveMenuCommand(commandId, webView: webView)
    }

    private func findBridge(for script: SumiInstalledUserScript) -> UserScriptGMBridge? {
        for bridgesByScript in activeBridges.values {
            if let bridge = bridgesByScript[script.id] {
                return bridge
            }
        }
        return nil
    }
}

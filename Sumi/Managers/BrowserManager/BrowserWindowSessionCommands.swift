import Foundation
import SwiftUI

/// Window-session command façade: shell window lifecycle and profile maintenance.
/// Absorbs the former `BrowserWindowShellCommandOwner` and
/// `BrowserProfileMaintenanceOwner` so BrowserManager no longer holds two
/// separate `.live(browserManager:)` Owners for thin session routing.
@MainActor
final class BrowserWindowSessionCommands {
    let windowShellService = BrowserWindowShellService()
    let profileMaintenanceService = SumiProfileMaintenanceService()

    private weak var browserManager: BrowserManager?

    init(browserManager: BrowserManager) {
        self.browserManager = browserManager
    }

    // MARK: - Window shell

    func createNewWindow() {
        windowShellService.createNewWindow(using: makeWindowShellContext())
    }

    func createIncognitoWindow() {
        windowShellService.createIncognitoWindow(using: makeWindowShellContext())
    }

    func closeIncognitoWindow(_ windowState: BrowserWindowState) async {
        await windowShellService.closeIncognitoWindow(
            windowState,
            using: makeWindowShellContext()
        )
    }

    func closeActiveWindow() {
        windowShellService.closeActiveWindow(in: windowRegistry())
    }

    func closeWindow(_ windowState: BrowserWindowState) {
        windowShellService.closeWindow(windowState, in: windowRegistry())
    }

    func toggleFullScreenForActiveWindow() {
        windowShellService.toggleFullScreenForActiveWindow(in: windowRegistry())
    }

    // MARK: - Profile maintenance

    func deleteProfile(_ profile: Profile) {
        guard let context = makeMaintenanceContext() else { return }
        profileMaintenanceService.deleteProfile(profile, using: context)
    }

    // MARK: - Private

    private func windowRegistry() -> WindowRegistry {
        guard let browserManager else {
            preconditionFailure(
                "BrowserManager was released before window session commands resolved the registry."
            )
        }
        return browserManager.shellRuntime.requireWindowRegistry()
    }

    private func makeWindowShellContext() -> BrowserWindowShellService.Context {
        guard let browserManager else {
            preconditionFailure(
                "BrowserManager was released before window session commands resolved their context."
            )
        }
        return BrowserWindowShellService.Context(
            windowRegistry: browserManager.shellRuntime.requireWindowRegistry(),
            webViewCoordinator: browserManager.shellRuntime.requireWebViewCoordinator(),
            permissionLifecycleController: browserManager.permissionRuntime.permissionLifecycleController,
            profileManager: browserManager.profileManager,
            tabManager: browserManager.tabManager,
            makeContentView: browserManager.shellRuntime.requireWindowShellContentViewFactory(),
            showEmptyState: { [weak browserManager] windowState, presentNewTabFloatingBar in
                browserManager?.showEmptyState(
                    in: windowState,
                    presentNewTabFloatingBar: presentNewTabFloatingBar
                )
            }
        )
    }

    private func makeMaintenanceContext() -> SumiProfileMaintenanceService.Context? {
        guard let browserManager else { return nil }
        return SumiProfileMaintenanceService.Context(
            currentProfile: { [weak browserManager] in
                browserManager?.currentProfile
            },
            profileManager: browserManager.profileManager,
            tabManager: browserManager.tabManager,
            browsingDataCleanupService: browserManager.browsingDataCleanupService,
            websiteDataCleanupService: browserManager.dataServices.websiteDataCleanupService,
            faviconService: browserManager.dataServices.faviconService,
            visitedLinkStore: browserManager.dataServices.visitedLinkStore,
            showNotice: { [weak browserManager] notice in
                browserManager?.nativeDialogPresentationOwner.presentNoticeSheet(
                    BrowserNoticeSheetModel(
                        title: notice.title,
                        subtitle: notice.subtitle,
                        message: notice.message
                    ),
                    source: nil
                )
            },
            switchToProfile: { [weak browserManager] profile in
                await browserManager?.switchToProfile(profile)
            }
        )
    }
}

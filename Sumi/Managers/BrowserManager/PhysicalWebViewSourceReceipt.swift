import AppKit
import Foundation
import SumiDomain
import SumiWebRuntime
import WebKit

enum PhysicalWebViewSourceResidence: Equatable {
    case regularSpaceMember
    case windowShortcut(ShortcutPinRole)
    case privateEphemeral
}

/// A synchronous proof that one physical WebView belongs to one exact browser
/// residence and execution partition. Presentation and execution profiles are
/// intentionally separate: a window-local shortcut may execute in profile B
/// while being presented in a Space belonging to profile A.
@MainActor
struct PhysicalWebViewSourceReceipt {
    let webView: FocusableWKWebView
    let trackedWebView: TrackedWebViewOwner
    let tab: Tab
    let window: BrowserWindowState
    let residence: PhysicalWebViewSourceResidence
    let presentationSpace: Space
    let presentationProfile: Profile
    let executionProfile: Profile
    let dataStore: WKWebsiteDataStore
    let appKitWindow: NSWindow?

    var usesPresentationProfileForExecution: Bool {
        executionProfile === presentationProfile
    }

    /// Stable regular members may keep inheriting their Space profile. A
    /// shortcut or an already-overridden regular Tab must propagate an
    /// explicit execution profile even when its ID currently equals the
    /// presentation profile (for example during an in-flight Space switch).
    var descendantProfileID: UUID? {
        if residence == .regularSpaceMember,
           tab.profileId == nil,
           usesPresentationProfileForExecution {
            return nil
        }
        return executionProfile.id
    }
}

/// Resolves physical browser commands without consulting active-window,
/// process-current-Space, or model-only Tab fallbacks.
@MainActor
final class PhysicalWebViewSourceResolver {
    private weak var ownership: WebViewOwnershipQuery?
    private weak var tabs: TabManager?
    private weak var profiles: ProfileManager?
    private let registry: @MainActor () -> WindowRegistry?

    init(
        ownership: WebViewOwnershipQuery,
        tabs: TabManager,
        profiles: ProfileManager,
        registry: @escaping @MainActor () -> WindowRegistry?
    ) {
        self.ownership = ownership
        self.tabs = tabs
        self.profiles = profiles
        self.registry = registry
    }

    func resolve(
        _ webView: FocusableWKWebView
    ) -> PhysicalWebViewSourceReceipt? {
        guard let ownership,
              let tabs,
              let profiles,
              let registry = registry(),
              let tab = webView.owningTab,
              let tracked = ownership.trackedOwner(containing: webView),
              tracked.tabID == tab.id,
              ownership.webView(
                  for: tracked.tabID,
                  in: tracked.windowID
              ) === webView,
              let window = registry.windows[tracked.windowID],
              window.id == tracked.windowID
        else {
            return nil
        }

        if window.isIncognito {
            return resolvePrivate(
                webView,
                tracked: tracked,
                tab: tab,
                window: window,
                registry: registry,
                profiles: profiles
            )
        }
        return resolveRegular(
            webView,
            tracked: tracked,
            tab: tab,
            window: window,
            registry: registry,
            tabs: tabs,
            profiles: profiles
        )
    }

    func isCurrent(_ receipt: PhysicalWebViewSourceReceipt) -> Bool {
        guard let current = resolve(receipt.webView) else { return false }
        return current.trackedWebView == receipt.trackedWebView
            && current.tab === receipt.tab
            && current.window === receipt.window
            && current.residence == receipt.residence
            && current.presentationSpace === receipt.presentationSpace
            && current.presentationProfile === receipt.presentationProfile
            && current.executionProfile === receipt.executionProfile
            && current.dataStore === receipt.dataStore
    }

    private func resolvePrivate(
        _ webView: FocusableWKWebView,
        tracked: TrackedWebViewOwner,
        tab: Tab,
        window: BrowserWindowState,
        registry: WindowRegistry,
        profiles: ProfileManager
    ) -> PhysicalWebViewSourceReceipt? {
        guard let profile = window.ephemeralProfile,
              profiles.hasEphemeralProfileLease(
                  profile,
                  forWindowID: window.id
              ),
              window.currentProfileId == profile.id,
              tab.profileId == profile.id,
              tab.spaceId == nil,
              window.ephemeralTabs.contains(where: { $0 === tab }),
              let spaceID = window.currentSpaceId,
              let space = window.ephemeralSpaces.first(where: {
                  $0.id == spaceID
              }),
              space.profileId == profile.id,
              space.isEphemeral,
              webView.configuration.websiteDataStore === profile.dataStore
        else {
            return nil
        }
        return PhysicalWebViewSourceReceipt(
            webView: webView,
            trackedWebView: tracked,
            tab: tab,
            window: window,
            residence: .privateEphemeral,
            presentationSpace: space,
            presentationProfile: profile,
            executionProfile: profile,
            dataStore: profile.dataStore,
            appKitWindow: registry.appKitWindow(for: window)
        )
    }

    private func resolveRegular(
        _ webView: FocusableWKWebView,
        tracked: TrackedWebViewOwner,
        tab: Tab,
        window: BrowserWindowState,
        registry: WindowRegistry,
        tabs: TabManager,
        profiles: ProfileManager
    ) -> PhysicalWebViewSourceReceipt? {
        guard let context = BrowserWindowSourceContextResolver.resolve(
            tab: tab,
            window: window,
            tabs: tabs
        ),
              let space = tabs.spaceStateOwner.space(with: context.spaceID),
              let presentationProfile = profiles.profiles.first(where: {
                  $0.id == context.profileID
              })
        else {
            return nil
        }

        let residence: PhysicalWebViewSourceResidence
        let executionProfileID: UUID
        switch context.residence {
        case .regularSpaceTab:
            residence = .regularSpaceMember
            executionProfileID = tab.profileId ?? context.profileID
        case .windowShortcut:
            guard let pinID = tab.shortcutPinId,
                  let role = tab.shortcutPinRole,
                  let pin = tabs.shortcutPinCollectionStateOwner
                    .shortcutPin(by: pinID),
                  pin.role == role,
                  let resolvedProfileID = tabs
                    .shortcutPinRuntimeResolutionOwner
                    .resolvedExecutionProfileId(
                        for: pin,
                        currentSpaceId: context.spaceID
                    ),
                  tab.profileId == resolvedProfileID
            else {
                return nil
            }
            residence = .windowShortcut(role)
            executionProfileID = resolvedProfileID
        }

        guard let executionProfile = profiles.profiles.first(where: {
            $0.id == executionProfileID
        }),
              webView.configuration.websiteDataStore
                === executionProfile.dataStore
        else {
            return nil
        }
        return PhysicalWebViewSourceReceipt(
            webView: webView,
            trackedWebView: tracked,
            tab: tab,
            window: window,
            residence: residence,
            presentationSpace: space,
            presentationProfile: presentationProfile,
            executionProfile: executionProfile,
            dataStore: executionProfile.dataStore,
            appKitWindow: registry.appKitWindow(for: window)
        )
    }
}

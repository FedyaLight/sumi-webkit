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
    private let ownership: WebViewOwnershipQuery
    private let sourceContexts: BrowserWindowSourceContextResolver
    private let pins: ShortcutPinCollectionStateOwner
    private let shortcutResolution: ShortcutPinRuntimeResolutionOwner
    private let profiles: ProfileManager
    private let registry: @MainActor () -> WindowRegistry?

    init(
        ownership: WebViewOwnershipQuery,
        sourceContexts: BrowserWindowSourceContextResolver,
        pins: ShortcutPinCollectionStateOwner,
        shortcutResolution: ShortcutPinRuntimeResolutionOwner,
        profiles: ProfileManager,
        registry: @escaping @MainActor () -> WindowRegistry?
    ) {
        self.ownership = ownership
        self.sourceContexts = sourceContexts
        self.pins = pins
        self.shortcutResolution = shortcutResolution
        self.profiles = profiles
        self.registry = registry
    }

    func resolve(
        _ webView: FocusableWKWebView
    ) -> PhysicalWebViewSourceReceipt? {
        guard let registry = registry(),
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
        profiles: ProfileManager
    ) -> PhysicalWebViewSourceReceipt? {
        guard let source = sourceContexts.resolve(
            tab: tab,
            window: window
        ),
              let presentationProfile = profiles.profiles.first(where: {
                  $0.id == source.context.profileID
              })
        else {
            return nil
        }

        let residence: PhysicalWebViewSourceResidence
        let executionProfileID: UUID
        switch source.context.residence {
        case .regularSpaceTab:
            residence = .regularSpaceMember
            executionProfileID = tab.profileId ?? source.context.profileID
        case .windowShortcut:
            guard let pinID = tab.shortcutPinId,
                  let role = tab.shortcutPinRole,
                  let pin = pins.shortcutPin(by: pinID),
                  pin.role == role,
                  let resolvedProfileID = shortcutResolution
                  .resolvedExecutionProfileId(
                      for: pin,
                      currentSpaceId: source.context.spaceID
                  ),
                  tab.profileId == shortcutResolution
                    .desiredLiveTabProfileId(for: pin)
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
            presentationSpace: source.space,
            presentationProfile: presentationProfile,
            executionProfile: executionProfile,
            dataStore: executionProfile.dataStore,
            appKitWindow: registry.appKitWindow(for: window)
        )
    }
}

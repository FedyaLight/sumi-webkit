import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
struct ExtensionRequestedTabOpeningService {
    let recentRequests: ExtensionRecentTabRequestHistory
    let loadResolver: ExtensionRequestedTabLoadResolver
    let targetResolver: ExtensionRequestedTabTargetResolver
    let materializer: ExtensionRequestedTabWebViewMaterializer
    let registrar: ExtensionCreatedTabRuntimeRegistrar
    private let browserContext: @MainActor () -> (any ExtensionTabCreation)?
    private let profileRuntime: ExtensionProfileRuntime
    private let runtime: @MainActor () -> ExtensionManagerRuntime
    private let hasTabAdapter: @MainActor (Tab) -> Bool

    init(
        recentRequests: ExtensionRecentTabRequestHistory,
        loadResolver: ExtensionRequestedTabLoadResolver,
        targetResolver: ExtensionRequestedTabTargetResolver,
        materializer: ExtensionRequestedTabWebViewMaterializer,
        registrar: ExtensionCreatedTabRuntimeRegistrar,
        browserContext: @escaping @MainActor () -> (any ExtensionTabCreation)?,
        profileRuntime: ExtensionProfileRuntime,
        runtime: @escaping @MainActor () -> ExtensionManagerRuntime,
        hasTabAdapter: @escaping @MainActor (Tab) -> Bool
    ) {
        self.recentRequests = recentRequests
        self.loadResolver = loadResolver
        self.targetResolver = targetResolver
        self.materializer = materializer
        self.registrar = registrar
        self.browserContext = browserContext
        self.profileRuntime = profileRuntime
        self.runtime = runtime
        self.hasTabAdapter = hasTabAdapter
    }

    @discardableResult
    func open(
        url: URL?,
        shouldBeActive: Bool,
        shouldBePinned: Bool,
        requestedWindow: (any WKWebExtensionWindow)?,
        controller: WKWebExtensionController,
        extensionContext: WKWebExtensionContext? = nil,
        reason: String
    ) throws -> Tab {
        guard let browserContext = browserContext() else {
            throw ExtensionManagerCallbackError
                .requestedTabBrowserManagerUnavailable.nsError()
        }

        let target = try targetResolver.resolve(
            requestedWindow: requestedWindow,
            extensionContext: extensionContext
        )
        let load = loadResolver.resolve(url, controller: controller)
        let opensTransientInternalTab = shouldOpenTransientInternalTab(
            load: load,
            shouldBeActive: shouldBeActive,
            shouldBePinned: shouldBePinned
        )
        let currentRuntime = runtime()
        let diagnosticProfileId = target.space?.profileId
            ?? target.window.flatMap {
                profileRuntime.resolvedProfileId(
                    for: $0,
                    runtime: currentRuntime
                )
            }
            ?? extensionContext.flatMap { profileRuntime.profileId(for: $0) }
            ?? profileRuntime.profileId(for: controller)
            ?? profileRuntime.currentProfileId

        let newTab: Tab
        if opensTransientInternalTab, let loadURL = load.url {
            newTab = browserContext.createTransientExtensionTab(
                url: loadURL,
                in: target.space,
                webExtensionContextOverride: load.extensionContext
            )
        } else if let loadURL = load.url {
            recentRequests.record(url)
            newTab = browserContext.createExtensionTab(
                url: loadURL,
                in: target.space,
                activate: shouldBeActive,
                webExtensionContextOverride: load.extensionContext
            )
        } else {
            newTab = browserContext.createExtensionTab(
                url: nil,
                in: target.space,
                activate: shouldBeActive,
                webExtensionContextOverride: load.extensionContext
            )
        }

        if shouldBePinned {
            browserContext.pinExtensionTab(
                newTab,
                targetWindow: target.window,
                targetSpace: target.space
            )
        }
        materializer.materializeNormalTabIfNeeded(
            newTab,
            isActive: shouldBeActive,
            targetWindow: target.window
        )
        if shouldBeActive, let targetWindow = target.window {
            browserContext.selectExtensionTab(newTab, in: targetWindow)
        }
        registrar.register(newTab, reason: reason)
        materializer.materializeExtensionOwnedTabIfNeeded(
            newTab,
            isActive: shouldBeActive,
            hasWindowSelection: target.window != nil
        )

        SafariExtensionPermissionLifecycleDiagnostics.logTabBinding(
            SafariExtensionTabBindingSnapshot(
                route: opensTransientInternalTab
                    ? .extensionInternal
                    : .normalBrowserTab,
                profileBucket: SafariExtensionPermissionLifecycleDiagnostics
                    .bucket(
                        profileRuntime.resolvedProfileId(
                            for: newTab,
                            runtime: runtime()
                        )
                            ?? diagnosticProfileId
                    ),
                tabBucket: SafariExtensionPermissionLifecycleDiagnostics
                    .bucket(newTab.id),
                dataStoreMatched: nil,
                controllerMatched: nil,
                tabAdapterCreated: hasTabAdapter(newTab),
                didOpenTabTiming: newTab.extensionPageRuntimeOwner
                    .hasAnyDidOpenTabNotification()
                    ? .beforeNavigation
                    : .deferred,
                firstNavigationHost: SafariExtensionPermissionLifecycleDiagnostics
                    .host(from: load.url),
                firstCommitHost: nil
            )
        )
        return newTab
    }

    private func shouldOpenTransientInternalTab(
        load: ExtensionRequestedTabLoad,
        shouldBeActive: Bool,
        shouldBePinned: Bool
    ) -> Bool {
        guard shouldBeActive == false,
              shouldBePinned == false,
              load.extensionContext != nil,
              let url = load.url
        else {
            return false
        }
        return ExtensionUtils.isExtensionOwnedURL(url)
    }
}

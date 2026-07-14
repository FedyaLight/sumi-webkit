import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
struct ExtensionRequestedTabOpeningService {
    let recentRequests: ExtensionRecentTabRequestHistory
    let loadResolver: ExtensionRequestedTabLoadResolver
    let placement: ExtensionRequestedTabTargetResolver
    let materializer: ExtensionRequestedTabWebViewMaterializer
    let registrar: ExtensionCreatedTabRuntimeRegistrar
    private let browserContext: @MainActor () -> (any ExtensionTabCreation)?
    private let profileRuntime: ExtensionProfileRuntime
    private let runtime: @MainActor () -> ExtensionManagerRuntime
    private let hasTabAdapter: @MainActor (Tab) -> Bool

    init(
        recentRequests: ExtensionRecentTabRequestHistory,
        loadResolver: ExtensionRequestedTabLoadResolver,
        placement: ExtensionRequestedTabTargetResolver,
        materializer: ExtensionRequestedTabWebViewMaterializer,
        registrar: ExtensionCreatedTabRuntimeRegistrar,
        browserContext: @escaping @MainActor () -> (any ExtensionTabCreation)?,
        profileRuntime: ExtensionProfileRuntime,
        runtime: @escaping @MainActor () -> ExtensionManagerRuntime,
        hasTabAdapter: @escaping @MainActor (Tab) -> Bool
    ) {
        self.recentRequests = recentRequests
        self.loadResolver = loadResolver
        self.placement = placement
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

        let target = try placement.resolve(
            requestedWindow: requestedWindow,
            extensionContext: extensionContext
        )
        let load = loadResolver.resolve(url, controller: controller)
        let controllerProfileID = profileRuntime.profileId(for: controller)
        for context in [extensionContext, load.extensionContext].compactMap({
            $0
        }) {
            guard let identity = profileRuntime.exactContextIdentity(
                for: context
            ), identity.profileId == controllerProfileID else {
                throw ExtensionManagerCallbackError
                    .requestedTabUnavailable.nsError()
            }
        }
        let opensTransientInternalTab = shouldOpenTransientInternalTab(
            load: load,
            shouldBeActive: shouldBeActive,
            shouldBePinned: shouldBePinned
        )
        let currentRuntime = runtime()
        let rollbackSelectionID = target.window?.currentTabId
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
            newTab = browserContext.createExtensionTab(
                url: loadURL,
                in: target.space,
                activate: false,
                webExtensionContextOverride: load.extensionContext
            )
        } else {
            newTab = browserContext.createExtensionTab(
                url: nil,
                in: target.space,
                activate: false,
                webExtensionContextOverride: load.extensionContext
            )
        }

        var didCommit = false
        defer {
            if didCommit == false {
                if browserContext.discardExtensionRequestedTab(
                    newTab,
                    restoringSelectionTo: rollbackSelectionID
                ) == false {
                    // The concrete browser adapter admits only the exact
                    // inactive Tab created above. This fallback keeps a
                    // released adapter implementation from leaving a live
                    // model behind.
                    newTab.closeTab()
                }
            }
        }

        if let targetWindow = target.window {
            browserContext.placeExtensionTab(newTab, in: targetWindow)
        }

        let preparedResidence = try placement.publishedResidence(
            for: newTab,
            target: target,
            extensionContext: extensionContext
        )
        guard opensTransientInternalTab || preparedResidence != nil else {
            throw ExtensionManagerCallbackError
                .requestedTabUnavailable.nsError()
        }
        if let preparedResidence {
            browserContext.placeExtensionTab(newTab, in: preparedResidence)
        }
        materializer.materializeNormalTabIfNeeded(
            newTab,
            targetWindow: preparedResidence
        )
        materializer.materializeExtensionOwnedTabIfNeeded(
            newTab,
            isActive: shouldBeActive,
            hasWindowSelection: false
        )
        guard registrar.register(
            newTab,
            runtime: runtime(),
            reason: reason
        ) else {
            throw ExtensionManagerCallbackError
                .requestedTabUnavailable.nsError()
        }

        let committedResidence = try placement.publishedResidence(
            for: newTab,
            target: target,
            extensionContext: extensionContext
        )
        guard opensTransientInternalTab || committedResidence != nil else {
            throw ExtensionManagerCallbackError
                .requestedTabUnavailable.nsError()
        }

        if shouldBeActive {
            guard let committedResidence else {
                throw ExtensionManagerCallbackError
                    .requestedTabUnavailable.nsError()
            }
            browserContext.selectExtensionTab(
                newTab,
                in: committedResidence
            )
        }
        if shouldBePinned {
            // Display active Tabs before regular-to-shortcut conversion.
            guard browserContext.pinExtensionTab(
                newTab,
                targetWindow: committedResidence,
                targetSpace: target.space
            ) else {
                throw ExtensionManagerCallbackError
                    .requestedTabUnavailable.nsError()
            }
        }

        recentRequests.record(url)
        didCommit = true

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

import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
struct ExtensionRequestedTabOpeningService {
    let recentRequests: ExtensionRecentTabRequestHistory
    let loadResolver: ExtensionRequestedTabLoadResolver
    let placement: ExtensionRequestedTabTargetResolver
    let materializer: ExtensionRequestedTabWebViewMaterializer
    let runtimeAdmission: ExtensionRequestedTabRuntimeAdmission
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
        runtimeAdmission = ExtensionRequestedTabRuntimeAdmission(
            registrar: registrar
        )
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
        evidence: ExtensionControllerCallbackEvidence? = nil,
        callbackAdmission: ExtensionControllerCallbackAdmission? = nil,
        reason: String
    ) throws -> Tab {
        let invocation = ExtensionRequestedTabInvocationAuthority(
            profileRuntime: profileRuntime,
            controller: controller,
            sourceContext: extensionContext,
            evidence: evidence,
            callbackAdmission: callbackAdmission
        )
        guard invocation.isCurrent else {
            throw CancellationError()
        }
        guard let browserContext = browserContext() else {
            throw ExtensionManagerCallbackError
                .requestedTabBrowserManagerUnavailable.nsError()
        }

        let load = loadResolver.resolve(url, controller: controller)
        guard load.hasUnresolvedExtensionOwnership == false else {
            throw ExtensionManagerCallbackError.requestedTabUnavailable.nsError()
        }
        let residencePolicy: ExtensionRequestedTabResidencePolicy =
            load.isOrdinaryBrowserRequest
                ? .ordinaryBrowser
                : .extensionPublished
        let target = try placement.resolve(
            requestedWindow: requestedWindow,
            extensionContext: extensionContext,
            residencePolicy: residencePolicy
        )
        try invocation.validateSource(for: load)
        guard invocation.isCurrent else { throw CancellationError() }
        let opensTransientInternalTab = load.shouldOpenTransientInternalTab(
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

        guard invocation.isCurrent else { throw CancellationError() }
        if let targetWindow = target.window {
            browserContext.placeExtensionTab(newTab, in: targetWindow)
        }

        guard invocation.isCurrent else { throw CancellationError() }
        let preparedResidence = try placement.validatedResidence(
            for: newTab,
            target: target,
            extensionContext: extensionContext,
            residencePolicy: residencePolicy
        )
        guard opensTransientInternalTab || preparedResidence != nil else {
            throw ExtensionManagerCallbackError
                .requestedTabUnavailable.nsError()
        }
        if let preparedResidence {
            guard invocation.isCurrent else { throw CancellationError() }
            browserContext.placeExtensionTab(newTab, in: preparedResidence)
        }
        guard invocation.isCurrent else { throw CancellationError() }
        materializer.materializeNormalTabIfNeeded(
            newTab,
            targetWindow: preparedResidence
        )
        materializer.materializeExtensionOwnedTabIfNeeded(
            newTab,
            isActive: shouldBeActive,
            hasWindowSelection: false
        )
        guard invocation.isCurrent else { throw CancellationError() }
        let publicationControllerIsReady = extensionContext.map { context in
            controller.extensionContexts.contains { $0 === context }
        } ?? true
        guard runtimeAdmission.admit(
            newTab,
            load: load,
            publicationControllerIsReady: publicationControllerIsReady,
            runtime: runtime(),
            reason: reason
        ) else {
            throw ExtensionManagerCallbackError
                .requestedTabUnavailable.nsError()
        }
        guard invocation.isCurrent else { throw CancellationError() }

        let committedResidence = try placement.validatedResidence(
            for: newTab,
            target: target,
            extensionContext: extensionContext,
            residencePolicy: residencePolicy
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
            guard invocation.isCurrent else { throw CancellationError() }
            browserContext.selectExtensionTab(
                newTab,
                in: committedResidence
            )
        }
        if shouldBePinned {
            // Display active Tabs before regular-to-shortcut conversion.
            guard invocation.isCurrent else { throw CancellationError() }
            guard browserContext.pinExtensionTab(
                newTab,
                targetWindow: committedResidence,
                targetSpace: target.space
            ) else {
                throw ExtensionManagerCallbackError
                    .requestedTabUnavailable.nsError()
            }
        }

        guard invocation.isCurrent else { throw CancellationError() }
        recentRequests.record(url)
        didCommit = true

        ExtensionRequestedTabBindingDiagnostics.record(
            tab: newTab,
            load: load,
            opensTransientInternalTab: opensTransientInternalTab,
            diagnosticProfileID: diagnosticProfileId,
            profileRuntime: profileRuntime,
            runtime: runtime(),
            hasTabAdapter: hasTabAdapter(newTab)
        )
        return newTab
    }

}

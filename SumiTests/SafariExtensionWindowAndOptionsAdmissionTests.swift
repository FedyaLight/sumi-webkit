import AppKit
@testable import Sumi
import WebKit
import XCTest

@available(macOS 15.5, *)
@MainActor
extension SafariExtensionWebViewControllerWiringTests {
    func testUnresolvedExtensionWindowFailsBeforePreparationOrMutation()
        async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Unresolved requested window")
        let browserConfiguration = BrowserConfiguration()
        let manager = makeManager(
            context: container.mainContext,
            profile: profile,
            browserConfiguration: browserConfiguration
        ).manager
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(
                userDefaults: UserDefaults(suiteName: UUID().uuidString)!
            )
        )
        registry.enable(.extensions)
        let extensionsModule = SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            browserConfiguration: browserConfiguration,
            initialProfileProvider: { profile },
            managerFactory: { _, _, _, _ in manager }
        )
        let browserManager = makeBrowserManager(
            moduleRegistry: registry,
            extensionsModule: extensionsModule,
            profile: profile
        )
        let windowRegistry = WindowRegistry()
        browserManager.windowRegistry = windowRegistry
        _ = browserManager.tabManager.spaceServices.catalog.createSpace(
            name: "Work",
            profileId: profile.id
        )
        manager.attach(browserManager: browserManager)
        let controller = manager.ensureExtensionController(for: profile.id)

        let prepared = UnresolvedRequestedWindowPreparedStub()
        let creator = UnresolvedRequestedWindowCreatorStub(prepared: prepared)
        manager.extensionRequestedWindowCreation = creator
        let originalWindowIDs = Set(windowRegistry.windows.keys)
        let originalTabIDs = Set(
            browserManager.tabManager.tabCollectionMembershipOwner
                .allTabs().map(\.id)
        )
        let completed = expectation(
            description: "unresolved extension window rejected"
        )
        var completionWindow: (any WKWebExtensionWindow)?
        var completionError: (any Error)?

        manager.openExtensionWindowUsingTabURLs(
            [
                URL(
                    string: "safari-web-extension://unresolved-owner/page.html"
                )!,
            ],
            controller: controller,
            completionHandler: { window, error in
                completionWindow = window
                completionError = error
                completed.fulfill()
            }
        )

        await fulfillment(of: [completed], timeout: 2.0)
        XCTAssertNil(completionWindow)
        XCTAssertEqual(
            (completionError as NSError?)?.code,
            ExtensionManagerCallbackError.newWindowUnavailable.code
        )
        XCTAssertTrue(creator.preparedSeeds.isEmpty)
        XCTAssertEqual(prepared.presentCallCount, 0)
        XCTAssertEqual(prepared.acceptCallCount, 0)
        XCTAssertEqual(prepared.cancelCallCount, 0)
        XCTAssertEqual(Set(windowRegistry.windows.keys), originalWindowIDs)
        XCTAssertEqual(
            Set(
                browserManager.tabManager.tabCollectionMembershipOwner
                    .allTabs().map(\.id)
            ),
            originalTabIDs
        )
    }

    func testExtensionOptionsPageRendersThroughContextConfiguration() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Extension Options Profile")
        let browserConfiguration = BrowserConfiguration()
        let manager = makeManager(
            context: container.mainContext,
            profile: profile,
            browserConfiguration: browserConfiguration
        ).manager
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(
                userDefaults: UserDefaults(suiteName: UUID().uuidString)!
            )
        )
        registry.enable(.extensions)
        let extensionsModule = SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            browserConfiguration: browserConfiguration,
            initialProfileProvider: { profile },
            managerFactory: { _, _, _, _ in manager }
        )
        let browserManager = makeBrowserManager(
            moduleRegistry: registry,
            extensionsModule: extensionsModule,
            profile: profile
        )
        manager.attach(browserManager: browserManager)

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installUnpackedExtension(
            manager: manager,
            scratchDirectory: scratchDirectory,
            name: "ExtensionOptionsRenderedPage",
            optionsPage: "options.html"
        )
        let enabledInstalled = try await manager.installedExtensionLifecycle
            .enable(installed.id)

        let loadedContext = try await manager.ensureExtensionLoaded(
            extensionId: installed.id,
            profileId: profile.id
        )
        let extensionContext = try XCTUnwrap(loadedContext)
        let controller = try XCTUnwrap(
            manager.profileRuntime.controllersByProfile[profile.id]
        )
        let staleEvidence = try XCTUnwrap(
            manager.controllerCallbackAdmission.capture(
                context: extensionContext,
                controller: controller
            )
        )
        let enabledInvocation = try XCTUnwrap(
            ExtensionOptionsWindowCallbackComposition.invocation(
                from: manager,
                evidence: staleEvidence
            )
        )

        manager.installedExtensionCollection.upsert(installed)
        XCTAssertNil(
            ExtensionOptionsWindowCallbackComposition.invocation(
                from: manager,
                evidence: staleEvidence
            ),
            "disabled options record rejected"
        )
        let disabledReceipt = ExtensionOptionsWindowPresentationReceipt(
            evidence: enabledInvocation.receipt.evidence,
            profile: enabledInvocation.receipt.profile,
            displayName: enabledInvocation.receipt.displayName,
            optionsURL: enabledInvocation.receipt.optionsURL,
            packageURL: enabledInvocation.receipt.packageURL,
            extensionRoot: enabledInvocation.receipt.extensionRoot,
            configuration: enabledInvocation.receipt.configuration,
            visitedLinkStore: enabledInvocation.receipt.visitedLinkStore,
            installedRecordRevision: manager.installedExtensionCollection
                .recordRevision(for: installed.id)
        )
        XCTAssertFalse(
            enabledInvocation.runtime.isCurrent(disabledReceipt),
            "disabled options record rejected during revalidation"
        )
        manager.installedExtensionCollection.upsert(enabledInstalled)

        let attachedRuntime = manager.runtime
        let mutationAdmission = OptionsMutationAdmissionGate()
        var mutationWaiter: CheckedContinuation<Bool, Never>?
        let didSuspend = expectation(description: "options admission suspended")
        manager.runtime = ExtensionManagerRuntime(
            currentProfile: attachedRuntime.currentProfile,
            profile: attachedRuntime.profile,
            ephemeralProfile: attachedRuntime.ephemeralProfile,
            windowState: attachedRuntime.windowState,
            windowRegistrationReceipt:
            attachedRuntime.windowRegistrationReceipt,
            registeredWindow: attachedRuntime.registeredWindow,
            activeWindowState: attachedRuntime.activeWindowState,
            allTabs: attachedRuntime.allTabs,
            allWindowStates: attachedRuntime.allWindowStates,
            windowStateContainingTab: attachedRuntime.windowStateContainingTab,
            windowOwnedWebView: attachedRuntime.windowOwnedWebView,
            primaryTrackedWindowId: attachedRuntime.primaryTrackedWindowId,
            untrackedOwnedWebView: attachedRuntime.untrackedOwnedWebView,
            trackedWebViews: attachedRuntime.trackedWebViews,
            rebuildLiveWebViews: attachedRuntime.rebuildLiveWebViews,
            websiteDataMutationAdmissionIsBlocked: { _ in
                mutationAdmission.isBlocked
            },
            waitForWebsiteDataMutationAdmission: { _ in
                didSuspend.fulfill()
                return await withCheckedContinuation { mutationWaiter = $0 }
            },
            browserRuntimeAvailable: attachedRuntime.browserRuntimeAvailable,
            extensionsModuleEnabled: attachedRuntime.extensionsModuleEnabled
        )
        let staleCompletion = expectation(
            description: "stale options admission rejected"
        )
        var staleCompletionError: Error?
        var staleCompletionCount = 0
        let staleInvocation = try XCTUnwrap(
            ExtensionOptionsWindowCallbackComposition.invocation(
                from: manager,
                evidence: staleEvidence
            )
        )
        manager.optionsWindows.presentOptionsPageWindow(
            invocation: staleInvocation
        ) { error in
            staleCompletionCount += 1
            staleCompletionError = error
            staleCompletion.fulfill()
        }
        await fulfillment(of: [didSuspend], timeout: 2.0)
        let replacementRoot = try makeScratchDirectory()
        manager.installedExtensionCollection.upsert(
            replacingPackageRoot(
                of: enabledInstalled,
                with: replacementRoot
            )
        )
        mutationAdmission.isBlocked = false
        mutationWaiter?.resume(returning: true)
        await fulfillment(of: [staleCompletion], timeout: 2.0)
        XCTAssertEqual(staleCompletionCount, 1)
        XCTAssertTrue(staleCompletionError is CancellationError)
        XCTAssertNil(manager.optionsWindows.windows[installed.id])

        manager.runtime = attachedRuntime
        manager.installedExtensionCollection.upsert(enabledInstalled)
        let reloadedContext = try await manager.ensureExtensionLoaded(
            extensionId: installed.id,
            profileId: profile.id
        )
        let restoredContext = try XCTUnwrap(reloadedContext)
        let restoredController = try XCTUnwrap(
            manager.profileRuntime.controller(for: profile.id)
        )
        let evidence = try XCTUnwrap(
            manager.controllerCallbackAdmission.capture(
                context: restoredContext,
                controller: restoredController
            )
        )
        let otherProfile = Profile(name: "Current Profile B")
        let profileAReference = browserConfiguration
            .auxiliaryWebViewConfiguration(
                for: profile,
                surface: .extensionOptions
            )
        let profileBReference = browserConfiguration
            .auxiliaryWebViewConfiguration(
                for: otherProfile,
                surface: .extensionOptions
            )
        manager.profileRuntime.currentProfileId = otherProfile.id

        let openedOptions = expectation(description: "options page opened")
        var completionError: Error?
        let invocation = try XCTUnwrap(
            ExtensionOptionsWindowCallbackComposition.invocation(
                from: manager,
                evidence: evidence
            )
        )
        XCTAssertIdentical(
            invocation.receipt.configuration.webExtensionController,
            restoredController
        )
        XCTAssertIdentical(
            invocation.receipt.configuration.websiteDataStore,
            profile.dataStore
        )
        XCTAssertNotIdentical(
            invocation.receipt.configuration.websiteDataStore,
            otherProfile.dataStore
        )
        XCTAssertIdentical(
            invocation.receipt.configuration.sumiVisitedLinkStoreObject,
            profileAReference.sumiVisitedLinkStoreObject
        )
        XCTAssertNotIdentical(
            invocation.receipt.configuration.sumiVisitedLinkStoreObject,
            profileBReference.sumiVisitedLinkStoreObject
        )

        var supersededWaiter: CheckedContinuation<Bool, Never>?
        let supersededDidSuspend = expectation(
            description: "older options presentation suspended"
        )
        let supersededCompletion = expectation(
            description: "older options presentation settled"
        )
        var supersededCompletionCount = 0
        var supersededCompletionError: Error?
        let supersededRuntime = ExtensionOptionsWindowCallbackRuntime(
            admission: invocation.runtime.admission,
            installedExtensions: invocation.runtime.installedExtensions,
            websiteDataMutationAdmissionIsBlocked: { _ in true },
            waitForWebsiteDataMutationAdmission: { _ in
                supersededDidSuspend.fulfill()
                return await withCheckedContinuation { supersededWaiter = $0 }
            }
        )
        let supersededInvocation = ExtensionOptionsWindowCallbackComposition
            .Invocation(
                receipt: invocation.receipt,
                runtime: supersededRuntime
            )
        manager.optionsWindows.presentOptionsPageWindow(
            invocation: supersededInvocation
        ) { error in
            supersededCompletionCount += 1
            supersededCompletionError = error
            supersededCompletion.fulfill()
        }
        await fulfillment(of: [supersededDidSuspend], timeout: 2.0)

        manager.optionsWindows.presentOptionsPageWindow(
            invocation: invocation
        ) { error in
            completionError = error
            openedOptions.fulfill()
        }
        await fulfillment(of: [openedOptions], timeout: 2.0)
        XCTAssertNil(completionError)

        let window = try XCTUnwrap(manager.optionsWindows.windows[installed.id])
        let currentReceipt = try XCTUnwrap(
            manager.optionsWindows.receipt(for: installed.id)
        )
        supersededWaiter?.resume(returning: true)
        await fulfillment(of: [supersededCompletion], timeout: 2.0)
        XCTAssertEqual(supersededCompletionCount, 1)
        XCTAssertTrue(supersededCompletionError is CancellationError)
        XCTAssertEqual(
            manager.optionsWindows.receipt(for: installed.id),
            currentReceipt
        )
        XCTAssertIdentical(
            manager.optionsWindows.windows[installed.id],
            window
        )
        let contentView = try XCTUnwrap(window.contentView)
        let webView = try XCTUnwrap(Self.firstWebView(in: contentView))

        let metrics = try await awaitExtensionRenderMetrics(in: webView)
        XCTAssertEqual(webView.url, invocation.receipt.optionsURL)
        XCTAssertTrue(ExtensionURLIdentity.isOwned(webView.url))
        XCTAssertTrue(metrics.loadedFromExtensionScheme, metrics.debugSummary)
        XCTAssertEqual(metrics.readyState, "complete", metrics.debugSummary)
        XCTAssertGreaterThan(metrics.elementCount, 0, metrics.debugSummary)
        XCTAssertGreaterThan(metrics.scriptCount, 0, metrics.debugSummary)
        XCTAssertEqual(metrics.marker, "rendered", metrics.debugSummary)
        XCTAssertIdentical(
            webView.configuration.webExtensionController,
            restoredController
        )
        XCTAssertIdentical(
            webView.configuration.websiteDataStore,
            restoredController.configuration.defaultWebsiteDataStore
        )
        XCTAssertIdentical(
            webView.configuration.sumiVisitedLinkStoreObject,
            profileAReference.sumiVisitedLinkStoreObject
        )
        XCTAssertNotIdentical(
            webView.configuration.sumiVisitedLinkStoreObject,
            profileBReference.sumiVisitedLinkStoreObject
        )

        let orderFrontWindow = ReentrantOptionsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        let replacementWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let reentrantService = ExtensionOptionsWindowService {
            orderFrontWindow
        }
        var replacementReceipt: ExtensionOptionsWindowReceipt?
        orderFrontWindow.onFirstOrderFront = {
            reentrantService.closeWindow(for: installed.id)
            replacementReceipt = reentrantService.trackPresentedWindow(
                replacementWindow,
                delegate: nil,
                for: installed.id,
                profileID: profile.id
            )
        }
        var reentrantCompletionCount = 0
        var reentrantCompletionError: Error?
        reentrantService.presentOptionsPageWindow(
            invocation: invocation
        ) { error in
            reentrantCompletionCount += 1
            reentrantCompletionError = error
        }
        XCTAssertEqual(reentrantCompletionCount, 1)
        XCTAssertTrue(reentrantCompletionError is CancellationError)
        XCTAssertEqual(
            reentrantService.receipt(for: installed.id),
            replacementReceipt
        )
        XCTAssertIdentical(
            reentrantService.windows[installed.id],
            replacementWindow
        )
        XCTAssertNil(orderFrontWindow.contentView)
        XCTAssertFalse(orderFrontWindow.isVisible)
        reentrantService.closeWindow(for: installed.id)
    }
}

@MainActor
private final class OptionsMutationAdmissionGate {
    var isBlocked = true
}

@MainActor
private final class ReentrantOptionsWindow: NSWindow {
    var onFirstOrderFront: (() -> Void)?
    private var didInvokeOrderFrontHook = false

    override func orderFront(_ sender: Any?) {
        if didInvokeOrderFrontHook == false {
            didInvokeOrderFrontHook = true
            onFirstOrderFront?()
        }
        super.orderFront(sender)
    }
}

@MainActor
private final class UnresolvedRequestedWindowPreparedStub:
    PreparedExtensionRequestedWindow {
    let window = BrowserWindowState()
    private(set) var presentCallCount = 0
    private(set) var acceptCallCount = 0
    private(set) var cancelCallCount = 0

    func present() -> Bool {
        presentCallCount += 1
        return true
    }

    func accept() -> Bool {
        acceptCallCount += 1
        return true
    }

    func cancel() {
        cancelCallCount += 1
    }
}

@MainActor
private final class UnresolvedRequestedWindowCreatorStub:
    ExtensionRequestedWindowCreating {
    let prepared: UnresolvedRequestedWindowPreparedStub
    private(set) var preparedSeeds: [ExtensionRequestedWindowSeed] = []

    init(prepared: UnresolvedRequestedWindowPreparedStub) {
        self.prepared = prepared
    }

    func prepareExtensionRequestedWindow(
        _ seed: ExtensionRequestedWindowSeed
    ) -> (any PreparedExtensionRequestedWindow)? {
        preparedSeeds.append(seed)
        return prepared
    }
}

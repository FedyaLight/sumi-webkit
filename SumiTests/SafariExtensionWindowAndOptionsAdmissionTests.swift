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
        let managerFixture = makeManager(
            context: container,
            profile: profile,
            browserConfiguration: browserConfiguration
        )
        let manager = managerFixture.manager
        let inspection = managerFixture.inspection
        let attachedRuntime = managerFixture.attachedRuntime
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(
                userDefaults: UserDefaults(suiteName: UUID().uuidString)!
            )
        )
        registry.enable(.extensions)
        let extensionsModule = SumiExtensionsModule(
            moduleRegistry: registry,
            database: container,
            browserConfiguration: browserConfiguration,
            initialProfileProvider: { profile },
            managerFactory: { _, _, _, _ in manager }
        )
        let windowRegistry = WindowRegistry()
        let browserManager = makeBrowserManager(
            moduleRegistry: registry,
            extensionsModule: extensionsModule,
            profile: profile,
            windowRegistry: windowRegistry
        )
        _ = installTestSpace(
            in: browserManager.spaceStateOwner,
            name: "Work",
            profileID: profile.id
        )
        manager.attach(browserManager: browserManager)
        let controller = inspection.controller.provisioning
            .ensureExtensionController(for: profile.id)

        let prepared = UnresolvedRequestedWindowPreparedStub()
        let creator = UnresolvedRequestedWindowCreatorStub(prepared: prepared)
        let router = makeWindowRequestRouter(
            inspection: inspection,
            attachedRuntime: attachedRuntime.runtime,
            windowCreation: creator
        )
        let originalWindowIDs = Set(windowRegistry.windows.keys)
        let originalTabIDs = Set(
            browserManager.tabCollectionMembershipOwner
                .allTabs().map(\.id)
        )
        let completed = expectation(
            description: "unresolved extension window rejected"
        )
        var completionWindow: (any WKWebExtensionWindow)?
        var completionError: (any Error)?

        router.open(
            tabURLs: [
                URL(
                    string: "safari-web-extension://unresolved-owner/page.html"
                )!,
            ],
            controller: controller,
            extensionContext: nil,
            completion: { window, error in
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
                browserManager.tabCollectionMembershipOwner
                    .allTabs().map(\.id)
            ),
            originalTabIDs
        )
    }

    func testExtensionOptionsPageRendersThroughContextConfiguration() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Extension Options Profile")
        let browserConfiguration = BrowserConfiguration()
        let optionsManagerFixture = makeManager(
            context: container,
            profile: profile,
            browserConfiguration: browserConfiguration
        )
        let manager = optionsManagerFixture.manager
        let inspection = optionsManagerFixture.inspection
        let attachedRuntime = optionsManagerFixture.attachedRuntime
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(
                userDefaults: UserDefaults(suiteName: UUID().uuidString)!
            )
        )
        registry.enable(.extensions)
        let extensionsModule = SumiExtensionsModule(
            moduleRegistry: registry,
            database: container,
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
        let enabledInstalled = try await inspection.installation.lifecycle
            .enable(installed.id)

        let loadedContext = try await inspection.contextCoordination.residency
            .ensureExtensionLoaded(
            extensionId: installed.id,
            profileId: profile.id
        )
        let extensionContext = try XCTUnwrap(loadedContext)
        let controller = try XCTUnwrap(
            inspection.contextState.profiles.controllersByProfile[profile.id]
        )
        let staleEvidence = try XCTUnwrap(
            inspection.controller.callbackAdmission.capture(
                context: extensionContext,
                controller: controller
            )
        )
        let enabledInvocation = try XCTUnwrap(
            attachedRuntime.runtime.optionsComposer
                .invocation(evidence: staleEvidence)
        )

        inspection.actionSurfaces.installedExtensions.upsert(installed)
        XCTAssertNil(
            attachedRuntime.runtime.optionsComposer
                .invocation(evidence: staleEvidence),
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
            installedRecordRevision:
                inspection.actionSurfaces.installedExtensions
                .recordRevision(for: installed.id)
        )
        XCTAssertFalse(
            enabledInvocation.runtime.isCurrent(disabledReceipt),
            "disabled options record rejected during revalidation"
        )
        inspection.actionSurfaces.installedExtensions.upsert(enabledInstalled)

        let attached = attachedRuntime.runtime
        let mutationAdmission = OptionsMutationAdmissionGate()
        var mutationWaiter: CheckedContinuation<Bool, Never>?
        let didSuspend = expectation(description: "options admission suspended")
        let gatedComposer = ExtensionOptionsWindowCallbackComposer(
            admission: inspection.controller.callbackAdmission,
            profiles: attached.profileQuery,
            profileRuntime: inspection.contextState.profiles,
            installedExtensions:
                inspection.actionSurfaces.installedExtensions,
            browserConfiguration: browserConfiguration,
            configurationPreparation: inspection.normalTabs.configuration,
            websiteDataAdmission: ExtensionWebsiteDataMutationAdmission(
                isBlocked: { _ in
                    mutationAdmission.isBlocked
                },
                wait: { _ in
                    didSuspend.fulfill()
                    return await withCheckedContinuation {
                        mutationWaiter = $0
                    }
                }
            )
        )
        let staleCompletion = expectation(
            description: "stale options admission rejected"
        )
        var staleCompletionError: Error?
        var staleCompletionCount = 0
        let staleInvocation = try XCTUnwrap(
            gatedComposer.invocation(evidence: staleEvidence)
        )
        inspection.actionSurfaces.optionsWindows.presentOptionsPageWindow(
            invocation: staleInvocation
        ) { error in
            staleCompletionCount += 1
            staleCompletionError = error
            staleCompletion.fulfill()
        }
        await fulfillment(of: [didSuspend], timeout: 2.0)
        let replacementRoot = try makeScratchDirectory()
        inspection.actionSurfaces.installedExtensions.upsert(
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
        XCTAssertNil(
            inspection.actionSurfaces.optionsWindows.windows[installed.id]
        )

        inspection.actionSurfaces.installedExtensions.upsert(enabledInstalled)
        let reloadedContext = try await inspection.contextCoordination.residency
            .ensureExtensionLoaded(
            extensionId: installed.id,
            profileId: profile.id
        )
        let restoredContext = try XCTUnwrap(reloadedContext)
        let restoredController = try XCTUnwrap(
            inspection.contextState.profiles.controller(for: profile.id)
        )
        let evidence = try XCTUnwrap(
            inspection.controller.callbackAdmission.capture(
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
        inspection.contextState.profiles.currentProfileId = otherProfile.id

        let openedOptions = expectation(description: "options page opened")
        var completionError: Error?
        let invocation = try XCTUnwrap(
            attachedRuntime.runtime.optionsComposer
                .invocation(evidence: evidence)
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
            websiteDataAdmission: ExtensionWebsiteDataMutationAdmission(
                isBlocked: { _ in true },
                wait: { _ in
                    supersededDidSuspend.fulfill()
                    return await withCheckedContinuation {
                        supersededWaiter = $0
                    }
                }
            )
        )
        let supersededInvocation = ExtensionOptionsWindowCallbackComposition
            .Invocation(
                receipt: invocation.receipt,
                runtime: supersededRuntime
            )
        inspection.actionSurfaces.optionsWindows.presentOptionsPageWindow(
            invocation: supersededInvocation
        ) { error in
            supersededCompletionCount += 1
            supersededCompletionError = error
            supersededCompletion.fulfill()
        }
        await fulfillment(of: [supersededDidSuspend], timeout: 2.0)

        inspection.actionSurfaces.optionsWindows.presentOptionsPageWindow(
            invocation: invocation
        ) { error in
            completionError = error
            openedOptions.fulfill()
        }
        await fulfillment(of: [openedOptions], timeout: 2.0)
        XCTAssertNil(completionError)

        let window = try XCTUnwrap(
            inspection.actionSurfaces.optionsWindows.windows[installed.id]
        )
        let currentReceipt = try XCTUnwrap(
            inspection.actionSurfaces.optionsWindows.receipt(for: installed.id)
        )
        supersededWaiter?.resume(returning: true)
        await fulfillment(of: [supersededCompletion], timeout: 2.0)
        XCTAssertEqual(supersededCompletionCount, 1)
        XCTAssertTrue(supersededCompletionError is CancellationError)
        XCTAssertEqual(
            inspection.actionSurfaces.optionsWindows.receipt(for: installed.id),
            currentReceipt
        )
        XCTAssertIdentical(
            inspection.actionSurfaces.optionsWindows.windows[installed.id],
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

    func present(activate _: Bool) -> Bool {
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

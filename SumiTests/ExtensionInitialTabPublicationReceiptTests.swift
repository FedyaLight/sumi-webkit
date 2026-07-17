import AppKit
import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class ExtensionInitialTabPublicationReceiptTests:
    SafariExtensionWebViewControllerWiringTestCase {
    func testDidOpenReentrancyWithRegistryRemovalBalancesExactOpenOnce()
        async throws {
        let harness = try await makeHarness()
        var events: [String] = []

        harness.manager.testHooks.didOpenTab = { tabID in
            guard tabID == harness.tab.id else { return }
            events.append("didOpen")
            harness.windowRegistry.unregister(harness.window.id)
        }
        harness.manager.testHooks.didCloseTab = { tabID in
            guard tabID == harness.tab.id else { return }
            events.append("didClose")
        }
        defer {
            harness.manager.testHooks.didOpenTab = nil
            harness.manager.testHooks.didCloseTab = nil
        }

        harness.publication.commitRegistration(harness.window)

        XCTAssertEqual(events, ["didOpen", "didClose"])
        XCTAssertEqual(
            harness.publication.initialPublicationResult(for: harness.window),
            .suppressed
        )
        XCTAssertFalse(harness.tab.extensionPageRuntimeOwner
            .hasAnyDidOpenTabNotification())
        XCTAssertNil(harness.inspection.normalTabs.adapters.tabAdapters[harness.tab.id])

        harness.publication.revokeCommittedPublicationIfNeeded(
            for: harness.window
        )
        XCTAssertEqual(events, ["didOpen", "didClose"])
    }

    func testDidOpenReentrancyWithContextReplacementBalancesExactOpenOnce()
        async throws {
        let harness = try await makeHarness()
        let identity = try XCTUnwrap(
            harness.inspection.contextState.profiles.exactContextIdentity(
                for: harness.context
            )
        )
        var events: [String] = []

        harness.manager.testHooks.didOpenTab = { tabID in
            guard tabID == harness.tab.id else { return }
            events.append("didOpen")
            let replacement = WKWebExtensionContext(
                for: harness.context.webExtension
            )
            _ = harness.inspection.contextState.profiles.setContext(
                replacement,
                extensionId: identity.extensionId,
                profileId: identity.profileId
            )
        }
        harness.manager.testHooks.didCloseTab = { tabID in
            guard tabID == harness.tab.id else { return }
            events.append("didClose")
        }
        defer {
            harness.manager.testHooks.didOpenTab = nil
            harness.manager.testHooks.didCloseTab = nil
        }

        harness.publication.commitRegistration(harness.window)

        XCTAssertEqual(events, ["didOpen", "didClose"])
        XCTAssertEqual(
            harness.publication.initialPublicationResult(for: harness.window),
            .suppressed
        )
        XCTAssertFalse(harness.tab.extensionPageRuntimeOwner
            .hasAnyDidOpenTabNotification())
        XCTAssertNil(harness.inspection.normalTabs.adapters.tabAdapters[harness.tab.id])

        harness.publication.revokeCommittedPublicationIfNeeded(
            for: harness.window
        )
        XCTAssertEqual(events, ["didOpen", "didClose"])
    }

    func testOldReceiptCannotCloseNewGenerationUsingSameAdapter()
        async throws {
        let harness = try await makeHarness()
        var closeCount = 0
        harness.manager.testHooks.didCloseTab = { tabID in
            guard tabID == harness.tab.id else { return }
            closeCount += 1
        }
        defer { harness.manager.testHooks.didCloseTab = nil }

        harness.publication.commitRegistration(harness.window)
        let adapter = try XCTUnwrap(
            harness.inspection.normalTabs.adapters.tabAdapters[harness.tab.id]
        )
        let profileID = harness.profileID
        let nextGeneration = try XCTUnwrap(
            harness.inspection.runtimeAuthorities.tabPublicationRevisions.advance(
                ifCurrent: harness.inspection.runtimeAuthorities.tabPublicationRevisions.issue()
            )
        )
        harness.tab.extensionPageRuntimeOwner.prepareGeneration(
            nextGeneration
        )
        harness.tab.extensionPageRuntimeOwner.markEligible(
            for: nextGeneration
        )
        harness.tab.extensionPageRuntimeOwner.noteOpenNotification(
            extensionContextBindingGeneration: harness.inspection.contextState.profiles
                .contextBindingGeneration(for: profileID),
            contextReadiness: .loaded
        )
        harness.tab.extensionPageRuntimeOwner.markDidOpenTab(
            generation: nextGeneration
        )
        harness.inspection.contextState.profiles.controller(
            for: profileID
        )?.didOpenTab(adapter)

        harness.publication.revokeCommittedPublicationIfNeeded(
            for: harness.window
        )

        XCTAssertEqual(closeCount, 0)
        XCTAssertTrue(
            harness.tab.extensionPageRuntimeOwner
                .hasDidOpenTabNotification(for: nextGeneration)
        )
    }

    func testDidOpenWindowHandoffBalancesDelegatedOpenOnRollback()
        async throws {
        let harness = try await makeHarness()
        var events: [String] = []
        harness.manager.testHooks.didOpenTab = { tabID in
            guard tabID == harness.tab.id else { return }
            events.append("didOpen")
        }
        harness.manager.testHooks.didCloseTab = { tabID in
            guard tabID == harness.tab.id else { return }
            events.append("didClose")
        }
        defer {
            harness.manager.testHooks.didOpenTab = nil
            harness.manager.testHooks.didCloseTab = nil
        }

        XCTAssertTrue(
            harness.attachedRuntime.publications.normalWindows
                .opened(harness.window)
        )
        harness.attachedRuntime.normalTabs.tabRegistration.register(
            harness.tab,
            reason: #function
        )
        XCTAssertEqual(events, ["didOpen"])

        harness.publication.commitRegistration(harness.window)
        XCTAssertEqual(
            harness.publication.initialPublicationResult(for: harness.window),
            .extensionPublished
        )
        XCTAssertEqual(events, ["didOpen"])

        harness.publication.revokeCommittedPublicationIfNeeded(
            for: harness.window
        )
        XCTAssertEqual(events, ["didOpen", "didClose"])
        XCTAssertFalse(
            harness.tab.extensionPageRuntimeOwner
                .hasAnyDidOpenTabNotification()
        )
    }

    private struct Harness {
        let manager: ExtensionManager
        let inspection: ExtensionManagerTestInspection
        let attachedRuntime: ExtensionAttachedBrowserRuntimeInspection
        let windowRegistry: WindowRegistry
        let window: BrowserWindowState
        let tab: Tab
        let profileID: UUID
        let context: WKWebExtensionContext
        let publication: WindowExtensionPublicationTransaction
    }

    private func makeHarness() async throws -> Harness {
        SafariExtensionLiveWebKitTestLease.holdForProcess()
        let container = try makeTestContainer()
        let profile = Profile(name: "Initial Tab Transaction")
        let browserConfiguration = BrowserConfiguration()
        let moduleRegistry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(
                userDefaults: UserDefaults(suiteName: UUID().uuidString)!
            )
        )
        moduleRegistry.enable(.extensions)
        let attachedRuntime = ExtensionAttachedRuntimeCapture()
        let inspection = ExtensionManagerInspectionCapture()
        let manager = makeSafariExtensionTestExtensionManager(
            context: container.mainContext,
            initialProfile: profile,
            browserConfiguration: browserConfiguration,
            moduleRegistry: moduleRegistry,
            attachedRuntimeCapture: attachedRuntime,
            inspectionCapture: inspection
        )
        let extensionsModule = SumiExtensionsModule(
            moduleRegistry: moduleRegistry,
            context: container.mainContext,
            browserConfiguration: browserConfiguration,
            initialProfileProvider: { profile },
            managerFactory: { _, _, _, _ in manager }
        )
        let windowRegistry = WindowRegistry()
        let browserManager = makeSafariExtensionTestBrowserManager(
            moduleRegistry: moduleRegistry,
            extensionsModule: extensionsModule,
            profile: profile,
            windowRegistry: windowRegistry
        )
        extensionsModule.attach(
            runtime: BrowserExtensionsModuleRuntimeFactory.runtime(
                for: browserManager
            )
        )
        manager.attach(browserManager: browserManager)

        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installUnpackedExtension(
            manager: manager,
            scratchDirectory: scratchDirectory,
            name: "InitialTabPublicationExtension"
        )
        _ = try await inspection.inspection.installation.lifecycle.enable(installed.id)
        let loadedContext = try await inspection.inspection.contextCoordination.residency.ensureExtensionLoaded(
            extensionId: installed.id,
            profileId: profile.id
        )
        let context = try XCTUnwrap(loadedContext)

        let space = Space(name: "Primary", profileId: profile.id)
        browserManager.spaceStateOwner.replaceSpaces([space])
        browserManager.spaceStateOwner.replaceCurrentSpace(space)

        let window = BrowserWindowState()
        browserManager.tabResidenceAuthority.establishResidenceSession(on: window)
        window.currentProfileId = profile.id
        window.currentSpaceId = space.id
        let tab = browserManager.regularTabLifecycleOwner
            .createNewTab(
                url: "https://initial.example/page",
                in: space,
                activate: false
            )
        browserManager.selectTab(tab, in: window)
        browserManager.materializeVisibleTabWebViewIfNeeded(tab, in: window)
        let webView = try XCTUnwrap(
            browserManager.webViewRuntime.ownershipQuery.webView(
                for: tab.id,
                in: window.id
            ) as? FocusableWKWebView
        )

        let publication = browserManager.windowExtensionPublication
        publication.prepareRegistration(window)
        XCTAssertEqual(
            publication.stageInitialTab(
                tab,
                webView: webView,
                in: window,
                reason: #function
            ),
            .extensionPrepared
        )

        let appKitWindow = NSWindow(
            contentRect: NSRect(x: 140, y: 140, width: 900, height: 680),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        windowRegistry.bindAppKitWindow(appKitWindow, to: window)
        windowRegistry.register(window)
        windowRegistry.setActive(window)
        addTeardownBlock {
            withExtendedLifetime(appKitWindow) {
                windowRegistry.unregister(window.id)
            }
        }

        return Harness(
            manager: manager,
            inspection: inspection.inspection,
            attachedRuntime: attachedRuntime.runtime,
            windowRegistry: windowRegistry,
            window: window,
            tab: tab,
            profileID: profile.id,
            context: context,
            publication: publication
        )
    }
}

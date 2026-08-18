import AppKit
import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)

@MainActor
extension SafariExtensionWebViewControllerRuntimeWarmupTests {
    func testRuntimeTeardownInvalidatesLoadBeforeControllerLoad() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let managerFixture = makeManager(
            context: container,
            profile: profile
        )
        let manager = managerFixture.manager
        let inspection = managerFixture.inspection
        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installUnpackedExtension(
            manager: manager,
            scratchDirectory: scratchDirectory,
            name: "TeardownRaceProbe"
        )
        let entity = try XCTUnwrap(try inspection.installation.metadata.extensionMetadata(for: installed.id))
        entity.isEnabled = true
        try inspection.installation.metadata.save(entity)
        let controller = inspection.controller.provisioning.ensureExtensionController(for: profile.id)

        manager.testHooks.beforeControllerLoad = { _ in
            _ = manager.shutDownExtensionRuntime(
                reason: "SafariExtensionWebViewControllerWiringTests"
            )
        }

        do {
            _ = try await inspection.contextCoordination.loader.loadEnabled(from: entity)
            XCTFail("A load invalidated by runtime teardown must not reach WebKit")
        } catch {
            XCTAssertTrue(error is CancellationError, String(describing: error))
        }

        XCTAssertTrue(controller.extensionContexts.isEmpty)
        XCTAssertTrue(inspection.contextState.profiles.contextsByProfile.isEmpty)
        XCTAssertTrue(inspection.contextState.profiles.controllersByProfile.isEmpty)
    }

    func testRuntimeTeardownUnloadsLoadedContexts() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let managerFixture = makeManager(
            context: container,
            profile: profile
        )
        let manager = managerFixture.manager
        let inspection = managerFixture.inspection
        let extensionContext = try await makeLoadedExtensionContext(
            manager: manager,
            inspection: inspection,
            profile: profile
        )
        let controller = try XCTUnwrap(extensionContext.webExtensionController)

        XCTAssertTrue(extensionContext.isLoaded)
        XCTAssertFalse(controller.extensionContexts.isEmpty)

        _ = manager.shutDownExtensionRuntime(
            reason: "SafariExtensionWebViewControllerWiringTests"
        )

        XCTAssertFalse(extensionContext.isLoaded)
        XCTAssertTrue(controller.extensionContexts.isEmpty)
        XCTAssertTrue(inspection.contextState.profiles.contextsByProfile.isEmpty)
        XCTAssertTrue(inspection.contextState.profiles.controllersByProfile.isEmpty)
    }

    func testUserExtensionRuntimeTeardownMarksAllLiveNormalTabsAffected()
        async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let browserConfiguration = BrowserConfiguration()
        let managerFixture = makeManager(
            context: container,
            profile: profile,
            browserConfiguration: browserConfiguration
        )
        let manager = managerFixture.manager
        let inspection = managerFixture.inspection
        let browserManager = makeBrowserManager(
            profile: profile
        )
        manager.attach(browserManager: browserManager)
        let space = installTestSpace(
            in: browserManager.spaceStateOwner,
            name: "Work",
            profileID: profile.id
        )
        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installContentScriptProbeExtension(
            manager: manager,
            scratchDirectory: scratchDirectory
        )
        _ = try await inspection.installation.lifecycle.enable(installed.id)
        _ = try await inspection.contextCoordination.residency.ensureExtensionLoaded(
            extensionId: installed.id,
            profileId: profile.id
        )
        inspection.actionSurfaces.publication.markRuntimePublicationReady()

        let tabWithController = browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/with-controller",
            in: space,
            activate: false
        )
        tabWithController.profileId = profile.id
        let controllerConfiguration = browserConfiguration
            .auxiliaryWebViewConfiguration(surface: .extensionOptions)
        inspection.normalTabs.configuration.prepareWebViewConfigForExtensionRuntime(
            controllerConfiguration,
            profileId: profile.id,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )
        let webViewWithController = FocusableWKWebView(
            frame: .zero,
            configuration: controllerConfiguration
        )
        webViewWithController.owningTab = tabWithController
        tabWithController.replaceUntrackedWebView(webViewWithController)

        let tabWithoutController = browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/without-controller",
            in: space,
            activate: false
        )
        tabWithoutController.profileId = profile.id
        let plainConfiguration = browserConfiguration
            .auxiliaryWebViewConfiguration(surface: .extensionOptions)
        let webViewWithoutController = FocusableWKWebView(
            frame: .zero,
            configuration: plainConfiguration
        )
        webViewWithoutController.owningTab = tabWithoutController
        tabWithoutController.replaceUntrackedWebView(webViewWithoutController)

        let shutdown = manager.shutDownExtensionRuntime(
            reason: "SafariExtensionWebViewControllerWiringTests"
        )
        let affectedIDs = Set(
            inspection.retirement.termination.executeRebuildPlan(
                shutdown.tabRebuildPlan,
                reason: "SafariExtensionWebViewControllerWiringTests"
            ).map(\.tabID)
        )

        XCTAssertTrue(shutdown.completed)
        XCTAssertTrue(affectedIDs.contains(tabWithController.id))
        XCTAssertTrue(affectedIDs.contains(tabWithoutController.id))
    }

    func testPrepareExtensionRuntimeBeforeNavigationReNotifiesOnReload() throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let managerFixture = makeManager(
            context: container,
            profile: profile
        )
        let manager = managerFixture.manager
        let inspection = managerFixture.inspection
        _ = inspection.contextCoordination.demand.requestRuntimeExplicitly(
            reason: .install
        )
        _ = inspection.controller.provisioning.ensureExtensionController(for: profile.id)
        inspection.actionSurfaces.publication.markRuntimePublicationReady()

        let browserManager = makeBrowserManager(profile: profile)
        manager.attach(browserManager: browserManager)

        let pageURL = URL(string: "http://127.0.0.1:8765/login-basic.html")!
        let tab = makeTab(
            profileId: profile.id,
            url: pageURL,
            browserManager: browserManager
        )
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))
        registerWindowDisplaying(
            tab,
            profileId: profile.id,
            browserManager: browserManager
        )

        let configuration = BrowserConfiguration().auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        inspection.normalTabs.configuration.prepareWebViewConfigForExtensionRuntime(
            configuration,
            profileId: profile.id,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.owningTab = tab
        tab.replaceUntrackedWebView(webView)

        tab.extensionPageRuntimeOwner.markEligible(
            for: inspection.runtimeAuthorities.tabPublicationRevisions.issue()
        )
        XCTAssertTrue(
            managerFixture.attachedRuntime.runtime.normalTabs.tabOpening
                .publishOpen(tab)
        )
        tab.extensionPageRuntimeOwner.noteCommittedMainDocumentNavigation(to: pageURL)

        XCTAssertFalse(
            managerFixture.attachedRuntime.runtime.normalTabs.tabRebind
                .needsContentScriptRebind(tab)
        )

        let didCloseExpectation = expectation(description: "didCloseTab before reload commit")
        let didOpenExpectation = expectation(description: "didOpenTab before reload commit")
        manager.testHooks.didCloseTab = { tabID in
            if tabID == tab.id {
                didCloseExpectation.fulfill()
            }
        }
        manager.testHooks.didOpenTab = { tabID in
            if tabID == tab.id {
                didOpenExpectation.fulfill()
            }
        }

        managerFixture.attachedRuntime.runtime.normalTabs.tabRebind
            .prepareBeforeCommittedMainFrameNavigation(
            tab,
            destinationURL: pageURL,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )

        wait(for: [didCloseExpectation, didOpenExpectation], timeout: 2)
        XCTAssertEqual(tab.extensionPageRuntimeOwner.openNotifiedDocumentSequence, tab.extensionPageRuntimeOwner.documentSequence)
        XCTAssertEqual(
            tab.extensionPageRuntimeOwner.openNotifiedContextBindingGeneration,
            inspection.contextState.profiles.contextBindingGeneration(for: profile.id)
        )

        tab.extensionPageRuntimeOwner.noteCommittedMainDocumentNavigation(to: pageURL)
        XCTAssertFalse(
            managerFixture.attachedRuntime.runtime.normalTabs.tabRebind
                .needsContentScriptRebind(tab)
        )
    }

    func testPrepareBeforeNavigationCyclesCloseOpenOnReload() throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let managerFixture = makeManager(
            context: container,
            profile: profile
        )
        let manager = managerFixture.manager
        let inspection = managerFixture.inspection
        _ = inspection.contextCoordination.demand.requestRuntimeExplicitly(
            reason: .install
        )
        let controller = inspection.controller.provisioning.ensureExtensionController(for: profile.id)
        inspection.actionSurfaces.publication.markRuntimePublicationReady()
        _ = controller

        let browserManager = makeBrowserManager(profile: profile)
        manager.attach(browserManager: browserManager)

        let pageURL = URL(string: "http://127.0.0.1:8765/login-basic.html")!
        let tab = makeTab(
            profileId: profile.id,
            url: pageURL,
            browserManager: browserManager
        )
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))
        registerWindowDisplaying(
            tab,
            profileId: profile.id,
            browserManager: browserManager
        )
        attachUsableExtensionWebView(
            to: tab,
            inspection: inspection,
            profile: profile
        )
        tab.extensionPageRuntimeOwner.markEligible(
            for: inspection.runtimeAuthorities.tabPublicationRevisions.issue()
        )
        XCTAssertTrue(
            managerFixture.attachedRuntime.runtime.normalTabs.tabOpening
                .publishOpen(tab)
        )
        tab.extensionPageRuntimeOwner.noteCommittedMainDocumentNavigation(to: pageURL)

        let didCloseExpectation = expectation(description: "didCloseTab before reload commit")
        let didOpenExpectation = expectation(description: "didOpenTab before reload commit")
        manager.testHooks.didCloseTab = { tabID in
            if tabID == tab.id {
                didCloseExpectation.fulfill()
            }
        }
        manager.testHooks.didOpenTab = { tabID in
            if tabID == tab.id {
                didOpenExpectation.fulfill()
            }
        }

        managerFixture.attachedRuntime.runtime.normalTabs.tabRebind
            .prepareBeforeCommittedMainFrameNavigation(
            tab,
            destinationURL: pageURL,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )

        wait(for: [didCloseExpectation, didOpenExpectation], timeout: 2)
    }

    func testWrongControllerRequiresRuntimeRebuild() throws {
        let container = try makeTestContainer()
        let profileA = Profile(name: "Profile A")
        let profileB = Profile(name: "Profile B")
        let browserConfiguration = BrowserConfiguration()
        let managerFixture = makeManager(
            context: container,
            profile: profileA,
            browserConfiguration: browserConfiguration
        )
        let manager = managerFixture.manager
        defer { withExtendedLifetime(manager) {} }
        let inspection = managerFixture.inspection
        let attachedRuntime = managerFixture.attachedRuntime
        _ = inspection.contextCoordination.demand.requestRuntimeExplicitly(
            reason: .install
        )
        let controllerA = inspection.controller.provisioning.ensureExtensionController(for: profileA.id)
        let controllerB = inspection.controller.provisioning.ensureExtensionController(for: profileB.id)
        let browserManager = makeBrowserManager(profile: profileA)
        browserManager.profileManager.profiles = [profileA, profileB]
        manager.attach(browserManager: browserManager)

        let pageURL = URL(string: "http://127.0.0.1:8765/login-basic.html")!
        let tab = makeTab(
            profileId: profileA.id,
            url: pageURL,
            browserManager: browserManager
        )
        tab.attachBrowserRuntime(
            TabBrowserRuntimeFactory.make(for: browserManager)
        )
        tab.extensionPageRuntimeOwner.openNotifiedDocumentSequence = 0
        tab.extensionPageRuntimeOwner.openNotifiedContextBindingGeneration = 0
        tab.extensionPageRuntimeOwner.noteCommittedMainDocumentNavigation(to: pageURL)

        let configuration = browserConfiguration.auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        inspection.normalTabs.configuration.prepareWebViewConfigForExtensionRuntime(
            configuration,
            profileId: profileB.id,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )
        XCTAssertEqual(
            attachedRuntime.runtime.controller.profiles.profileID(for: tab),
            profileA.id
        )
        XCTAssertIdentical(configuration.webExtensionController, controllerB)
        XCTAssertNotIdentical(configuration.webExtensionController, controllerA)
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.owningTab = tab
        tab.replaceUntrackedWebView(webView)
        let currentController = try XCTUnwrap(webView.configuration.webExtensionController)
        XCTAssertIdentical(currentController, controllerB)
        XCTAssertEqual(inspection.contextState.profiles.profileId(for: currentController), profileB.id)
        XCTAssertEqual(
            attachedRuntime.runtime.controller.profiles.profileID(for: tab),
            profileA.id
        )
        XCTAssertIdentical(inspection.contextState.profiles.controllersByProfile[profileA.id], controllerA)
        XCTAssertIdentical(inspection.contextState.profiles.controllersByProfile[profileB.id], controllerB)
        XCTAssertIdentical(
            managerFixture.attachedRuntime.runtime.controller.controllers
                .existingController(for: tab),
            controllerA
        )

        XCTAssertTrue(
            attachedRuntime.runtime.controller.mismatch
                .webViewNeedsExtensionRuntimeRebuild(webView, for: tab)
        )
    }

    func testContentScriptProbeExtensionDeclaresManifestCSS() async throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let managerFixture = makeManager(
            context: container,
            profile: profile
        )
        let manager = managerFixture.manager
        let scratchDirectory = try makeScratchDirectory()
        let installed = try await installContentScriptProbeExtension(
            manager: manager,
            scratchDirectory: scratchDirectory
        )
        let manifestURL = URL(fileURLWithPath: installed.packagePath)
            .appendingPathComponent("manifest.json")
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        let contentScripts = manifest?["content_scripts"] as? [[String: Any]]
        let css = contentScripts?.first?["css"] as? [String]
        XCTAssertEqual(css, ["overlay.css"])
        XCTAssertTrue(
            ((manifest?["web_accessible_resources"] as? [[String: Any]])?.first?["resources"] as? [String])?
                .contains("overlay.html") == true
        )
    }

    func testConfigureContextIdentityKeepsPublicIdentifierAndScopesBaseURL() async throws {
        let profile = Profile(name: "Profile A")
        let otherProfile = Profile(name: "Profile B")
        let extensionId = "probe-extension-id"
        let scratchDirectory = try makeScratchDirectory()
        let directoryURL = scratchDirectory.appendingPathComponent("BaseURLProbe", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Probe",
            "version": "1.0",
        ]
        let manifestURL = directoryURL.appendingPathComponent("manifest.json")
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
            .write(to: manifestURL, options: [.atomic])

        let webExtension = try await WKWebExtension(resourceBaseURL: directoryURL)
        let extensionContext = WKWebExtensionContext(for: webExtension)
        let otherExtensionContext = WKWebExtensionContext(for: webExtension)
        ExtensionContextPreparation.configureIdentity(
            extensionContext,
            extensionID: extensionId,
            profileID: profile.id,
            runtimeIdentifier: extensionId
        )
        ExtensionContextPreparation.configureIdentity(
            otherExtensionContext,
            extensionID: extensionId,
            profileID: otherProfile.id,
            runtimeIdentifier: extensionId
        )

        let baseURL = try XCTUnwrap(extensionContext.baseURL)
        let otherBaseURL = try XCTUnwrap(otherExtensionContext.baseURL)
        XCTAssertEqual(extensionContext.uniqueIdentifier, extensionId)
        XCTAssertEqual(otherExtensionContext.uniqueIdentifier, extensionId)
        XCTAssertEqual(baseURL.scheme, "safari-web-extension")
        XCTAssertTrue(baseURL.host?.hasPrefix("ext-") == true)
        XCTAssertNotEqual(baseURL.host, otherBaseURL.host)
    }

    func testPrepareWebViewForExtensionRuntimePreservesPreconfiguredController() throws {
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let browserConfiguration = BrowserConfiguration()
        let managerFixture = makeManager(
            context: container,
            profile: profile,
            browserConfiguration: browserConfiguration
        )
        let manager = managerFixture.manager
        let inspection = managerFixture.inspection
        let attachedRuntime = managerFixture.attachedRuntime
        _ = inspection.contextCoordination.demand.requestRuntimeExplicitly(
            reason: .install
        )
        let expectedController = inspection.controller.provisioning.ensureExtensionController(for: profile.id)
        let browserManager = makeBrowserManager(profile: profile)
        manager.attach(browserManager: browserManager)

        let configuration = browserConfiguration.auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        inspection.normalTabs.configuration.prepareWebViewConfigForExtensionRuntime(
            configuration,
            profileId: profile.id,
            reason: "SafariExtensionWebViewControllerWiringTests"
        )
        let tab = makeTab(
            profileId: profile.id,
            url: URL(string: "about:blank")!,
            browserManager: browserManager
        )
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.owningTab = tab
        tab.replaceUntrackedWebView(webView)

        attachedRuntime.runtime.normalTabs.liveWebViewPreparation
            .prepareWebViewForExtensionRuntime(
            webView,
            currentURL: URL(string: "about:blank"),
            reason: "SafariExtensionWebViewControllerWiringTests"
        )

        XCTAssertIdentical(
            webView.configuration.webExtensionController,
            expectedController
        )
    }
}

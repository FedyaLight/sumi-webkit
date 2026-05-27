import Foundation
import SwiftData
import WebKit
import XCTest

@testable import Sumi

final class ChromeMV3NormalTabConfigurationAttachmentTests: XCTestCase {
    @MainActor
    func testDefaultBrowserConfigHelperLeavesNormalTabUnattached() {
        let browserConfiguration = BrowserConfiguration()
        let profile = Profile(name: "Chrome MV3 Default Off")

        let result = browserConfiguration
            .normalTabWebViewConfigurationWithChromeMV3AttachmentGate(
                for: profile,
                url: URL(string: "https://example.com")
            )

        XCTAssertTrue(result.configuration.sumiIsNormalTabWebViewConfiguration)
        XCTAssertNil(result.configuration.webExtensionController)
        XCTAssertFalse(result.diagnostics.normalTabConfigurationAttached)
        XCTAssertFalse(
            result.diagnostics.gateDecision
                .canAttachNormalTabConfigurationNow
        )
        XCTAssertTrue(
            result.diagnostics.gateDecision.blockers
                .contains(.extensionsModuleDisabled)
        )
        XCTAssertFalse(result.diagnostics.runtimeLoadable)
        XCTAssertFalse(result.diagnostics.canLoadContextNow)
        XCTAssertFalse(result.diagnostics.attachmentRequested)
        XCTAssertEqual(result.diagnostics.targetSurface, .normalTab)
        XCTAssertFalse(result.diagnostics.emptyControllerOwnerPresent)
        XCTAssertFalse(
            result.diagnostics.explicitInternalNormalTabAttachmentAllowed
        )
    }

    @MainActor
    func testDisabledModuleLeavesNormalTabConfigurationUnattached() throws {
        let fixture = try makeModuleFixture(extensionsEnabled: false)
        defer { fixture.tearDown() }
        let request = fixture.module
            .chromeMV3NormalTabConfigurationAttachmentRequestIfEnabled(
                explicitInternalNormalTabAttachmentAllowed: true
            )

        let result = fixture.browserConfiguration
            .normalTabWebViewConfigurationWithChromeMV3AttachmentGate(
                for: fixture.profile,
                url: URL(string: "https://example.com"),
                chromeMV3AttachmentRequest: request
            )

        XCTAssertNil(request)
        XCTAssertNil(result.configuration.webExtensionController)
        XCTAssertFalse(result.diagnostics.normalTabConfigurationAttached)
        XCTAssertFalse(
            result.diagnostics.gateDecision
                .canAttachNormalTabConfigurationNow
        )
        XCTAssertEqual(fixture.probe.ownerFactoryCount, 0)
        XCTAssertEqual(fixture.probe.managerCount, 0)
        XCTAssertFalse(fixture.module.hasLoadedRuntime)
    }

    @MainActor
    func testEnabledModuleWithInternalGateOffLeavesNormalTabUnattached()
        throws
    {
        let fixture = try makeModuleFixture(extensionsEnabled: true)
        defer { fixture.tearDown() }
        _ = try XCTUnwrap(
            fixture.module.createChromeMV3EmptyControllerOwnerIfEnabled(
                explicitControllerCreationAllowed: true
            )
        )
        let request = try XCTUnwrap(
            fixture.module
                .chromeMV3NormalTabConfigurationAttachmentRequestIfEnabled(
                    explicitInternalNormalTabAttachmentAllowed: false
                )
        )

        let result = fixture.browserConfiguration
            .normalTabWebViewConfigurationWithChromeMV3AttachmentGate(
                for: fixture.profile,
                url: URL(string: "https://example.com"),
                chromeMV3AttachmentRequest: request
            )

        XCTAssertNil(result.configuration.webExtensionController)
        XCTAssertFalse(result.diagnostics.normalTabConfigurationAttached)
        XCTAssertTrue(
            result.diagnostics.gateDecision.blockers.contains(
                .explicitInternalNormalTabAttachmentNotAllowed
            )
        )
        XCTAssertEqual(result.diagnostics.contextCount, 0)
        XCTAssertEqual(result.diagnostics.loadedExtensionCount, 0)
        XCTAssertEqual(result.diagnostics.nativeMessagingPortCount, 0)
        XCTAssertTrue(result.diagnostics.attachmentRequested)
        XCTAssertEqual(result.diagnostics.targetSurface, .normalTab)
        XCTAssertFalse(fixture.module.hasLoadedRuntime)
        XCTAssertEqual(fixture.probe.managerCount, 0)
    }

    @MainActor
    func testEnabledInternalGateAttachesSameEmptyControllerToNormalTabOnly()
        throws
    {
        let fixture = try makeModuleFixture(extensionsEnabled: true)
        defer { fixture.tearDown() }
        let owner = try XCTUnwrap(
            fixture.module.createChromeMV3EmptyControllerOwnerIfEnabled(
                explicitControllerCreationAllowed: true
            )
        )
        let controller = try XCTUnwrap(owner.controller)
        let request = try XCTUnwrap(
            fixture.module
                .chromeMV3NormalTabConfigurationAttachmentRequestIfEnabled(
                    explicitInternalNormalTabAttachmentAllowed: true
                )
        )

        let result = fixture.browserConfiguration
            .normalTabWebViewConfigurationWithChromeMV3AttachmentGate(
                for: fixture.profile,
                url: URL(string: "https://example.com"),
                chromeMV3AttachmentRequest: request
            )
        let attachedController = try XCTUnwrap(
            result.configuration.webExtensionController
        )

        XCTAssertEqual(
            ObjectIdentifier(attachedController),
            ObjectIdentifier(controller)
        )
        XCTAssertTrue(result.configuration.sumiIsNormalTabWebViewConfiguration)
        XCTAssertTrue(
            result.configuration.sumiHasChromeMV3NormalTabConfigurationAttachment
        )
        XCTAssertTrue(result.diagnostics.normalTabConfigurationAttached)
        XCTAssertFalse(result.diagnostics.auxiliaryConfigurationAttached)
        XCTAssertTrue(result.diagnostics.attachedControllerMatchesOwner)
        XCTAssertTrue(
            result.diagnostics.gateDecision
                .canAttachNormalTabConfigurationNow
        )
        XCTAssertFalse(
            result.diagnostics.gateDecision
                .canAttachAuxiliaryConfigurationNow
        )
        XCTAssertEqual(result.diagnostics.contextCount, 0)
        XCTAssertEqual(result.diagnostics.loadedExtensionCount, 0)
        XCTAssertEqual(result.diagnostics.attachedWebViewCount, 0)
        XCTAssertFalse(result.diagnostics.webExtensionCreated)
        XCTAssertFalse(result.diagnostics.webExtensionContextCreated)
        XCTAssertFalse(result.diagnostics.contextLoadCalled)
        XCTAssertFalse(result.diagnostics.generatedExtensionBundleLoaded)
        XCTAssertFalse(result.diagnostics.nativeMessagingLaunched)
        XCTAssertEqual(result.diagnostics.nativeMessagingPortCount, 0)
        XCTAssertFalse(result.diagnostics.runtimeLoadable)
        XCTAssertFalse(result.diagnostics.canLoadContextNow)
        XCTAssertTrue(result.diagnostics.attachmentRequested)
        XCTAssertEqual(result.diagnostics.targetSurface, .normalTab)
        XCTAssertTrue(result.diagnostics.emptyControllerOwnerPresent)
        XCTAssertTrue(
            result.diagnostics.explicitInternalNormalTabAttachmentAllowed
        )
        XCTAssertEqual(result.diagnostics.userScriptRegistrationCount, 0)
        XCTAssertNotNil(result.diagnostics.attachedControllerIdentity)
        XCTAssertFalse(fixture.module.hasLoadedRuntime)
        XCTAssertEqual(fixture.probe.managerCount, 0)
    }

    @MainActor
    func testRequestModelClassifiesNormalTabAndAuxiliaryTargets() throws {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 WebKit attachment APIs require macOS 15.5.")
        }

        let liveRequest = ChromeMV3NormalTabConfigurationAttachmentRequest(
            owner: nil,
            extensionsModuleEnabled: true,
            profileHostEnabled: true,
            explicitInternalNormalTabAttachmentAllowed: true,
            surface: .pinnedEssentialsLiveNormalBrowsing
        )
        let previewRequest = ChromeMV3NormalTabConfigurationAttachmentRequest(
            owner: nil,
            extensionsModuleEnabled: true,
            profileHostEnabled: true,
            explicitInternalNormalTabAttachmentAllowed: true,
            surface: .peekGlancePreview
        )

        XCTAssertFalse(liveRequest.emptyControllerOwnerPresent)
        XCTAssertFalse(liveRequest.targetIsLiveNormalTab)
        XCTAssertTrue(liveRequest.targetIsPinnedEssentialsLiveNormalBrowsing)
        XCTAssertFalse(liveRequest.targetIsLauncherMetadata)
        XCTAssertFalse(liveRequest.targetIsPreviewHelperMiniFaviconDownloadAuxiliary)
        XCTAssertFalse(liveRequest.runtimeLoadable)
        XCTAssertFalse(liveRequest.canLoadContextNow)

        XCTAssertEqual(previewRequest.targetSurface, .peekGlancePreview)
        XCTAssertFalse(previewRequest.targetIsLiveNormalTab)
        XCTAssertFalse(previewRequest.targetIsPinnedEssentialsLiveNormalBrowsing)
        XCTAssertTrue(previewRequest.targetIsPreviewHelperMiniFaviconDownloadAuxiliary)
        XCTAssertFalse(previewRequest.runtimeLoadable)
        XCTAssertFalse(previewRequest.canLoadContextNow)
    }

    @MainActor
    func testLiveNormalTabDisabledModuleRemainsUnattachedAndCreatesNoRuntime()
        throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 WebKit attachment APIs require macOS 15.5.")
        }

        let fixture = try makeLiveTabFixture(extensionsEnabled: false)
        defer { fixture.tearDown() }
        fixture.module.chromeMV3InternalNormalTabConfigurationAttachmentAllowed = true

        let tab = fixture.makeTab()
        let webView = try XCTUnwrap(
            tab.makeNormalTabWebView(reason: "test.disabled.live")
        )

        XCTAssertEqual(tab.chromeMV3NormalTabAttachmentSurface, .normalTab)
        XCTAssertNil(webView.configuration.webExtensionController)
        XCTAssertFalse(
            webView.configuration.sumiHasChromeMV3NormalTabConfigurationAttachment
        )
        XCTAssertEqual(fixture.probe.profileProviderCount, 0)
        XCTAssertEqual(fixture.probe.ownerFactoryCount, 0)
        XCTAssertEqual(fixture.probe.managerCount, 0)
        XCTAssertNil(
            fixture.module.chromeMV3LiveNormalTabAttachmentDiagnosticsSnapshot()
        )
        XCTAssertFalse(fixture.module.hasLoadedRuntime)
    }

    @MainActor
    func testLiveNormalTabEnabledInternalGateOffRemainsUnattached()
        throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 WebKit attachment APIs require macOS 15.5.")
        }

        let fixture = try makeLiveTabFixture(extensionsEnabled: true)
        defer { fixture.tearDown() }
        let owner = try XCTUnwrap(
            fixture.module.createChromeMV3EmptyControllerOwnerIfEnabled(
                explicitControllerCreationAllowed: true
            )
        )

        let tab = fixture.makeTab()
        let webView = try XCTUnwrap(
            tab.makeNormalTabWebView(reason: "test.enabled.gateOff.live")
        )

        XCTAssertNotNil(owner.controller)
        XCTAssertNil(webView.configuration.webExtensionController)
        XCTAssertFalse(
            webView.configuration.sumiHasChromeMV3NormalTabConfigurationAttachment
        )
        XCTAssertEqual(owner.diagnostics().contextCount, 0)
        XCTAssertEqual(owner.diagnostics().loadedExtensionCount, 0)
        XCTAssertEqual(owner.diagnostics().nativeMessagingPortCount, 0)
        XCTAssertEqual(fixture.probe.ownerFactoryCount, 1)
        XCTAssertEqual(fixture.probe.managerCount, 0)
        XCTAssertFalse(fixture.module.hasLoadedRuntime)
    }

    @MainActor
    func testLiveNormalTabEnabledInternalGateAttachesSameEmptyController()
        throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 WebKit attachment APIs require macOS 15.5.")
        }

        let fixture = try makeLiveTabFixture(extensionsEnabled: true)
        defer { fixture.tearDown() }
        fixture.module.chromeMV3InternalNormalTabConfigurationAttachmentAllowed = true
        let owner = try XCTUnwrap(
            fixture.module.createChromeMV3EmptyControllerOwnerIfEnabled(
                explicitControllerCreationAllowed: true
            )
        )
        let controller = try XCTUnwrap(owner.controller)

        let tab = fixture.makeTab()
        let webView = try XCTUnwrap(
            tab.makeNormalTabWebView(reason: "test.enabled.gateOn.live")
        )
        let attachedController = try XCTUnwrap(
            webView.configuration.webExtensionController
        )

        XCTAssertEqual(
            ObjectIdentifier(attachedController),
            ObjectIdentifier(controller)
        )
        XCTAssertEqual(tab.chromeMV3NormalTabAttachmentSurface, .normalTab)
        XCTAssertEqual(owner.diagnostics().contextCount, 0)
        XCTAssertEqual(owner.diagnostics().loadedExtensionCount, 0)
        XCTAssertEqual(owner.diagnostics().nativeMessagingPortCount, 0)
        XCTAssertFalse(owner.diagnostics().runtimeLoadable)
        XCTAssertFalse(owner.diagnostics().canLoadContextNow)
        XCTAssertEqual(fixture.probe.managerCount, 0)
        XCTAssertFalse(fixture.module.hasLoadedRuntime)
    }

    @MainActor
    func testLiveNormalTabAttachmentRecorderCapturesDecisionMetadata()
        throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 WebKit attachment APIs require macOS 15.5.")
        }

        let fixture = try makeLiveTabFixture(extensionsEnabled: true)
        defer { fixture.tearDown() }
        fixture.module.chromeMV3InternalNormalTabConfigurationAttachmentAllowed = true
        let owner = try XCTUnwrap(
            fixture.module.createChromeMV3EmptyControllerOwnerIfEnabled(
                explicitControllerCreationAllowed: true
            )
        )
        let controllerIdentity = try XCTUnwrap(
            owner.diagnostics().dataStoreIdentityPolicy
                .controllerConfigurationIdentityString
        )
        let windowID = UUID()
        let tab = fixture.makeTab()
        tab.primaryWindowId = windowID

        let webView = try XCTUnwrap(
            tab.makeNormalTabWebView(reason: "test.recorder.live")
        )
        let snapshot = try XCTUnwrap(
            fixture.module.chromeMV3LiveNormalTabAttachmentDiagnosticsSnapshot()
        )
        let record = try XCTUnwrap(snapshot.recentDecisions.last)

        XCTAssertNotNil(webView.configuration.webExtensionController)
        XCTAssertEqual(snapshot.recentDecisions.count, 1)
        XCTAssertEqual(snapshot.attachedConfigurationCount, 1)
        XCTAssertEqual(snapshot.createdAttachedWebViewCount, 1)
        XCTAssertEqual(snapshot.staleOrNeedsRecreationCount, 0)
        XCTAssertEqual(snapshot.attachedTabDiagnosticIdentifiers, [
            tab.id.uuidString,
        ])
        XCTAssertFalse(snapshot.accidentallyAttachedAuxiliarySurface)
        XCTAssertFalse(snapshot.runtimeLoadable)
        XCTAssertFalse(snapshot.canLoadContextNow)
        XCTAssertEqual(snapshot.contextCount, 0)
        XCTAssertFalse(snapshot.contextLoadCalled)
        XCTAssertFalse(snapshot.webExtensionCreated)
        XCTAssertFalse(snapshot.webExtensionContextCreated)
        XCTAssertFalse(snapshot.generatedExtensionBundleLoaded)
        XCTAssertFalse(snapshot.nativeMessagingLaunched)

        XCTAssertEqual(record.sequenceNumber, 1)
        XCTAssertEqual(record.tabIdentifier, tab.id.uuidString)
        XCTAssertEqual(record.tabDiagnosticIdentifier, tab.id.uuidString)
        XCTAssertEqual(record.windowIdentifier, windowID.uuidString)
        XCTAssertEqual(record.profileIdentifier, fixture.profile.id.uuidString)
        XCTAssertEqual(record.creationReason, "test.recorder.live")
        XCTAssertEqual(record.surface, .normalTab)
        XCTAssertTrue(record.extensionsModuleEnabled)
        XCTAssertTrue(record.profileHostEnabled)
        XCTAssertEqual(record.emptyControllerState, .createdEmpty)
        XCTAssertTrue(record.emptyControllerOwnerPresent)
        XCTAssertTrue(record.emptyControllerExists)
        XCTAssertTrue(record.explicitInternalNormalTabAttachmentAllowed)
        XCTAssertTrue(record.gateDecision.canAttachNormalTabConfigurationNow)
        XCTAssertTrue(record.normalTabConfigurationAttached)
        XCTAssertFalse(record.auxiliaryConfigurationAttached)
        XCTAssertTrue(record.attachedControllerMatchesOwner)
        XCTAssertEqual(record.attachedControllerIdentity, controllerIdentity)
        XCTAssertEqual(record.lifecycleState, .attached)
        XCTAssertFalse(record.recreationPlan.recreationRequired)
        XCTAssertFalse(record.runtimeLoadable)
        XCTAssertFalse(record.canLoadContextNow)
        XCTAssertEqual(record.contextCount, 0)
        XCTAssertFalse(record.contextLoadCalled)
        XCTAssertFalse(record.webExtensionCreated)
        XCTAssertFalse(record.webExtensionContextCreated)
        XCTAssertFalse(record.generatedExtensionBundleLoaded)
        XCTAssertFalse(record.nativeMessagingLaunched)
        XCTAssertEqual(record.nativeMessagingPortCount, 0)
    }

    @MainActor
    func testGateOffMarksExistingAttachedWebViewStaleAndFutureTabsUnattached()
        throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 WebKit attachment APIs require macOS 15.5.")
        }

        let fixture = try makeLiveTabFixture(extensionsEnabled: true)
        defer { fixture.tearDown() }
        fixture.module.chromeMV3InternalNormalTabConfigurationAttachmentAllowed = true
        _ = try XCTUnwrap(
            fixture.module.createChromeMV3EmptyControllerOwnerIfEnabled(
                explicitControllerCreationAllowed: true
            )
        )
        let attachedTab = fixture.makeTab(url: URL(string: "https://one.example")!)
        let attachedWebView = try XCTUnwrap(
            attachedTab.makeNormalTabWebView(reason: "test.gateOff.before")
        )

        XCTAssertNotNil(attachedWebView.configuration.webExtensionController)

        fixture.module.chromeMV3InternalNormalTabConfigurationAttachmentAllowed = false
        let staleSnapshot = try XCTUnwrap(
            fixture.module.chromeMV3LiveNormalTabAttachmentDiagnosticsSnapshot()
        )
        let staleRecord = try XCTUnwrap(staleSnapshot.recentDecisions.first)

        XCTAssertNotNil(
            attachedWebView.configuration.webExtensionController,
            "Existing WKWebViews are not claimed detached when the gate turns off."
        )
        XCTAssertEqual(staleSnapshot.createdAttachedWebViewCount, 0)
        XCTAssertEqual(staleSnapshot.staleOrNeedsRecreationCount, 1)
        XCTAssertEqual(
            staleSnapshot.staleOrNeedsRecreationTabDiagnosticIdentifiers,
            [attachedTab.id.uuidString]
        )
        XCTAssertEqual(staleRecord.lifecycleState, .staleNeedsRecreation)
        XCTAssertTrue(staleRecord.recreationPlan.recreationRequired)
        XCTAssertEqual(
            staleRecord.teardownTrigger,
            .normalTabAttachmentGateOff
        )

        let laterTab = fixture.makeTab(url: URL(string: "https://two.example")!)
        let laterWebView = try XCTUnwrap(
            laterTab.makeNormalTabWebView(reason: "test.gateOff.after")
        )
        let finalSnapshot = try XCTUnwrap(
            fixture.module.chromeMV3LiveNormalTabAttachmentDiagnosticsSnapshot()
        )
        let laterRecord = try XCTUnwrap(finalSnapshot.recentDecisions.last)

        XCTAssertNil(laterWebView.configuration.webExtensionController)
        XCTAssertFalse(
            laterWebView.configuration.sumiHasChromeMV3NormalTabConfigurationAttachment
        )
        XCTAssertEqual(finalSnapshot.recentDecisions.count, 2)
        XCTAssertFalse(laterRecord.normalTabConfigurationAttached)
        XCTAssertEqual(laterRecord.lifecycleState, .unaffected)
        XCTAssertTrue(
            laterRecord.gateDecision.blockers.contains(
                .explicitInternalNormalTabAttachmentNotAllowed
            )
        )
    }

    @MainActor
    func testLivePinnedEssentialsTabFollowsNormalTabAttachmentGate()
        throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 WebKit attachment APIs require macOS 15.5.")
        }

        let fixture = try makeLiveTabFixture(extensionsEnabled: true)
        defer { fixture.tearDown() }
        fixture.module.chromeMV3InternalNormalTabConfigurationAttachmentAllowed = true
        let owner = try XCTUnwrap(
            fixture.module.createChromeMV3EmptyControllerOwnerIfEnabled(
                explicitControllerCreationAllowed: true
            )
        )
        let controller = try XCTUnwrap(owner.controller)
        let pin = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: fixture.profile.id,
            index: 0,
            launchURL: URL(string: "https://pinned.example")!,
            title: "Pinned"
        )
        let originalPinId = pin.id
        let originalPinRole = pin.role
        let originalPinIndex = pin.index
        let originalLaunchURL = pin.launchURL
        let originalTitle = pin.title

        let tab = fixture.makeTab(url: pin.launchURL)
        tab.bindToShortcutPin(pin)
        let webView = try XCTUnwrap(
            tab.makeNormalTabWebView(reason: "test.pinned.live")
        )
        let attachedController = try XCTUnwrap(
            webView.configuration.webExtensionController
        )

        XCTAssertEqual(
            tab.chromeMV3NormalTabAttachmentSurface,
            .pinnedEssentialsLiveNormalBrowsing
        )
        XCTAssertEqual(
            ObjectIdentifier(attachedController),
            ObjectIdentifier(controller)
        )
        XCTAssertEqual(owner.diagnostics().contextCount, 0)
        XCTAssertFalse(owner.diagnostics().runtimeLoadable)
        XCTAssertFalse(owner.diagnostics().canLoadContextNow)

        fixture.module.chromeMV3InternalNormalTabConfigurationAttachmentAllowed = false
        let snapshot = try XCTUnwrap(
            fixture.module.chromeMV3LiveNormalTabAttachmentDiagnosticsSnapshot()
        )

        XCTAssertEqual(snapshot.staleOrNeedsRecreationCount, 1)
        XCTAssertEqual(pin.id, originalPinId)
        XCTAssertEqual(pin.role, originalPinRole)
        XCTAssertEqual(pin.index, originalPinIndex)
        XCTAssertEqual(pin.launchURL, originalLaunchURL)
        XCTAssertEqual(pin.title, originalTitle)
    }

    @MainActor
    func testGlancePreviewLivePathRemainsUnattachedDespiteInternalGate()
        async throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 WebKit attachment APIs require macOS 15.5.")
        }

        let fixture = try makeLiveTabFixture(extensionsEnabled: true)
        defer { fixture.tearDown() }
        fixture.module.chromeMV3InternalNormalTabConfigurationAttachmentAllowed = true
        _ = try XCTUnwrap(
            fixture.module.createChromeMV3EmptyControllerOwnerIfEnabled(
                explicitControllerCreationAllowed: true
            )
        )
        let sourceTab = fixture.makeTab(url: URL(string: "https://source.example")!)

        fixture.browserManager.glanceManager.presentExternalURL(
            URL(string: "https://preview.example")!,
            from: sourceTab
        )
        let session = try XCTUnwrap(
            fixture.browserManager.glanceManager.currentSession
        )
        let webView = try await waitForPreviewWebView(in: session)

        XCTAssertEqual(
            session.previewTab.chromeMV3AttachmentSurfaceOverride,
            .peekGlancePreview
        )
        XCTAssertNil(webView.configuration.webExtensionController)
        XCTAssertFalse(
            webView.configuration.sumiHasChromeMV3NormalTabConfigurationAttachment
        )
        XCTAssertEqual(fixture.probe.managerCount, 0)
        XCTAssertFalse(fixture.module.hasLoadedRuntime)
    }

    @MainActor
    func testLiveNormalTabAfterTeardownReturnsToUnattachedBehavior()
        throws
    {
        guard #available(macOS 15.5, *) else {
            throw XCTSkip("Chrome MV3 WebKit attachment APIs require macOS 15.5.")
        }

        let fixture = try makeLiveTabFixture(extensionsEnabled: true)
        defer { fixture.tearDown() }
        fixture.module.chromeMV3InternalNormalTabConfigurationAttachmentAllowed = true
        _ = try XCTUnwrap(
            fixture.module.createChromeMV3EmptyControllerOwnerIfEnabled(
                explicitControllerCreationAllowed: true
            )
        )

        let attachedTab = fixture.makeTab(url: URL(string: "https://one.example")!)
        let attachedWebView = try XCTUnwrap(
            attachedTab.makeNormalTabWebView(reason: "test.teardown.before")
        )
        XCTAssertNotNil(attachedWebView.configuration.webExtensionController)

        let teardown = try XCTUnwrap(
            fixture.module.tearDownChromeMV3EmptyControllerOwnerIfEnabled(
                trigger: .explicitReset
            )
        )
        let teardownPolicy = try XCTUnwrap(teardown.teardownPolicy)
        let staleSnapshot = try XCTUnwrap(
            fixture.module.chromeMV3LiveNormalTabAttachmentDiagnosticsSnapshot()
        )
        let laterTab = fixture.makeTab(url: URL(string: "https://two.example")!)
        let laterWebView = try XCTUnwrap(
            laterTab.makeNormalTabWebView(reason: "test.teardown.after")
        )

        XCTAssertNotNil(
            attachedWebView.configuration.webExtensionController,
            "Teardown does not prove an already-created WKWebView detached."
        )
        XCTAssertNil(laterWebView.configuration.webExtensionController)
        XCTAssertFalse(
            laterWebView.configuration.sumiHasChromeMV3NormalTabConfigurationAttachment
        )
        XCTAssertEqual(staleSnapshot.staleOrNeedsRecreationCount, 1)
        XCTAssertEqual(
            staleSnapshot.staleOrNeedsRecreationTabDiagnosticIdentifiers,
            [attachedTab.id.uuidString]
        )
        XCTAssertTrue(
            teardownPolicy.futureConfigurationsBecomeUnattachedImmediately
        )
        XCTAssertTrue(teardownPolicy.marksExistingDebugAttachedWebViewsStale)
        XCTAssertFalse(teardownPolicy.claimsExistingWebViewsDetached)
        XCTAssertTrue(
            teardownPolicy
                .requiresWebViewRecreationForExistingDebugAttachedInstances
        )
        XCTAssertFalse(teardownPolicy.shouldDeleteGeneratedArtifacts)
        XCTAssertFalse(teardownPolicy.shouldClearWebsiteData)
        XCTAssertEqual(fixture.probe.managerCount, 0)
        XCTAssertFalse(fixture.module.hasLoadedRuntime)
    }

    @MainActor
    func testPinnedEssentialsLiveNormalBrowsingFollowsNormalTabGate()
        throws
    {
        let fixture = try makeModuleFixture(extensionsEnabled: true)
        defer { fixture.tearDown() }
        let owner = try XCTUnwrap(
            fixture.module.createChromeMV3EmptyControllerOwnerIfEnabled(
                explicitControllerCreationAllowed: true
            )
        )
        let controller = try XCTUnwrap(owner.controller)
        let request = try XCTUnwrap(
            fixture.module
                .chromeMV3NormalTabConfigurationAttachmentRequestIfEnabled(
                    explicitInternalNormalTabAttachmentAllowed: true,
                    surface: .pinnedEssentialsLiveNormalBrowsing
                )
        )

        let result = fixture.browserConfiguration
            .normalTabWebViewConfigurationWithChromeMV3AttachmentGate(
                for: fixture.profile,
                url: URL(string: "https://example.com"),
                chromeMV3AttachmentRequest: request
            )
        let attachedController = try XCTUnwrap(
            result.configuration.webExtensionController
        )

        XCTAssertEqual(
            ObjectIdentifier(attachedController),
            ObjectIdentifier(controller)
        )
        XCTAssertEqual(
            result.diagnostics.gateDecision.input.surface,
            .pinnedEssentialsLiveNormalBrowsing
        )
        XCTAssertTrue(result.diagnostics.normalTabConfigurationAttached)
        XCTAssertEqual(result.diagnostics.contextCount, 0)
        XCTAssertFalse(result.diagnostics.canLoadContextNow)
    }

    @MainActor
    func testLauncherPreviewMiniFaviconDownloadHelperAndExtensionUISurfacesDoNotAttach()
        throws
    {
        let fixture = try makeModuleFixture(extensionsEnabled: true)
        defer { fixture.tearDown() }
        _ = try XCTUnwrap(
            fixture.module.createChromeMV3EmptyControllerOwnerIfEnabled(
                explicitControllerCreationAllowed: true
            )
        )
        let browserConfiguration = fixture.browserConfiguration
        let normalConfiguration = browserConfiguration.normalTabWebViewConfiguration(
            for: fixture.profile,
            url: URL(string: "https://example.com")
        )
        let auxiliaryConfigurations: [(ChromeMV3WebViewSurface, WKWebViewConfiguration)] = [
            (
                .peekGlancePreview,
                browserConfiguration.auxiliaryWebViewConfiguration(
                    surface: .glance
                )
            ),
            (
                .miniWindow,
                browserConfiguration.auxiliaryWebViewConfiguration(
                    surface: .miniWindow
                )
            ),
            (
                .faviconDownload,
                browserConfiguration.auxiliaryWebViewConfiguration(
                    surface: .faviconDownload
                )
            ),
            (
                .downloadHelper,
                browserConfiguration.auxiliaryWebViewConfiguration(
                    surface: .faviconDownload
                )
            ),
            (
                .helperWebView,
                browserConfiguration.auxiliaryWebViewConfiguration(
                    surface: .miniWindow
                )
            ),
            (
                .extensionOwnedPopup,
                browserConfiguration.auxiliaryWebViewConfiguration(
                    surface: .extensionOptions
                )
            ),
            (
                .extensionOwnedOptionsPage,
                browserConfiguration.auxiliaryWebViewConfiguration(
                    surface: .extensionOptions
                )
            ),
        ]

        let launcherRequest = try XCTUnwrap(
            fixture.module
                .chromeMV3NormalTabConfigurationAttachmentRequestIfEnabled(
                    explicitInternalNormalTabAttachmentAllowed: true,
                    surface: .pinnedEssentialsLauncherMetadata
                )
        )
        let launcherDiagnostics =
            ChromeMV3NormalTabConfigurationAttachmentBridge.attachIfAllowed(
                configuration: normalConfiguration,
                request: launcherRequest
            )
        XCTAssertNil(normalConfiguration.webExtensionController)
        XCTAssertFalse(launcherDiagnostics.normalTabConfigurationAttached)
        XCTAssertTrue(
            launcherDiagnostics.gateDecision.blockers
                .contains(.launcherMetadataSurface)
        )

        for (surface, configuration) in auxiliaryConfigurations {
            let request = try XCTUnwrap(
                fixture.module
                    .chromeMV3NormalTabConfigurationAttachmentRequestIfEnabled(
                        explicitInternalNormalTabAttachmentAllowed: true,
                        surface: surface
                    )
            )
            let diagnostics =
                ChromeMV3NormalTabConfigurationAttachmentBridge
                    .attachIfAllowed(
                        configuration: configuration,
                        request: request
                    )

            XCTAssertNil(configuration.webExtensionController, surface.rawValue)
            XCTAssertFalse(
                diagnostics.normalTabConfigurationAttached,
                surface.rawValue
            )
            XCTAssertFalse(
                diagnostics.auxiliaryConfigurationAttached,
                surface.rawValue
            )
            XCTAssertFalse(
                diagnostics.gateDecision.canAttachNormalTabConfigurationNow,
                surface.rawValue
            )
            XCTAssertFalse(
                diagnostics.gateDecision.canAttachAuxiliaryConfigurationNow,
                surface.rawValue
            )
            XCTAssertEqual(diagnostics.contextCount, 0, surface.rawValue)
            XCTAssertEqual(diagnostics.loadedExtensionCount, 0, surface.rawValue)
        }

        let snapshot = try XCTUnwrap(
            fixture.module.chromeMV3LiveNormalTabAttachmentDiagnosticsSnapshot()
        )
        XCTAssertFalse(snapshot.accidentallyAttachedAuxiliarySurface)
        XCTAssertTrue(snapshot.auxiliaryAttachmentSequenceNumbers.isEmpty)
    }

    @MainActor
    func testExtensionOptionsLegacyCopyDoesNotPropagateMarkedChromeMV3NormalTabAttachment()
        throws
    {
        let fixture = try makeModuleFixture(extensionsEnabled: true)
        defer { fixture.tearDown() }
        _ = try XCTUnwrap(
            fixture.module.createChromeMV3EmptyControllerOwnerIfEnabled(
                explicitControllerCreationAllowed: true
            )
        )
        let request = try XCTUnwrap(
            fixture.module
                .chromeMV3NormalTabConfigurationAttachmentRequestIfEnabled(
                    explicitInternalNormalTabAttachmentAllowed: true
                )
        )
        let attachedNormal = fixture.browserConfiguration
            .normalTabWebViewConfigurationWithChromeMV3AttachmentGate(
                for: fixture.profile,
                url: URL(string: "https://example.com"),
                chromeMV3AttachmentRequest: request
            )

        let optionsConfiguration = fixture.browserConfiguration
            .auxiliaryWebViewConfiguration(
                from: attachedNormal.configuration,
                surface: .extensionOptions
            )
        let snapshot = try XCTUnwrap(
            fixture.module.chromeMV3LiveNormalTabAttachmentDiagnosticsSnapshot()
        )

        XCTAssertNotNil(attachedNormal.configuration.webExtensionController)
        XCTAssertTrue(
            attachedNormal.configuration
                .sumiHasChromeMV3NormalTabConfigurationAttachment
        )
        XCTAssertNil(optionsConfiguration.webExtensionController)
        XCTAssertFalse(
            optionsConfiguration.sumiHasChromeMV3NormalTabConfigurationAttachment
        )
        XCTAssertFalse(optionsConfiguration.sumiIsNormalTabWebViewConfiguration)
        XCTAssertEqual(snapshot.recentDecisions.count, 1)
        XCTAssertEqual(snapshot.attachedConfigurationCount, 1)
        XCTAssertFalse(snapshot.accidentallyAttachedAuxiliarySurface)
    }

    @MainActor
    func testTeardownResetsTrackedNormalTabConfigurationAndFutureDiagnosticsBlock()
        throws
    {
        let fixture = try makeModuleFixture(extensionsEnabled: true)
        defer { fixture.tearDown() }
        _ = try XCTUnwrap(
            fixture.module.createChromeMV3EmptyControllerOwnerIfEnabled(
                explicitControllerCreationAllowed: true
            )
        )
        let request = try XCTUnwrap(
            fixture.module
                .chromeMV3NormalTabConfigurationAttachmentRequestIfEnabled(
                    explicitInternalNormalTabAttachmentAllowed: true
                )
        )
        let result = fixture.browserConfiguration
            .normalTabWebViewConfigurationWithChromeMV3AttachmentGate(
                for: fixture.profile,
                url: URL(string: "https://example.com"),
                chromeMV3AttachmentRequest: request
            )

        XCTAssertNotNil(result.configuration.webExtensionController)
        XCTAssertTrue(
            result.configuration.sumiHasChromeMV3NormalTabConfigurationAttachment
        )

        let teardown = try XCTUnwrap(
            fixture.module.tearDownChromeMV3EmptyControllerOwnerIfEnabled(
                trigger: .moduleDisable
            )
        )
        let postTeardownRequest = try XCTUnwrap(
            fixture.module
                .chromeMV3NormalTabConfigurationAttachmentRequestIfEnabled(
                    explicitInternalNormalTabAttachmentAllowed: true
                )
        )
        let diagnostics =
            ChromeMV3NormalTabConfigurationAttachmentBridge.inspect(
                configuration: result.configuration,
                request: postTeardownRequest
            )

        XCTAssertNil(result.configuration.webExtensionController)
        XCTAssertFalse(
            result.configuration.sumiHasChromeMV3NormalTabConfigurationAttachment
        )
        XCTAssertEqual(teardown.contextCount, 0)
        XCTAssertEqual(teardown.loadedExtensionCount, 0)
        XCTAssertEqual(teardown.nativeMessagingPortCount, 0)
        XCTAssertFalse(diagnostics.normalTabConfigurationAttached)
        XCTAssertTrue(
            diagnostics.gateDecision.blockers.contains(.emptyControllerMissing)
        )
        XCTAssertFalse(diagnostics.runtimeLoadable)
        XCTAssertFalse(diagnostics.canLoadContextNow)
    }

    func testGateBlocksContextLoadabilityAndRuntimeReadinessRequests() {
        let requested = !false
        let contextDecision = ChromeMV3NormalTabConfigurationAttachmentGate
            .evaluate(
                input: gateInput(
                    requestedContextLoading: requested
                )
            )
        let loadCapabilityDecision = ChromeMV3NormalTabConfigurationAttachmentGate
            .evaluate(
                input: gateInput(
                    canLoadContextNow: requested
                )
            )
        let loadabilityDecision = ChromeMV3NormalTabConfigurationAttachmentGate
            .evaluate(
                input: gateInput(
                    runtimeLoadable: requested
                )
            )

        XCTAssertFalse(
            contextDecision.canAttachNormalTabConfigurationNow
        )
        XCTAssertTrue(
            contextDecision.blockers.contains(.contextLoadingRequested)
        )
        XCTAssertFalse(contextDecision.canLoadContextNow)
        XCTAssertFalse(contextDecision.runtimeLoadable)

        XCTAssertFalse(
            loadCapabilityDecision.canAttachNormalTabConfigurationNow
        )
        XCTAssertTrue(
            loadCapabilityDecision.blockers.contains(
                .contextLoadingCapabilityEnabled
            )
        )
        XCTAssertFalse(loadCapabilityDecision.canLoadContextNow)

        XCTAssertFalse(loadabilityDecision.canAttachNormalTabConfigurationNow)
        XCTAssertTrue(
            loadabilityDecision.blockers.contains(.runtimeLoadableRequested)
        )
        XCTAssertFalse(loadabilityDecision.runtimeLoadable)
    }

    func testSourceGuardForNormalTabAttachmentBoundary() throws {
        let sourceFiles = try Self.sourceFiles(in: [
            "Sumi/Models/Extension/ChromeMV3",
            "Sumi/Models/BrowserConfig",
            "Sumi/Models/Tab",
            "Sumi/Components/MiniWindow",
            "Sumi/Favicons",
            "Sumi/Managers/GlanceManager",
        ])
        let assignmentFiles = sourceFiles
            .filter { Self.containsWebViewControllerAssignment($0.contents) }
            .map(\.relativePath)
            .sorted()

        XCTAssertEqual(
            assignmentFiles,
            [
                "Sumi/Models/BrowserConfig/BrowserConfig.swift",
                "Sumi/Models/Extension/ChromeMV3/ChromeMV3NormalTabConfigurationAttachmentBridge.swift",
                "Sumi/Models/Extension/ChromeMV3/ChromeMV3SyntheticConfigurationAttachmentHarness.swift",
            ]
        )

        let chromeMV3Source = try Self.sourceFiles(in: [
            "Sumi/Models/Extension/ChromeMV3",
        ])
        let extensionObjectInitializerFiles = chromeMV3Source
            .filter { $0.contents.contains("WKWebExtension" + "(") }
            .map(\.relativePath)
            .sorted()

        XCTAssertEqual(
            extensionObjectInitializerFiles,
            [
                "Sumi/Models/Extension/ChromeMV3/ChromeMV3ExtensionObjectProbeRunner.swift",
            ]
        )

        let syntheticBridgeScopedFiles: Set<String> = [
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3RuntimeJSMessagingMVP.swift",
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3TabsScriptingJSMVP.swift",
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3StorageLocalRuntime.swift",
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3PasswordManagerSyntheticFixture.swift",
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3ExtensionEventAPIsRuntime.swift",
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3SidePanelOffscreenIdentitySyntheticWebKitHarness.swift",
            "Sumi/Models/Extension/ChromeMV3/ChromeMV3NativeMessagingInternalRuntime.swift",
        ]
        let source = chromeMV3Source
            .filter { syntheticBridgeScopedFiles.contains($0.relativePath) == false }
            .map(\.contents)
            .joined(separator: "\n")
        for forbidden in [
            "WKWebExtension" + "Context(",
            "load" + "ExtensionContext",
            "add" + "UserScript",
            "connect" + "Native",
            "DispatchSource" + "Ti" + "mer",
            "scheduled" + "Ti" + "mer",
            "Ti" + "mer",
            "poll" + "ing",
        ] {
            XCTAssertFalse(source.contains(forbidden), forbidden)
        }
    }

    private static func containsWebViewControllerAssignment(
        _ contents: String
    ) -> Bool {
        [
            "configuration.webExtensionController" + " =",
            "config.webExtensionController" + " =",
            "result.configuration?.webExtensionController" + " =",
        ].contains { contents.contains($0) }
    }

    private func gateInput(
        extensionsModuleEnabled: Bool = true,
        profileHostEnabled: Bool = true,
        emptyControllerExists: Bool = true,
        explicitInternalNormalTabAttachmentAllowed: Bool = true,
        surface: ChromeMV3WebViewSurface = .normalTab,
        isRealNormalTabConfiguration: Bool = true,
        configurationHasControllerAttachment: Bool = false,
        requestedContextLoading: Bool = false,
        canLoadContextNow: Bool = false,
        runtimeLoadable: Bool = false,
        contextCount: Int = 0,
        loadedExtensionCount: Int = 0,
        nativeMessagingPortCount: Int = 0
    ) -> ChromeMV3NormalTabConfigurationAttachmentGateInput {
        ChromeMV3NormalTabConfigurationAttachmentGateInput(
            extensionsModuleEnabled: extensionsModuleEnabled,
            profileHostEnabled: profileHostEnabled,
            emptyControllerExists: emptyControllerExists,
            explicitInternalNormalTabAttachmentAllowed:
                explicitInternalNormalTabAttachmentAllowed,
            surface: surface,
            isRealNormalTabConfiguration: isRealNormalTabConfiguration,
            configurationHasControllerAttachment:
                configurationHasControllerAttachment,
            requestedContextLoading: requestedContextLoading,
            canLoadContextNow: canLoadContextNow,
            runtimeLoadable: runtimeLoadable,
            contextCount: contextCount,
            loadedExtensionCount: loadedExtensionCount,
            nativeMessagingPortCount: nativeMessagingPortCount
        )
    }

    @MainActor
    private func makeModuleFixture(
        extensionsEnabled: Bool
    ) throws -> ChromeMV3NormalTabAttachmentModuleFixture {
        let harness = TestDefaultsHarness()
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        if extensionsEnabled {
            registry.enable(.extensions)
        }
        let container = try ModelContainer(
            for: Schema([ExtensionEntity.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let browserConfiguration = BrowserConfiguration()
        let profile = Profile(name: "Chrome MV3 Normal Attachment Test")
        let probe = ChromeMV3NormalTabAttachmentModuleProbe()
        let module = SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            browserConfiguration: browserConfiguration,
            initialProfileProvider: {
                probe.profileProviderCount += 1
                return profile
            },
            managerFactory: { context, initialProfile, browserConfiguration in
                probe.managerCount += 1
                return ExtensionManager(
                    context: context,
                    initialProfile: initialProfile,
                    browserConfiguration: browserConfiguration
                )
            },
            chromeMV3EmptyControllerOwnerFactory: { decision, dataStore, identifier in
                probe.ownerFactoryCount += 1
                return ChromeMV3EmptyControllerFactory.makeOwner(
                    gateDecision: decision,
                    defaultWebsiteDataStore: dataStore,
                    controllerIdentifier: identifier
                )
            }
        )

        return ChromeMV3NormalTabAttachmentModuleFixture(
            defaultsHarness: harness,
            browserConfiguration: browserConfiguration,
            profile: profile,
            module: module,
            probe: probe
        )
    }

    @MainActor
    private func makeLiveTabFixture(
        extensionsEnabled: Bool
    ) throws -> ChromeMV3LiveNormalTabAttachmentFixture {
        let harness = TestDefaultsHarness()
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        if extensionsEnabled {
            registry.enable(.extensions)
        }
        let container = try ModelContainer(
            for: Schema([ExtensionEntity.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let browserConfiguration = BrowserConfiguration()
        let profile = Profile(name: "Chrome MV3 Live Normal Attachment Test")
        let probe = ChromeMV3NormalTabAttachmentModuleProbe()
        let module = SumiExtensionsModule(
            moduleRegistry: registry,
            context: container.mainContext,
            browserConfiguration: browserConfiguration,
            initialProfileProvider: {
                probe.profileProviderCount += 1
                return profile
            },
            managerFactory: { context, initialProfile, browserConfiguration in
                probe.managerCount += 1
                return ExtensionManager(
                    context: context,
                    initialProfile: initialProfile,
                    browserConfiguration: browserConfiguration
                )
            },
            chromeMV3EmptyControllerOwnerFactory: { decision, dataStore, identifier in
                probe.ownerFactoryCount += 1
                return ChromeMV3EmptyControllerFactory.makeOwner(
                    gateDecision: decision,
                    defaultWebsiteDataStore: dataStore,
                    controllerIdentifier: identifier
                )
            }
        )
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            extensionsModule: module
        )
        browserManager.profileManager.profiles = [profile]
        browserManager.currentProfile = profile

        return ChromeMV3LiveNormalTabAttachmentFixture(
            defaultsHarness: harness,
            container: container,
            browserConfiguration: browserConfiguration,
            profile: profile,
            module: module,
            browserManager: browserManager,
            probe: probe
        )
    }

    @MainActor
    private func waitForPreviewWebView(
        in session: GlanceSession
    ) async throws -> WKWebView {
        for _ in 0..<100 {
            if let webView = session.previewTab.existingWebView {
                return webView
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        return try XCTUnwrap(
            session.previewTab.existingWebView,
            "Timed out waiting for Glance preview WebView."
        )
    }

    private static func sourceFiles(
        in directories: [String]
    ) throws -> [(relativePath: String, contents: String)] {
        try directories.flatMap { directory
            -> [(relativePath: String, contents: String)] in
            let root = repoRoot.appendingPathComponent(directory)
            guard FileManager.default.fileExists(atPath: root.path) else {
                return []
            }
            let urls = FileManager.default
                .enumerator(
                    at: root,
                    includingPropertiesForKeys: nil
                )?
                .compactMap { $0 as? URL } ?? []
            return try urls
                .filter { $0.pathExtension == "swift" }
                .map { url in
                    let relativePath = url.path
                        .replacingOccurrences(
                            of: repoRoot.path + "/",
                            with: ""
                        )
                    return (
                        relativePath,
                        try String(contentsOf: url, encoding: .utf8)
                    )
                }
        }
    }

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

@MainActor
private struct ChromeMV3NormalTabAttachmentModuleFixture {
    let defaultsHarness: TestDefaultsHarness
    let browserConfiguration: BrowserConfiguration
    let profile: Profile
    let module: SumiExtensionsModule
    let probe: ChromeMV3NormalTabAttachmentModuleProbe

    func tearDown() {
        defaultsHarness.reset()
    }
}

@MainActor
private struct ChromeMV3LiveNormalTabAttachmentFixture {
    let defaultsHarness: TestDefaultsHarness
    let container: ModelContainer
    let browserConfiguration: BrowserConfiguration
    let profile: Profile
    let module: SumiExtensionsModule
    let browserManager: BrowserManager
    let probe: ChromeMV3NormalTabAttachmentModuleProbe

    func makeTab(
        url: URL = URL(string: "https://example.com")!
    ) -> Tab {
        let tab = Tab(
            url: url,
            name: url.host ?? "Chrome MV3 Live Normal",
            favicon: "globe",
            index: 0,
            browserManager: browserManager
        )
        tab.profileId = profile.id
        return tab
    }

    func tearDown() {
        _ = module.tearDownChromeMV3EmptyControllerOwnerIfEnabled(
            trigger: .explicitReset
        )
        module.setEnabled(false)
        defaultsHarness.reset()
    }
}

@MainActor
private final class ChromeMV3NormalTabAttachmentModuleProbe {
    var profileProviderCount = 0
    var managerCount = 0
    var ownerFactoryCount = 0
}

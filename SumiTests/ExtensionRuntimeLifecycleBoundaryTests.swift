import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class ExtensionRuntimeLifecycleBoundaryTests: XCTestCase {
    func testNoDemandDoesNotProvisionControllerOrPublishRuntime() {
        let profileID = UUID()
        let harness = DemandHarness(profileID: profileID)

        XCTAssertNil(harness.coordinator.request(reason: .install))
        XCTAssertEqual(harness.provisioning.ensureCount, 0)
        XCTAssertEqual(harness.session.runtimeState, .idle)
        XCTAssertFalse(harness.session.extensionsLoaded)
    }

    func testNoDemandDoesNotSuspendExistingRuntimePublication() {
        let harness = DemandHarness(profileID: UUID())
        harness.session.extensionsLoaded = true

        XCTAssertNil(harness.coordinator.request(reason: .install))
        XCTAssertTrue(harness.session.extensionsLoaded)
        XCTAssertEqual(harness.provisioning.ensureCount, 0)
    }

    func testUnsupportedDemandDoesNotProvisionOrPublishRuntime() {
        let profileID = UUID()
        let harness = DemandHarness(
            profileID: profileID,
            extensionSupportAvailable: false
        )

        XCTAssertNil(
            harness.coordinator.request(
                reason: .install,
                allowWithoutEnabledExtensions: true,
                profileId: profileID
            )
        )
        XCTAssertEqual(harness.provisioning.ensureCount, 0)
        XCTAssertEqual(harness.session.runtimeState, .unavailable)
        XCTAssertFalse(harness.session.extensionsLoaded)
    }

    func testDemandWithoutAnyProfilePreservesFailedStateAndDoesNotProvision() {
        let harness = DemandHarness(profileID: nil)
        harness.session.runtimeState = .failed

        XCTAssertNil(
            harness.coordinator.request(
                reason: .install,
                allowWithoutEnabledExtensions: true
            )
        )
        XCTAssertEqual(harness.provisioning.ensureCount, 0)
        XCTAssertEqual(harness.session.runtimeState, .failed)
        XCTAssertFalse(harness.session.extensionsLoaded)
    }

    func testExplicitDemandIsStickyAndReusesLoadingController() throws {
        let profileID = UUID()
        let harness = DemandHarness(profileID: profileID)
        let initial = try XCTUnwrap(
            harness.coordinator.request(
                reason: .install,
                allowWithoutEnabledExtensions: true,
                profileId: profileID
            )
        )
        harness.session.runtimeState = .loading

        let reused = try XCTUnwrap(
            harness.coordinator.request(
                reason: .install,
                profileId: profileID
            )
        )

        XCTAssertIdentical(reused, initial)
        XCTAssertEqual(harness.provisioning.ensureCount, 2)
        XCTAssertEqual(harness.provisioning.createdControllerCount, 1)
        XCTAssertEqual(harness.session.runtimeState, .loading)
        XCTAssertFalse(harness.session.extensionsLoaded)
    }

    func testABATransitionRejectsStaleImmediateSettlementAndRebindsBaseConfiguration()
        async throws {
        let profileA = UUID()
        let profileB = UUID()
        let profileRuntime = ExtensionProfileRuntime(initialProfileId: profileA)
        let session = ExtensionRuntimeSession()
        session.runtimeState = .ready
        let provisioning = ControllerProvisioningProbe(
            profileRuntime: profileRuntime
        )
        let retirement = InactiveContextRetirementProbe()
        let toolbar = ToolbarProfileReloadProbe()
        let browserConfiguration = BrowserConfiguration()
        var reconciledProfiles: [UUID] = []
        let latestReconciliation = expectation(
            description: "latest ABA transition reconciled"
        )
        var refreshedProfiles: [UUID] = []
        let transition = ExtensionProfileRuntimeTransition(
            installedExtensions: InstalledExtensionCollection(),
            profileRuntime: profileRuntime,
            runtimeSession: session,
            browserConfiguration: browserConfiguration,
            controllerProvisioning: provisioning,
            inactiveContextRetirement: retirement,
            actionAnchors: ExtensionActionPopupAnchorStore(),
            toolbarProfiles: toolbar,
            extensionSupportAvailable: true,
            reconcileProfile: {
                reconciledProfiles.append($0)
                latestReconciliation.fulfill()
            },
            refreshActionSurfaces: { refreshedProfiles.append($0) }
        )

        let staleA = transition.switchProfile(profileID: profileA)
        _ = transition.switchProfile(profileID: profileB)
        let currentA = transition.switchProfile(profileID: profileA)
        transition.settleImmediately(staleA)

        await fulfillment(of: [latestReconciliation], timeout: 1)

        let controllerA = try XCTUnwrap(
            provisioning.controllersByProfile[profileA]
        )
        XCTAssertTrue(transition.isCurrent(currentA))
        XCTAssertEqual(profileRuntime.currentProfileId, profileA)
        XCTAssertIdentical(
            browserConfiguration.webViewConfiguration.webExtensionController,
            controllerA
        )
        XCTAssertEqual(reconciledProfiles, [profileA])
        XCTAssertEqual(refreshedProfiles, [profileA])
        XCTAssertEqual(toolbar.reloadCount, 3)
        XCTAssertEqual(retirement.keptProfileIDs, [profileA, profileB, profileA])
    }

    func testReadyRuntimeBecomesLoadingWhenTargetProfileLacksEnabledContext() {
        let profileA = UUID()
        let profileB = UUID()
        let profileRuntime = ExtensionProfileRuntime(initialProfileId: profileA)
        let session = ExtensionRuntimeSession()
        session.runtimeState = .ready
        let installed = InstalledExtensionCollection()
        installed.connectRecordChanges {}
        installed.upsert(makeInstalledExtension(id: "enabled-runtime"))
        let provisioning = ControllerProvisioningProbe(
            profileRuntime: profileRuntime
        )
        let browserConfiguration = BrowserConfiguration()
        let transition = ExtensionProfileRuntimeTransition(
            installedExtensions: installed,
            profileRuntime: profileRuntime,
            runtimeSession: session,
            browserConfiguration: browserConfiguration,
            controllerProvisioning: provisioning,
            inactiveContextRetirement: InactiveContextRetirementProbe(),
            actionAnchors: ExtensionActionPopupAnchorStore(),
            toolbarProfiles: ToolbarProfileReloadProbe(),
            extensionSupportAvailable: true,
            reconcileProfile: { _ in },
            refreshActionSurfaces: { _ in }
        )

        _ = transition.switchProfile(profileID: profileB)

        XCTAssertEqual(profileRuntime.currentProfileId, profileB)
        XCTAssertEqual(session.runtimeState, .loading)
        XCTAssertIdentical(
            browserConfiguration.webViewConfiguration.webExtensionController,
            provisioning.controllersByProfile[profileB]
        )
    }

    func testDeferredTransitionDoesNotRetainTransitionRole() async {
        let profileID = UUID()
        let profileRuntime = ExtensionProfileRuntime(initialProfileId: profileID)
        let session = ExtensionRuntimeSession()
        session.runtimeState = .ready
        let provisioning = ControllerProvisioningProbe(
            profileRuntime: profileRuntime
        )
        var reconciledProfiles: [UUID] = []
        var transition: ExtensionProfileRuntimeTransition? =
            ExtensionProfileRuntimeTransition(
                installedExtensions: InstalledExtensionCollection(),
                profileRuntime: profileRuntime,
                runtimeSession: session,
                browserConfiguration: BrowserConfiguration(),
                controllerProvisioning: provisioning,
                inactiveContextRetirement: InactiveContextRetirementProbe(),
                actionAnchors: ExtensionActionPopupAnchorStore(),
                toolbarProfiles: ToolbarProfileReloadProbe(),
                extensionSupportAvailable: true,
                reconcileProfile: { reconciledProfiles.append($0) },
                refreshActionSurfaces: { _ in }
            )
        weak var retainedTransition = transition
        _ = transition?.switchProfile(profileID: profileID)

        transition = nil
        await Task.yield()
        await Task.yield()

        XCTAssertNil(retainedTransition)
        XCTAssertTrue(reconciledProfiles.isEmpty)
    }

    func testImmediateSettlementCancelsDeferredDuplicate() async {
        let profileID = UUID()
        let profileRuntime = ExtensionProfileRuntime(initialProfileId: profileID)
        let session = ExtensionRuntimeSession()
        session.runtimeState = .ready
        let provisioning = ControllerProvisioningProbe(
            profileRuntime: profileRuntime
        )
        var reconciledProfiles: [UUID] = []
        var refreshedProfiles: [UUID] = []
        let transition = ExtensionProfileRuntimeTransition(
            installedExtensions: InstalledExtensionCollection(),
            profileRuntime: profileRuntime,
            runtimeSession: session,
            browserConfiguration: BrowserConfiguration(),
            controllerProvisioning: provisioning,
            inactiveContextRetirement: InactiveContextRetirementProbe(),
            actionAnchors: ExtensionActionPopupAnchorStore(),
            toolbarProfiles: ToolbarProfileReloadProbe(),
            extensionSupportAvailable: true,
            reconcileProfile: { reconciledProfiles.append($0) },
            refreshActionSurfaces: { refreshedProfiles.append($0) }
        )
        let receipt = transition.switchProfile(profileID: profileID)

        transition.settleImmediately(receipt)
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(reconciledProfiles, [profileID])
        XCTAssertEqual(refreshedProfiles, [profileID])
    }

    func testCurrentEnabledLoadedContextPublishesRuntime() async throws {
        let fixture = try await makeResidencySettlementFixture(
            extensionID: "current-loaded"
        )

        XCTAssertTrue(
            fixture.residency.settleLoadedContext(fixture.loadedContext)
        )
        XCTAssertTrue(fixture.session.extensionsLoaded)
        XCTAssertEqual(fixture.session.runtimeState, .ready)
    }

    func testSupersededLoadedContextDoesNotPublishRuntime() async throws {
        let fixture = try await makeResidencySettlementFixture(
            extensionID: "superseded-loaded"
        )
        let replacement = WKWebExtensionContext(
            for: fixture.loadedContext.context.webExtension
        )
        _ = fixture.profileRuntime.setContext(
            replacement,
            extensionId: fixture.extensionID,
            profileId: fixture.profileID
        )

        XCTAssertFalse(
            fixture.residency.settleLoadedContext(fixture.loadedContext)
        )
        XCTAssertFalse(fixture.session.extensionsLoaded)
        XCTAssertEqual(fixture.session.runtimeState, .loading)
    }

    private func makeResidencySettlementFixture(
        extensionID: String
    ) async throws -> ResidencySettlementFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try FileManager.default.removeItem(at: directory)
        }
        try JSONSerialization.data(
            withJSONObject: [
                "manifest_version": 3,
                "name": extensionID,
                "version": "1.0.0",
            ],
            options: [.sortedKeys]
        ).write(
            to: directory.appendingPathComponent("manifest.json"),
            options: [.atomic]
        )

        let webExtension = try await WKWebExtension(resourceBaseURL: directory)
        let context = WKWebExtensionContext(for: webExtension)
        let controller = WKWebExtensionController(
            configuration: .init(identifier: UUID())
        )
        try controller.load(context)
        addTeardownBlock {
            try controller.unload(context)
        }

        let profileID = UUID()
        let profileRuntime = ExtensionProfileRuntime(initialProfileId: profileID)
        profileRuntime.setController(controller, for: profileID)
        let receipt = profileRuntime.setContext(
            context,
            extensionId: extensionID,
            profileId: profileID
        )
        let runtimeSession = ExtensionRuntimeSession()
        runtimeSession.runtimeState = .loading
        let installedExtensions = InstalledExtensionCollection()
        installedExtensions.connectRecordChanges {}
        installedExtensions.upsert(makeInstalledExtension(id: extensionID))
        let contextLoadRegistry = ExtensionContextLoadRegistry()
        let claim = contextLoadRegistry.begin(for: receipt.key)
        let contextRetirement = ExtensionContextRetirement(
            profileRuntime: profileRuntime,
            backgroundRuntimeState: ExtensionBackgroundRuntimeStateOwner(),
            runtimeSession: runtimeSession,
            errorObservation: ExtensionContextErrorObservation(
                recordRuntimeMetric: { _, _ in },
                trace: { _ in },
                isEnabled: { false }
            ),
            diagnostics: ExtensionRuntimeDiagnostics(),
            unloadContext: { _, _ in },
            isLoadedContext: { _, context in context.isLoaded }
        )
        let residency = ExtensionContextResidencyOwner(
            dependencies: .init(
                profileRuntime: profileRuntime,
                runtimeSession: runtimeSession,
                installedExtensions: installedExtensions,
                contextLoadRegistry: contextLoadRegistry,
                contextRetirement: contextRetirement,
                isExtensionSupportAvailable: { true },
                extensionsModuleEnabledForRuntimeBoundary: { true },
                ensureExtensionController: { _ in },
                getExtensionContext: { extensionID, profileID in
                    profileRuntime.contexts(for: profileID)[extensionID]
                },
                countLoadedContexts: {
                    profileRuntime.contextsByProfile.values.reduce(0) {
                        $0 + $1.count
                    }
                },
                extensionEntity: { _ in nil },
                loadEnabledExtension: { _, _ in },
                markRuntimePublicationReady: {
                    runtimeSession.extensionsLoaded = true
                },
                trace: { _ in }
            )
        )
        return ResidencySettlementFixture(
            extensionID: extensionID,
            profileID: profileID,
            profileRuntime: profileRuntime,
            session: runtimeSession,
            controller: controller,
            loadedContext: ExtensionLoadedContext(
                context: context,
                controller: controller,
                bindingReceipt: receipt,
                loadClaim: claim,
                mutationLease: nil
            ),
            residency: residency
        )
    }

    private func makeInstalledExtension(id: String) -> InstalledExtension {
        InstalledExtension(
            id: id,
            name: id,
            version: "1.0.0",
            manifestVersion: 3,
            description: nil,
            isEnabled: true,
            installDate: Date(),
            lastUpdateDate: Date(),
            packagePath: "/tmp/\(id)",
            iconPath: nil,
            sourceKind: .directory,
            backgroundModel: .none,
            incognitoMode: .spanning,
            sourcePathFingerprint: id,
            manifestRootFingerprint: id,
            sourceBundlePath: "/tmp/\(id)",
            optionsPagePath: nil,
            defaultPopupPath: nil,
            hasBackground: false,
            hasAction: false,
            hasOptionsPage: false,
            hasContentScripts: false,
            hasExtensionPages: false,
            activationSummary: ExtensionActivationSummary(
                matchPatternStrings: [],
                broadScope: false,
                hasContentScripts: false,
                hasAction: false,
                hasOptionsPage: false,
                hasExtensionPages: false
            ),
            manifest: [
                "manifest_version": 3,
                "name": id,
                "version": "1.0.0",
            ]
        )
    }
}

@available(macOS 15.5, *)
@MainActor
private struct ResidencySettlementFixture {
    let extensionID: String
    let profileID: UUID
    let profileRuntime: ExtensionProfileRuntime
    let session: ExtensionRuntimeSession
    let controller: WKWebExtensionController
    let loadedContext: ExtensionLoadedContext
    let residency: ExtensionContextResidencyOwner
}

@available(macOS 15.5, *)
@MainActor
private struct DemandHarness {
    let session: ExtensionRuntimeSession
    let provisioning: ControllerProvisioningProbe
    let coordinator: ExtensionRuntimeDemandCoordinator

    init(
        profileID: UUID?,
        extensionSupportAvailable: Bool = true
    ) {
        let profileRuntime = ExtensionProfileRuntime(
            initialProfileId: profileID
        )
        let session = ExtensionRuntimeSession()
        let provisioning = ControllerProvisioningProbe(
            profileRuntime: profileRuntime
        )
        self.session = session
        self.provisioning = provisioning
        coordinator = ExtensionRuntimeDemandCoordinator(
            installedExtensions: InstalledExtensionCollection(),
            profileRuntime: profileRuntime,
            runtimeSession: session,
            controllerProvisioning: provisioning,
            runtimeProfileID: { nil },
            extensionSupportAvailable: extensionSupportAvailable,
            diagnostics: ExtensionRuntimeDiagnostics()
        )
    }
}

@available(macOS 15.5, *)
@MainActor
private final class ControllerProvisioningProbe:
    ExtensionControllerProvisioning {
    private let profileRuntime: ExtensionProfileRuntime
    private(set) var ensureCount = 0
    private(set) var controllersByProfile: [UUID: WKWebExtensionController] = [:]

    var createdControllerCount: Int {
        controllersByProfile.count
    }

    init(profileRuntime: ExtensionProfileRuntime) {
        self.profileRuntime = profileRuntime
    }

    func ensureExtensionController(
        for profileId: UUID
    ) -> WKWebExtensionController {
        ensureCount += 1
        if let existing = controllersByProfile[profileId] {
            return existing
        }
        let configuration = WKWebExtensionController.Configuration(
            identifier: UUID()
        )
        let controller = WKWebExtensionController(configuration: configuration)
        controllersByProfile[profileId] = controller
        profileRuntime.setController(controller, for: profileId)
        return controller
    }
}

@available(macOS 15.5, *)
@MainActor
private final class InactiveContextRetirementProbe:
    ExtensionInactiveProfileContextRetiring {
    private(set) var keptProfileIDs: [UUID] = []

    func unloadExtensionContextsForInactiveProfiles(keepingProfileId: UUID) {
        keptProfileIDs.append(keepingProfileId)
    }
}

@available(macOS 15.5, *)
@MainActor
private final class ToolbarProfileReloadProbe: ExtensionToolbarProfileReloading {
    private(set) var reloadCount = 0

    func reloadPinnedToolbarExtensionsForCurrentProfile() {
        reloadCount += 1
    }
}

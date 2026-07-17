import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class ExtensionRuntimeLifecycleBoundaryTests: XCTestCase {
    func testNoDemandDoesNotProvisionControllerOrPublishRuntime() {
        let profileID = UUID()
        let harness = DemandHarness(profileID: profileID)

        XCTAssertNil(
            harness.coordinator.requestRuntimeIfDemanded(reason: .install)
        )
        XCTAssertEqual(harness.provisioning.ensureCount, 0)
        XCTAssertEqual(harness.lifecycle.state, .idle)
        XCTAssertFalse(harness.loadStatus.extensionsLoaded)
    }

    func testNoDemandDoesNotSuspendExistingRuntimePublication() {
        let harness = DemandHarness(profileID: UUID())
        harness.loadStatus.markExtensionsLoaded()

        XCTAssertNil(
            harness.coordinator.requestRuntimeIfDemanded(reason: .install)
        )
        XCTAssertTrue(harness.loadStatus.extensionsLoaded)
        XCTAssertEqual(harness.provisioning.ensureCount, 0)
    }

    func testUnsupportedDemandDoesNotProvisionOrPublishRuntime() {
        let profileID = UUID()
        let harness = DemandHarness.unavailable(profileID: profileID)

        XCTAssertNil(
            harness.coordinator.requestRuntimeExplicitly(
                reason: .install,
                profileId: profileID
            )
        )
        XCTAssertEqual(harness.provisioning.ensureCount, 0)
        XCTAssertEqual(harness.lifecycle.state, .unavailable)
        XCTAssertFalse(harness.loadStatus.extensionsLoaded)
    }

    func testDemandWithoutAnyProfilePreservesFailedStateAndDoesNotProvision() {
        let harness = DemandHarness(profileID: nil)
        harness.lifecycle.markFailed()

        XCTAssertNil(
            harness.coordinator.requestRuntimeExplicitly(reason: .install)
        )
        XCTAssertEqual(harness.provisioning.ensureCount, 0)
        XCTAssertEqual(harness.lifecycle.state, .failed)
        XCTAssertFalse(harness.loadStatus.extensionsLoaded)
    }

    func testExplicitDemandIsStickyAndReusesLoadingController() throws {
        let profileID = UUID()
        let harness = DemandHarness(profileID: profileID)
        let initial = try XCTUnwrap(
            harness.coordinator.requestRuntimeExplicitly(
                reason: .install,
                profileId: profileID
            )
        )
        harness.lifecycle.beginLoading()

        let reused = try XCTUnwrap(
            harness.coordinator.requestRuntimeIfDemanded(
                reason: .install,
                profileId: profileID
            )
        )

        XCTAssertIdentical(reused, initial)
        XCTAssertEqual(harness.provisioning.ensureCount, 2)
        XCTAssertEqual(harness.provisioning.createdControllerCount, 1)
        XCTAssertEqual(harness.lifecycle.state, .loading)
        XCTAssertFalse(harness.loadStatus.extensionsLoaded)
    }

    func testABATransitionRejectsStaleImmediateSettlementAndRebindsBaseConfiguration()
        async throws {
        let profileA = UUID()
        let profileB = UUID()
        let profileRuntime = ExtensionProfileRuntime(initialProfileId: profileA)
        let lifecycle = ExtensionRuntimeLifecycleAuthority()
        lifecycle.updateReadiness(isReady: true)
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
            runtimeLifecycle: lifecycle,
            browserConfiguration: browserConfiguration,
            controllerProvisioning: provisioning,
            inactiveContextRetirement: retirement,
            actionAnchors: ExtensionActionPopupAnchorStore(),
            toolbarProfiles: toolbar,
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
        let lifecycle = ExtensionRuntimeLifecycleAuthority()
        lifecycle.updateReadiness(isReady: true)
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
            runtimeLifecycle: lifecycle,
            browserConfiguration: browserConfiguration,
            controllerProvisioning: provisioning,
            inactiveContextRetirement: InactiveContextRetirementProbe(),
            actionAnchors: ExtensionActionPopupAnchorStore(),
            toolbarProfiles: ToolbarProfileReloadProbe(),
            reconcileProfile: { _ in },
            refreshActionSurfaces: { _ in }
        )

        _ = transition.switchProfile(profileID: profileB)

        XCTAssertEqual(profileRuntime.currentProfileId, profileB)
        XCTAssertEqual(lifecycle.state, .loading)
        XCTAssertIdentical(
            browserConfiguration.webViewConfiguration.webExtensionController,
            provisioning.controllersByProfile[profileB]
        )
    }

    func testDeferredTransitionDoesNotRetainTransitionRole() async {
        let profileID = UUID()
        let profileRuntime = ExtensionProfileRuntime(initialProfileId: profileID)
        let lifecycle = ExtensionRuntimeLifecycleAuthority()
        lifecycle.updateReadiness(isReady: true)
        let provisioning = ControllerProvisioningProbe(
            profileRuntime: profileRuntime
        )
        var reconciledProfiles: [UUID] = []
        var transition: ExtensionProfileRuntimeTransition? =
            ExtensionProfileRuntimeTransition(
                installedExtensions: InstalledExtensionCollection(),
                profileRuntime: profileRuntime,
                runtimeLifecycle: lifecycle,
                browserConfiguration: BrowserConfiguration(),
                controllerProvisioning: provisioning,
                inactiveContextRetirement: InactiveContextRetirementProbe(),
                actionAnchors: ExtensionActionPopupAnchorStore(),
                toolbarProfiles: ToolbarProfileReloadProbe(),
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
        let lifecycle = ExtensionRuntimeLifecycleAuthority()
        lifecycle.updateReadiness(isReady: true)
        let provisioning = ControllerProvisioningProbe(
            profileRuntime: profileRuntime
        )
        var reconciledProfiles: [UUID] = []
        var refreshedProfiles: [UUID] = []
        let transition = ExtensionProfileRuntimeTransition(
            installedExtensions: InstalledExtensionCollection(),
            profileRuntime: profileRuntime,
            runtimeLifecycle: lifecycle,
            browserConfiguration: BrowserConfiguration(),
            controllerProvisioning: provisioning,
            inactiveContextRetirement: InactiveContextRetirementProbe(),
            actionAnchors: ExtensionActionPopupAnchorStore(),
            toolbarProfiles: ToolbarProfileReloadProbe(),
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
            fixture.settlement.settle(fixture.loadedContext)
        )
        XCTAssertTrue(fixture.loadStatus.extensionsLoaded)
        XCTAssertEqual(fixture.lifecycle.state, .ready)
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
            fixture.settlement.settle(fixture.loadedContext)
        )
        XCTAssertFalse(fixture.loadStatus.extensionsLoaded)
        XCTAssertEqual(fixture.lifecycle.state, .loading)
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
        let runtimeLifecycle = ExtensionRuntimeLifecycleAuthority()
        runtimeLifecycle.beginLoading()
        let runtimeLoadStatus = ExtensionRuntimeLoadStatusAuthority()
        let installedExtensions = InstalledExtensionCollection()
        installedExtensions.connectRecordChanges {}
        installedExtensions.upsert(makeInstalledExtension(id: extensionID))
        let contextLoadRegistry = ExtensionContextLoadRegistry()
        let claim = contextLoadRegistry.begin(for: receipt.key)
        let settlement = ExtensionContextSettlementOwner(
            profileRuntime: profileRuntime,
            runtimeLifecycle: runtimeLifecycle,
            installedExtensions: installedExtensions,
            markPublicationReady: {
                runtimeLoadStatus.markExtensionsLoaded()
            },
            diagnostics: ExtensionRuntimeDiagnostics()
        )
        return ResidencySettlementFixture(
            extensionID: extensionID,
            profileID: profileID,
            profileRuntime: profileRuntime,
            lifecycle: runtimeLifecycle,
            loadStatus: runtimeLoadStatus,
            controller: controller,
            loadedContext: ExtensionLoadedContext(
                context: context,
                controller: controller,
                bindingReceipt: receipt,
                loadClaim: claim,
                mutationLease: nil
            ),
            settlement: settlement
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
    let lifecycle: ExtensionRuntimeLifecycleAuthority
    let loadStatus: ExtensionRuntimeLoadStatusAuthority
    let controller: WKWebExtensionController
    let loadedContext: ExtensionLoadedContext
    let settlement: ExtensionContextSettlementOwner
}

@available(macOS 15.5, *)
@MainActor
private struct DemandHarness {
    let lifecycle: ExtensionRuntimeLifecycleAuthority
    let loadStatus: ExtensionRuntimeLoadStatusAuthority
    let demand: ExtensionRuntimeDemandAuthority
    let provisioning: ControllerProvisioningProbe
    let coordinator: ExtensionRuntimeDemandCoordinator

    init(profileID: UUID?) {
        self.init(
            profileID: profileID,
            lifecycle: ExtensionRuntimeLifecycleAuthority()
        )
    }

    static func unavailable(profileID: UUID?) -> Self {
        let lifecycle = ExtensionRuntimeLifecycleAuthority()
        lifecycle.markUnavailable()
        return Self(profileID: profileID, lifecycle: lifecycle)
    }

    private init(
        profileID: UUID?,
        lifecycle: ExtensionRuntimeLifecycleAuthority
    ) {
        let profileRuntime = ExtensionProfileRuntime(
            initialProfileId: profileID
        )
        let loadStatus = ExtensionRuntimeLoadStatusAuthority()
        let demand = ExtensionRuntimeDemandAuthority()
        let provisioning = ControllerProvisioningProbe(
            profileRuntime: profileRuntime
        )
        self.lifecycle = lifecycle
        self.loadStatus = loadStatus
        self.demand = demand
        self.provisioning = provisioning
        coordinator = ExtensionRuntimeDemandCoordinator(
            installedExtensions: InstalledExtensionCollection(),
            profileRuntime: profileRuntime,
            runtimeLifecycle: lifecycle,
            runtimeDemand: demand,
            controllerProvisioning: provisioning,
            runtimeProfileID: { nil },
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

    func controllerIfAdmitted(
        for profileId: UUID,
        mutationLease: ProfileReferenceMutationLease?
    ) -> WKWebExtensionController? {
        ensureCount += 1
        if let existing = controllersByProfile[profileId] {
            return existing
        }
        let configuration = WKWebExtensionController.Configuration(
            identifier: UUID()
        )
        let controller = WKWebExtensionController(configuration: configuration)
        controllersByProfile[profileId] = controller
        let lease = mutationLease
            ?? profileRuntime.beginProfileReferenceMutation(to: profileId)
        guard let lease,
              profileRuntime.publishControllerIfAdmitted(
                  controller,
                  for: profileId,
                  mutationLease: lease
              ) != nil
        else { return nil }
        if mutationLease == nil {
            _ = profileRuntime.endProfileReferenceMutation(lease)
        }
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

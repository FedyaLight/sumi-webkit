import SwiftData
import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class ExtensionProfileReferenceAdmissionTests: XCTestCase {
    func testUnavailableAdmissionRejectsInitialAndControllerPublication() {
        let profile = Profile(name: "Unavailable")
        let runtime = ExtensionProfileRuntime(
            initialProfileId: profile.id,
            initialProfile: profile,
            profileReferenceAdmission: .failClosed()
        )
        let provisioning = makeProvisioning(runtime: runtime)

        XCTAssertNil(runtime.currentProfileId)
        XCTAssertNil(runtime.rememberedProfile(for: profile.id))
        XCTAssertNil(provisioning.controllerIfAdmitted(for: profile.id))
        XCTAssertTrue(runtime.controllersByProfile.isEmpty)
        XCTAssertFalse(provisioning.hasExtensionPageUserContentControllers)
        XCTAssertFalse(runtime.containsProfileReference(to: profile.id))
    }

    func testCanceledReservationDoesNotAdmitStaleContextPublication()
        async throws {
        let fixture = try makeFixture()
        let runtime = ExtensionProfileRuntime(
            initialProfileId: fixture.retiring.id,
            initialProfile: fixture.retiring,
            profileReferenceAdmission: fixture.ledger
        )
        let staleAdmission = try XCTUnwrap(
            runtime.admitProfileReference(to: fixture.retiring.id)
        )
        let token = try fixture.ledger.reserve(
            profile: fixture.retiring,
            fallbackID: fixture.fallback.id
        )
        XCTAssertTrue(try fixture.ledger.cancel(token))
        XCTAssertTrue(
            fixture.ledger.isReferenceAllowed(fixture.retiring.id)
        )
        let context = try await makeExtensionContext()

        XCTAssertNil(
            runtime.publishContextIfAdmitted(
                context,
                extensionId: "stale-load",
                profileId: fixture.retiring.id,
                admission: staleAdmission
            )
        )
        XCTAssertTrue(runtime.contextsByProfile.isEmpty)
    }

    func testReservedProfileRejectsProvisioningAndRetirementRemovesExactKeys()
        throws {
        let fixture = try makeFixture()
        let runtime = ExtensionProfileRuntime(
            initialProfileId: fixture.retiring.id,
            initialProfile: fixture.retiring,
            profileReferenceAdmission: fixture.ledger
        )
        XCTAssertTrue(runtime.rememberProfile(fixture.fallback))
        let provisioning = makeProvisioning(runtime: runtime)
        let retiringController = try XCTUnwrap(
            provisioning.controllerIfAdmitted(for: fixture.retiring.id)
        )
        let fallbackController = try XCTUnwrap(
            provisioning.controllerIfAdmitted(for: fixture.fallback.id)
        )
        let token = try fixture.ledger.reserve(
            profile: fixture.retiring,
            fallbackID: fixture.fallback.id
        )
        XCTAssertTrue(try fixture.ledger.beginReferenceMigration(token))

        XCTAssertThrowsError(
            try fixture.ledger.beginRetirementReferenceMigration(
                to: [fixture.third.id]
            )
        ) { error in
            XCTAssertEqual(
                error as? ProfileReferenceAdmissionLedgerError,
                .retirementMigrationTargetMismatch(
                    expected: fixture.fallback.id,
                    requested: [fixture.third.id]
                )
            )
        }

        XCTAssertNil(
            provisioning.controllerIfAdmitted(for: fixture.retiring.id)
        )
        XCTAssertIdentical(
            runtime.controller(for: fixture.retiring.id),
            retiringController
        )
        let migrationLease = try XCTUnwrap(
            runtime.beginProfileRetirementMigration(to: fixture.fallback.id)
        )
        provisioning.retireProfileController(
            profileID: fixture.retiring.id,
            fallbackProfileID: fixture.fallback.id
        )
        XCTAssertTrue(
            runtime.retireProfile(
                fixture.retiring.id,
                fallbackProfileID: fixture.fallback.id,
                mutationLease: migrationLease
            )
        )
        XCTAssertTrue(runtime.endProfileReferenceMutation(migrationLease))

        XCTAssertFalse(runtime.containsProfileReference(to: fixture.retiring.id))
        XCTAssertFalse(
            provisioning.containsProfileReference(to: fixture.retiring.id)
        )
        XCTAssertEqual(runtime.currentProfileId, fixture.fallback.id)
        XCTAssertIdentical(
            runtime.controller(for: fixture.fallback.id),
            fallbackController
        )
        XCTAssertEqual(
            runtime.rememberedProfile(for: fixture.fallback.id)?.id,
            fixture.fallback.id
        )
    }

    private func makeProvisioning(
        runtime: ExtensionProfileRuntime
    ) -> ExtensionControllerProvisioningOwner {
        ExtensionControllerProvisioningOwner(dependencies: .init(
            browserConfiguration: BrowserConfiguration(),
            profileRuntime: runtime,
            currentProfileId: { runtime.currentProfileId },
            assignControllerDelegate: { _ in },
            controllerDelegateReadiness: ExtensionControllerDelegateReadiness(
                profileRuntime: runtime,
                bind: { _ in }
            ),
            traceControllerBinding: { _, _, _, _ in },
            controllerDescription: { _ in "" },
            trace: { _ in }
        ))
    }

    private func makeFixture() throws -> AdmissionFixture {
        let container = try makeInMemoryStartupModelContainer()
        let context = container.mainContext
        let retiring = Profile(name: "Retiring")
        let fallback = Profile(name: "Fallback")
        let third = Profile(name: "Third")
        context.insert(ProfileEntity(
            id: retiring.id,
            name: retiring.name,
            icon: retiring.icon,
            index: 0
        ))
        context.insert(ProfileEntity(
            id: fallback.id,
            name: fallback.name,
            icon: fallback.icon,
            index: 1
        ))
        context.insert(ProfileEntity(
            id: third.id,
            name: third.name,
            icon: third.icon,
            index: 2
        ))
        try context.save()
        return AdmissionFixture(
            container: container,
            retiring: retiring,
            fallback: fallback,
            third: third,
            ledger: try ProfileReferenceAdmissionLedger(context: context)
        )
    }

    private func makeExtensionContext() async throws -> WKWebExtensionContext {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Profile Admission",
            "version": "1.0",
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(
            to: directory.appendingPathComponent("manifest.json"),
            options: .atomic
        )
        let webExtension = try await WKWebExtension(
            resourceBaseURL: directory
        )
        return WKWebExtensionContext(for: webExtension)
    }
}

@MainActor
private struct AdmissionFixture {
    let container: ModelContainer
    let retiring: Profile
    let fallback: Profile
    let third: Profile
    let ledger: ProfileReferenceAdmissionLedger
}

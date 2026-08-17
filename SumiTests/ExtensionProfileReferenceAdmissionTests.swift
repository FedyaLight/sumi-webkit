import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class ExtensionProfileReferenceAdmissionTests: XCTestCase {
    func testUnavailableAdmissionRejectsInitialAndControllerPublication() {
        let profile = Profile(name: "Unavailable")
        let host = SumiProfileWebExtensionRuntime(
            browserConfiguration: BrowserConfiguration(),
            profileReferenceAdmission: .failClosed(),
            initialProfileProvider: { profile }
        )
        let runtime = host.profileRuntimeForUserDemand(initialProfile: profile)
        let provisioning = makeProvisioning(runtime: runtime, host: host)

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
        let host = SumiProfileWebExtensionRuntime(
            browserConfiguration: BrowserConfiguration(),
            profileReferenceAdmission: fixture.ledger,
            initialProfileProvider: { fixture.retiring }
        )
        let runtime = host.profileRuntimeForUserDemand(
            initialProfile: fixture.retiring
        )
        XCTAssertTrue(runtime.rememberProfile(fixture.fallback))
        let provisioning = makeProvisioning(runtime: runtime, host: host)
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
        runtime: ExtensionProfileRuntime,
        host: SumiProfileWebExtensionRuntime
    ) -> ExtensionControllerProvisioningOwner {
        ExtensionControllerProvisioningOwner(dependencies: .init(
            profileRuntime: runtime,
            profileWebExtensionRuntime: host,
            assignControllerDelegate: { _ in },
            controllerDelegateReadiness: ExtensionControllerDelegateReadiness(
                profileRuntime: runtime,
                bind: { _ in }
            )
        ))
    }

    private func makeFixture() throws -> AdmissionFixture {
        let container = try makeInMemoryStartupDatabase()
        let retiring = Profile(name: "Retiring")
        let fallback = Profile(name: "Fallback")
        let third = Profile(name: "Third")
        try container.transaction {
            try $0.profiles.save(
                ProfileRecord(id: retiring.id, name: retiring.name, index: 0)
            )
            try $0.profiles.save(
                ProfileRecord(id: fallback.id, name: fallback.name, index: 1)
            )
            try $0.profiles.save(
                ProfileRecord(id: third.id, name: third.name, index: 2)
            )
        }
        return AdmissionFixture(
            container: container,
            retiring: retiring,
            fallback: fallback,
            third: third,
            ledger: try ProfileReferenceAdmissionLedger(database: container)
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
    let container: SumiDatabase
    let retiring: Profile
    let fallback: Profile
    let third: Profile
    let ledger: ProfileReferenceAdmissionLedger
}

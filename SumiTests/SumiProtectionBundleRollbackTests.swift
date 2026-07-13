import CryptoKit
import XCTest

@testable import Sumi

final class SumiProtectionBundleRollbackTests: XCTestCase {
    func testValidCurrentQuarantinesInvalidPrevious() throws {
        let fixture = try RollbackFixture()
        defer { fixture.remove() }
        try fixture.installPrevious(valid: false)
        let transaction = try fixture.makeTransaction()
        try fixture.stageCandidate(in: transaction, valid: true)

        let result = try transaction.commit(
            expectedIdentity: fixture.currentIdentity
        )

        XCTAssertEqual(result, fixture.destination)
        XCTAssertEqual(transaction.phase, .active)
        XCTAssertEqual(
            try fixture.validator.validateBundle(at: result).identity,
            fixture.currentIdentity
        )
        XCTAssertTrue(fixture.isQuarantined(role: "previous"))
        XCTAssertFalse(fixture.unavailableMarkerExists)
    }

    func testInvalidPublishedCurrentRestoresAndRevalidatesPrevious() throws {
        let fixture = try RollbackFixture()
        defer { fixture.remove() }
        try fixture.installPrevious(valid: true)
        var stages = [SumiProtectionBundleCacheTransaction.FaultStage]()
        let transaction = try fixture.makeTransaction { stage, url in
            stages.append(stage)
            if stage == .publishedValidation {
                try fixture.invalidateBundle(at: url)
            }
        }
        try fixture.stageCandidate(in: transaction, valid: true)

        XCTAssertThrowsError(
            try transaction.commit(expectedIdentity: fixture.currentIdentity)
        )

        XCTAssertEqual(transaction.phase, .restoredActive)
        XCTAssertEqual(
            try fixture.validator.validateBundle(
                at: fixture.destination
            ).identity,
            fixture.previousIdentity
        )
        XCTAssertTrue(fixture.isQuarantined(role: "candidate"))
        XCTAssertLessThan(
            try XCTUnwrap(stages.firstIndex(of: .rollbackSwap)),
            try XCTUnwrap(stages.firstIndex(of: .restoredRevalidation))
        )
        XCTAssertLessThan(
            try XCTUnwrap(stages.firstIndex(of: .restoredRevalidation)),
            try XCTUnwrap(stages.firstIndex(of: .quarantinePublication))
        )
    }

    func testTamperedRestoredBytesQuarantineBothAndPersistUnavailable() throws {
        let fixture = try RollbackFixture()
        defer { fixture.remove() }
        try fixture.installPrevious(valid: true)
        let transaction = try fixture.makeTransaction { stage, url in
            switch stage {
            case .publishedValidation, .restoredRevalidation:
                try fixture.invalidateBundle(at: url)
            default:
                break
            }
        }
        try fixture.stageCandidate(in: transaction, valid: true)

        XCTAssertThrowsError(
            try transaction.commit(expectedIdentity: fixture.currentIdentity)
        ) { error in
            guard case .cacheUnavailable =
                error as? SumiProtectionBundleRemoteUpdateError
            else {
                return XCTFail("Expected typed unavailable state, got \(error)")
            }
        }

        XCTAssertEqual(transaction.phase, .unavailable)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: fixture.destination.path
        ))
        XCTAssertTrue(fixture.isQuarantined(role: "candidate"))
        XCTAssertTrue(fixture.isQuarantined(role: "previous"))
        XCTAssertTrue(fixture.unavailableMarkerExists)
        XCTAssertNil(fixture.remoteDiscovery.resolvedBundle)
    }

    func testMarkerAndQuarantinePublicationFailuresStillRejectInvalidArtifacts() throws {
        let fixture = try RollbackFixture()
        defer { fixture.remove() }
        try fixture.installPrevious(valid: true)
        var transaction: SumiProtectionBundleCacheTransaction!
        transaction = try fixture.makeTransaction { stage, url in
            switch stage {
            case .publishedValidation:
                try fixture.invalidateBundle(at: url)
                try fixture.invalidateBundle(at: transaction.stagedBundleURL)
            case .unavailablePublication, .quarantinePublication:
                throw RollbackFixture.Fault.injected(stage)
            default:
                break
            }
        }
        try fixture.stageCandidate(in: transaction, valid: true)

        XCTAssertThrowsError(
            try transaction.commit(expectedIdentity: fixture.currentIdentity)
        ) { error in
            guard case .cacheUnavailable(
                _,
                _,
                _,
                let recovery
            ) = error as? SumiProtectionBundleRemoteUpdateError else {
                return XCTFail("Expected typed unavailable state, got \(error)")
            }
            XCTAssertTrue(recovery?.contains("unavailablePublication") == true)
            XCTAssertTrue(recovery?.contains("quarantinePublication") == true)
        }

        XCTAssertEqual(transaction.phase, .unavailable)
        XCTAssertFalse(fixture.unavailableMarkerExists)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: fixture.destination.path
        ))
        XCTAssertThrowsError(
            try fixture.validator.validateBundle(at: fixture.destination)
        )
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: transaction.stagedBundleURL.path
        ))
        XCTAssertThrowsError(
            try fixture.validator.validateBundle(at: transaction.stagedBundleURL)
        )
        XCTAssertNil(fixture.remoteDiscovery.resolvedBundle)
    }

    func testExactPublishedByteTamperingCannotActivateCandidate() throws {
        let fixture = try RollbackFixture()
        defer { fixture.remove() }
        try fixture.installPrevious(valid: true)
        let transaction = try fixture.makeTransaction { stage, url in
            if stage == .publishedValidation {
                try fixture.tamperPayload(at: url)
            }
        }
        try fixture.stageCandidate(in: transaction, valid: true)

        XCTAssertThrowsError(
            try transaction.commit(expectedIdentity: fixture.currentIdentity)
        )

        XCTAssertEqual(transaction.phase, .restoredActive)
        XCTAssertEqual(
            try fixture.validator.validateBundle(
                at: fixture.destination
            ).identity,
            fixture.previousIdentity
        )
        XCTAssertTrue(fixture.isQuarantined(role: "candidate"))
    }

    func testInvalidCandidateNeverDisplacesValidPrevious() throws {
        let fixture = try RollbackFixture()
        defer { fixture.remove() }
        try fixture.installPrevious(valid: true)
        let transaction = try fixture.makeTransaction()
        try fixture.stageCandidate(in: transaction, valid: false)

        XCTAssertThrowsError(
            try transaction.commit(expectedIdentity: fixture.currentIdentity)
        )

        XCTAssertEqual(transaction.phase, .previousActive)
        XCTAssertEqual(
            try fixture.validator.validateBundle(
                at: fixture.destination
            ).identity,
            fixture.previousIdentity
        )
        XCTAssertTrue(fixture.isQuarantined(role: "candidate"))
    }

    func testLaterValidUpdateClearsUnavailableButRetainsForensics() throws {
        let fixture = try RollbackFixture()
        defer { fixture.remove() }
        try fixture.installPrevious(valid: true)
        let damaged = try fixture.makeTransaction { stage, url in
            if stage == .publishedValidation
                || stage == .restoredRevalidation {
                try fixture.invalidateBundle(at: url)
            }
        }
        try fixture.stageCandidate(in: damaged, valid: true)
        XCTAssertThrowsError(
            try damaged.commit(expectedIdentity: fixture.currentIdentity)
        )
        XCTAssertTrue(fixture.unavailableMarkerExists)
        XCTAssertTrue(fixture.isQuarantined(role: "candidate"))
        XCTAssertTrue(fixture.isQuarantined(role: "previous"))

        let retryId = UUID(
            uuidString: "00000000-0000-0000-0000-000000000037"
        )!
        let retry = try fixture.makeTransaction(transactionId: retryId)
        try fixture.stageCandidate(in: retry, valid: true)

        _ = try retry.commit(expectedIdentity: fixture.currentIdentity)

        XCTAssertEqual(retry.phase, .active)
        XCTAssertFalse(fixture.unavailableMarkerExists)
        XCTAssertTrue(fixture.isQuarantined(role: "candidate"))
        XCTAssertTrue(fixture.isQuarantined(role: "previous"))
        XCTAssertEqual(
            try fixture.validator.validateBundle(
                at: fixture.destination
            ).identity,
            fixture.currentIdentity
        )
    }

    func testEveryRollbackBoundaryFailsWithoutInvalidActivation() throws {
        let rollbackStages: Set<SumiProtectionBundleCacheTransaction.FaultStage> = [
            .rollbackSwap,
            .rollbackDurability,
            .restoredRevalidation,
            .unavailablePublication,
            .unavailableDurability,
            .quarantinePublication,
            .quarantineDurability,
        ]
        let bothInvalidStages: Set<SumiProtectionBundleCacheTransaction.FaultStage> = [
            .unavailablePublication,
            .unavailableDurability,
            .quarantinePublication,
            .quarantineDurability,
        ]

        for target in SumiProtectionBundleCacheTransaction.FaultStage.allCases {
            let fixture = try RollbackFixture()
            var reachedTarget = false
            try fixture.installPrevious(valid: true)
            let transaction = try fixture.makeTransaction { stage, url in
                if stage == .publishedValidation,
                   rollbackStages.contains(target) {
                    try fixture.invalidateBundle(at: url)
                }
                if stage == .restoredRevalidation,
                   bothInvalidStages.contains(target) {
                    try fixture.invalidateBundle(at: url)
                }
                if stage == target {
                    reachedTarget = true
                    throw RollbackFixture.Fault.injected(target)
                }
            }
            try fixture.stageCandidate(in: transaction, valid: true)

            _ = try? transaction.commit(
                expectedIdentity: fixture.currentIdentity
            )

            XCTAssertTrue(reachedTarget, "Fault stage not reached: \(target)")
            if fixture.unavailableMarkerExists {
                XCTAssertNil(
                    fixture.remoteDiscovery.resolvedBundle,
                    "Unavailable marker must prevent reuse at \(target)"
                )
            } else if FileManager.default.fileExists(
                atPath: fixture.destination.path
            ) {
                XCTAssertNoThrow(
                    try fixture.validator.validateBundle(
                        at: fixture.destination
                    ),
                    "Invalid fixed-path bundle survived \(target)"
                )
            } else {
                XCTAssertTrue(
                    fixture.isQuarantined(role: "candidate"),
                    "Missing active cache must retain evidence at \(target)"
                )
            }
            fixture.remove()
        }
    }
}

private struct RollbackFixture {
    enum Fault: LocalizedError {
        case injected(SumiProtectionBundleCacheTransaction.FaultStage)

        var errorDescription: String? {
            switch self {
            case .injected(let stage):
                return "injected \(stage.rawValue) fault"
            }
        }
    }

    let profileId = "profile"
    let transactionId = UUID(uuidString: "00000000-0000-0000-0000-000000000036")!
    let root: URL
    let destination: URL
    let validator = RollbackBundleValidator()
    let currentIdentity = SumiProtectionBundleIdentity(
        profileId: "profile",
        bundleId: "current-bundle",
        generationId: "current-generation"
    )
    let previousIdentity = SumiProtectionBundleIdentity(
        profileId: "profile",
        bundleId: "previous-bundle",
        generationId: "previous-generation"
    )

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SumiProtectionRollback-\(UUID().uuidString)",
            isDirectory: true
        )
        destination = SumiRemoteAdblockBundleCache.bundleURL(
            profileId: profileId,
            rootDirectory: root
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
    }

    func makeTransaction(
        transactionId: UUID? = nil,
        faultInjector: SumiProtectionBundleCacheTransaction.FaultInjector? = nil
    ) throws -> SumiProtectionBundleCacheTransaction {
        try SumiProtectionBundleCacheTransaction(
            profileId: profileId,
            rootDirectory: root,
            payloadValidator: validator,
            transactionId: transactionId ?? self.transactionId,
            faultInjector: faultInjector
        )
    }

    func installPrevious(valid: Bool) throws {
        try writeBundle(
            at: destination,
            identity: previousIdentity,
            payload: "previous",
            valid: valid
        )
    }

    func stageCandidate(
        in transaction: SumiProtectionBundleCacheTransaction,
        valid: Bool
    ) throws {
        try transaction.write(
            identityData(currentIdentity),
            relativePath: "identity.txt"
        )
        try transaction.write(Data("candidate".utf8), relativePath: "payload.txt")
        if !valid {
            try transaction.write(Data(), relativePath: "invalid")
        }
    }

    func invalidateBundle(at url: URL) throws {
        try Data().write(to: url.appendingPathComponent("invalid"))
    }

    func tamperPayload(at url: URL) throws {
        try Data("tampered".utf8).write(
            to: url.appendingPathComponent("payload.txt")
        )
    }

    func isQuarantined(role: String) -> Bool {
        FileManager.default.fileExists(
            atPath: quarantineRoot.appendingPathComponent(role).path
        )
    }

    var unavailableMarkerExists: Bool {
        FileManager.default.fileExists(
            atPath: SumiRemoteAdblockBundleCache.unavailableMarkerURL(
                profileId: profileId,
                rootDirectory: root
            ).path
        )
    }

    var remoteDiscovery: SumiPreparedAdblockBundleDiscovery {
        SumiPreparedAdblockBundleResolver().discover(
            profileId: profileId,
            resourceURL: nil,
            remoteBundlesRootURL: root,
            generatedBundlesRootURL: nil
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    private var quarantineRoot: URL {
        root.appendingPathComponent("Quarantine", isDirectory: true)
            .appendingPathComponent(profileId, isDirectory: true)
            .appendingPathComponent(
                transactionId.uuidString.lowercased(),
                isDirectory: true
            )
    }

    private func writeBundle(
        at url: URL,
        identity: SumiProtectionBundleIdentity,
        payload: String,
        valid: Bool
    ) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        try identityData(identity).write(
            to: url.appendingPathComponent("identity.txt")
        )
        try Data(payload.utf8).write(
            to: url.appendingPathComponent("payload.txt")
        )
        if !valid {
            try invalidateBundle(at: url)
        }
    }

    private func identityData(_ identity: SumiProtectionBundleIdentity) -> Data {
        Data(
            "\(identity.profileId)|\(identity.bundleId)|\(identity.generationId)".utf8
        )
    }
}

private struct RollbackBundleValidator: SumiProtectionBundlePayloadValidating {
    func validateBundle(
        at bundleURL: URL
    ) throws -> SumiProtectionBundleValidationReceipt {
        let invalidURL = bundleURL.appendingPathComponent("invalid")
        guard !FileManager.default.fileExists(atPath: invalidURL.path) else {
            throw RollbackFixture.Fault.injected(.candidateValidation)
        }
        let identityData = try Data(
            contentsOf: bundleURL.appendingPathComponent("identity.txt")
        )
        let components = String(decoding: identityData, as: UTF8.self)
            .split(separator: "|", omittingEmptySubsequences: false)
        guard components.count == 3 else {
            throw RollbackFixture.Fault.injected(.candidateValidation)
        }
        let payloadData = try Data(
            contentsOf: bundleURL.appendingPathComponent("payload.txt")
        )
        let fingerprint = SHA256.hash(data: identityData + payloadData)
            .map { String(format: "%02x", $0) }
            .joined()
        return SumiProtectionBundleValidationReceipt(
            identity: SumiProtectionBundleIdentity(
                profileId: String(components[0]),
                bundleId: String(components[1]),
                generationId: String(components[2])
            ),
            payloadFingerprint: fingerprint
        )
    }
}

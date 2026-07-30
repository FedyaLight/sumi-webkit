import XCTest

@testable import Sumi

@MainActor
final class PrivatePartitionResidueCleanupTests: XCTestCase {
    func testCleanupRunsEveryDomainInOrder() {
        let recorder = PrivatePartitionResidueCleanupRecorder()
        let cleanup = PrivatePartitionResidueCleanup(
            operations: recorder.operations
        )
        let profileID = UUID()

        cleanup.cleanup(profileID: profileID)

        XCTAssertEqual(
            recorder.calls,
            [.siteDataPolicies, .zoom, .adblockZapper, .extensionPrivateData]
        )
        XCTAssertEqual(recorder.profileIDs, Array(repeating: profileID, count: 4))
    }

    func testCleanupContinuesAfterEachOperationFailure() {
        let recorder = PrivatePartitionResidueCleanupRecorder(
            failingDomains: [.siteDataPolicies, .adblockZapper]
        )
        let cleanup = PrivatePartitionResidueCleanup(
            operations: recorder.operations
        )

        cleanup.cleanup(profileID: UUID())

        XCTAssertEqual(
            recorder.calls,
            [.siteDataPolicies, .zoom, .adblockZapper, .extensionPrivateData]
        )
    }

    func testCleanupCanRunIdempotentlyMoreThanOnce() {
        let recorder = PrivatePartitionResidueCleanupRecorder()
        let cleanup = PrivatePartitionResidueCleanup(
            operations: recorder.operations
        )
        let profileID = UUID()

        cleanup.cleanup(profileID: profileID)
        cleanup.cleanup(profileID: profileID)

        XCTAssertEqual(
            recorder.calls,
            [
                .siteDataPolicies, .zoom, .adblockZapper, .extensionPrivateData,
                .siteDataPolicies, .zoom, .adblockZapper, .extensionPrivateData,
            ]
        )
    }
}

private enum PrivatePartitionResidueDomain: Hashable {
    case siteDataPolicies
    case zoom
    case adblockZapper
    case extensionPrivateData
}

private enum PrivatePartitionResidueTestError: Error {
    case injectedFailure
}

@MainActor
private final class PrivatePartitionResidueCleanupRecorder {
    private let failingDomains: Set<PrivatePartitionResidueDomain>
    private(set) var calls: [PrivatePartitionResidueDomain] = []
    private(set) var profileIDs: [UUID] = []

    init(
        failingDomains: Set<PrivatePartitionResidueDomain> = []
    ) {
        self.failingDomains = failingDomains
    }

    var operations: PrivatePartitionResidueCleanup.Operations {
        .init(
            clearSiteDataPolicies: operation(for: .siteDataPolicies),
            clearZoomPreferences: operation(for: .zoom),
            discardAdblockZapperState: operation(for: .adblockZapper),
            clearExtensionPrivateData: operation(for: .extensionPrivateData)
        )
    }

    private func operation(
        for domain: PrivatePartitionResidueDomain
    ) -> @MainActor (UUID) throws -> Void {
        { [self] profileID in
            calls.append(domain)
            profileIDs.append(profileID)
            if failingDomains.contains(domain) {
                throw PrivatePartitionResidueTestError.injectedFailure
            }
        }
    }
}

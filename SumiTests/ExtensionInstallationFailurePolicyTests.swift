import XCTest

@testable import Sumi

@available(macOS 15.5, *)
final class ExtensionInstallationFailurePolicyTests: XCTestCase {
    func testEveryPackageAndRollbackDispositionHasExactCompensation() {
        typealias Policy = ExtensionInstallationFailurePolicy
        struct Case {
            let ownership: ExtensionInstallationPackage.Ownership
            let disposition: ExternalStateRollbackDisposition
            let expected: Policy.Resolution
        }
        let copiedRollback = Policy.Resolution(
            package: .rollback,
            record: .leaveOriginal,
            runtime: .recoverPrevious
        )
        let externalRollback = Policy.Resolution(
            package: .none,
            record: .leaveOriginal,
            runtime: .leaveUnloaded
        )
        let copiedExact = Policy.Resolution(
            package: .preserve,
            record: .reconcileCandidateWithExactRuntime,
            runtime: .preserveCurrentAuthority
        )
        let externalExact = Policy.Resolution(
            package: .none,
            record: .reconcileCandidateWithExactRuntime,
            runtime: .preserveCurrentAuthority
        )
        let copiedOther = Policy.Resolution(
            package: .preserve,
            record: .leaveOriginal,
            runtime: .preserveCurrentAuthority
        )
        let externalOther = Policy.Resolution(
            package: .none,
            record: .leaveOriginal,
            runtime: .preserveCurrentAuthority
        )
        let cases: [Case] = [
            .init(
                ownership: .copiedDirectory,
                disposition: .rollbackAllowed,
                expected: copiedRollback
            ),
            .init(
                ownership: .externalSafariBundle,
                disposition: .rollbackAllowed,
                expected: externalRollback
            ),
            .init(
                ownership: .copiedDirectory,
                disposition: .preserveForExactRuntime,
                expected: copiedExact
            ),
            .init(
                ownership: .externalSafariBundle,
                disposition: .preserveForExactRuntime,
                expected: externalExact
            ),
            .init(
                ownership: .copiedDirectory,
                disposition: .preserveForReplacement,
                expected: copiedOther
            ),
            .init(
                ownership: .externalSafariBundle,
                disposition: .preserveForReplacement,
                expected: externalOther
            ),
            .init(
                ownership: .copiedDirectory,
                disposition: .preserveForActiveBinding,
                expected: copiedOther
            ),
            .init(
                ownership: .externalSafariBundle,
                disposition: .preserveForActiveBinding,
                expected: externalOther
            ),
            .init(
                ownership: .copiedDirectory,
                disposition: .preserveForCompetingTransaction,
                expected: copiedOther
            ),
            .init(
                ownership: .externalSafariBundle,
                disposition: .preserveForCompetingTransaction,
                expected: externalOther
            ),
            .init(
                ownership: .copiedDirectory,
                disposition: .preserveUntilSharedCleanup,
                expected: copiedOther
            ),
            .init(
                ownership: .externalSafariBundle,
                disposition: .preserveUntilSharedCleanup,
                expected: externalOther
            ),
        ]

        for testCase in cases {
            XCTAssertEqual(
                Policy.resolve(
                    packageOwnership: testCase.ownership,
                    disposition: testCase.disposition
                ),
                testCase.expected,
                "\(testCase.ownership) / \(testCase.disposition)"
            )
        }
    }
}

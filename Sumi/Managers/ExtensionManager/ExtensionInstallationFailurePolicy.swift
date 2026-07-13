import Foundation

/// Pure compensation policy for the two package ownership models and every
/// runtime rollback disposition.
@available(macOS 15.5, *)
enum ExtensionInstallationFailurePolicy {
    enum PackageAction: Equatable {
        case rollback
        case preserve
        case none
    }

    enum RecordAction: Equatable {
        case leaveOriginal
        case reconcileCandidateWithExactRuntime
    }

    enum RuntimeAction: Equatable {
        case recoverPrevious
        case leaveUnloaded
        case preserveCurrentAuthority
    }

    struct Resolution: Equatable {
        let package: PackageAction
        let record: RecordAction
        let runtime: RuntimeAction
    }

    static func resolve(
        packageOwnership: ExtensionInstallationPackage.Ownership,
        disposition: ExternalStateRollbackDisposition
    ) -> Resolution {
        let packageAction: PackageAction
        switch packageOwnership {
        case .externalSafariBundle:
            packageAction = .none
        case .copiedDirectory:
            packageAction = disposition == .rollbackAllowed
                ? .rollback
                : .preserve
        }

        switch disposition {
        case .rollbackAllowed:
            return Resolution(
                package: packageAction,
                record: .leaveOriginal,
                runtime: packageOwnership == .copiedDirectory
                    ? .recoverPrevious
                    : .leaveUnloaded
            )
        case .preserveForExactRuntime:
            return Resolution(
                package: packageAction,
                record: .reconcileCandidateWithExactRuntime,
                runtime: .preserveCurrentAuthority
            )
        case .preserveForReplacement,
             .preserveForActiveBinding,
             .preserveForCompetingTransaction,
             .preserveUntilSharedCleanup:
            return Resolution(
                package: packageAction,
                record: .leaveOriginal,
                runtime: .preserveCurrentAuthority
            )
        }
    }
}

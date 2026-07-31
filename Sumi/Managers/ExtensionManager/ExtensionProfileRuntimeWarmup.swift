import Foundation

/// Loads one profile's enabled extension contexts right after the runtime moves
/// onto that profile, so the first action click finds a settled runtime instead
/// of being the thing that loads it.
///
/// Without this, a cross-profile space switch leaves the destination profile
/// with zero resident contexts (the switch unloads every inactive profile), and
/// the first click both loads the runtime and presents a popup. The load's
/// publication then rebuilds the tab's WebViews and republishes the toolbar
/// underneath the popover AppKit has just shown, and the popover closes itself.
///
/// Only the newest activation survives: a warm-up for a profile the runtime has
/// already left is cancelled and never revived.
@available(macOS 15.5, *)
@MainActor
final class ExtensionProfileRuntimeWarmup {
    private let readiness: ExtensionProfileReadinessProbe
    private let residency: ExtensionContextResidencyOwner
    private let profileRuntime: ExtensionProfileRuntime
    private let runtimeIsEnabled: @MainActor () -> Bool

    private var revision: UInt64 = 0
    private var task: Task<Void, Never>?

    init(
        readiness: ExtensionProfileReadinessProbe,
        residency: ExtensionContextResidencyOwner,
        profileRuntime: ExtensionProfileRuntime,
        runtimeIsEnabled: @escaping @MainActor () -> Bool
    ) {
        self.readiness = readiness
        self.residency = residency
        self.profileRuntime = profileRuntime
        self.runtimeIsEnabled = runtimeIsEnabled
    }

    /// Warms `profileID` unless it is already resident, nothing is enabled, or
    /// `isCurrent` reports the activation that requested it has been superseded.
    /// Any previous warm-up is cancelled first, so switching away never leaves
    /// residency accruing for a profile the runtime has left.
    func warm(profileID: UUID, isCurrent: @escaping @MainActor () -> Bool) {
        task?.cancel()
        task = nil
        guard runtimeIsEnabled() else { return }
        let enabledExtensionIDs = readiness.enabledExtensionIDs
        guard enabledExtensionIDs.isEmpty == false,
              readiness.isProfileReady(
                  profileID,
                  enabledExtensionIDs: enabledExtensionIDs
              ) == false,
              isCurrent()
        else { return }

        precondition(
            revision < UInt64.max,
            "Extension profile warm-up revision exhausted"
        )
        revision += 1
        let issued = revision
        task = Self.runtimeTask { [weak self] in
            await Task.yield()
            guard let self else { return }
            defer { self.finishWarming(issued) }
            guard Task.isCancelled == false,
                  self.revision == issued,
                  isCurrent(),
                  self.profileRuntime.currentProfileId == profileID
            else { return }
            await self.residency.ensureEnabledExtensionsLoaded(
                for: profileID
            )
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    #if DEBUG
        func runtimeTasksForDrain() -> [Task<Void, Never>] {
            task.map { [$0] } ?? []
        }
    #endif

    private func finishWarming(_ issued: UInt64) {
        guard revision == issued else { return }
        task = nil
    }

    nonisolated private static func runtimeTask(
        _ operation: @escaping @MainActor @Sendable () async -> Void
    ) -> Task<Void, Never> {
        Task { @MainActor in
            await operation()
        }
    }
}

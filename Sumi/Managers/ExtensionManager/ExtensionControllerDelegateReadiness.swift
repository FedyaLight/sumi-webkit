import Foundation
import WebKit

/// Holds the exact controller registration receipt until the first successful
/// WebKit context load proves that controller is active. No work is scheduled
/// while readiness is pending.
@available(macOS 15.5, *)
@MainActor
final class ExtensionControllerDelegateReadiness {
    private let profileRuntime: ExtensionProfileRuntime
    private let bind:
        @MainActor (ExtensionControllerBindingSnapshot) -> Void
    private var pendingByProfile:
        [UUID: ExtensionControllerBindingSnapshot] = [:]

    init(
        profileRuntime: ExtensionProfileRuntime,
        bind: @escaping @MainActor (
            ExtensionControllerBindingSnapshot
        ) -> Void
    ) {
        self.profileRuntime = profileRuntime
        self.bind = bind
    }

    func controllerInstalled(_ receipt: ExtensionControllerBindingSnapshot) {
        guard profileRuntime.isCurrent(receipt) else { return }
        pendingByProfile[receipt.profileID] = receipt
    }

    @discardableResult
    func controllerDidBecomeReady(
        _ receipt: ExtensionControllerBindingSnapshot
    ) -> Bool {
        guard let pending = pendingByProfile[receipt.profileID],
              matches(pending, receipt)
        else {
            return false
        }
        guard profileRuntime.isCurrent(receipt) else {
            pendingByProfile.removeValue(forKey: receipt.profileID)
            return false
        }

        pendingByProfile.removeValue(forKey: receipt.profileID)
        bind(receipt)
        return true
    }

    func cancelAll() {
        pendingByProfile.removeAll()
    }

    private func matches(
        _ lhs: ExtensionControllerBindingSnapshot,
        _ rhs: ExtensionControllerBindingSnapshot
    ) -> Bool {
        lhs.profileID == rhs.profileID
            && lhs.revision == rhs.revision
            && lhs.controller === rhs.controller
    }
}

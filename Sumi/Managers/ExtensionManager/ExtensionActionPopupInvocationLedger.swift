import Foundation
import WebKit

@available(macOS 15.5, *)
struct ExtensionActionPopupInvocationTarget: Equatable {
    let anchorSessionToken: UUID
    let windowID: UUID
}

@available(macOS 15.5, *)
enum ExtensionActionPopupTargetRequest {
    case implicit
    case explicitAnchor(UUID)
}

@available(macOS 15.5, *)
struct ExtensionActionPopupInvocationReceipt {
    let target: ExtensionActionPopupInvocationTarget
}

@available(macOS 15.5, *)
enum ExtensionActionPopupInvocationClaim {
    case claimed(ExtensionActionPopupInvocationReceipt)
    case staleBrowserInvocation
    case unsolicited
}

@available(macOS 15.5, *)
struct ExtensionActionPopupInvocationRegistration: Equatable {
    let revision: UInt64
}

@available(macOS 15.5, *)
enum ExtensionActionPopupInvocationRegistrationResult {
    case registered(ExtensionActionPopupInvocationRegistration)
    case awaitingSettlement
    case recoveryRequired(ExtensionContextBindingReceipt)
}

/// Bounded exact pending registry joining browser-initiated action calls to WebKit's
/// later presentActionPopup callback for the exact action/runtime binding.
@available(macOS 15.5, *)
@MainActor
final class ExtensionActionPopupInvocationLedger {
    private struct Entry {
        let revision: UInt64
        let bindingReceipt: ExtensionContextBindingReceipt
        weak var action: WKWebExtension.Action?
        weak var context: WKWebExtensionContext?
        weak var controller: WKWebExtensionController?
        let profileID: UUID
        let extensionID: String
        let controllerBindingRevision: UInt64
        let contextBindingRevision: UInt64
        let extensionLoadRevision: ExtensionLoadRevision
        let installedRecordRevision: UInt64
        var target: ExtensionActionPopupInvocationTarget
        let registeredAt: TimeInterval
        var isCanceled: Bool
    }

    private static let maximumPendingCount = 16
    static let defaultRecoveryInterval: TimeInterval = 5
    private let recoveryInterval: TimeInterval
    private let now: @MainActor () -> TimeInterval
    private var entries: [Entry] = []
    private var nextRevision: UInt64 = 1
    private var latestRegisteredRevision: UInt64 = 0

    init(
        recoveryInterval: TimeInterval =
            ExtensionActionPopupInvocationLedger.defaultRecoveryInterval,
        now: @escaping @MainActor () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        }
    ) {
        precondition(recoveryInterval >= 0)
        self.recoveryInterval = recoveryInterval
        self.now = now
    }

    func register(
        evidence: ExtensionActionInvocationEvidence,
        action: WKWebExtension.Action,
        target: ExtensionActionPopupInvocationTarget
    ) -> ExtensionActionPopupInvocationRegistrationResult {
        prune()
        entries.removeAll {
            $0.action === action
                && sameBinding($0, evidence.runtimeBinding)
                && $0.installedRecordRevision
                    != evidence.request.installedRecordRevision
        }
        if let existingIndex = entries.firstIndex(where: {
            $0.action === action
                && sameBinding($0, evidence.runtimeBinding)
                && $0.installedRecordRevision
                    == evidence.request.installedRecordRevision
        }) {
            let existing = entries[existingIndex]
            guard existing.isCanceled
                    || now() - existing.registeredAt >= recoveryInterval
            else {
                // WebKit coalesces another performAction while its first popup
                // is still preparing. Keep that physical invocation, but bind
                // its eventual callback to the newest admitted click target;
                // otherwise storing the newer anchor makes the old target
                // unclaimable and both clicks fail.
                entries[existingIndex].target = target
                return .awaitingSettlement
            }
            return .recoveryRequired(existing.bindingReceipt)
        }
        precondition(
            nextRevision < UInt64.max,
            "Action popup invocation revision exhausted"
        )
        let binding = evidence.runtimeBinding
        guard entries.count < Self.maximumPendingCount else {
            return .awaitingSettlement
        }
        let bindingReceipt = ExtensionContextBindingReceipt(
            key: .init(
                profileId: binding.profileID,
                extensionId: binding.extensionID
            ),
            contextIdentifier: ObjectIdentifier(binding.context),
            bindingRevision: binding.contextBindingRevision,
            controllerIdentifier: ObjectIdentifier(binding.controller),
            controllerBindingRevision: binding.controllerBindingRevision
        )
        let revision = nextRevision
        entries.append(.init(
            revision: revision,
            bindingReceipt: bindingReceipt,
            action: action,
            context: binding.context,
            controller: binding.controller,
            profileID: binding.profileID,
            extensionID: binding.extensionID,
            controllerBindingRevision: binding.controllerBindingRevision,
            contextBindingRevision: binding.contextBindingRevision,
            extensionLoadRevision: binding.extensionLoadRevision,
            installedRecordRevision: evidence.request.installedRecordRevision,
            target: target,
            registeredAt: now(),
            isCanceled: false
        ))
        latestRegisteredRevision = revision
        nextRevision += 1
        return .registered(.init(revision: revision))
    }

    func claim(
        action: WKWebExtension.Action,
        evidence: ExtensionActionPopupCallbackEvidence
    ) -> ExtensionActionPopupInvocationClaim {
        prune()
        if let exactIndex = entries.firstIndex(where: {
            $0.action === action
                && sameBinding($0, evidence.runtimeBinding)
                && $0.installedRecordRevision
                    == evidence.installedRecordRevision
        }) {
            let entry = entries.remove(at: exactIndex)
            guard entry.revision == latestRegisteredRevision,
                  entry.isCanceled == false else {
                return .staleBrowserInvocation
            }
            return .claimed(.init(
                target: entry.target
            ))
        }
        guard let staleIndex = entries.firstIndex(where: {
            $0.action === action
                && sameBinding($0, evidence.runtimeBinding)
        }) else {
            guard entries.contains(where: { $0.action === action }) else {
                return .unsolicited
            }
            return .staleBrowserInvocation
        }
        entries.remove(at: staleIndex)
        return .staleBrowserInvocation
    }

    func cancel(_ registration: ExtensionActionPopupInvocationRegistration) {
        guard let index = entries.firstIndex(where: {
            $0.revision == registration.revision
        }) else { return }
        entries[index].isCanceled = true
    }

    func removeAll() {
        entries.removeAll()
    }

    func quarantine(binding receipt: ExtensionContextBindingReceipt) {
        for index in entries.indices
        where entries[index].bindingReceipt == receipt {
            entries[index].isCanceled = true
        }
    }

    func retire(binding receipt: ExtensionContextBindingReceipt) {
        entries.removeAll { $0.bindingReceipt == receipt }
    }

    private func prune() {
        entries.removeAll { $0.action == nil }
    }

    private func sameBinding(
        _ lhs: Entry,
        _ rhs: ExtensionControllerCallbackEvidence
    ) -> Bool {
        lhs.context === rhs.context
            && lhs.controller === rhs.controller
            && lhs.profileID == rhs.profileID
            && lhs.extensionID == rhs.extensionID
            && lhs.controllerBindingRevision == rhs.controllerBindingRevision
            && lhs.contextBindingRevision == rhs.contextBindingRevision
            && lhs.extensionLoadRevision == rhs.extensionLoadRevision
    }
}

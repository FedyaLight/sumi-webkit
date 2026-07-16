import Foundation
import SumiWebRuntime
import WebKit

/// Owns the attachment lifetime of the browser-session ports consumed by the
/// tab runtime. The connection has no reference back to its composition root;
/// callers may retain it without retaining the tab graph or browser session.
@MainActor
final class TabRuntimePortConnection {
    private final class AttachmentIdentity {}

    private var registry: RuntimePortRegistry?
    private var attachmentIdentity: AttachmentIdentity?
    private var attachmentRevision: UInt64 = 0

    init(_ registry: RuntimePortRegistry? = nil) {
        self.registry = registry
        attachmentIdentity = registry == nil ? nil : AttachmentIdentity()
    }

    var current: RuntimePortRegistry? {
        registry
    }

    func attach(_ registry: RuntimePortRegistry) {
        self.registry = registry
        attachmentIdentity = AttachmentIdentity()
        attachmentRevision &+= 1
    }

    func detach() {
        registry = nil
        attachmentIdentity = nil
        attachmentRevision &+= 1
    }

    /// Captures one exact attachment generation. Transactions retain the
    /// captured ports instead of repeatedly resolving mutable composition-root
    /// state through weak manager callbacks.
    func captureLease() -> TabRuntimePortLease {
        let capturedRegistry = registry
        let capturedIdentity = attachmentIdentity
        let capturedRevision = attachmentRevision
        return TabRuntimePortLease(
            registry: capturedRegistry,
            attachmentIdentity: capturedIdentity,
            attachmentRevision: capturedRevision,
            currentProfileID: capturedRegistry?.currentProfileId,
            defaultProfileID: capturedRegistry?.defaultProfileId
        )
    }

    func accepts(_ lease: TabRuntimePortLease) -> Bool {
        guard registry != nil, lease.registry != nil,
              let attachmentIdentity,
              let leasedIdentity = lease.attachmentIdentity else {
            return false
        }
        return leasedIdentity === attachmentIdentity
            && lease.attachmentRevision == attachmentRevision
    }

    func acceptsExactAttachment(_ lease: TabRuntimePortLease) -> Bool {
        if registry == nil || lease.registry == nil {
            return registry == nil
                && lease.registry == nil
                && attachmentIdentity == nil
                && lease.attachmentIdentity == nil
                && lease.attachmentRevision == attachmentRevision
        }
        return accepts(lease)
    }

    func sameAttachment(
        _ lhs: TabRuntimePortLease,
        _ rhs: TabRuntimePortLease
    ) -> Bool {
        lhs.attachmentIdentity === rhs.attachmentIdentity
            && lhs.attachmentRevision == rhs.attachmentRevision
    }

    func requireLease() -> RuntimePortRegistry {
        guard let registry else {
            preconditionFailure(
                "Tab runtime ports are detached. BrowserManagerRuntimeWiring.attach(to:) must run before destructive tab operations."
            )
        }
        return registry
    }
}

@MainActor
struct TabRuntimePortLease {
    let registry: RuntimePortRegistry?
    fileprivate let attachmentIdentity: AnyObject?
    fileprivate let attachmentRevision: UInt64
    let currentProfileID: UUID?
    let defaultProfileID: UUID?

    func windowState(for windowID: UUID) -> BrowserWindowState? {
        registry?.windowState(for: windowID)
    }

    func persistWindowSession(for state: BrowserWindowState) {
        registry?.persistWindowSession(for: state)
    }

    func profile(with profileID: UUID) -> Profile? {
        registry?.profile(with: profileID)
    }

    func captureFallbackProfileWitness()
        -> TabRuntimeFallbackProfileWitness? {
        guard let registry,
              let profileID = currentProfileID ?? defaultProfileID else {
            return nil
        }
        return TabRuntimeFallbackProfileWitness(
            profileQuery: registry.profileQuery,
            profileID: profileID
        )
    }

    func captureProfileAssignmentWitness(
        sourceProfile: Profile,
        targetProfile: Profile
    ) -> TabRuntimeProfileAssignmentWitness? {
        guard let registry else { return nil }
        return TabRuntimeProfileAssignmentWitness(
            profileQuery: registry.profileQuery,
            sourceProfile: sourceProfile,
            targetProfile: targetProfile
        )
    }

    func accepts(_ assignment: PreparedTabProfileAssignment) -> Bool {
        assignment.isCurrent()
            && registry?.profile(with: assignment.sourceResolvedProfileID)
                === assignment.profileWitness.sourceProfile
            && registry?.profile(with: assignment.targetProfile.id)
                === assignment.targetProfile
    }

    func liveDocumentWebView(for tab: Tab) -> WKWebView? {
        registry?.webViewLifecycle.anyLiveWebView(for: tab)
    }

    func executePreparedProfileAssignments(
        _ assignments: [PreparedTabProfileAssignment],
        bindingModel: any ShortcutTabBindingAggregateTransaction,
        settlement: @escaping ProfileTransitionService.Settlement
    ) -> PreparedProfileAssignmentBatchTransitionOutcome? {
        registry?.webViewLifecycle.executePreparedProfileAssignments(
            assignments,
            bindingModel: bindingModel,
            settlement: settlement
        )
    }
}

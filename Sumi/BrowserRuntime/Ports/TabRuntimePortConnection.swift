import Foundation

/// Owns the attachment lifetime of the browser-session ports consumed by the
/// tab runtime. The connection has no reference back to its composition root;
/// callers may retain it without retaining the tab graph or browser session.
@MainActor
final class TabRuntimePortConnection {
    private var registry: RuntimePortRegistry?
    private var attachmentRevision: UInt64 = 0

    init(_ registry: RuntimePortRegistry? = nil) {
        self.registry = registry
    }

    var current: RuntimePortRegistry? {
        registry
    }

    func attach(_ registry: RuntimePortRegistry) {
        self.registry = registry
        attachmentRevision &+= 1
    }

    func detach() {
        registry = nil
        attachmentRevision &+= 1
    }

    /// Captures one exact attachment generation. Transactions retain the
    /// captured ports instead of repeatedly resolving mutable composition-root
    /// state through weak manager callbacks.
    func captureLease() -> TabRuntimePortLease {
        TabRuntimePortLease(
            registry: registry,
            attachmentRevision: attachmentRevision
        )
    }

    func accepts(_ lease: TabRuntimePortLease) -> Bool {
        lease.attachmentRevision == attachmentRevision
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
    fileprivate let attachmentRevision: UInt64

    func windowState(for windowID: UUID) -> BrowserWindowState? {
        registry?.windowState(for: windowID)
    }

    func persistWindowSession(for state: BrowserWindowState) {
        registry?.persistWindowSession(for: state)
    }
}

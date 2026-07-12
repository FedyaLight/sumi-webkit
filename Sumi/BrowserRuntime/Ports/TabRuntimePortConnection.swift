import Foundation

/// Owns the attachment lifetime of the browser-session ports consumed by the
/// tab runtime. The connection has no reference back to its composition root;
/// callers may retain it without retaining the tab graph or browser session.
@MainActor
final class TabRuntimePortConnection {
    private var registry: RuntimePortRegistry?

    init(_ registry: RuntimePortRegistry? = nil) {
        self.registry = registry
    }

    var current: RuntimePortRegistry? {
        registry
    }

    func attach(_ registry: RuntimePortRegistry) {
        self.registry = registry
    }

    func detach() {
        registry = nil
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

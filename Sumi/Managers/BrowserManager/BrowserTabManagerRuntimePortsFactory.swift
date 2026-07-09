import Foundation

@MainActor
enum BrowserTabManagerRuntimePortsFactory {
    static func registry(for browserManager: BrowserManager) -> RuntimePortRegistry {
        var registry = RuntimePortRegistry()
        registry.attach(from: browserManager)
        return registry
    }
}

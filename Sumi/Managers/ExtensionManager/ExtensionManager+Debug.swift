#if DEBUG
import Foundation
import WebKit

@available(macOS 15.5, *)
private final class ExtensionManagerDebugRegistry {
    private static let lock = NSLock()
    private static var hooksByManagerID: [ObjectIdentifier: ExtensionManager.TestHooks] = [:]

    static func hooks(for managerID: ObjectIdentifier) -> ExtensionManager.TestHooks {
        lock.lock()
        defer { lock.unlock() }
        return hooksByManagerID[managerID] ?? ExtensionManager.TestHooks()
    }

    static func setHooks(
        _ hooks: ExtensionManager.TestHooks,
        for managerID: ObjectIdentifier
    ) {
        lock.lock()
        hooksByManagerID[managerID] = hooks
        lock.unlock()
    }

    static func clearHooks(for managerID: ObjectIdentifier) {
        lock.lock()
        hooksByManagerID.removeValue(forKey: managerID)
        lock.unlock()
    }
}

@available(macOS 15.5, *)
extension ExtensionManager {
    struct TestHooks {
        var beforePersistInstalledRecord: ((InstalledExtension) throws -> Void)?
        var beforeControllerLoad:
            ((String, ExtensionManager.WebExtensionStorageSnapshot) throws -> Void)?
        var backgroundContentWake:
            (@MainActor (String, WKWebExtensionContext) async throws -> Void)?
        var webExtensionDataCleanup: (@MainActor (String) async -> Bool)?
        var didOpenTab: ((UUID) -> Void)?
        var didChangeTabProperties:
            ((UUID, WKWebExtension.TabChangedProperties) -> Void)?
    }

    var testHooks: TestHooks {
        get {
            ExtensionManagerDebugRegistry.hooks(for: ObjectIdentifier(self))
        }
        set {
            ExtensionManagerDebugRegistry.setHooks(
                newValue,
                for: ObjectIdentifier(self)
            )
        }
    }

    nonisolated func clearDebugState() {
        ExtensionManagerDebugRegistry.clearHooks(for: ObjectIdentifier(self))
    }
}
#endif

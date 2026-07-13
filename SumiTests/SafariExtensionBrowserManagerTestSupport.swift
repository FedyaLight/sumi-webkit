import Darwin
import Foundation
import SwiftData
import XCTest

@testable import Sumi

@MainActor
private final class SafariExtensionBrowserManagerTeardownBox {
    var browserManager: BrowserManager?
    var windowRegistry: WindowRegistry?

    init(
        browserManager: BrowserManager,
        windowRegistry: WindowRegistry?
    ) {
        self.browserManager = browserManager
        self.windowRegistry = windowRegistry
    }
}

@MainActor
private final class SafariExtensionManagerTeardownBox {
    var manager: ExtensionManager?

    init(manager: ExtensionManager) {
        self.manager = manager
    }
}

@MainActor
enum SafariExtensionLiveWebKitTestLease {
    private static var processLeaseFileDescriptor: Int32?

    static func holdForProcess(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard processLeaseFileDescriptor == nil else { return }

        let lockURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiSafariExtensionLiveWebKitTests.lock")
        let fileDescriptor = open(
            lockURL.path,
            O_CREAT | O_RDWR,
            S_IRUSR | S_IWUSR
        )
        guard fileDescriptor >= 0 else {
            XCTFail("Failed to open live WebKit test lock", file: file, line: line)
            return
        }
        guard flock(fileDescriptor, LOCK_EX) == 0 else {
            close(fileDescriptor)
            XCTFail("Failed to acquire live WebKit test lock", file: file, line: line)
            return
        }
        processLeaseFileDescriptor = fileDescriptor
    }
}

@MainActor
extension XCTestCase {
    func makeSafariExtensionTestExtensionManager(
        context: ModelContext,
        initialProfile: Profile?,
        browserConfiguration: BrowserConfiguration? = nil,
        moduleRegistry: SumiModuleRegistry = .unavailable(),
        extensionPreferences: UserDefaults? = nil
    ) -> ExtensionManager {
        let manager = ExtensionManager(
            context: context,
            initialProfile: initialProfile,
            browserConfiguration: browserConfiguration,
            moduleRegistry: moduleRegistry,
            extensionPreferences: extensionPreferences
                ?? UserDefaults(suiteName: UUID().uuidString)!
        )
        let teardownBox = SafariExtensionManagerTeardownBox(manager: manager)
        addTeardownBlock { @MainActor in
            guard let manager = teardownBox.manager else { return }
            await manager.drainExtensionRuntimeTasksForTests()
            _ = manager.shutDownExtensionRuntime(
                reason: "SafariExtensionTestExtensionManager.tearDown"
            )
            manager.clearDebugState()
            teardownBox.manager = nil
        }
        return manager
    }

    func makeSafariExtensionTestBrowserManager(
        moduleRegistry: SumiModuleRegistry? = nil,
        extensionsModule: SumiExtensionsModule? = nil,
        profile: Profile? = nil,
        windowRegistry: WindowRegistry? = nil,
        retainUntilTestTeardown: Bool = true
    ) -> BrowserManager {
        let startupPersistence: BrowserManagerStartupPersistence
        do {
            let startupContainer = try ModelContainer(
                for: SumiStartupPersistence.schema,
                configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
            )
            startupPersistence = BrowserManagerStartupPersistence(container: startupContainer)
        } catch {
            XCTFail("Failed to create in-memory browser startup persistence: \(error)")
            startupPersistence = .production
        }

        let createdDefaultRegistry = moduleRegistry == nil
        let moduleRegistry: SumiModuleRegistry = if let moduleRegistry {
            moduleRegistry
        } else {
            SumiModuleRegistry(
                settingsStore: SumiModuleSettingsStore(
                    userDefaults: UserDefaults(suiteName: UUID().uuidString)!
                )
            )
        }
        if createdDefaultRegistry {
            moduleRegistry.enable(.extensions)
        }
        let adBlockingModule = SumiAdBlockingModule(
            moduleRegistry: moduleRegistry,
            preparedBundleResourceURL: nil,
            preparedBundleRemoteRootURL: nil
        )
        let protectionDefaults = UserDefaults(suiteName: UUID().uuidString)!
        let protectionCoordinator = SumiProtectionCoordinator(
            settings: SumiProtectionSettings(
                userDefaults: protectionDefaults
            ),
            adBlockingModule: adBlockingModule,
            bundleUpdateStatusStore: SumiProtectionBundleUpdateStatusStore(
                userDefaults: protectionDefaults
            )
        )
        let browserManager = BrowserManager(
            moduleRegistry: moduleRegistry,
            startupPersistence: startupPersistence,
            adBlockingModule: adBlockingModule,
            protectionCoordinator: protectionCoordinator,
            extensionsModule: extensionsModule
        )
        if let windowRegistry {
            browserManager.windowRegistry = windowRegistry
        }
        if let profile {
            browserManager.profileManager.profiles = [profile]
            browserManager.currentProfile = profile
        }
        if retainUntilTestTeardown {
            let teardownBox = SafariExtensionBrowserManagerTeardownBox(
                browserManager: browserManager,
                windowRegistry: windowRegistry
            )
            addTeardownBlock { @MainActor in
                guard let browserManager = teardownBox.browserManager else { return }
                if #available(macOS 15.5, *),
                   let extensionManager = browserManager.optionalModules.extensions
                   .managerIfLoadedAndEnabled() {
                    await extensionManager.drainExtensionRuntimeTasksForTests()
                }
                await browserManager.drainBrowserRuntimeTasksForTests(cancel: true)
                teardownBox.browserManager = nil
                teardownBox.windowRegistry = nil
            }
        }
        return browserManager
    }
}

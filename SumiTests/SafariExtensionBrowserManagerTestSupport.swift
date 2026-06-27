import Foundation
import Darwin
import SwiftData
import XCTest

@testable import Sumi

@MainActor
private final class SafariExtensionBrowserManagerTeardownBox {
    var browserManager: BrowserManager?

    init(browserManager: BrowserManager) {
        self.browserManager = browserManager
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
        extensionPreferences: UserDefaults? = nil
    ) -> ExtensionManager {
        let manager = ExtensionManager(
            context: context,
            initialProfile: initialProfile,
            browserConfiguration: browserConfiguration,
            extensionPreferences: extensionPreferences
                ?? UserDefaults(suiteName: UUID().uuidString)!
        )
        let teardownBox = SafariExtensionManagerTeardownBox(manager: manager)
        addTeardownBlock { @MainActor in
            guard let manager = teardownBox.manager else { return }
            await manager.drainExtensionRuntimeTasksForTests()
            manager.tearDownExtensionRuntime(
                reason: "SafariExtensionTestExtensionManager.tearDown",
                removeUIState: true,
                releaseController: true
            )
            manager.clearDebugState()
            teardownBox.manager = nil
        }
        return manager
    }

    func makeSafariExtensionTestBrowserManager(
        moduleRegistry: SumiModuleRegistry? = nil,
        extensionsModule: SumiExtensionsModule? = nil,
        profile: Profile? = nil
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
        let protectionCoordinator = SumiProtectionCoordinator(
            settings: SumiProtectionSettings(
                userDefaults: UserDefaults(suiteName: UUID().uuidString)!
            ),
            adBlockingModule: adBlockingModule
        )
        let browserManager = BrowserManager(
            moduleRegistry: moduleRegistry,
            startupPersistence: startupPersistence,
            adBlockingModule: adBlockingModule,
            protectionCoordinator: protectionCoordinator,
            extensionsModule: extensionsModule
        )
        if let profile {
            browserManager.profileManager.profiles = [profile]
            browserManager.currentProfile = profile
        }
        let teardownBox = SafariExtensionBrowserManagerTeardownBox(browserManager: browserManager)
        addTeardownBlock { @MainActor in
            guard let browserManager = teardownBox.browserManager else { return }
            await browserManager.drainBrowserRuntimeTasksForTests(cancel: true)
            teardownBox.browserManager = nil
        }
        return browserManager
    }
}

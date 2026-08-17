import Darwin
import Foundation
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

@available(macOS 15.5, *)
@MainActor
struct SafariExtensionManagerTestFixture {
    let manager: ExtensionManager
    let inspection: ExtensionManagerTestInspection
    let attachedRuntime: ExtensionAttachedRuntimeCapture
}

@MainActor
extension XCTestCase {
    func makeSafariExtensionManagerTestFixture(
        context database: SumiDatabase,
        initialProfile: Profile?,
        browserConfiguration: BrowserConfiguration? = nil,
        moduleRegistry: SumiModuleRegistry = .unavailable(),
        extensionPreferences: UserDefaults? = nil,
        profileWebExtensionRuntime: SumiProfileWebExtensionRuntime? = nil,
        assemblyOverrides: ExtensionManagerTestAssemblyOverrides? = nil
    ) -> SafariExtensionManagerTestFixture {
        let attachedRuntime = ExtensionAttachedRuntimeCapture()
        let inspection = ExtensionManagerInspectionCapture()
        let manager = makeSafariExtensionTestExtensionManager(
            database: database,
            initialProfile: initialProfile,
            browserConfiguration: browserConfiguration,
            moduleRegistry: moduleRegistry,
            extensionPreferences: extensionPreferences,
            profileWebExtensionRuntime: profileWebExtensionRuntime,
            attachedRuntimeCapture: attachedRuntime,
            inspectionCapture: inspection,
            assemblyOverrides: assemblyOverrides
        )
        return SafariExtensionManagerTestFixture(
            manager: manager,
            inspection: inspection.inspection,
            attachedRuntime: attachedRuntime
        )
    }

    func makeSafariExtensionTestExtensionManager(
        database: SumiDatabase,
        initialProfile: Profile?,
        browserConfiguration: BrowserConfiguration? = nil,
        moduleRegistry: SumiModuleRegistry = .unavailable(),
        extensionPreferences: UserDefaults? = nil,
        profileWebExtensionRuntime: SumiProfileWebExtensionRuntime? = nil,
        attachedRuntimeCapture: ExtensionAttachedRuntimeCapture? = nil,
        inspectionCapture: ExtensionManagerInspectionCapture? = nil,
        assemblyOverrides: ExtensionManagerTestAssemblyOverrides? = nil
    ) -> ExtensionManager {
        let preferences = extensionPreferences
            ?? UserDefaults(suiteName: UUID().uuidString)!
        let manager: ExtensionManager
        if let attachedRuntimeCapture {
            manager = ExtensionManager(
                database: database,
                initialProfile: initialProfile,
                browserConfiguration: browserConfiguration,
                moduleRegistry: moduleRegistry,
                extensionPreferences: preferences,
                profileWebExtensionRuntime: profileWebExtensionRuntime,
                attachedRuntimeDidInstall: attachedRuntimeCapture.install,
                testInspectionDidAssemble: inspectionCapture?.install,
                testAssemblyOverrides: assemblyOverrides
            )
        } else if let inspectionCapture {
            manager = ExtensionManager(
                database: database,
                initialProfile: initialProfile,
                browserConfiguration: browserConfiguration,
                moduleRegistry: moduleRegistry,
                extensionPreferences: preferences,
                profileWebExtensionRuntime: profileWebExtensionRuntime,
                testInspectionDidAssemble: inspectionCapture.install,
                testAssemblyOverrides: assemblyOverrides
            )
        } else if let assemblyOverrides {
            manager = ExtensionManager(
                database: database,
                initialProfile: initialProfile,
                browserConfiguration: browserConfiguration,
                moduleRegistry: moduleRegistry,
                extensionPreferences: preferences,
                profileWebExtensionRuntime: profileWebExtensionRuntime,
                testAssemblyOverrides: assemblyOverrides
            )
        } else {
            manager = ExtensionManager(
                database: database,
                initialProfile: initialProfile,
                browserConfiguration: browserConfiguration,
                moduleRegistry: moduleRegistry,
                extensionPreferences: preferences,
                profileWebExtensionRuntime: profileWebExtensionRuntime
            )
        }
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
        browserConfiguration: BrowserConfiguration? = nil,
        automaticallyStartPersistedStateLoad: Bool = false,
        retainUntilTestTeardown: Bool = true
    ) -> BrowserManager {
        let startupPersistence: BrowserManagerStartupPersistence
        do {
            let startupContainer = try SumiDatabase.inMemory()
            startupPersistence = BrowserManagerStartupPersistence(database: startupContainer)
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
            filterListCatalog: nil,
            compiledRuleListCatalog: SumiCompiledContentRuleListCatalog()
        )
        let protectionDefaults = UserDefaults(suiteName: UUID().uuidString)!
        let protectionCoordinator = SumiProtectionCoordinator(
            settings: SumiProtectionSettings(
                userDefaults: protectionDefaults
            ),
            adBlockingModule: adBlockingModule,
            compiledRuleListCatalog: SumiCompiledContentRuleListCatalog()
        )
        let browserManager = BrowserManager(
            windowRegistry: windowRegistry ?? WindowRegistry(),
            moduleRegistry: moduleRegistry,
            startupPersistence: startupPersistence,
            browserConfiguration: browserConfiguration,
            adBlockingModule: adBlockingModule,
            protectionCoordinator: protectionCoordinator,
            extensionsModule: extensionsModule,
            automaticallyStartPersistedStateLoad: automaticallyStartPersistedStateLoad
        )
        if let profile {
            browserManager.profileManager.profiles = [profile]
            browserManager.currentProfile = profile
            browserManager.optionalModules.extensions
                .switchProfileIfLoaded(profile)
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
                   .managerForTesting(materializeIfNeeded: false) {
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

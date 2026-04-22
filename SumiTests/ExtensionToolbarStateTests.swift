import XCTest
import SwiftData
@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class ExtensionToolbarStateTests: XCTestCase {
    private var containers: [ModelContainer] = []
    private var defaultsSnapshots: [String: Data?] = [:]

    override func setUpWithError() throws {
        try super.setUpWithError()
        containers = []
        defaultsSnapshots = [:]
        preserveDefaultsValueIfNeeded(for: pinnedToolbarStorageKey)
        UserDefaults.standard.removeObject(forKey: pinnedToolbarStorageKey)
    }

    override func tearDownWithError() throws {
        let defaults = UserDefaults.standard
        for (key, snapshot) in defaultsSnapshots {
            if let snapshot {
                defaults.set(snapshot, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        containers.removeAll()
        defaultsSnapshots.removeAll()
        try super.tearDownWithError()
    }

    func testPinningPreservesOrderAndSkipsDuplicates() throws {
        let manager = makeManager(initialProfile: Profile(name: "Primary"))

        manager.pinToToolbar("first")
        manager.pinToToolbar("second")
        manager.pinToToolbar("first")

        XCTAssertEqual(manager.pinnedToolbarExtensionIDs, ["first", "second"])
    }

    func testOrderedPinnedToolbarExtensionsOnlyIncludesEnabledPinnedOnes() throws {
        let manager = makeManager(initialProfile: Profile(name: "Primary"))
        let first = makeExtension(id: "first", isEnabled: true)
        let second = makeExtension(id: "second", isEnabled: false)
        let third = makeExtension(id: "third", isEnabled: true)

        manager.pinToToolbar("third")
        manager.pinToToolbar("missing")
        manager.pinToToolbar("second")
        manager.pinToToolbar("first")

        let ordered = manager.orderedPinnedToolbarExtensions(
            from: [first, second, third],
        )

        XCTAssertEqual(ordered.map(\.id), ["third", "first"])
    }

    func testPinnedToolbarStateRestoresForSameProfile() throws {
        let profile = Profile(name: "Persisted")
        let manager = makeManager(initialProfile: profile)

        manager.pinToToolbar("alpha")
        manager.pinToToolbar("beta")

        let restored = makeManager(initialProfile: profile)

        XCTAssertEqual(restored.pinnedToolbarExtensionIDs, ["alpha", "beta"])
    }

    func testSwitchProfileLoadsDifferentPinnedToolbarSets() throws {
        let firstProfile = Profile(name: "First")
        let secondProfile = Profile(name: "Second")
        let manager = makeManager(initialProfile: firstProfile)

        manager.pinToToolbar("alpha")

        manager.switchProfile(secondProfile)
        XCTAssertEqual(manager.pinnedToolbarExtensionIDs, [])

        manager.pinToToolbar("beta")

        manager.switchProfile(firstProfile)
        XCTAssertEqual(manager.pinnedToolbarExtensionIDs, ["alpha"])

        manager.switchProfile(secondProfile)
        XCTAssertEqual(manager.pinnedToolbarExtensionIDs, ["beta"])
    }

    func testReconcilePinnedToolbarExtensionsDropsMissingIDs() throws {
        let manager = makeManager(initialProfile: Profile(name: "Primary"))
        manager.pinToToolbar("missing")
        manager.pinToToolbar("present")

        manager.installedExtensions = [makeExtension(id: "present", isEnabled: true)]
        manager.reconcilePinnedToolbarExtensions()

        XCTAssertEqual(manager.pinnedToolbarExtensionIDs, ["present"])
    }

    private func makeManager(initialProfile: Profile) -> ExtensionManager {
        let container = try! ModelContainer(
            for: Schema([ExtensionEntity.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        containers.append(container)

        return ExtensionManager(
            context: container.mainContext,
            initialProfile: initialProfile,
            browserConfiguration: BrowserConfiguration()
        )
    }

    private var pinnedToolbarStorageKey: String {
        "\(SumiAppIdentity.bundleIdentifier).extensions.toolbarPinnedIDsByProfile"
    }

    private func preserveDefaultsValueIfNeeded(for key: String) {
        guard defaultsSnapshots[key] == nil else { return }
        defaultsSnapshots[key] = UserDefaults.standard.data(forKey: key)
    }

    private func makeExtension(
        id: String,
        isEnabled: Bool
    ) -> InstalledExtension {
        InstalledExtension(
            id: id,
            name: id,
            version: "1.0",
            manifestVersion: 3,
            description: nil,
            isEnabled: isEnabled,
            installDate: Date(timeIntervalSince1970: 0),
            lastUpdateDate: Date(timeIntervalSince1970: 0),
            packagePath: "/tmp/\(id)",
            iconPath: nil,
            sourceKind: .directory,
            backgroundModel: .none,
            incognitoMode: .spanning,
            sourcePathFingerprint: id,
            manifestRootFingerprint: id,
            sourceBundlePath: "/tmp/\(id)",
            teamID: nil,
            appBundleID: nil,
            appexBundleID: nil,
            optionsPagePath: nil,
            defaultPopupPath: nil,
            hasBackground: false,
            hasAction: true,
            hasOptionsPage: false,
            hasContentScripts: false,
            hasExtensionPages: false,
            trustSummary: SafariExtensionTrustSummary(
                state: .developmentDirectory,
                teamID: nil,
                appBundleID: nil,
                appexBundleID: nil,
                signingIdentifier: nil,
                sourcePath: "/tmp/\(id)",
                importedAt: Date(timeIntervalSince1970: 0)
            ),
            activationSummary: ExtensionActivationSummary(
                matchPatternStrings: [],
                broadScope: false,
                hasContentScripts: false,
                hasAction: true,
                hasOptionsPage: false,
                hasExtensionPages: false
            ),
            manifest: [:]
        )
    }
}

@testable import Sumi
import SwiftData
import XCTest

@MainActor
final class SumiProfileRouterTests: XCTestCase {
    func testActiveProfileIdPrefersSpaceProfile() {
        let router = SumiProfileRouter()
        let currentProfile = Profile(name: "Current")
        let routedProfile = Profile(name: "Routed")
        let space = Space(name: "Work", profileId: routedProfile.id)

        XCTAssertEqual(
            router.activeProfileId(for: space, currentProfile: currentProfile),
            routedProfile.id
        )
    }

    func testAdoptProfileIfNeededRepairsUnknownWindowProfileId() throws {
        let router = SumiProfileRouter()
        let currentProfile = Profile(name: "Current")
        let support = try FakeSumiProfileRoutingSupport(
            currentProfile: currentProfile,
            profiles: [currentProfile]
        )

        let windowState = BrowserWindowState()
        windowState.currentProfileId = UUID()

        router.adoptProfileIfNeeded(
            for: windowState,
            context: .windowActivation,
            support: support
        )

        XCTAssertEqual(windowState.currentProfileId, currentProfile.id)
        XCTAssertNil(support.switchedProfileId)
    }

    func testAdoptProfileIfNeededSwitchesToWindowProfile() async throws {
        let router = SumiProfileRouter()
        let currentProfile = Profile(name: "Current")
        let targetProfile = Profile(name: "Target")
        let support = try FakeSumiProfileRoutingSupport(
            currentProfile: currentProfile,
            profiles: [currentProfile, targetProfile]
        )

        let windowState = BrowserWindowState()
        windowState.currentProfileId = targetProfile.id

        router.adoptProfileIfNeeded(
            for: windowState,
            context: .windowActivation,
            support: support
        )

        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(support.switchedProfileId, targetProfile.id)
        XCTAssertEqual(support.switchedWindowId, windowState.id)
    }

    func testWindowActivationSwitchUpdatesActiveRequestedWindow() async throws {
        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(
                container: try makeInMemoryStartupContainer()
            )
        )
        let currentProfile = try XCTUnwrap(browserManager.currentProfile)
        let targetProfile = Profile(name: "Target")
        let requestedWindow = BrowserWindowState()
        let activeWindow = BrowserWindowState()
        requestedWindow.currentProfileId = currentProfile.id
        activeWindow.currentProfileId = currentProfile.id

        let registry = WindowRegistry()
        registry.register(requestedWindow)
        registry.register(activeWindow)
        registry.setActive(requestedWindow)
        browserManager.windowRegistry = registry

        await browserManager.switchToProfile(
            targetProfile,
            context: .windowActivation,
            in: requestedWindow
        )

        XCTAssertEqual(requestedWindow.currentProfileId, targetProfile.id)
        XCTAssertEqual(activeWindow.currentProfileId, currentProfile.id)
        XCTAssertEqual(browserManager.currentProfile?.id, targetProfile.id)
    }

    func testWindowActivationSwitchIgnoresInactiveRequestedWindow() async throws {
        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(
                container: try makeInMemoryStartupContainer()
            )
        )
        let currentProfile = try XCTUnwrap(browserManager.currentProfile)
        let targetProfile = Profile(name: "Target")
        let requestedWindow = BrowserWindowState()
        let activeWindow = BrowserWindowState()
        requestedWindow.currentProfileId = currentProfile.id
        activeWindow.currentProfileId = currentProfile.id

        let registry = WindowRegistry()
        registry.register(requestedWindow)
        registry.register(activeWindow)
        registry.setActive(activeWindow)
        browserManager.windowRegistry = registry

        await browserManager.switchToProfile(
            targetProfile,
            context: .windowActivation,
            in: requestedWindow
        )

        XCTAssertEqual(requestedWindow.currentProfileId, currentProfile.id)
        XCTAssertEqual(activeWindow.currentProfileId, currentProfile.id)
        XCTAssertEqual(browserManager.currentProfile?.id, currentProfile.id)
    }

    private func makeInMemoryStartupContainer() throws -> ModelContainer {
        try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }
}

@MainActor
private final class FakeSumiProfileRoutingSupport: SumiProfileRoutingSupport {
    let currentProfile: Profile?
    let startupContainer: ModelContainer
    let profileManager: ProfileManager
    let windowRegistry: WindowRegistry? = WindowRegistry()

    private(set) var switchedProfileId: UUID?
    private(set) var switchedWindowId: UUID?

    init(currentProfile: Profile?, profiles: [Profile]) throws {
        self.currentProfile = currentProfile
        startupContainer = try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        self.profileManager = ProfileManager(context: startupContainer.mainContext)
        self.profileManager.profiles = profiles
    }

    func switchToProfile(
        _ profile: Profile,
        context _: BrowserManager.ProfileSwitchContext,
        in windowState: BrowserWindowState?
    ) async {
        switchedProfileId = profile.id
        switchedWindowId = windowState?.id
    }
}

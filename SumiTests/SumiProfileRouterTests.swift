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
    }
}

@MainActor
private final class FakeSumiProfileRoutingSupport: SumiProfileRoutingSupport {
    let currentProfile: Profile?
    let isSwitchingProfile = false
    let startupContainer: ModelContainer
    let profileManager: ProfileManager
    let windowRegistry: WindowRegistry? = WindowRegistry()

    private(set) var switchedProfileId: UUID?

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
        in _: BrowserWindowState?
    ) async {
        switchedProfileId = profile.id
    }
}

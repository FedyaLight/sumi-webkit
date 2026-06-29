import XCTest

@testable import Sumi

@MainActor
final class TabProfileResolutionOwnerTests: XCTestCase {
    func testResolveProfilePrefersMatchingEphemeralWindowProfile() {
        let harness = makeHarness()
        let ephemeralProfile = Profile(name: "Private")
        let tab = Tab(browserManager: harness.browserManager, loadsCachedFaviconOnInit: false)
        tab.profileId = ephemeralProfile.id

        let windowState = BrowserWindowState()
        windowState.isIncognito = true
        windowState.ephemeralProfile = ephemeralProfile
        windowState.ephemeralTabs = [tab]
        harness.windowRegistry.register(windowState)

        XCTAssertIdentical(
            tab.resolveProfile(),
            ephemeralProfile
        )
    }

    func testResolveProfileUsesExplicitProfileBeforeSpaceAndCurrentProfile() {
        let harness = makeHarness()
        let explicitProfile = Profile(name: "Explicit")
        let spaceProfile = Profile(name: "Space")
        let currentProfile = Profile(name: "Current")
        let space = Space(name: "Space", profileId: spaceProfile.id)
        let tab = Tab(browserManager: harness.browserManager, loadsCachedFaviconOnInit: false)

        harness.browserManager.profileManager.profiles = [
            currentProfile,
            spaceProfile,
            explicitProfile,
        ]
        harness.browserManager.currentProfile = currentProfile
        harness.browserManager.tabManager.spaces = [space]
        tab.spaceId = space.id
        tab.profileId = explicitProfile.id

        XCTAssertIdentical(
            tab.resolveProfile(),
            explicitProfile
        )
    }

    func testResolveProfileUsesSpaceProfileBeforeCurrentProfile() {
        let harness = makeHarness()
        let currentProfile = Profile(name: "Current")
        let spaceProfile = Profile(name: "Space")
        let space = Space(name: "Space", profileId: spaceProfile.id)
        let tab = Tab(browserManager: harness.browserManager, loadsCachedFaviconOnInit: false)

        harness.browserManager.profileManager.profiles = [currentProfile, spaceProfile]
        harness.browserManager.currentProfile = currentProfile
        harness.browserManager.tabManager.spaces = [space]
        tab.spaceId = space.id

        XCTAssertIdentical(
            tab.resolveProfile(),
            spaceProfile
        )
    }

    func testResolveProfileFallsBackToCurrentThenFirstProfile() {
        let harness = makeHarness()
        let firstProfile = Profile(name: "First")
        let currentProfile = Profile(name: "Current")
        let tab = Tab(browserManager: harness.browserManager, loadsCachedFaviconOnInit: false)

        harness.browserManager.profileManager.profiles = [firstProfile, currentProfile]
        harness.browserManager.currentProfile = currentProfile

        XCTAssertIdentical(tab.resolveProfile(), currentProfile)

        harness.browserManager.currentProfile = nil

        XCTAssertIdentical(tab.resolveProfile(), firstProfile)
    }

    private func makeHarness() -> Harness {
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        browserManager.windowRegistry = windowRegistry
        return Harness(
            browserManager: browserManager,
            windowRegistry: windowRegistry
        )
    }
}

@MainActor
private struct Harness {
    let browserManager: BrowserManager
    let windowRegistry: WindowRegistry
}

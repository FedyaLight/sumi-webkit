import Foundation
@testable import Sumi
import SumiDomain
import XCTest

@MainActor
final class BrowserWindowSpaceTransitionServiceTests: XCTestCase {
    func testTransitionRejectsStaleSameIDWindowAtEntry() throws {
        let harness = makeHarness()
        let staleWindow = BrowserWindowState(id: harness.window.id)
        harness.browser.tabResidenceAuthority.establishResidenceSession(on: staleWindow)
        staleWindow.currentSpaceId = harness.source.id
        staleWindow.currentProfileId = harness.profile.id

        harness.browser.windowSpaceTransitions.setActiveSpace(
            harness.destination,
            in: staleWindow
        )

        XCTAssertIdentical(
            harness.browser.spaceStateOwner.currentSpace,
            harness.source
        )
        XCTAssertEqual(staleWindow.currentSpaceId, harness.source.id)
        XCTAssertEqual(harness.window.currentSpaceId, harness.source.id)
    }

    func testRegisteredActiveWindowTransitionCommitsExactWindowAndSelection()
        throws {
        let harness = makeHarness()

        harness.browser.windowSpaceTransitions.setActiveSpace(
            harness.destination,
            in: harness.window
        )

        XCTAssertIdentical(
            harness.browser.spaceStateOwner.currentSpace,
            harness.destination
        )
        XCTAssertEqual(harness.window.currentSpaceId, harness.destination.id)
        XCTAssertEqual(
            harness.window.currentProfileId,
            harness.destination.profileId
        )
        XCTAssertEqual(harness.window.currentTabId, harness.targetTab.id)
    }

    func testInactiveRegisteredWindowDoesNotMutateProcessSpace() throws {
        let harness = makeHarness(active: false)

        harness.browser.windowSpaceTransitions.setActiveSpace(
            harness.destination,
            in: harness.window
        )

        XCTAssertIdentical(
            harness.browser.spaceStateOwner.currentSpace,
            harness.source
        )
        XCTAssertEqual(harness.window.currentSpaceId, harness.destination.id)
        XCTAssertEqual(harness.window.currentTabId, harness.targetTab.id)
    }

    func testDeferredRetryRejectsSameIDWindowReplacement() throws {
        let browser = BrowserManager()
        browser.tabRuntimeLifecycle.shutdown()
        let profile = Profile(name: "Deferred")
        let transition = DeferredSpaceProfileTransition()
        browser.runtimePortConnection.attach(TestRuntimePorts.make(
            currentProfileId: { profile.id },
            defaultProfileId: { profile.id },
            profileExists: { $0 == profile.id },
            profile: { $0 == profile.id ? profile : nil },
            webViewLifecycle: transition.makeLifecycle()
        ))
        browser.profileManager.profiles = [profile]
        browser.currentProfile = profile
        let source = Space(name: "Source", profileId: profile.id)
        let destination = Space(name: "Destination")
        browser.spaceStateOwner.replaceSpaces([source, destination])
        browser.spaceStateOwner.replaceCurrentSpace(source)
        let original = BrowserWindowState()
        browser.tabResidenceAuthority.establishResidenceSession(on: original)
        original.currentSpaceId = source.id
        original.currentProfileId = profile.id
        XCTAssertEqual(browser.windowRegistry.register(original), .registered)
        browser.windowRegistry.setActive(original)

        browser.windowSpaceTransitions.setActiveSpace(
            destination,
            in: original
        )
        XCTAssertEqual(transition.assignmentCount, 1)

        browser.windowRegistry.unregister(original.id)
        let replacement = BrowserWindowState(id: original.id)
        browser.tabResidenceAuthority.establishResidenceSession(on: replacement)
        replacement.currentSpaceId = source.id
        replacement.currentProfileId = profile.id
        XCTAssertEqual(
            browser.windowRegistry.register(replacement),
            .registered
        )
        browser.windowRegistry.setActive(replacement)

        XCTAssertTrue(try XCTUnwrap(transition.stageModel)())
        try XCTUnwrap(transition.publishCommit)()
        try XCTUnwrap(transition.settlement)(.committed)

        XCTAssertIdentical(browser.spaceStateOwner.currentSpace, source)
        XCTAssertEqual(original.currentSpaceId, source.id)
        XCTAssertEqual(replacement.currentSpaceId, source.id)
        XCTAssertEqual(destination.profileId, profile.id)
    }

    func testStaleInteractiveIdentityHasNoSideEffects() throws {
        let harness = makeHarness()
        let currentIdentity = SpaceTransitionIdentity(
            sourceSpaceId: harness.source.id,
            destinationSpaceId: harness.destination.id
        )
        harness.window.windowThemeState.beginInteractive(
            identity: currentIdentity,
            from: harness.source.workspaceTheme,
            to: harness.destination.workspaceTheme,
            initialProgress: 0.5
        )
        let staleIdentity = SpaceTransitionIdentity(
            sourceSpaceId: harness.source.id,
            destinationSpaceId: harness.destination.id
        )

        harness.browser.windowSpaceTransitions.setActiveSpace(
            harness.destination,
            in: harness.window,
            completingTransition: staleIdentity
        )

        XCTAssertIdentical(
            harness.browser.spaceStateOwner.currentSpace,
            harness.source
        )
        XCTAssertEqual(harness.window.currentSpaceId, harness.source.id)
    }

    private func makeHarness(active: Bool = true) -> Harness {
        let browser = BrowserManager()
        let profile = Profile(name: "Profile")
        browser.profileManager.profiles = [profile]
        browser.currentProfile = profile
        let source = Space(name: "Source", profileId: profile.id)
        let destination = Space(
            name: "Destination",
            workspaceTheme: WorkspaceTheme(gradientTheme: .incognito),
            profileId: profile.id
        )
        browser.spaceStateOwner.replaceSpaces([source, destination])
        browser.spaceStateOwner.replaceCurrentSpace(source)
        let targetTab = browser.regularTabLifecycleOwner.createNewTab(
            in: destination,
            activate: false
        )
        destination.activeTabId = targetTab.id
        let window = BrowserWindowState()
        browser.tabResidenceAuthority.establishResidenceSession(on: window)
        window.currentSpaceId = source.id
        window.currentProfileId = profile.id
        XCTAssertEqual(browser.windowRegistry.register(window), .registered)

        if active {
            browser.windowRegistry.setActive(window)
        } else {
            let activeWindow = BrowserWindowState()
            browser.tabResidenceAuthority.establishResidenceSession(on: activeWindow)
            activeWindow.currentSpaceId = source.id
            activeWindow.currentProfileId = profile.id
            XCTAssertEqual(
                browser.windowRegistry.register(activeWindow),
                .registered
            )
            browser.windowRegistry.setActive(activeWindow)
        }

        return Harness(
            browser: browser,
            profile: profile,
            source: source,
            destination: destination,
            targetTab: targetTab,
            window: window
        )
    }
}

@MainActor
private struct Harness {
    let browser: BrowserManager
    let profile: Profile
    let source: Space
    let destination: Space
    let targetTab: Tab
    let window: BrowserWindowState
}

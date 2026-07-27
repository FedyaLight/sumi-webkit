import AppKit
import SumiDomain
import SwiftUI
import XCTest

@testable import Sumi

@MainActor
final class SidebarPinCommandIdentityTests: XCTestCase {
    func testBackToPinnedURLSurvivesCustomMetadataReplacement() throws {
        let browser = try makeBrowser()
        defer { browser.tabRuntimeLifecycle.shutdown() }
        let space = Space(name: "Work")
        let window = BrowserWindowState()
        let pin = makePin(
            id: UUID(),
            title: "Launcher",
            spaceID: space.id
        )
        browser.spaceStateOwner.replaceSpaces([space])
        install(pin, in: browser, spaceID: space.id)
        browser.tabResidenceAuthority.establishResidenceSession(on: window)
        XCTAssertEqual(browser.windowRegistry.register(window), .registered)
        let liveTab = try XCTUnwrap(
            browser.shortcutTabMaterializer.materialize(
                pin,
                in: window.id,
                currentSpaceId: space.id
            )
        )
        let customized = try XCTUnwrap(
            browser.sidebarPinCommands.update(
                pin,
                title: "My Launcher",
                launchURL: pin.launchURL,
                iconAsset: "😥"
            )
        )
        liveTab.url = try XCTUnwrap(URL(string: "https://drifted.example"))

        XCTAssertTrue(
            browser.shortcutPresentationOwner.shortcutHasDrifted(
                customized,
                in: window
            )
        )
        XCTAssertTrue(
            browser.sidebarPinCommands.resetToLaunchURL(
                pin,
                in: window,
                preserveCurrentPage: false
            )
        )
        XCTAssertEqual(liveTab.url, pin.launchURL)
    }

    func testEditorCommitPersistsCustomMetadataAgainstReplacementInstance() throws {
        let browser = try makeBrowser()
        defer { browser.tabRuntimeLifecycle.shutdown() }
        let space = Space(name: "Work")
        browser.spaceStateOwner.replaceSpaces([space])
        let leading = makePin(
            id: UUID(),
            title: "Leading",
            spaceID: space.id,
            index: 2
        )
        let pin = makePin(
            id: UUID(),
            title: "Launcher",
            spaceID: space.id,
            index: 5
        )
        let trailing = makePin(
            id: UUID(),
            title: "Trailing",
            spaceID: space.id,
            index: 9
        )
        browser.shortcutPinCollectionStateOwner.replaceSpacePinnedShortcuts([
            space.id: [leading, pin, trailing],
        ])
        let session = ShortcutLinkEditorSession(pin: pin)
        session.title = "My Launcher"
        session.iconAsset = "😥"
        let replacement = makePin(
            id: pin.id,
            title: "CurrentPage",
            spaceID: space.id,
            index: pin.index
        )
        browser.shortcutPinCollectionStateOwner.replaceSpacePinnedShortcuts([
            space.id: [leading, replacement, trailing],
        ])

        XCTAssertTrue(session.hasChanges)
        browser.composeSidebarShortcutEditorPresentation().commit(session)

        let stored = try XCTUnwrap(
            browser.shortcutPinCollectionStateOwner.shortcutPin(by: pin.id)
        )
        XCTAssertEqual(stored.iconAsset, "😥")
        XCTAssertEqual(stored.title, "My Launcher")
        XCTAssertEqual(stored.launchURL, replacement.launchURL)
        XCTAssertTrue(stored.titleIsCustom)
        let orderedPins = browser.shortcutPinCollectionStateOwner
            .spacePinnedShortcutsSnapshot()[space.id] ?? []
        XCTAssertEqual(
            orderedPins.map(\.id),
            [leading.id, pin.id, trailing.id]
        )
        XCTAssertEqual(orderedPins.map(\.index), [2, 5, 9])
    }

    func testEditorEmojiRendersBeyondFaviconFrameWithoutCropping() throws {
        let pin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: UUID(),
            index: 0,
            launchURL: URL(string: "https://launcher.example")!,
            title: "Launcher"
        )
        let host = NSHostingView(rootView: ShortcutLinkEditorIcon(
            pin: pin,
            iconAsset: "😥",
            faviconImageReader: TabDependencyIsolationDefaults
                .faviconCapabilities.images
        ))
        host.frame = NSRect(x: 0, y: 0, width: 26, height: 26)
        host.layoutSubtreeIfNeeded()
        let image = try XCTUnwrap(
            host.bitmapImageRepForCachingDisplay(in: host.bounds)
        )
        host.cacheDisplay(in: host.bounds, to: image)

        let visibleColumns = (0..<image.pixelsWide).filter { x in
            (0..<image.pixelsHigh).contains { y in
                (image.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05
            }
        }
        let renderedWidth = CGFloat(
            try XCTUnwrap(visibleColumns.last)
                - XCTUnwrap(visibleColumns.first)
                + 1
        ) / (CGFloat(image.pixelsWide) / host.bounds.width)

        XCTAssertGreaterThan(
            renderedWidth,
            18,
            "Emoji was constrained to the editor's 18pt favicon frame"
        )
    }

    func testUserMetadataWinsAcrossInstancesUntilExplicitReset() throws {
        for role in [ShortcutPinRole.spacePinned, .essential] {
            let browser = try makeBrowser()
            defer { browser.tabRuntimeLifecycle.shutdown() }
            let profileID = UUID()
            let space = Space(name: "Work", profileId: profileID)
            browser.spaceStateOwner.replaceSpaces([space])
            let pin = ShortcutPin(
                id: UUID(),
                role: role,
                profileId: role == .essential ? profileID : nil,
                spaceId: role == .spacePinned ? space.id : nil,
                index: 0,
                launchURL: URL(string: "https://launcher.example")!,
                title: "Launcher"
            )
            if role == .essential {
                browser.structuralCollectionMutationOwner.setPinnedTabs(
                    [pin],
                    for: profileID
                )
            } else {
                install(pin, in: browser, spaceID: space.id)
            }

            let customized = try XCTUnwrap(
                browser.sidebarPinCommands.update(
                    pin,
                    title: "My Launcher",
                    launchURL: pin.launchURL,
                    iconAsset: "star.fill"
                )
            )
            let liveTabs = ["First Page", "Second Page"].map {
                Tab(name: $0, loadsCachedFaviconOnInit: false)
            }

            XCTAssertTrue(customized.titleIsCustom)
            XCTAssertEqual(customized.iconAsset, "star.fill")
            for liveTab in liveTabs {
                XCTAssertEqual(
                    customized.resolvedDisplayTitle(liveTab: liveTab),
                    "My Launcher"
                )
                let icon = SidebarShortcutIconResolver.resolve(
                    pin: customized,
                    liveTab: liveTab,
                    loadedStoredFavicon: nil,
                    partition: .regular(nil),
                    imageReader: TabDependencyIsolationDefaults
                        .faviconCapabilities.images
                )
                XCTAssertEqual(icon.systemImageName, "star.fill")
                XCTAssertNil(icon.image)
            }

            let reset = try XCTUnwrap(
                browser.sidebarPinCommands.update(
                    customized,
                    title: customized.title,
                    launchURL: customized.launchURL,
                    iconAsset: nil,
                    titleIsCustom: false
                )
            )

            XCTAssertFalse(reset.titleIsCustom)
            XCTAssertNil(reset.iconAsset)
            XCTAssertEqual(
                reset.resolvedDisplayTitle(liveTab: liveTabs[0]),
                "First Page"
            )
        }
    }

    func testExecutionProfileRejectsReplacedPinWithSameIdentity() throws {
        let browser = try makeBrowser()
        defer { browser.tabRuntimeLifecycle.shutdown() }
        let profile = Profile(name: "Execution")
        let space = Space(name: "Work", profileId: profile.id)
        let (stale, replacement) = makePinPair(spaceID: space.id)
        browser.profileManager.profiles = [profile]
        browser.spaceStateOwner.replaceSpaces([space])
        install(replacement, in: browser, spaceID: space.id)

        XCTAssertFalse(
            makeExecutionCommands(browser: browser)
                .assignExecutionProfile(stale, profileID: profile.id)
        )
        XCTAssertNil(replacement.executionProfileId)
    }

    func testMaterializationRejectsReplacedPinWithSameIdentity() throws {
        let browser = try makeBrowser()
        defer { browser.tabRuntimeLifecycle.shutdown() }
        let space = Space(name: "Work")
        let window = BrowserWindowState()
        let (stale, replacement) = makePinPair(spaceID: space.id)
        browser.spaceStateOwner.replaceSpaces([space])
        install(replacement, in: browser, spaceID: space.id)
        browser.tabResidenceAuthority.establishResidenceSession(on: window)
        XCTAssertEqual(browser.windowRegistry.register(window), .registered)

        XCTAssertNil(
            makeExecutionCommands(browser: browser).materialize(
                stale,
                in: window,
                currentSpaceID: space.id
            )
        )
        XCTAssertNil(
            browser.liveShortcutTabs.tab(for: replacement.id, in: window.id)
        )
    }

    func testMoveRejectsReplacedPinWithSameIdentity() throws {
        let browser = try makeBrowser()
        defer { browser.tabRuntimeLifecycle.shutdown() }
        let source = Space(name: "Source")
        let destination = Space(name: "Destination")
        let (stale, replacement) = makePinPair(spaceID: source.id)
        browser.spaceStateOwner.replaceSpaces([source, destination])
        install(replacement, in: browser, spaceID: source.id)

        XCTAssertFalse(
            browser.sidebarPinCommands.move(stale, toSpace: destination.id)
        )
        XCTAssertTrue(
            browser.shortcutPinCollectionStateOwner
                .shortcutPin(by: replacement.id) === replacement
        )
        XCTAssertEqual(replacement.spaceId, source.id)
    }

    private func makeBrowser() throws -> BrowserManager {
        let browser = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(
                container: try makeInMemoryStartupModelContainer()
            )
        )
        browser.startupRestoreLifecycle.markLoadFinished()
        browser.startupSessionRestoreOwner.markRestoreOfferConsumed()
        return browser
    }

    private func makeExecutionCommands(
        browser: BrowserManager
    ) -> SidebarPinExecutionCommands {
        SidebarPinExecutionCommands(
            runtime: browser.runtimePortConnection,
            windows: SidebarWindowIdentityQuery(
                registry: browser.windowRegistry
            ),
            pins: browser.shortcutPinCollectionStateOwner,
            materializer: browser.shortcutTabMaterializer,
            profiles: browser.shortcutExecutionProfileAssignments
        )
    }

    private func makePinPair(
        spaceID: UUID
    ) -> (stale: ShortcutPin, replacement: ShortcutPin) {
        let identity = UUID()
        return (
            makePin(id: identity, title: "Stale", spaceID: spaceID),
            makePin(id: identity, title: "Replacement", spaceID: spaceID)
        )
    }

    private func makePin(
        id: UUID,
        title: String,
        spaceID: UUID,
        index: Int = 0
    ) -> ShortcutPin {
        ShortcutPin(
            id: id,
            role: .spacePinned,
            spaceId: spaceID,
            index: index,
            launchURL: URL(string: "https://\(title.lowercased()).example")!,
            title: title
        )
    }

    private func install(
        _ pin: ShortcutPin,
        in browser: BrowserManager,
        spaceID: UUID
    ) {
        browser.shortcutPinCollectionStateOwner.replaceSpacePinnedShortcuts([
            spaceID: [pin],
        ])
    }
}

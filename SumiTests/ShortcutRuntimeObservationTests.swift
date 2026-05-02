import AppKit
import SwiftData
import SwiftUI
import UserScript
import XCTest
@testable import Sumi

@MainActor
final class ShortcutRuntimeObservationTests: XCTestCase {
    func testShortcutLiveTitleStaysTransientAndLauncherTitleRestoresAfterUnload() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.createSpace(name: "Videos")
        let sourceTab = Tab(
            url: URL(string: "https://www.youtube.com/watch?v=abc123")!,
            name: "Pinned Launcher Title",
            spaceId: space.id,
            index: 0
        )
        tabManager.addTab(sourceTab)

        let pin = try XCTUnwrap(
            tabManager.ensureSpacePinnedLauncher(for: sourceTab, in: space.id)
        )
        let windowId = UUID()
        let liveTab = tabManager.activateShortcutPin(
            pin,
            in: windowId,
            currentSpaceId: space.id
        )

        XCTAssertTrue(
            liveTab.acceptResolvedDisplayTitle(
                "Actual Video Title",
                url: liveTab.url
            )
        )
        XCTAssertEqual(tabManager.shortcutPin(by: pin.id)?.title, "Pinned Launcher Title")
        tabManager.deactivateShortcutLiveTab(pinId: pin.id, in: windowId)

        let reopened = tabManager.activateShortcutPin(
            pin,
            in: windowId,
            currentSpaceId: space.id
        )

        XCTAssertEqual(reopened.name, "Pinned Launcher Title")
        XCTAssertEqual(tabManager.shortcutPin(by: pin.id)?.title, "Pinned Launcher Title")
    }

    func testDriftedShortcutLiveTitleDoesNotReplaceLauncherTitleAfterUnload() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.createSpace(name: "Videos")
        let sourceTab = Tab(
            url: URL(string: "https://www.youtube.com/watch?v=launcher")!,
            name: "Launcher Video",
            spaceId: space.id,
            index: 0
        )
        tabManager.addTab(sourceTab)

        let pin = try XCTUnwrap(
            tabManager.ensureSpacePinnedLauncher(for: sourceTab, in: space.id)
        )
        let windowId = UUID()
        let liveTab = tabManager.activateShortcutPin(
            pin,
            in: windowId,
            currentSpaceId: space.id
        )

        let driftedURL = URL(string: "https://www.youtube.com/watch?v=drifted")!
        liveTab.handleSameDocumentNavigation(to: driftedURL)
        XCTAssertTrue(liveTab.acceptResolvedDisplayTitle("Drifted Video Title", url: driftedURL))

        XCTAssertEqual(liveTab.name, "Drifted Video Title")
        waitUntil("drifted live title is not persisted to launcher") {
            tabManager.shortcutPin(by: pin.id)?.title == "Launcher Video"
        }

        let preservedPin = try XCTUnwrap(tabManager.shortcutPin(by: pin.id))
        tabManager.deactivateShortcutLiveTab(pinId: pin.id, in: windowId)

        let reopened = tabManager.activateShortcutPin(
            preservedPin,
            in: windowId,
            currentSpaceId: space.id
        )

        XCTAssertEqual(reopened.name, "Launcher Video")
        XCTAssertEqual(tabManager.shortcutPin(by: pin.id)?.title, "Launcher Video")
    }

    func testLiveTitleUpdateChangesLauncherPresentationWithoutMutatingSavedTitle() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.createSpace(name: "Videos")
        let sourceTab = Tab(
            url: URL(string: "https://www.youtube.com/watch?v=launcher")!,
            name: "Launcher Video",
            spaceId: space.id,
            index: 0
        )
        tabManager.addTab(sourceTab)

        let pin = try XCTUnwrap(
            tabManager.ensureSpacePinnedLauncher(for: sourceTab, in: space.id)
        )
        let windowId = UUID()
        let liveTab = tabManager.activateShortcutPin(
            pin,
            in: windowId,
            currentSpaceId: space.id
        )
        let driftedURL = URL(string: "https://www.youtube.com/watch?v=drifted")!

        liveTab.handleSameDocumentNavigation(to: driftedURL)
        XCTAssertEqual(pin.resolvedDisplayTitle(liveTab: liveTab), "Launcher Video")

        XCTAssertTrue(liveTab.acceptResolvedDisplayTitle("Drifted Video Title", url: driftedURL))

        XCTAssertEqual(pin.resolvedDisplayTitle(liveTab: liveTab), "Drifted Video Title")
        XCTAssertEqual(tabManager.shortcutPin(by: pin.id)?.title, "Launcher Video")

        tabManager.deactivateShortcutLiveTab(pinId: pin.id, in: windowId)
        let reopened = tabManager.activateShortcutPin(
            pin,
            in: windowId,
            currentSpaceId: space.id
        )

        XCTAssertEqual(reopened.name, "Launcher Video")
        XCTAssertEqual(tabManager.shortcutPin(by: pin.id)?.title, "Launcher Video")
    }

    func testReplaceLauncherURLWithCurrentPersistsCurrentLiveTitleAndURL() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.createSpace(name: "Videos")
        let sourceTab = Tab(
            url: URL(string: "https://www.youtube.com/watch?v=launcher")!,
            name: "Launcher Video",
            spaceId: space.id,
            index: 0
        )
        tabManager.addTab(sourceTab)

        let pin = try XCTUnwrap(
            tabManager.ensureSpacePinnedLauncher(for: sourceTab, in: space.id)
        )
        let windowId = UUID()
        let liveTab = tabManager.activateShortcutPin(
            pin,
            in: windowId,
            currentSpaceId: space.id
        )

        let replacedURL = URL(string: "https://www.youtube.com/watch?v=replaced")!
        liveTab.handleSameDocumentNavigation(to: replacedURL)
        XCTAssertTrue(liveTab.acceptResolvedDisplayTitle("Replacement Video", url: replacedURL))

        let windowState = BrowserWindowState(id: windowId)
        windowState.currentSpaceId = space.id
        windowState.currentTabId = liveTab.id
        windowState.currentShortcutPinId = pin.id

        let updatedPin = try XCTUnwrap(
            tabManager.replaceShortcutPinURLWithCurrent(pin, in: windowState)
        )

        XCTAssertEqual(updatedPin.title, "Replacement Video")
        XCTAssertEqual(updatedPin.launchURL.absoluteString, "https://www.youtube.com/watch?v=replaced")

        tabManager.deactivateShortcutLiveTab(pinId: pin.id, in: windowId)

        let reopened = tabManager.activateShortcutPin(
            updatedPin,
            in: windowId,
            currentSpaceId: space.id
        )

        XCTAssertEqual(reopened.name, "Replacement Video")
        XCTAssertEqual(reopened.url.absoluteString, "https://www.youtube.com/watch?v=replaced")
    }

    func testReplaceLauncherURLWithCurrentKeepsPinInSpacePinnedProjection() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.createSpace(name: "Videos")
        let sourceTab = Tab(
            url: URL(string: "https://www.youtube.com/watch?v=launcher")!,
            name: "Launcher Video",
            spaceId: space.id,
            index: 0
        )
        tabManager.addTab(sourceTab)

        let pin = try XCTUnwrap(
            tabManager.ensureSpacePinnedLauncher(for: sourceTab, in: space.id)
        )
        let windowId = UUID()
        let liveTab = tabManager.activateShortcutPin(
            pin,
            in: windowId,
            currentSpaceId: space.id
        )

        let replacedURL = URL(string: "https://www.youtube.com/watch?v=replaced")!
        liveTab.handleSameDocumentNavigation(to: replacedURL)
        XCTAssertTrue(liveTab.acceptResolvedDisplayTitle("Replacement Video", url: replacedURL))

        let windowState = BrowserWindowState(id: windowId)
        windowState.currentSpaceId = space.id
        windowState.currentTabId = liveTab.id
        windowState.currentShortcutPinId = pin.id

        let updatedPin = try XCTUnwrap(
            tabManager.replaceShortcutPinURLWithCurrent(pin, in: windowState)
        )
        let projection = tabManager.launcherProjection(for: space.id, in: windowId)

        XCTAssertEqual(tabManager.spacePinnedPins(for: space.id).map(\.id), [pin.id])
        XCTAssertEqual(projection.topLevelPins.map(\.id), [pin.id])
        XCTAssertEqual(projection.liveTabsByPinId[pin.id]?.id, liveTab.id)
        XCTAssertEqual(projection.liveTabsByPinId[pin.id]?.shortcutPinId, pin.id)
        XCTAssertEqual(projection.liveTabsByPinId[pin.id]?.shortcutPinRole, .spacePinned)
        XCTAssertEqual(projection.liveTabsByPinId[pin.id]?.spaceId, space.id)
        XCTAssertEqual(updatedPin.id, pin.id)
    }

    func testResetLauncherURLKeepsPinInSpacePinnedProjection() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.createSpace(name: "Videos")
        let sourceTab = Tab(
            url: URL(string: "https://www.youtube.com/watch?v=launcher")!,
            name: "Launcher Video",
            spaceId: space.id,
            index: 0
        )
        tabManager.addTab(sourceTab)

        let pin = try XCTUnwrap(
            tabManager.ensureSpacePinnedLauncher(for: sourceTab, in: space.id)
        )
        let windowId = UUID()
        let liveTab = tabManager.activateShortcutPin(
            pin,
            in: windowId,
            currentSpaceId: space.id
        )

        let driftedURL = URL(string: "https://www.youtube.com/watch?v=drifted")!
        liveTab.handleSameDocumentNavigation(to: driftedURL)
        XCTAssertTrue(liveTab.acceptResolvedDisplayTitle("Drifted Video Title", url: driftedURL))

        let windowState = BrowserWindowState(id: windowId)
        windowState.currentSpaceId = space.id
        windowState.currentTabId = liveTab.id
        windowState.currentShortcutPinId = pin.id

        let updatedPin = try XCTUnwrap(
            tabManager.resetShortcutPinToLaunchURL(pin, in: windowState)
        )
        let projection = tabManager.launcherProjection(for: space.id, in: windowId)

        XCTAssertEqual(tabManager.spacePinnedPins(for: space.id).map(\.id), [pin.id])
        XCTAssertEqual(projection.topLevelPins.map(\.id), [pin.id])
        XCTAssertEqual(projection.liveTabsByPinId[pin.id]?.id, liveTab.id)
        XCTAssertEqual(projection.liveTabsByPinId[pin.id]?.shortcutPinId, pin.id)
        XCTAssertEqual(projection.liveTabsByPinId[pin.id]?.shortcutPinRole, .spacePinned)
        XCTAssertEqual(projection.liveTabsByPinId[pin.id]?.spaceId, space.id)
        XCTAssertEqual(updatedPin.id, pin.id)
        XCTAssertEqual(projection.liveTabsByPinId[pin.id]?.url, pin.launchURL)
    }

    func testShortcutPinMigratesLegacySystemIconNameIntoIconAsset() {
        let pin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            profileId: nil,
            spaceId: UUID(),
            index: 0,
            folderId: nil,
            launchURL: URL(string: "https://example.com")!,
            title: "Launcher",
            systemIconName: "house"
        )

        XCTAssertEqual(pin.iconAsset, "house")
    }

    func testLauncherIconAssetPersistsAcrossSnapshotReload() async throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("store")
        defer {
            let fm = FileManager.default
            try? fm.removeItem(at: storeURL)
            try? fm.removeItem(at: URL(fileURLWithPath: storeURL.path + "-shm"))
            try? fm.removeItem(at: URL(fileURLWithPath: storeURL.path + "-wal"))
        }

        let container = try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(url: storeURL)]
        )
        let tabManager = TabManager(context: container.mainContext, loadPersistedState: false)
        let space = tabManager.createSpace(name: "Videos")
        let sourceTab = Tab(
            url: URL(string: "https://example.com/launcher")!,
            name: "Launcher",
            spaceId: space.id,
            index: 0
        )
        tabManager.addTab(sourceTab)

        let pin = try XCTUnwrap(
            tabManager.ensureSpacePinnedLauncher(for: sourceTab, in: space.id)
        )
        let updatedPin = try XCTUnwrap(
            tabManager.updateShortcutPin(pin, iconAsset: "🚀")
        )

        XCTAssertEqual(updatedPin.iconAsset, "🚀")
        let updatedPinID = updatedPin.id
        try await waitForPersistedShortcutPin(updatedPinID, in: container) { entity in
            entity.iconAsset == "🚀"
        }

        let verificationContext = ModelContext(container)
        let predicate = #Predicate<TabEntity> { $0.id == updatedPinID }
        let storedEntity = try XCTUnwrap(
            verificationContext.fetch(FetchDescriptor<TabEntity>(predicate: predicate)).first
        )
        XCTAssertEqual(storedEntity.iconAsset, "🚀")

        let restoredTabManager = TabManager(
            context: ModelContext(container),
            loadPersistedState: false
        )
        await restoredTabManager.loadFromStoreAwaitingResult()

        XCTAssertEqual(
            restoredTabManager.shortcutPin(by: updatedPin.id)?.iconAsset,
            "🚀"
        )
    }

    func testShortcutSidebarRuntimeUsesCurrentLiveTitleAndDragExclusions() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = tabManager.createSpace(name: "Videos")
        let sourceTab = Tab(
            url: URL(string: "https://www.youtube.com/watch?v=launcher")!,
            name: "Launcher Video",
            spaceId: space.id,
            index: 0
        )
        tabManager.addTab(sourceTab)

        let pin = try XCTUnwrap(
            tabManager.ensureSpacePinnedLauncher(for: sourceTab, in: space.id)
        )
        let windowId = UUID()
        let liveTab = tabManager.activateShortcutPin(
            pin,
            in: windowId,
            currentSpaceId: space.id
        )
        let windowState = BrowserWindowState(id: windowId)
        windowState.currentSpaceId = space.id
        let initialRuntimeAffordance = tabManager.shortcutRuntimeAffordanceState(
            for: pin,
            in: windowState
        )
        let initialDragConfiguration = try XCTUnwrap(
            makeShortcutSidebarDragSourceConfiguration(
                pin: pin,
                resolvedTitle: pin.resolvedDisplayTitle(liveTab: liveTab),
                runtimeAffordance: initialRuntimeAffordance,
                dragSourceZone: .spacePinned(space.id),
                dragHasTrailingActionExclusion: true
            )
        )

        XCTAssertEqual(pin.resolvedDisplayTitle(liveTab: liveTab), "Launcher Video")
        XCTAssertEqual(initialDragConfiguration.item.title, "Launcher Video")
        XCTAssertEqual(initialDragConfiguration.exclusionZones.count, 1)
        XCTAssertFalse(initialRuntimeAffordance.usesResetLeadingAction)

        let driftedURL = URL(string: "https://www.youtube.com/watch?v=drifted")!
        liveTab.handleSameDocumentNavigation(to: driftedURL)
        XCTAssertTrue(liveTab.acceptResolvedDisplayTitle("Drifted Video Title", url: driftedURL))

        let updatedRuntimeAffordance = tabManager.shortcutRuntimeAffordanceState(
            for: pin,
            in: windowState
        )
        let updatedDragConfiguration = try XCTUnwrap(
            makeShortcutSidebarDragSourceConfiguration(
                pin: pin,
                resolvedTitle: pin.resolvedDisplayTitle(liveTab: liveTab),
                runtimeAffordance: updatedRuntimeAffordance,
                dragSourceZone: .spacePinned(space.id),
                dragHasTrailingActionExclusion: true
            )
        )

        XCTAssertEqual(pin.resolvedDisplayTitle(liveTab: liveTab), "Drifted Video Title")
        XCTAssertEqual(updatedDragConfiguration.item.title, "Drifted Video Title")
        XCTAssertEqual(updatedDragConfiguration.exclusionZones.count, 2)
        XCTAssertTrue(updatedRuntimeAffordance.usesResetLeadingAction)
    }

    func testPinnedGridDragConfigurationTracksObservedLiveTabTitle() throws {
        let tabManager = try makeInMemoryTabManager()
        let profileId = UUID()
        let pin = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: profileId,
            spaceId: nil,
            index: 0,
            folderId: nil,
            launchURL: URL(string: "https://example.com/launcher")!,
            title: "Launcher",
            iconAsset: nil
        )
        tabManager.setPinnedTabs([pin], for: profileId)

        let windowId = UUID()
        let liveTab = tabManager.activateShortcutPin(
            pin,
            in: windowId,
            currentSpaceId: nil
        )
        let initialDragConfiguration = makePinnedTileDragSourceConfiguration(
            pin: pin,
            resolvedTitle: pin.resolvedDisplayTitle(liveTab: liveTab),
            previewIcon: pin.favicon,
            pinnedConfiguration: .large,
            exclusionZones: []
        )
        XCTAssertEqual(initialDragConfiguration.item.title, "Launcher")

        let updatedURL = URL(string: "https://example.com/updated")!
        liveTab.handleSameDocumentNavigation(to: updatedURL)
        XCTAssertTrue(liveTab.acceptResolvedDisplayTitle("Updated Essentials Title", url: updatedURL))

        let updatedDragConfiguration = makePinnedTileDragSourceConfiguration(
            pin: pin,
            resolvedTitle: pin.resolvedDisplayTitle(liveTab: liveTab),
            previewIcon: pin.favicon,
            pinnedConfiguration: .large,
            exclusionZones: []
        )
        XCTAssertEqual(updatedDragConfiguration.item.title, "Updated Essentials Title")
    }

    func testPropagateLauncherFaviconRefreshesPinCacheKey() throws {
        let tabManager = try makeInMemoryTabManager()
        let profileId = UUID()
        let pinId = UUID()
        let pin = ShortcutPin(
            id: pinId,
            role: .essential,
            profileId: profileId,
            spaceId: nil,
            index: 0,
            folderId: nil,
            launchURL: URL(string: "about:blank")!,
            title: "Example",
            iconAsset: nil
        )
        tabManager.setPinnedTabs([pin], for: profileId)

        let tab = Tab(
            url: URL(string: "https://example.com/favicon")!,
            name: "Example",
            favicon: "globe",
            spaceId: nil,
            index: 0
        )
        tab.bindToShortcutPin(try XCTUnwrap(tabManager.shortcutPin(by: pinId)))
        tab.favicon = Image(systemName: "house.fill")
        tab.faviconIsTemplateGlobePlaceholder = false

        XCTAssertNil(pin.faviconCacheKey)

        tabManager.propagateLauncherFaviconFromLiveTabIfNeeded(tab)

        XCTAssertEqual(
            pin.faviconCacheKey,
            ShortcutPin.makeFaviconCacheKey(for: URL(string: "https://example.com/favicon")!)
        )
    }

    func testFaviconCacheUpdateRefreshesLauncherOnlyPinWithoutReopening() async throws {
        let tabManager = try makeInMemoryTabManager()
        let profileId = UUID()
        let launchURL = URL(string: "https://refresh.example.com/page")!
        let pin = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: profileId,
            spaceId: nil,
            index: 0,
            folderId: nil,
            launchURL: launchURL,
            title: "Launcher",
            iconAsset: nil
        )
        tabManager.setPinnedTabs([pin], for: profileId)

        let beforeRender = render(image: pin.favicon)
        let expectedData = try XCTUnwrap(makeImageData(color: .systemGreen, size: 64))
        let expectedImage = try XCTUnwrap(NSImage(data: expectedData))
        let expectedRender = render(image: Image(nsImage: expectedImage))
        let faviconURL = try XCTUnwrap(URL(string: "https://refresh.example.com/apple-touch-icon.png"))
        try await SumiFaviconSystem.shared.manager.storeFavicon(expectedData, with: faviconURL, for: launchURL)

        waitUntil("launcher-only pin should refresh from favicon cache update") {
            self.render(image: pin.favicon).tiffRepresentation == expectedRender.tiffRepresentation
        }

        let afterRender = render(image: pin.favicon)
        XCTAssertNotEqual(beforeRender.tiffRepresentation, afterRender.tiffRepresentation)
        XCTAssertEqual(afterRender.tiffRepresentation, expectedRender.tiffRepresentation)
    }

    private func makeInMemoryTabManager() throws -> TabManager {
        let container = try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return TabManager(context: container.mainContext, loadPersistedState: false)
    }

    private func render(image: Image, size: CGSize = CGSize(width: 18, height: 18)) -> NSImage {
        let host = NSHostingView(
            rootView: image
                .resizable()
                .scaledToFit()
                .frame(width: size.width, height: size.height)
        )
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()

        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)

        let rendered = NSImage(size: host.bounds.size)
        rendered.addRepresentation(rep)
        return rendered
    }

    private func makeImageData(color: NSColor, size: CGFloat) -> Data? {
        let pixelSize = max(1, Int(size.rounded()))
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        color.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize)).fill()
        NSGraphicsContext.restoreGraphicsState()

        return bitmap.representation(using: .png, properties: [:])
    }

    private func makeDataURL(color: NSColor, size: CGFloat) -> URL? {
        guard let data = makeImageData(color: color, size: size) else { return nil }
        return URL(string: "data:image/png;base64,\(data.base64EncodedString())")
    }

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 1.0,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: () -> Bool
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }

            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }

        XCTAssertTrue(condition(), description, file: file, line: line)
    }

    private func waitForPersistedShortcutPin(
        _ pinId: UUID,
        in container: ModelContainer,
        file: StaticString = #filePath,
        line: UInt = #line,
        matching predicate: (TabEntity) -> Bool
    ) async throws {
        let predicateID = pinId
        let fetchDescriptor = FetchDescriptor<TabEntity>(
            predicate: #Predicate<TabEntity> { $0.id == predicateID }
        )

        for _ in 0..<50 {
            let context = ModelContext(container)
            if let entity = try context.fetch(fetchDescriptor).first,
               predicate(entity) {
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        let context = ModelContext(container)
        let entity = try XCTUnwrap(
            context.fetch(fetchDescriptor).first,
            file: file,
            line: line
        )
        XCTAssertTrue(predicate(entity), file: file, line: line)
    }
}

import AppKit
import SumiDomain
import XCTest

@testable import Sumi

@MainActor
final class SumiFavoriteBackdropStoreTests: XCTestCase {
    func testOnlyFavoriteRetainAndBakeArtifacts() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let reader = CountingBackdropFaviconReader(image: testImage())
        let store = SumiFavoriteBackdropStore(
            rootDirectory: root,
            imageReader: reader
        )
        let profileID = UUID()
        let regular = pin(
            url: "https://regular.example",
            profileID: profileID,
            role: .spacePinned
        )
        let builtInFavorite = ShortcutPin(
            id: UUID(),
            role: .favorite,
            profileId: profileID,
            index: 1,
            launchURL: URL(string: "https://built-in.example")!,
            title: "Built-in",
            iconAsset: "🌍"
        )

        store.syncFavorite([regular, builtInFavorite])

        let result = await store.loadBackdrop(
            for: regular.launchURL,
            partition: .regular()
        )
        XCTAssertNil(result)
        let builtInResult = await store.loadBackdrop(
            for: builtInFavorite.launchURL,
            partition: .regular()
        )
        XCTAssertNil(builtInResult)
        XCTAssertEqual(reader.requestCount, 0)
    }

    func testDuplicateSiteSharesArtifactAcrossRegularProfiles() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let reader = CountingBackdropFaviconReader(image: testImage())
        let store = SumiFavoriteBackdropStore(
            rootDirectory: root,
            imageReader: reader
        )
        let firstProfile = UUID()
        let secondProfile = UUID()
        let first = pin(
            url: "https://example.com/one",
            profileID: firstProfile
        )
        let duplicate = pin(
            url: "https://example.com/two",
            profileID: firstProfile
        )
        let separateProfile = pin(
            url: "https://example.com/three",
            profileID: secondProfile
        )

        store.syncFavorite([first, duplicate, separateProfile])
        _ = await store.loadBackdrop(
            for: first.launchURL,
            partition: .regular()
        )
        _ = await store.loadBackdrop(
            for: duplicate.launchURL,
            partition: .regular()
        )
        _ = await store.loadBackdrop(
            for: separateProfile.launchURL,
            partition: .regular()
        )

        XCTAssertEqual(reader.requestCount, 1)
    }

    func testRemovingLastOwnerCancelsStaleBakeWithoutResurrection() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = ControlledBackdropFaviconReader()
        let store = SumiFavoriteBackdropStore(
            rootDirectory: root,
            imageReader: controller
        )
        let profileID = UUID()
        let favorite = pin(
            url: "https://cancel.example/page",
            profileID: profileID
        )

        store.syncFavorite([favorite])
        await controller.waitUntilRequested()
        store.syncFavorite([])
        await controller.resume(with: testImage())

        for _ in 0..<20 {
            if try await SumiFavoriteBackdropDiskStorage(
                rootDirectory: root
            ).existingKeys().isEmpty {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertNil(store.cachedBackdrop(
            for: favorite.launchURL,
            partition: .regular()
        ))
        let keys = try await SumiFavoriteBackdropDiskStorage(
            rootDirectory: root
        ).existingKeys()
        XCTAssertTrue(keys.isEmpty)
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func pin(
        url: String,
        profileID: UUID,
        role: ShortcutPinRole = .favorite
    ) -> ShortcutPin {
        ShortcutPin(
            id: UUID(),
            role: role,
            profileId: profileID,
            index: 0,
            launchURL: URL(string: url)!,
            title: "Test"
        )
    }

    private func testImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.lockFocus()
        NSColor.systemRed.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 16, height: 16)).fill()
        image.unlockFocus()
        return image
    }
}

private final class CountingBackdropFaviconReader:
    BrowserFaviconImageReading,
    @unchecked Sendable
{
    private let lock = NSLock()
    private let image: NSImage
    private var requests = 0

    init(image: NSImage) {
        self.image = image
    }

    var requestCount: Int {
        lock.withLock { requests }
    }

    func cachedPreparedImage(for _: SumiPreparedFaviconRequest) -> NSImage? {
        lock.withLock {
            requests += 1
            return image
        }
    }

    func cachedSelection(
        for _: URL,
        partition _: SumiFaviconPartition
    ) -> SumiStoredFaviconSelection? {
        nil
    }

    func preparedImage(
        for _: SumiPreparedFaviconRequest,
        priority _: SumiFaviconFetchPriority,
        scheduleFetchOnMiss _: Bool
    ) async -> NSImage? {
        nil
    }
}

private final class ControlledBackdropFaviconReader:
    BrowserFaviconImageReading,
    @unchecked Sendable
{
    private let state = ControlledBackdropFaviconState()

    func cachedPreparedImage(for _: SumiPreparedFaviconRequest) -> NSImage? {
        nil
    }

    func cachedSelection(
        for _: URL,
        partition _: SumiFaviconPartition
    ) -> SumiStoredFaviconSelection? {
        nil
    }

    func preparedImage(
        for _: SumiPreparedFaviconRequest,
        priority _: SumiFaviconFetchPriority,
        scheduleFetchOnMiss _: Bool
    ) async -> NSImage? {
        guard let data = await state.requestImage() else { return nil }
        return NSImage(data: data)
    }

    func waitUntilRequested() async {
        await state.waitUntilRequested()
    }

    func resume(with image: NSImage?) async {
        await state.resume(with: image?.tiffRepresentation)
    }
}

private actor ControlledBackdropFaviconState {
    private var imageContinuation: CheckedContinuation<Data?, Never>?
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []

    func requestImage() async -> Data? {
        for waiter in requestWaiters { waiter.resume() }
        requestWaiters.removeAll()
        return await withCheckedContinuation { continuation in
            imageContinuation = continuation
        }
    }

    func waitUntilRequested() async {
        if imageContinuation != nil { return }
        await withCheckedContinuation { continuation in
            requestWaiters.append(continuation)
        }
    }

    func resume(with data: Data?) {
        imageContinuation?.resume(returning: data)
        imageContinuation = nil
    }
}

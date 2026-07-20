import AppKit
import Combine
import OSLog

@MainActor
final class SumiEssentialBackdropStore: BrowserEssentialBackdropReading {
    private static let log = Logger.sumi(category: "EssentialBackdropStore")

    private let diskStorage: SumiEssentialBackdropDiskStorage
    private let imageReader: any BrowserFaviconImageReading
    private let imageCache = NSCache<NSString, NSImage>()
    private var currentEntries: [SumiEssentialBackdropKey: URL] = [:]
    private var generations: [SumiEssentialBackdropKey: UInt64] = [:]
    private var bakeTasks: [
        SumiEssentialBackdropKey: Task<NSImage?, Never>
    ] = [:]
    private var reconcileTask: Task<Void, Never>?
    private var faviconUpdates: AnyCancellable?

    init(
        rootDirectory: URL,
        imageReader: any BrowserFaviconImageReading
    ) {
        diskStorage = SumiEssentialBackdropDiskStorage(
            rootDirectory: rootDirectory
        )
        self.imageReader = imageReader
        imageCache.countLimit = 128
        imageCache.totalCostLimit = 2 * 1_024 * 1_024
    }

    func syncEssentials(_ pins: [ShortcutPin]) {
        let entries = SumiEssentialBackdropReconcilePlan.entries(for: pins)
        updateFaviconSubscription(isNeeded: !entries.isEmpty)
        let removedKeys = Set(currentEntries.keys).subtracting(entries.keys)
        for key in removedKeys {
            cancelWork(for: key)
            let removalGeneration = generations[key]
            imageCache.removeObject(forKey: key.cacheIdentifier)
            Task { [weak self] in
                await self?.removeArtifact(
                    for: key,
                    generation: removalGeneration
                )
            }
        }
        currentEntries = entries
        reconcileTask?.cancel()
        reconcileTask = Task { [weak self] in
            await self?.reconcile(entries: entries)
        }
    }

    func cachedBackdrop(
        for documentURL: URL,
        partition: SumiFaviconPartition
    ) -> NSImage? {
        guard let key = SumiEssentialBackdropKey(
            documentURL: documentURL,
            partition: partition
        ), currentEntries[key] != nil else { return nil }
        return imageCache.object(forKey: key.cacheIdentifier)
    }

    func loadBackdrop(
        for documentURL: URL,
        partition: SumiFaviconPartition
    ) async -> NSImage? {
        guard let key = SumiEssentialBackdropKey(
            documentURL: documentURL,
            partition: partition
        ), let currentURL = currentEntries[key] else { return nil }
        if let cached = imageCache.object(forKey: key.cacheIdentifier) {
            return cached
        }

        do {
            if let data = try await diskStorage.read(key.storedKey),
               let image = decodedImage(data) {
                cache(image, for: key)
                return image
            }
        } catch {
            Self.log.error(
                "Failed to read essential backdrop: \(String(describing: error), privacy: .public)"
            )
        }
        return await bake(
            key: key,
            documentURL: currentURL,
            replacesExisting: false
        )
    }

    private func reconcile(
        entries: [SumiEssentialBackdropKey: URL]
    ) async {
        do {
            let existing = try await diskStorage.existingKeys()
            guard !Task.isCancelled else { return }
            let plan = SumiEssentialBackdropReconcilePlan.compute(
                current: Set(entries.keys),
                existing: existing
            )

            for key in plan.toDelete {
                guard !Task.isCancelled else { return }
                try await diskStorage.remove(key)
            }
            for key in plan.toBake {
                guard !Task.isCancelled,
                      let documentURL = entries[key]
                else { return }
                _ = await bake(
                    key: key,
                    documentURL: documentURL,
                    replacesExisting: false
                )
            }
        } catch {
            Self.log.error(
                "Failed to reconcile essential backdrops: \(String(describing: error), privacy: .public)"
            )
        }
    }

    private func updateFaviconSubscription(isNeeded: Bool) {
        if isNeeded, faviconUpdates == nil {
            faviconUpdates = NotificationCenter.default
                .publisher(for: .faviconCacheUpdated)
                .sink { [weak self] notification in
                    self?.handleFaviconUpdate(notification)
                }
        } else if !isNeeded {
            faviconUpdates = nil
        }
    }

    private func handleFaviconUpdate(_ notification: Notification) {
        let affected = currentEntries.filter { key, documentURL in
            SumiFaviconNotificationMatcher.update(
                notification,
                matches: documentURL,
                partition: key.partition
            )
        }
        guard !affected.isEmpty else { return }

        Task { [weak self] in
            guard let self else { return }
            for (key, documentURL) in affected {
                _ = await bake(
                    key: key,
                    documentURL: documentURL,
                    replacesExisting: true
                )
            }
        }
    }

    private func bake(
        key: SumiEssentialBackdropKey,
        documentURL: URL,
        replacesExisting: Bool
    ) async -> NSImage? {
        if !replacesExisting, let task = bakeTasks[key] {
            return await task.value
        }
        cancelWork(for: key)
        let generation = generations[key, default: 0] &+ 1
        generations[key] = generation
        let task = Task { [weak self] in
            await self?.performBake(
                key: key,
                documentURL: documentURL,
                generation: generation
            )
        }
        bakeTasks[key] = task
        let image = await task.value
        if generations[key] == generation {
            bakeTasks[key] = nil
        }
        return image
    }

    private func performBake(
        key: SumiEssentialBackdropKey,
        documentURL: URL,
        generation: UInt64
    ) async -> NSImage? {
        let cachedFavicon = TabFaviconStore.getCachedImage(
            forDocumentURL: documentURL,
            partition: key.partition,
            context: .pinnedLauncher,
            imageReader: imageReader
        )
        let favicon = if let cachedFavicon {
            cachedFavicon
        } else {
            await TabFaviconStore.loadCachedLauncherImage(
                forDocumentURL: documentURL,
                partition: key.partition,
                imageReader: imageReader
            )
        }
        guard isCurrent(key, generation: generation),
              let favicon,
              let data = SumiEssentialBackdropRenderer.bake(favicon: favicon),
              let image = decodedImage(data)
        else { return nil }

        do {
            try await diskStorage.write(data, for: key.storedKey)
        } catch {
            Self.log.error(
                "Failed to write essential backdrop: \(String(describing: error), privacy: .public)"
            )
            return nil
        }
        guard isCurrent(key, generation: generation) else {
            try? await diskStorage.remove(key.storedKey, ifMatching: data)
            return nil
        }

        cache(image, for: key)
        NotificationCenter.default.post(
            name: .essentialBackdropUpdated,
            object: self,
            userInfo: [
                Notification.Name.essentialBackdropReferenceKey:
                    key.referenceKey,
                Notification.Name.essentialBackdropPartitionKey:
                    key.partition.storageComponent,
            ]
        )
        return image
    }

    private func isCurrent(
        _ key: SumiEssentialBackdropKey,
        generation: UInt64
    ) -> Bool {
        !Task.isCancelled
            && currentEntries[key] != nil
            && generations[key] == generation
    }

    private func cancelWork(for key: SumiEssentialBackdropKey) {
        generations[key] = generations[key, default: 0] &+ 1
        bakeTasks.removeValue(forKey: key)?.cancel()
    }

    private func removeArtifact(
        for key: SumiEssentialBackdropKey,
        generation: UInt64?
    ) async {
        guard currentEntries[key] == nil,
              generations[key] == generation
        else { return }
        do {
            try await diskStorage.remove(key.storedKey)
        } catch {
            Self.log.error(
                "Failed to remove essential backdrop: \(String(describing: error), privacy: .public)"
            )
        }
    }

    private func decodedImage(_ data: Data) -> NSImage? {
        guard let image = NSImage(data: data) else { return nil }
        image.size = NSSize(
            width: SumiEssentialBackdropRenderer.pixelDimension,
            height: SumiEssentialBackdropRenderer.pixelDimension
        )
        return image
    }

    private func cache(
        _ image: NSImage,
        for key: SumiEssentialBackdropKey
    ) {
        imageCache.setObject(
            image,
            forKey: key.cacheIdentifier,
            cost: SumiEssentialBackdropRenderer.pixelDimension
                * SumiEssentialBackdropRenderer.pixelDimension * 4
        )
    }
}

import Observation
import SumiDomain
import SwiftUI

@MainActor
@Observable
final class SidebarFaviconImageStore {
    struct Request: Hashable {
        let launchURL: URL
        let partition: SumiFaviconPartition
        let context: SumiFaviconDisplayContext
    }

    @MainActor
    @Observable
    final class Entry {
        weak var image: NSImage?
        var didLookupImage = false
        var revision: UInt64 = 0
    }

    private struct InFlightLoad {
        let id: UUID
        let task: Task<Void, Never>
    }

    @ObservationIgnored private var entries: [Request: Entry] = [:]
    @ObservationIgnored private var inFlightLoads: [Request: InFlightLoad] = [:]
    @ObservationIgnored private var prewarmQueue: [Request] = []
    @ObservationIgnored private var prewarmIndex = 0
    @ObservationIgnored private var queuedPrewarmRequests = Set<Request>()
    @ObservationIgnored private var prewarmTask: Task<Void, Never>?
    @ObservationIgnored private weak var configuredImageReader:
        (any BrowserFaviconImageReading)?
    @ObservationIgnored private let notificationCenter: NotificationCenter
    @ObservationIgnored private var cacheUpdateObserver: NSObjectProtocol?

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
        cacheUpdateObserver = notificationCenter.addObserver(
            forName: .faviconCacheUpdated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let updatedDomain = notification.userInfo?[
                NSNotification.Name.faviconCacheUpdatedDomainKey
            ] as? String
            let updatedPartition = notification.userInfo?[
                NSNotification.Name.faviconCacheUpdatedPartitionKey
            ] as? String
            Task { @MainActor [weak self] in
                self?.invalidateEntries(
                    updatedDomain: updatedDomain,
                    updatedPartition: updatedPartition
                )
            }
        }
    }

    deinit {
        MainActor.assumeIsolated {
            stopObserving()
        }
    }

    private func stopObserving() {
        if let cacheUpdateObserver {
            notificationCenter.removeObserver(cacheUpdateObserver)
            self.cacheUpdateObserver = nil
        }
        for load in inFlightLoads.values {
            load.task.cancel()
        }
        inFlightLoads.removeAll()
        prewarmTask?.cancel()
        prewarmTask = nil
        prewarmQueue.removeAll()
        prewarmIndex = 0
        queuedPrewarmRequests.removeAll()
    }

    func configure(imageReader: any BrowserFaviconImageReading) {
        configuredImageReader = imageReader
    }

    /// Starts durable window-scoped loads before SwiftUI rows mount. Repeated
    /// root updates are free once a request is loaded or already in flight.
    func prewarm(_ requests: [Request]) {
        guard let configuredImageReader else { return }
        for request in requests {
            guard entryImage(for: request, imageReader: configuredImageReader) == nil,
                  inFlightLoads[request] == nil,
                  queuedPrewarmRequests.insert(request).inserted
            else { continue }
            prewarmQueue.append(request)
        }
        guard prewarmTask == nil, !prewarmQueue.isEmpty else { return }
        prewarmTask = Task { @MainActor [weak self] in
            await self?.drainPrewarmQueue()
        }
    }

    func image(
        for launchURL: URL,
        partition: SumiFaviconPartition,
        context: SumiFaviconDisplayContext = .pinnedLauncher
    ) -> Image? {
        nsImage(
            for: launchURL,
            partition: partition,
            context: context
        ).map(Image.init(nsImage:))
    }

    func nsImage(
        for launchURL: URL,
        partition: SumiFaviconPartition,
        context: SumiFaviconDisplayContext = .pinnedLauncher
    ) -> NSImage? {
        guard let configuredImageReader else { return nil }
        return entryImage(
            for: cacheKey(launchURL, partition, context),
            imageReader: configuredImageReader
        )
    }

    func loadKey(
        launchURL: URL,
        partition: SumiFaviconPartition,
        context: SumiFaviconDisplayContext = .pinnedLauncher,
        isEnabled: Bool = true,
        disabledID: String? = nil
    ) -> String {
        guard isEnabled else {
            return "disabled|\(disabledID ?? launchURL.absoluteString)"
        }

        let revision = entry(for: cacheKey(launchURL, partition, context)).revision
        return [
            launchURL.absoluteString,
            partition.storageComponent,
            context.rawValue,
            String(revision),
        ].joined(separator: "|")
    }

    func load(
        launchURL: URL,
        partition: SumiFaviconPartition,
        context: SumiFaviconDisplayContext = .pinnedLauncher,
        imageReader: (any BrowserFaviconImageReading)? = nil
    ) async {
        let reader = imageReader ?? configuredImageReader
        guard let reader else { return }
        configuredImageReader = reader
        let request = cacheKey(launchURL, partition, context)
        guard let load = startLoadIfNeeded(
            request: request,
            imageReader: reader
        ) else { return }
        await load.task.value
    }

    private func startLoadIfNeeded(
        request: Request,
        imageReader: any BrowserFaviconImageReading
    ) -> InFlightLoad? {
        guard entryImage(for: request, imageReader: imageReader) == nil else {
            return nil
        }
        if let existing = inFlightLoads[request] {
            return existing
        }

        let id = UUID()
        let task = Task { @MainActor [weak self] in
            let loadedImage = await TabFaviconStore.loadCachedDisplayImage(
                forDocumentURL: request.launchURL,
                partition: request.partition,
                context: request.context,
                priority: request.context == .pinnedLauncher
                    ? .pinnedLauncher
                    : .visibleSidebarOrTabStrip,
                imageReader: imageReader
            )
            guard let self, self.inFlightLoads[request]?.id == id else {
                return
            }
            self.inFlightLoads[request] = nil
            if let loadedImage {
                let entry = self.entry(for: request)
                entry.image = loadedImage
                entry.didLookupImage = true
                entry.revision &+= 1
            }
        }
        let load = InFlightLoad(id: id, task: task)
        inFlightLoads[request] = load
        return load
    }

    private func drainPrewarmQueue() async {
        while !Task.isCancelled, prewarmIndex < prewarmQueue.count {
            let request = prewarmQueue[prewarmIndex]
            prewarmIndex += 1
            queuedPrewarmRequests.remove(request)
            await load(
                launchURL: request.launchURL,
                partition: request.partition,
                context: request.context
            )
        }
        prewarmQueue.removeAll(keepingCapacity: true)
        prewarmIndex = 0
        prewarmTask = nil
    }

    private func entry(for key: Request) -> Entry {
        if let entry = entries[key] {
            return entry
        }
        let entry = Entry()
        entries[key] = entry
        return entry
    }

    private func invalidateEntries(
        updatedDomain: String?,
        updatedPartition: String?
    ) {
        for (key, entry) in entries where cacheUpdate(
            updatedDomain: updatedDomain,
            updatedPartition: updatedPartition,
            matches: key
        ) {
            inFlightLoads[key]?.task.cancel()
            inFlightLoads[key] = nil
            entry.image = nil
            entry.didLookupImage = false
            entry.revision &+= 1
        }
    }

    private func cacheUpdate(
        updatedDomain: String?,
        updatedPartition: String?,
        matches key: Request
    ) -> Bool {
        if let updatedPartition,
           updatedPartition != key.partition.storageComponent {
            return false
        }
        guard let updatedDomain else { return true }
        let normalizer = SumiSiteNormalizer()
        guard let host = normalizer.host(for: key.launchURL) else {
            return false
        }
        return host == normalizer.host(fromRawHost: updatedDomain)
    }

    private func cacheKey(
        _ launchURL: URL,
        _ partition: SumiFaviconPartition,
        _ context: SumiFaviconDisplayContext
    ) -> Request {
        Request(
            launchURL: launchURL,
            partition: partition,
            context: context
        )
    }

    private func cachedImage(
        for request: Request,
        imageReader: any BrowserFaviconImageReading
    ) -> NSImage? {
        TabFaviconStore.getCachedImage(
            forDocumentURL: request.launchURL,
            partition: request.partition,
            context: request.context,
            imageReader: imageReader
        )
    }

    private func entryImage(
        for request: Request,
        imageReader: any BrowserFaviconImageReading
    ) -> NSImage? {
        let entry = entry(for: request)
        if let image = entry.image {
            return image
        }
        guard !entry.didLookupImage else { return nil }
        entry.didLookupImage = true
        let image = cachedImage(for: request, imageReader: imageReader)
        entry.image = image
        return image
    }
}

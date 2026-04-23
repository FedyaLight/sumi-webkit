import AppKit
import CoreData
import CoreImage
import Foundation
import ImageIO
import WebKit

enum FaviconUserScript {
    struct FaviconLink: Hashable, Sendable {
        let href: URL
        let rel: String

        init(href: URL, rel: String) {
            self.href = href
            self.rel = rel
        }
    }
}

struct Favicon {
    enum Relation: Int {
        case favicon = 2
        case icon = 1
        case other = 0

        init(relationString: String) {
            if relationString == "favicon" || relationString == "favicon.ico" {
                self = .favicon
                return
            }
            if relationString.contains("icon") {
                self = .icon
                return
            }
            self = .other
        }
    }

    enum SizeCategory: CGFloat {
        case noImage = 0
        case tiny = 1
        case small = 32
        case medium = 132
        case large = 264
        case huge = 2_048

        init(imageSize: CGSize?) {
            guard let imageSize else {
                self = .noImage
                return
            }

            let longestSide = max(imageSize.width, imageSize.height)
            switch longestSide {
            case 0:
                self = .noImage
            case 1..<Self.small.rawValue:
                self = .tiny
            case Self.small.rawValue..<Self.medium.rawValue:
                self = .small
            case Self.medium.rawValue..<Self.large.rawValue:
                self = .medium
            case Self.large.rawValue..<Self.huge.rawValue:
                self = .large
            default:
                self = .huge
            }
        }

        var smaller: SizeCategory? {
            switch self {
            case .noImage:
                return nil
            case .tiny:
                return .noImage
            case .small:
                return .tiny
            case .medium:
                return .small
            case .large:
                return .medium
            case .huge:
                return .large
            }
        }
    }

    init(
        identifier: UUID,
        url: URL,
        image: NSImage?,
        relationString: String,
        documentUrl: URL,
        dateCreated: Date
    ) {
        self.init(
            identifier: identifier,
            url: url,
            image: image,
            relation: Relation(relationString: relationString),
            documentUrl: documentUrl,
            dateCreated: dateCreated
        )
    }

    init(
        identifier: UUID,
        url: URL,
        image: NSImage?,
        relation: Relation,
        documentUrl: URL,
        dateCreated: Date
    ) {
        let sanitizedImage: NSImage?
        if let image, image.isValid {
            let sizeCategory = SizeCategory(imageSize: image.sumiPixelSize)
            if sizeCategory == .huge || sizeCategory == .noImage {
                sanitizedImage = nil
            } else {
                sanitizedImage = image
            }
        } else {
            sanitizedImage = nil
        }

        self.identifier = identifier
        self.url = url
        self.image = sanitizedImage
        self.relation = relation
        self.sizeCategory = SizeCategory(imageSize: self.image?.sumiPixelSize)
        self.documentUrl = documentUrl
        self.dateCreated = dateCreated
    }

    let identifier: UUID
    let url: URL
    let image: NSImage?
    let relation: Relation
    let sizeCategory: SizeCategory
    let documentUrl: URL
    let dateCreated: Date

    var longestSide: CGFloat {
        guard let image else { return 0 }
        return image.sumiPixelLongestSide
    }
}

struct FaviconHostReference {
    let identifier: UUID
    let smallFaviconUrl: URL?
    let mediumFaviconUrl: URL?
    let host: String
    let documentUrl: URL
    let dateCreated: Date
}

struct FaviconUrlReference {
    let identifier: UUID
    let smallFaviconUrl: URL?
    let mediumFaviconUrl: URL?
    let documentUrl: URL
    let dateCreated: Date
}

extension Notification.Name {
    static let faviconCacheUpdated = Notification.Name("FaviconCacheUpdatedNotification")
}

extension Date {
    static var weekAgo: Date { Date().addingTimeInterval(-7 * 24 * 60 * 60) }
}

enum SumiFaviconLookupKey {
    static func cacheKey(for url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            return nil
        }

        let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let host, !host.isEmpty {
            return host.lowercased()
        }

        let absolute = url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        return absolute.isEmpty ? nil : absolute.lowercased()
    }

    static func documentURL(for key: String) -> URL? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let explicitURL = URL(string: trimmed),
           let scheme = explicitURL.scheme?.lowercased(),
           scheme == "http" || scheme == "https"
        {
            return explicitURL
        }

        return URL(string: "https://\(trimmed)")
    }
}

private extension String {
    var sumiRegistrableDomain: String? {
        let parts = split(separator: ".").map(String.init)
        guard parts.count >= 2 else { return nil }
        return parts.suffix(2).joined(separator: ".")
    }
}

private enum SumiFaviconPersistence {
    static func defaultStoreURL() -> URL {
        let rootDirectory: URL
        if RuntimeDiagnostics.isRunningTests {
            let processRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("SumiFavicons-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
            try? FileManager.default.createDirectory(at: processRoot, withIntermediateDirectories: true)
            rootDirectory = processRoot
        } else if let overridePath = ProcessInfo.processInfo.environment["SUMI_APP_SUPPORT_OVERRIDE"],
                  !overridePath.isEmpty
        {
            let overrideURL = URL(fileURLWithPath: overridePath, isDirectory: true)
            try? FileManager.default.createDirectory(at: overrideURL, withIntermediateDirectories: true)
            rootDirectory = overrideURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let bundleDirectory = appSupport.appendingPathComponent(SumiAppIdentity.runtimeBundleIdentifier, isDirectory: true)
            try? FileManager.default.createDirectory(at: bundleDirectory, withIntermediateDirectories: true)
            rootDirectory = bundleDirectory
        }

        let faviconDirectory = rootDirectory.appendingPathComponent("Favicons", isDirectory: true)
        try? FileManager.default.createDirectory(at: faviconDirectory, withIntermediateDirectories: true)
        return faviconDirectory.appendingPathComponent("favicons.sqlite", isDirectory: false)
    }
}

@MainActor
protocol FaviconDownloading {
    func download(from url: URL, using webView: WKWebView?) async throws -> Data
}

@MainActor
protocol FaviconDownloadSessionDelegate: AnyObject {
    func faviconDownloadSession(
        _ session: any FaviconDownloadSession,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String
    ) async -> URL?
    func faviconDownloadSessionDidFinish(_ session: any FaviconDownloadSession)
    func faviconDownloadSession(
        _ session: any FaviconDownloadSession,
        didFailWithError error: Error,
        resumeData: Data?
    )
}

@MainActor
protocol FaviconDownloadSession: AnyObject {
    var delegate: (any FaviconDownloadSessionDelegate)? { get set }
    func cancel(_ completionHandler: @escaping @Sendable (Data?) -> Void)
}

@MainActor
private final class WKFaviconDownloadSession: NSObject, FaviconDownloadSession {
    private let download: WKDownload
    weak var delegate: (any FaviconDownloadSessionDelegate)?

    init(download: WKDownload) {
        self.download = download
        super.init()
        download.delegate = self
    }

    func cancel(_ completionHandler: @escaping @Sendable (Data?) -> Void) {
        download.cancel(completionHandler)
    }
}

extension WKFaviconDownloadSession: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        await delegate?.faviconDownloadSession(
            self,
            decideDestinationUsing: response,
            suggestedFilename: suggestedFilename
        )
    }

    func downloadDidFinish(_ download: WKDownload) {
        delegate?.faviconDownloadSessionDidFinish(self)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        delegate?.faviconDownloadSession(self, didFailWithError: error, resumeData: resumeData)
    }
}

@MainActor
final class FaviconDownloader: NSObject, FaviconDownloading {
    typealias DownloadSessionStarter = @MainActor (
        _ request: URLRequest,
        _ webView: WKWebView?
    ) async -> (session: any FaviconDownloadSession, retainedDownloadSurface: AnyObject?)

    private struct PendingDownload {
        let url: URL
        let continuation: CheckedContinuation<Data, Error>
        let session: any FaviconDownloadSession
        let retainedDownloadSurface: AnyObject?
        var destinationURL: URL?
    }

    private static let maxFaviconSize: Int64 = 1_024 * 1_024

    private var startDownloadSession: DownloadSessionStarter
    private var pendingDownloads: [ObjectIdentifier: PendingDownload] = [:]
    private let fallbackSession: URLSession

    init(
        fallbackSession: URLSession = URLSession(configuration: .ephemeral),
        startDownloadSession: DownloadSessionStarter? = nil
    ) {
        self.fallbackSession = fallbackSession
        self.startDownloadSession = { _, _ in
            preconditionFailure("FaviconDownloader.startDownloadSession used before initialization")
        }
        super.init()
        if let startDownloadSession {
            self.startDownloadSession = startDownloadSession
        } else {
            self.startDownloadSession = { [unowned self] request, webView in
                await self.makeDownloadSession(using: request, webView: webView)
            }
        }
    }

    func download(from url: URL, using webView: WKWebView?) async throws -> Data {
        do {
            return try await downloadUsingWKDownload(from: url, using: webView)
        } catch {
            return try await fallbackSession.data(from: url).0
        }
    }

    private func downloadUsingWKDownload(from url: URL, using webView: WKWebView?) async throws -> Data {
        let (session, retainedDownloadSurface) = await startDownloadSession(URLRequest(url: url), webView)
        let identifier = ObjectIdentifier(session as AnyObject)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pendingDownloads[identifier] = PendingDownload(
                    url: url,
                    continuation: continuation,
                    session: session,
                    retainedDownloadSurface: retainedDownloadSurface,
                    destinationURL: nil
                )
                session.delegate = self
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelDownload(withIdentifier: identifier)
            }
        }
    }

    private func makeDownloadSession(
        using request: URLRequest,
        webView: WKWebView?
    ) async -> (session: any FaviconDownloadSession, retainedDownloadSurface: AnyObject?) {
        let temporaryWebView = webView == nil ? makeTemporaryWebView() : nil
        let targetWebView = webView ?? temporaryWebView!
        let download = await targetWebView.startDownload(using: request)
        return (WKFaviconDownloadSession(download: download), temporaryWebView)
    }

    private func makeTemporaryWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        return webView
    }

    private func cancelDownload(withIdentifier identifier: ObjectIdentifier) {
        guard let pending = pendingDownloads.removeValue(forKey: identifier) else { return }
        withExtendedLifetime(pending.retainedDownloadSurface) {
            pending.session.delegate = nil
            pending.session.cancel { _ in
                if let destinationURL = pending.destinationURL {
                    try? FileManager.default.removeItem(at: destinationURL)
                }
            }
            pending.continuation.resume(throwing: URLError(.cancelled))
        }
    }
}

extension FaviconDownloader: WKNavigationDelegate {
    nonisolated func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        preferences: WKWebpagePreferences,
        decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
    ) {
        decisionHandler(.cancel, preferences)
    }
}

extension FaviconDownloader: FaviconDownloadSessionDelegate {
    func faviconDownloadSession(
        _ session: any FaviconDownloadSession,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String
    ) async -> URL? {
        if response.expectedContentLength > 0 && response.expectedContentLength > Self.maxFaviconSize {
            return nil
        }

        let destinationURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        let identifier = ObjectIdentifier(session as AnyObject)
        guard var pending = pendingDownloads[identifier] else { return nil }
        pending.destinationURL = destinationURL
        pendingDownloads[identifier] = pending
        return destinationURL
    }

    func faviconDownloadSessionDidFinish(_ session: any FaviconDownloadSession) {
        let identifier = ObjectIdentifier(session as AnyObject)
        guard let pending = pendingDownloads.removeValue(forKey: identifier) else { return }
        withExtendedLifetime(pending.retainedDownloadSurface) {
            defer {
                if let destinationURL = pending.destinationURL {
                    try? FileManager.default.removeItem(at: destinationURL)
                }
            }

            do {
                guard let destinationURL = pending.destinationURL else {
                    throw CocoaError(.fileNoSuchFile)
                }
                let attributes = try FileManager.default.attributesOfItem(atPath: destinationURL.path)
                if let fileSize = attributes[.size] as? Int64, fileSize > Self.maxFaviconSize {
                    throw URLError(.dataLengthExceedsMaximum, userInfo: [NSURLErrorKey: pending.url])
                }
                let data = try Data(contentsOf: destinationURL)
                pending.continuation.resume(returning: data)
            } catch {
                pending.continuation.resume(throwing: error)
            }
        }
    }

    func faviconDownloadSession(
        _ session: any FaviconDownloadSession,
        didFailWithError error: Error,
        resumeData: Data?
    ) {
        let identifier = ObjectIdentifier(session as AnyObject)
        guard let pending = pendingDownloads.removeValue(forKey: identifier) else { return }
        withExtendedLifetime(pending.retainedDownloadSurface) {
            if let destinationURL = pending.destinationURL {
                try? FileManager.default.removeItem(at: destinationURL)
            }
            pending.continuation.resume(throwing: error)
        }
    }
}

protocol FaviconStoring {
    func loadFavicons() async throws -> [Favicon]
    func save(_ favicons: [Favicon]) async throws
    func removeFavicons(_ favicons: [Favicon]) async throws

    func loadFaviconReferences() async throws -> ([FaviconHostReference], [FaviconUrlReference])
    func save(hostReference: FaviconHostReference) async throws
    func save(urlReference: FaviconUrlReference) async throws
    func remove(hostReferences: [FaviconHostReference]) async throws
    func remove(urlReferences: [FaviconUrlReference]) async throws

    func clearAll() throws
}

final class FaviconNullStore: FaviconStoring {
    func loadFavicons() async throws -> [Favicon] { [] }
    func save(_ favicons: [Favicon]) async throws { _ = favicons }
    func removeFavicons(_ favicons: [Favicon]) async throws { _ = favicons }
    func loadFaviconReferences() async throws -> ([FaviconHostReference], [FaviconUrlReference]) { ([], []) }
    func save(hostReference: FaviconHostReference) async throws { _ = hostReference }
    func save(urlReference: FaviconUrlReference) async throws { _ = urlReference }
    func remove(hostReferences: [FaviconHostReference]) async throws { _ = hostReferences }
    func remove(urlReferences: [FaviconUrlReference]) async throws { _ = urlReferences }
    func clearAll() throws {}
}

final class FaviconStore: @unchecked Sendable, FaviconStoring {
    enum StoreError: Error {
        case saveFailed
    }

    private enum EntityName {
        static let favicon = "FaviconManagedObject"
        static let hostReference = "FaviconHostReferenceManagedObject"
        static let urlReference = "FaviconUrlReferenceManagedObject"
    }

    private enum Key {
        static let identifier = "identifier"
        static let dateCreated = "dateCreated"
        static let urlEncrypted = "urlEncrypted"
        static let documentUrlEncrypted = "documentUrlEncrypted"
        static let imageEncrypted = "imageEncrypted"
        static let relation = "relation"
        static let hostEncrypted = "hostEncrypted"
        static let smallFaviconUrlEncrypted = "smallFaviconUrlEncrypted"
        static let mediumFaviconUrlEncrypted = "mediumFaviconUrlEncrypted"
    }

    private let container: NSPersistentContainer
    private let context: NSManagedObjectContext

    init(storeURL: URL) throws {
        let model = Self.makeModel()
        let container = NSPersistentContainer(name: "Favicons", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: storeURL)
        description.shouldAddStoreAsynchronously = false
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        if let loadError {
            throw loadError
        }

        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        self.container = container
        self.context = context
    }

    func loadFavicons() async throws -> [Favicon] {
        try await withCheckedThrowingContinuation { continuation in
            context.perform {
                do {
                    let request = NSFetchRequest<NSManagedObject>(entityName: EntityName.favicon)
                    request.sortDescriptors = [NSSortDescriptor(key: Key.dateCreated, ascending: true)]
                    request.returnsObjectsAsFaults = false
                    let objects = try self.context.fetch(request)
                    let favicons = objects.compactMap(Self.makeFavicon(from:))
                    continuation.resume(returning: favicons)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func save(_ favicons: [Favicon]) async throws {
        try await withCheckedThrowingContinuation { continuation in
            context.perform {
                do {
                    for favicon in favicons {
                        let object = NSEntityDescription.insertNewObject(forEntityName: EntityName.favicon, into: self.context)
                        object.setValue(favicon.identifier, forKey: Key.identifier)
                        object.setValue(favicon.dateCreated, forKey: Key.dateCreated)
                        object.setValue(favicon.url.absoluteString, forKey: Key.urlEncrypted)
                        object.setValue(favicon.documentUrl.absoluteString, forKey: Key.documentUrlEncrypted)
                        object.setValue(Int64(favicon.relation.rawValue), forKey: Key.relation)
                        object.setValue(favicon.image?.sumiPNGData, forKey: Key.imageEncrypted)
                    }
                    try self.context.save()
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: StoreError.saveFailed)
                }
            }
        }
    }

    func removeFavicons(_ favicons: [Favicon]) async throws {
        try await remove(identifiers: favicons.map(\.identifier), entityName: EntityName.favicon)
    }

    func loadFaviconReferences() async throws -> ([FaviconHostReference], [FaviconUrlReference]) {
        try await withCheckedThrowingContinuation { continuation in
            context.perform {
                do {
                    let hostRequest = NSFetchRequest<NSManagedObject>(entityName: EntityName.hostReference)
                    hostRequest.sortDescriptors = [NSSortDescriptor(key: Key.dateCreated, ascending: true)]
                    hostRequest.returnsObjectsAsFaults = false
                    let hostObjects = try self.context.fetch(hostRequest)
                    let hostReferences = hostObjects.compactMap(Self.makeHostReference(from:))

                    let urlRequest = NSFetchRequest<NSManagedObject>(entityName: EntityName.urlReference)
                    urlRequest.sortDescriptors = [NSSortDescriptor(key: Key.dateCreated, ascending: true)]
                    urlRequest.returnsObjectsAsFaults = false
                    let urlObjects = try self.context.fetch(urlRequest)
                    let urlReferences = urlObjects.compactMap(Self.makeURLReference(from:))
                    continuation.resume(returning: (hostReferences, urlReferences))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func save(hostReference: FaviconHostReference) async throws {
        try await saveReference(
            entityName: EntityName.hostReference,
            block: { object in
                object.setValue(hostReference.identifier, forKey: Key.identifier)
                object.setValue(hostReference.dateCreated, forKey: Key.dateCreated)
                object.setValue(hostReference.host, forKey: Key.hostEncrypted)
                object.setValue(hostReference.documentUrl.absoluteString, forKey: Key.documentUrlEncrypted)
                object.setValue(hostReference.smallFaviconUrl?.absoluteString, forKey: Key.smallFaviconUrlEncrypted)
                object.setValue(hostReference.mediumFaviconUrl?.absoluteString, forKey: Key.mediumFaviconUrlEncrypted)
            }
        )
    }

    func save(urlReference: FaviconUrlReference) async throws {
        try await saveReference(
            entityName: EntityName.urlReference,
            block: { object in
                object.setValue(urlReference.identifier, forKey: Key.identifier)
                object.setValue(urlReference.dateCreated, forKey: Key.dateCreated)
                object.setValue(urlReference.documentUrl.absoluteString, forKey: Key.documentUrlEncrypted)
                object.setValue(urlReference.smallFaviconUrl?.absoluteString, forKey: Key.smallFaviconUrlEncrypted)
                object.setValue(urlReference.mediumFaviconUrl?.absoluteString, forKey: Key.mediumFaviconUrlEncrypted)
            }
        )
    }

    func remove(hostReferences: [FaviconHostReference]) async throws {
        try await remove(identifiers: hostReferences.map(\.identifier), entityName: EntityName.hostReference)
    }

    func remove(urlReferences: [FaviconUrlReference]) async throws {
        try await remove(identifiers: urlReferences.map(\.identifier), entityName: EntityName.urlReference)
    }

    func clearAll() throws {
        var clearError: Error?
        context.performAndWait {
            do {
                try self.deleteAll(entityName: EntityName.favicon)
                try self.deleteAll(entityName: EntityName.hostReference)
                try self.deleteAll(entityName: EntityName.urlReference)
            } catch {
                clearError = error
            }
        }
        if let clearError {
            throw clearError
        }
    }

    private func saveReference(entityName: String, block: @escaping (NSManagedObject) -> Void) async throws {
        try await withCheckedThrowingContinuation { continuation in
            context.perform {
                do {
                    let object = NSEntityDescription.insertNewObject(forEntityName: entityName, into: self.context)
                    block(object)
                    try self.context.save()
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: StoreError.saveFailed)
                }
            }
        }
    }

    private func remove(identifiers: [UUID], entityName: String) async throws {
        guard !identifiers.isEmpty else { return }
        try await withCheckedThrowingContinuation { continuation in
            context.perform {
                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
                fetchRequest.predicate = NSPredicate(format: "\(Key.identifier) IN %@", identifiers)
                let batchDelete = NSBatchDeleteRequest(fetchRequest: fetchRequest)
                batchDelete.resultType = .resultTypeObjectIDs

                do {
                    let result = try self.context.execute(batchDelete) as? NSBatchDeleteResult
                    let deletedObjectIDs = result?.result as? [NSManagedObjectID] ?? []
                    if !deletedObjectIDs.isEmpty {
                        let changes: [AnyHashable: Any] = [NSDeletedObjectsKey: deletedObjectIDs]
                        NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [self.container.viewContext])
                        self.context.reset()
                    }
                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func deleteAll(entityName: String) throws {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        let batchDelete = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        batchDelete.resultType = .resultTypeObjectIDs
        let result = try context.execute(batchDelete) as? NSBatchDeleteResult
        let deletedObjectIDs = result?.result as? [NSManagedObjectID] ?? []
        if !deletedObjectIDs.isEmpty {
            let changes: [AnyHashable: Any] = [NSDeletedObjectsKey: deletedObjectIDs]
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [container.viewContext])
            context.reset()
        }
    }

    private static func makeFavicon(from object: NSManagedObject) -> Favicon? {
        guard let identifier = object.value(forKey: Key.identifier) as? UUID,
              let urlString = object.value(forKey: Key.urlEncrypted) as? String,
              let url = URL(string: urlString),
              let documentURLString = object.value(forKey: Key.documentUrlEncrypted) as? String,
              let documentURL = URL(string: documentURLString),
              let dateCreated = object.value(forKey: Key.dateCreated) as? Date,
              let relationRaw = object.value(forKey: Key.relation) as? Int64,
              let relation = Favicon.Relation(rawValue: Int(relationRaw))
        else {
            return nil
        }

        let imageData = object.value(forKey: Key.imageEncrypted) as? Data
        let image = imageData
            .flatMap(FaviconPayloadValidator.validatedImageData(from:))
            .flatMap(NSImage.init(dataUsingCIImage:))
        return Favicon(
            identifier: identifier,
            url: url,
            image: image,
            relation: relation,
            documentUrl: documentURL,
            dateCreated: dateCreated
        )
    }

    private static func makeHostReference(from object: NSManagedObject) -> FaviconHostReference? {
        guard let identifier = object.value(forKey: Key.identifier) as? UUID,
              let host = object.value(forKey: Key.hostEncrypted) as? String,
              let documentURLString = object.value(forKey: Key.documentUrlEncrypted) as? String,
              let documentURL = URL(string: documentURLString),
              let dateCreated = object.value(forKey: Key.dateCreated) as? Date
        else {
            return nil
        }

        let smallURL = (object.value(forKey: Key.smallFaviconUrlEncrypted) as? String).flatMap(URL.init(string:))
        let mediumURL = (object.value(forKey: Key.mediumFaviconUrlEncrypted) as? String).flatMap(URL.init(string:))
        return FaviconHostReference(
            identifier: identifier,
            smallFaviconUrl: smallURL,
            mediumFaviconUrl: mediumURL,
            host: host,
            documentUrl: documentURL,
            dateCreated: dateCreated
        )
    }

    private static func makeURLReference(from object: NSManagedObject) -> FaviconUrlReference? {
        guard let identifier = object.value(forKey: Key.identifier) as? UUID,
              let documentURLString = object.value(forKey: Key.documentUrlEncrypted) as? String,
              let documentURL = URL(string: documentURLString),
              let dateCreated = object.value(forKey: Key.dateCreated) as? Date
        else {
            return nil
        }

        let smallURL = (object.value(forKey: Key.smallFaviconUrlEncrypted) as? String).flatMap(URL.init(string:))
        let mediumURL = (object.value(forKey: Key.mediumFaviconUrlEncrypted) as? String).flatMap(URL.init(string:))
        return FaviconUrlReference(
            identifier: identifier,
            smallFaviconUrl: smallURL,
            mediumFaviconUrl: mediumURL,
            documentUrl: documentURL,
            dateCreated: dateCreated
        )
    }

    private static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        model.entities = [
            makeFaviconEntity(),
            makeHostReferenceEntity(),
            makeURLReferenceEntity(),
        ]
        return model
    }

    private static func makeFaviconEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = EntityName.favicon
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        entity.properties = [
            makeUUIDAttribute(name: Key.identifier),
            makeDateAttribute(name: Key.dateCreated),
            makeStringAttribute(name: Key.urlEncrypted),
            makeStringAttribute(name: Key.documentUrlEncrypted),
            makeBinaryAttribute(name: Key.imageEncrypted, optional: true),
            makeIntegerAttribute(name: Key.relation),
        ]
        return entity
    }

    private static func makeHostReferenceEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = EntityName.hostReference
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        entity.properties = [
            makeUUIDAttribute(name: Key.identifier),
            makeDateAttribute(name: Key.dateCreated),
            makeStringAttribute(name: Key.hostEncrypted),
            makeStringAttribute(name: Key.documentUrlEncrypted),
            makeStringAttribute(name: Key.smallFaviconUrlEncrypted, optional: true),
            makeStringAttribute(name: Key.mediumFaviconUrlEncrypted, optional: true),
        ]
        return entity
    }

    private static func makeURLReferenceEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = EntityName.urlReference
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        entity.properties = [
            makeUUIDAttribute(name: Key.identifier),
            makeDateAttribute(name: Key.dateCreated),
            makeStringAttribute(name: Key.documentUrlEncrypted),
            makeStringAttribute(name: Key.smallFaviconUrlEncrypted, optional: true),
            makeStringAttribute(name: Key.mediumFaviconUrlEncrypted, optional: true),
        ]
        return entity
    }

    private static func makeUUIDAttribute(name: String) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = .UUIDAttributeType
        attribute.isOptional = false
        return attribute
    }

    private static func makeDateAttribute(name: String) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = .dateAttributeType
        attribute.isOptional = false
        return attribute
    }

    private static func makeStringAttribute(name: String, optional: Bool = false) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = .stringAttributeType
        attribute.isOptional = optional
        return attribute
    }

    private static func makeBinaryAttribute(name: String, optional: Bool = false) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = .binaryDataAttributeType
        attribute.isOptional = optional
        attribute.allowsExternalBinaryDataStorage = true
        return attribute
    }

    private static func makeIntegerAttribute(name: String) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = .integer64AttributeType
        attribute.isOptional = false
        attribute.defaultValue = 0
        return attribute
    }
}

@MainActor
final class FaviconImageCache {
    enum LoadError: Error {
        case duplicateFaviconURL(URL)
    }

    private let storing: FaviconStoring
    private(set) var loaded = false
    private var entries: [URL: Favicon] = [:]

    init(faviconStoring: FaviconStoring) {
        self.storing = faviconStoring
    }

    func load() async throws {
        let favicons = try await storing.loadFavicons()
        entries = try Self.makeUniqueDictionary(
            values: favicons,
            key: \.url,
            makeError: LoadError.duplicateFaviconURL
        )
        loaded = true
    }

    func insert(_ favicons: [Favicon]) async {
        guard loaded, !favicons.isEmpty else { return }

        let oldFavicons = favicons.compactMap { entries[$0.url] }
        for favicon in favicons {
            entries[favicon.url] = favicon
        }

        try? await storing.removeFavicons(oldFavicons)
        try? await storing.save(favicons)
        NotificationCenter.default.post(name: .faviconCacheUpdated, object: nil)
    }

    func get(faviconUrl: URL) -> Favicon? {
        guard loaded else { return nil }
        return entries[faviconUrl]
    }

    func getFavicons(with urls: some Sequence<URL>) -> [Favicon]? {
        guard loaded else { return nil }
        return urls.compactMap { entries[$0] }
    }

    func reset() {
        entries.removeAll()
        loaded = true
        NotificationCenter.default.post(name: .faviconCacheUpdated, object: nil)
    }

    private static func makeUniqueDictionary<Key: Hashable>(
        values: [Favicon],
        key: KeyPath<Favicon, Key>,
        makeError: (Key) -> Error
    ) throws -> [Key: Favicon] {
        var result: [Key: Favicon] = [:]
        result.reserveCapacity(values.count)

        for value in values {
            let dictionaryKey = value[keyPath: key]
            if result.updateValue(value, forKey: dictionaryKey) != nil {
                throw makeError(dictionaryKey)
            }
        }

        return result
    }
}

@MainActor
final class FaviconReferenceCache {
    enum LoadError: Error {
        case duplicateHost(String)
        case duplicateDocumentURL(URL)
    }

    private let storing: FaviconStoring

    private(set) var hostReferences: [String: FaviconHostReference] = [:]
    private(set) var urlReferences: [URL: FaviconUrlReference] = [:]
    private(set) var loaded = false

    init(faviconStoring: FaviconStoring) {
        self.storing = faviconStoring
    }

    func load() async throws {
        let (hostReferences, urlReferences) = try await storing.loadFaviconReferences()
        self.hostReferences = try Self.makeUniqueDictionary(
            values: hostReferences,
            key: \.host,
            makeError: LoadError.duplicateHost
        )
        self.urlReferences = try Self.makeUniqueDictionary(
            values: urlReferences,
            key: \.documentUrl,
            makeError: LoadError.duplicateDocumentURL
        )
        loaded = true
        NotificationCenter.default.post(name: .faviconCacheUpdated, object: nil)
    }

    func insert(faviconUrls: (smallFaviconUrl: URL?, mediumFaviconUrl: URL?), documentUrl: URL) async {
        guard loaded else { return }

        guard let host = documentUrl.host else {
            await insertToURLCache(faviconUrls: faviconUrls, documentUrl: documentUrl)
            return
        }

        if let existing = hostReferences[host] {
            if existing.smallFaviconUrl == faviconUrls.smallFaviconUrl,
               existing.mediumFaviconUrl == faviconUrls.mediumFaviconUrl
            {
                if urlReferences[documentUrl] != nil {
                    await invalidateURLCache(for: host)
                }
                return
            }

            if existing.documentUrl == documentUrl {
                await invalidateURLCache(for: host)
                await insertToHostCache(faviconUrls: faviconUrls, host: host, documentUrl: documentUrl)
            } else {
                await insertToURLCache(faviconUrls: faviconUrls, documentUrl: documentUrl)
            }
            return
        }

        await insertToHostCache(faviconUrls: faviconUrls, host: host, documentUrl: documentUrl)
    }

    func getFaviconUrl(for documentURL: URL, sizeCategory: Favicon.SizeCategory) -> URL? {
        guard loaded else { return nil }

        if let urlReference = urlReferences[documentURL] {
            switch sizeCategory {
            case .small:
                return urlReference.smallFaviconUrl ?? urlReference.mediumFaviconUrl
            default:
                return urlReference.mediumFaviconUrl
            }
        }

        if let host = documentURL.host,
           let hostReference = hostReferences[host]
        {
            switch sizeCategory {
            case .small:
                return hostReference.smallFaviconUrl ?? hostReference.mediumFaviconUrl
            default:
                return hostReference.mediumFaviconUrl
            }
        }

        return nil
    }

    func getFaviconUrl(for host: String, sizeCategory: Favicon.SizeCategory) -> URL? {
        guard loaded, let hostReference = hostReferences[host] else { return nil }

        switch sizeCategory {
        case .small:
            return hostReference.smallFaviconUrl ?? hostReference.mediumFaviconUrl
        default:
            return hostReference.mediumFaviconUrl
        }
    }

    func cacheStats() -> (count: Int, domains: [String]) {
        let hostDomains = hostReferences.keys
        let urlDomains = urlReferences.keys.compactMap { url -> String? in
            guard url.host == nil else { return nil }
            return url.absoluteString
        }
        let domains = Array(Set(hostDomains).union(urlDomains)).sorted()
        return (domains.count, domains)
    }

    func reset() {
        hostReferences.removeAll()
        urlReferences.removeAll()
        loaded = true
        NotificationCenter.default.post(name: .faviconCacheUpdated, object: nil)
    }

    private static func makeUniqueDictionary<Key: Hashable, Value>(
        values: [Value],
        key: KeyPath<Value, Key>,
        makeError: (Key) -> Error
    ) throws -> [Key: Value] {
        var result: [Key: Value] = [:]
        result.reserveCapacity(values.count)

        for value in values {
            let dictionaryKey = value[keyPath: key]
            if result.updateValue(value, forKey: dictionaryKey) != nil {
                throw makeError(dictionaryKey)
            }
        }

        return result
    }

    private func insertToHostCache(
        faviconUrls: (smallFaviconUrl: URL?, mediumFaviconUrl: URL?),
        host: String,
        documentUrl: URL
    ) async {
        if let oldReference = hostReferences[host] {
            try? await storing.remove(hostReferences: [oldReference])
        }

        let reference = FaviconHostReference(
            identifier: UUID(),
            smallFaviconUrl: faviconUrls.smallFaviconUrl,
            mediumFaviconUrl: faviconUrls.mediumFaviconUrl,
            host: host,
            documentUrl: documentUrl,
            dateCreated: Date()
        )
        hostReferences[host] = reference

        try? await storing.save(hostReference: reference)
    }

    private func insertToURLCache(
        faviconUrls: (smallFaviconUrl: URL?, mediumFaviconUrl: URL?),
        documentUrl: URL
    ) async {
        if let oldReference = urlReferences[documentUrl] {
            try? await storing.remove(urlReferences: [oldReference])
        }

        let reference = FaviconUrlReference(
            identifier: UUID(),
            smallFaviconUrl: faviconUrls.smallFaviconUrl,
            mediumFaviconUrl: faviconUrls.mediumFaviconUrl,
            documentUrl: documentUrl,
            dateCreated: Date()
        )
        urlReferences[documentUrl] = reference

        try? await storing.save(urlReference: reference)
    }

    private func invalidateURLCache(for host: String) async {
        let referencesToRemove = urlReferences.values.filter { $0.documentUrl.host == host }
        for reference in referencesToRemove {
            urlReferences[reference.documentUrl] = nil
        }
        try? await storing.remove(urlReferences: referencesToRemove)
    }
}

final class FaviconSelector {
    static func getMostSuitableFavicon(for sizeCategory: Favicon.SizeCategory, favicons: [Favicon]) -> Favicon? {
        let preferredCategoryGroups = preferredGroups(for: sizeCategory)

        for categories in preferredCategoryGroups {
            for relation in [Favicon.Relation.favicon, .icon, .other] {
                if let favicon = favicons.first(where: {
                    categories.contains($0.sizeCategory) && $0.relation == relation
                }) {
                    return favicon
                }
            }
        }

        return nil
    }

    private static func preferredGroups(for sizeCategory: Favicon.SizeCategory) -> [Set<Favicon.SizeCategory>] {
        switch sizeCategory {
        case .small:
            // Favor downscaling a higher-resolution source image for small UI slots.
            return [.init([.medium, .large]), .init([.small]), .init([.tiny])]
        case .medium:
            return [.init([.medium]), .init([.large]), .init([.small])]
        default:
            return [.init([sizeCategory])]
        }
    }
}

@MainActor
final class FaviconManager {
    private enum ReferenceInsertionPolicy {
        case opportunistic
        case authoritativeCurrentLinks
    }

    enum CacheType {
        case standard(storeURL: URL)
        case inMemory
    }

    private let store: FaviconStoring
    private let faviconDownloader: FaviconDownloading
    private let imageCache: FaviconImageCache
    private let referenceCache: FaviconReferenceCache
    private var loadTask: Task<Void, Never>?

    private(set) var isCacheLoaded = false

    convenience init(
        cacheType: CacheType,
        downloader: FaviconDownloading? = nil
    ) {
        let store: FaviconStoring
        switch cacheType {
        case .standard(let storeURL):
            store = (try? FaviconStore(storeURL: storeURL)) ?? FaviconNullStore()
        case .inMemory:
            store = FaviconNullStore()
        }
        self.init(store: store, downloader: downloader)
    }

    init(
        store: FaviconStoring,
        downloader: FaviconDownloading? = nil
    ) {
        self.store = store
        self.faviconDownloader = downloader ?? FaviconDownloader()
        self.imageCache = FaviconImageCache(faviconStoring: store)
        self.referenceCache = FaviconReferenceCache(faviconStoring: store)
        self.loadTask = Task { [weak self] in
            await self?.loadCaches()
        }
    }

    func waitUntilLoaded() async {
        await loadTask?.value
        if isCacheLoaded == false {
            await loadCaches()
        }
    }

    func handleLiveFaviconLinks(
        _ faviconLinks: [FaviconUserScript.FaviconLink],
        documentUrl: URL,
        webView: WKWebView?
    ) async -> Favicon? {
        await resolveFavicon(
            faviconLinks: faviconLinks,
            documentUrl: documentUrl,
            webView: webView,
            allowFallback: false,
            referencePolicy: .authoritativeCurrentLinks
        )
    }

    func loadFavicon(for documentUrl: URL, webView: WKWebView?) async -> Favicon? {
        await resolveFavicon(
            faviconLinks: [],
            documentUrl: documentUrl,
            webView: webView,
            allowFallback: true,
            referencePolicy: .opportunistic
        )
    }

    private func resolveFavicon(
        faviconLinks: [FaviconUserScript.FaviconLink],
        documentUrl: URL,
        webView: WKWebView?,
        allowFallback: Bool,
        referencePolicy: ReferenceInsertionPolicy
    ) async -> Favicon? {
        await waitUntilLoaded()
        guard !Task.isCancelled else { return nil }

        var linksToFetch = await filteringAlreadyFetchedFaviconLinks(from: faviconLinks)
        var newFavicons = await fetchFavicons(faviconLinks: linksToFetch, documentUrl: documentUrl, webView: webView)
        if let favicon = await cacheFavicons(
            newFavicons,
            faviconURLs: faviconLinks.lazy.map(\.href),
            for: documentUrl,
            referencePolicy: referencePolicy
        ) {
            return favicon
        }

        guard allowFallback, !Task.isCancelled else { return nil }

        let fallbackLinks = fallbackFaviconLinks(for: documentUrl)
        linksToFetch = await filteringAlreadyFetchedFaviconLinks(from: fallbackLinks)
        newFavicons = await fetchFavicons(faviconLinks: linksToFetch, documentUrl: documentUrl, webView: webView)
        return await cacheFavicons(
            newFavicons,
            faviconURLs: fallbackLinks.lazy.map(\.href),
            for: documentUrl,
            referencePolicy: .opportunistic
        )
    }

    func getCachedFavicon(
        for documentUrl: URL,
        sizeCategory: Favicon.SizeCategory,
        fallBackToSmaller: Bool
    ) -> Favicon? {
        guard let faviconURL = referenceCache.getFaviconUrl(for: documentUrl, sizeCategory: sizeCategory) else {
            guard fallBackToSmaller, let smaller = sizeCategory.smaller else { return nil }
            return getCachedFavicon(for: documentUrl, sizeCategory: smaller, fallBackToSmaller: fallBackToSmaller)
        }
        return imageCache.get(faviconUrl: faviconURL)
    }

    func getCachedFavicon(
        for host: String,
        sizeCategory: Favicon.SizeCategory,
        fallBackToSmaller: Bool
    ) -> Favicon? {
        guard let faviconURL = referenceCache.getFaviconUrl(for: host, sizeCategory: sizeCategory) else {
            guard fallBackToSmaller, let smaller = sizeCategory.smaller else { return nil }
            return getCachedFavicon(for: host, sizeCategory: smaller, fallBackToSmaller: fallBackToSmaller)
        }
        return imageCache.get(faviconUrl: faviconURL)
    }

    func getCachedFavicon(
        forUrlOrAnySubdomain documentUrl: URL,
        sizeCategory: Favicon.SizeCategory,
        fallBackToSmaller: Bool
    ) -> Favicon? {
        if let favicon = getCachedFavicon(for: documentUrl, sizeCategory: sizeCategory, fallBackToSmaller: fallBackToSmaller) {
            return favicon
        }

        if let host = documentUrl.host {
            if let favicon = getCachedFavicon(for: host, sizeCategory: sizeCategory, fallBackToSmaller: fallBackToSmaller) {
                return favicon
            }

            if let baseDomain = host.sumiRegistrableDomain,
               let favicon = getCachedFavicon(for: baseDomain, sizeCategory: sizeCategory, fallBackToSmaller: fallBackToSmaller)
            {
                return favicon
            }

            if let subdomainMatch = referenceCache.hostReferences.keys.first(where: { $0.hasSuffix(host) || host.hasSuffix($0) }) {
                return getCachedFavicon(for: subdomainMatch, sizeCategory: sizeCategory, fallBackToSmaller: fallBackToSmaller)
            }
        }

        return nil
    }

    func image(forLookupKey key: String) -> NSImage? {
        guard let documentURL = SumiFaviconLookupKey.documentURL(for: key) else { return nil }
        return getCachedFavicon(
            forUrlOrAnySubdomain: documentURL,
            sizeCategory: .small,
            fallBackToSmaller: true
        )?.image
    }

    func clearAll() {
        try? store.clearAll()
        imageCache.reset()
        referenceCache.reset()
        isCacheLoaded = true
    }

    func cacheStats() -> (count: Int, domains: [String]) {
        referenceCache.cacheStats()
    }

    private func loadCaches() async {
        do {
            try await imageCache.load()
            try await referenceCache.load()
        } catch {
            try? store.clearAll()
            imageCache.reset()
            referenceCache.reset()
        }
        isCacheLoaded = true
    }

    private func fallbackFaviconLinks(for documentUrl: URL) -> [FaviconUserScript.FaviconLink] {
        guard let root = documentUrl.sumiRootURL else { return [] }

        var result: [FaviconUserScript.FaviconLink] = []
        if let scheme = documentUrl.scheme?.lowercased(),
           scheme == "http" || scheme == "https"
        {
            result.append(FaviconUserScript.FaviconLink(href: root.appendingPathComponent("favicon.ico"), rel: "favicon.ico"))
        }

        if documentUrl.scheme?.lowercased() == "http",
           let upgradedRoot = root.sumiHTTPSURL
        {
            result.append(FaviconUserScript.FaviconLink(href: upgradedRoot.appendingPathComponent("favicon.ico"), rel: "favicon.ico"))
        }

        return result
    }

    private func filteringAlreadyFetchedFaviconLinks(from faviconLinks: [FaviconUserScript.FaviconLink]) async -> [FaviconUserScript.FaviconLink] {
        guard !faviconLinks.isEmpty else { return [] }

        var seen = Set<URL>()
        let orderedUniqueLinks = faviconLinks.filter { link in
            seen.insert(link.href).inserted
        }
        let cachedFavicons = imageCache.getFavicons(with: orderedUniqueLinks.lazy.map(\.href))?
            .filter { $0.dateCreated > .weekAgo } ?? []
        let cachedURLs = Set(cachedFavicons.map(\.url))

        return orderedUniqueLinks.filter { !cachedURLs.contains($0.href) }
    }

    private func fetchFavicons(
        faviconLinks: [FaviconUserScript.FaviconLink],
        documentUrl: URL,
        webView: WKWebView?
    ) async -> [Favicon] {
        guard !faviconLinks.isEmpty else { return [] }

        return await withTaskGroup(of: Favicon?.self) { group in
            for faviconLink in faviconLinks {
                group.addTask { [faviconDownloader] in
                    do {
                        try Task.checkCancellation()
                        let data = try await faviconDownloader.download(from: faviconLink.href, using: webView)
                        try Task.checkCancellation()
                        guard let validImageData = FaviconPayloadValidator.validatedImageData(from: data) else {
                            throw URLError(.zeroByteResource, userInfo: [NSURLErrorKey: faviconLink.href])
                        }
                        guard let image = NSImage(dataUsingCIImage: validImageData) else {
                            throw CocoaError(.fileReadCorruptFile, userInfo: [NSURLErrorKey: faviconLink.href])
                        }
                        return Favicon(
                            identifier: UUID(),
                            url: faviconLink.href,
                            image: image,
                            relationString: faviconLink.rel,
                            documentUrl: documentUrl,
                            dateCreated: Date()
                        )
                    } catch {
                        return nil
                    }
                }
            }

            var favicons: [Favicon] = []
            for await favicon in group {
                if let favicon {
                    favicons.append(favicon)
                }
            }
            return favicons
        }
    }

    @discardableResult
    private func cacheFavicons(
        _ favicons: [Favicon],
        faviconURLs: some Sequence<URL>,
        for documentUrl: URL,
        referencePolicy: ReferenceInsertionPolicy
    ) async -> Favicon? {
        await imageCache.insert(favicons)
        let cachedFavicons = imageCache.getFavicons(with: faviconURLs)?
            .filter { $0.dateCreated > .weekAgo } ?? []
        return await handleReferenceInsertion(
            documentURL: documentUrl,
            cachedFavicons: cachedFavicons,
            referencePolicy: referencePolicy
        )
    }

    @discardableResult
    private func handleReferenceInsertion(
        documentURL: URL,
        cachedFavicons: [Favicon],
        referencePolicy: ReferenceInsertionPolicy
    ) async -> Favicon? {
        let currentSmallURL = referenceCache.getFaviconUrl(for: documentURL, sizeCategory: .small)
        let currentMediumURL = referenceCache.getFaviconUrl(for: documentURL, sizeCategory: .medium)
        let currentSmallFavicon = currentSmallURL.flatMap { imageCache.get(faviconUrl: $0) }
        let currentMediumFavicon = currentMediumURL.flatMap { imageCache.get(faviconUrl: $0) }

        guard !cachedFavicons.isEmpty else {
            return currentSmallFavicon
        }

        let sortedFavicons = cachedFavicons.sorted { $0.longestSide < $1.longestSide }
        let cachedURLs = Set(cachedFavicons.map(\.url))
        let candidateSmall = FaviconSelector.getMostSuitableFavicon(for: .small, favicons: sortedFavicons)
        let candidateMedium = FaviconSelector.getMostSuitableFavicon(for: .medium, favicons: sortedFavicons)

        let selectedSmall = preferredReference(
            current: currentSmallFavicon,
            candidate: candidateSmall,
            candidateURLs: cachedURLs,
            policy: referencePolicy,
            sizeCategory: .small
        )
        let selectedMedium = preferredReference(
            current: currentMediumFavicon,
            candidate: candidateMedium,
            candidateURLs: cachedURLs,
            policy: referencePolicy,
            sizeCategory: .medium
        )

        let selectedSmallURL = selectedSmall?.url
        let selectedMediumURL = selectedMedium?.url
        if selectedSmallURL != currentSmallURL || selectedMediumURL != currentMediumURL {
            await referenceCache.insert(
                faviconUrls: (smallFaviconUrl: selectedSmallURL, mediumFaviconUrl: selectedMediumURL),
                documentUrl: documentURL
            )
        }

        if let selectedSmall {
            return selectedSmall
        }

        if let currentSmallFavicon {
            return currentSmallFavicon
        }

        if let selectedMedium {
            return selectedMedium
        }

        return currentMediumFavicon
    }

    private func preferredReference(
        current: Favicon?,
        candidate: Favicon?,
        candidateURLs: Set<URL>,
        policy: ReferenceInsertionPolicy,
        sizeCategory: Favicon.SizeCategory
    ) -> Favicon? {
        guard let candidate else { return current }
        guard let current else { return candidate }

        if policy == .authoritativeCurrentLinks, !candidateURLs.contains(current.url) {
            return candidate
        }

        return shouldPrefer(candidate: candidate, over: current, for: sizeCategory) ? candidate : current
    }

    private func shouldPrefer(
        candidate: Favicon,
        over current: Favicon,
        for sizeCategory: Favicon.SizeCategory
    ) -> Bool {
        guard candidate.url != current.url else { return false }
        let preferred = FaviconSelector.getMostSuitableFavicon(
            for: sizeCategory,
            favicons: [current, candidate].sorted { $0.longestSide < $1.longestSide }
        )
        return preferred?.url == candidate.url
    }
}

@MainActor
final class SumiFaviconSystem {
    static let shared = SumiFaviconSystem()

    let manager: FaviconManager

    init(manager: FaviconManager? = nil) {
        self.manager = manager ?? FaviconManager(
            cacheType: .standard(storeURL: SumiFaviconPersistence.defaultStoreURL())
        )
    }
}

private extension URL {
    var sumiRootURL: URL? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: true),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host != nil
        else {
            return nil
        }

        components.path = "/"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    var sumiHTTPSURL: URL? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: true) else {
            return nil
        }
        components.scheme = "https"
        return components.url
    }
}

private enum FaviconPayloadValidator {
    static func validatedImageData(from data: Data) -> Data? {
        guard data.count >= 4 else { return nil }

        let prefix = data.prefix(min(data.count, 512))
        if prefix.allSatisfy({ $0 == 0 }) {
            return nil
        }

        if looksLikeHTML(prefix) {
            return nil
        }

        if looksLikePlainText(prefix), !looksLikeSVG(prefix) {
            return nil
        }

        return data
    }

    private static func looksLikeHTML(_ prefix: Data) -> Bool {
        let normalized = normalizedASCII(prefix)
        guard !normalized.isEmpty else { return false }
        if looksLikeSVG(prefix) {
            return false
        }

        return normalized.hasPrefix("<!doctype html")
            || normalized.hasPrefix("<html")
            || normalized.contains("<head")
            || normalized.contains("<body")
    }

    private static func looksLikeSVG(_ prefix: Data) -> Bool {
        let normalized = normalizedASCII(prefix)
        guard !normalized.isEmpty else { return false }
        return normalized.contains("<svg")
    }

    private static func looksLikePlainText(_ prefix: Data) -> Bool {
        guard let text = String(data: prefix, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty
        else {
            return false
        }

        let printableScalars = text.unicodeScalars.filter {
            $0.properties.isWhitespace || (0x20...0x7E).contains($0.value)
        }
        return Double(printableScalars.count) / Double(text.unicodeScalars.count) > 0.95
    }

    private static func normalizedASCII(_ prefix: Data) -> String {
        String(decoding: prefix, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

private extension NSImage {
    var sumiPixelSize: CGSize? {
        let representationSizes = representations.compactMap { representation -> CGSize? in
            if representation.pixelsWide > 0, representation.pixelsHigh > 0 {
                return CGSize(width: representation.pixelsWide, height: representation.pixelsHigh)
            }

            let size = representation.size
            guard size.width > 0, size.height > 0 else { return nil }
            return size
        }

        if let largestRepresentation = representationSizes.max(by: {
            max($0.width, $0.height) < max($1.width, $1.height)
        }) {
            return largestRepresentation
        }

        let fallbackSize = size
        guard fallbackSize.width > 0, fallbackSize.height > 0 else { return nil }
        return fallbackSize
    }

    var sumiPixelLongestSide: CGFloat {
        guard let pixelSize = sumiPixelSize else { return 0 }
        return max(pixelSize.width, pixelSize.height)
    }

    convenience init?(dataUsingCIImage data: Data) {
        if let imageSource = CGImageSourceCreateWithData(data as CFData, nil) {
            let imageCount = CGImageSourceGetCount(imageSource)
            var bestImage: CGImage?
            var bestLongestSide = 0

            for index in 0..<imageCount {
                guard let image = CGImageSourceCreateImageAtIndex(imageSource, index, nil) else {
                    continue
                }

                let longestSide = max(image.width, image.height)
                if longestSide > bestLongestSide {
                    bestLongestSide = longestSide
                    bestImage = image
                }
            }

            if let bestImage {
                let rep = NSBitmapImageRep(cgImage: bestImage)
                self.init(size: NSSize(width: bestImage.width, height: bestImage.height))
                addRepresentation(rep)
                return
            }
        }

        if let ciImage = CIImage(data: data) {
            let rep = NSCIImageRep(ciImage: ciImage)
            self.init(size: rep.size)
            addRepresentation(rep)
            return
        }
        self.init(data: data)
    }

    var sumiPNGData: Data? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return tiffRepresentation
        }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return bitmap.representation(using: .png, properties: [:]) ?? tiffRepresentation
    }
}

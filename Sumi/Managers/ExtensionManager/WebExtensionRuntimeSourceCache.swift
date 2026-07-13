import Foundation
import WebKit

/// Publishes one authoritative WebKit source per installed extension. Source
/// creation may suspend, so every attempted publication owns a monotonic
/// revision and can never overwrite a newer source or survive invalidation.
@available(macOS 15.5, *)
@MainActor
final class WebExtensionRuntimeSourceCache {
    struct Resolution {
        let webExtension: WKWebExtension
        let loadSource: SafariAppExtensionRuntimeLoadSource
    }

    struct Entry {
        let key: WebExtensionRuntimeSourceKey
        let resolution: Resolution
        fileprivate let publicationToken: UInt64
    }

    private struct PublicationWait {
        let key: WebExtensionRuntimeSourceKey
        let publicationToken: UInt64
        let waiterToken: UInt64
    }

    private struct PendingPublication {
        let key: WebExtensionRuntimeSourceKey
        let token: UInt64
        var task: Task<Void, Never>?
        var result: Result<Resolution, Error>?
        var waiterTokens: Set<UInt64>
        var continuations:
            [UInt64: CheckedContinuation<Resolution, Error>]
    }

    typealias SourceFactory = @MainActor (
        _ sourceKind: WebExtensionSourceKind,
        _ sourceBundlePath: String,
        _ packageRoot: URL
    ) async throws -> Resolution

    private let admission: ExtensionContextLoadAdmission
    private let makeSource: SourceFactory
    private var entriesByExtensionID: [String: Entry] = [:]
    private var nextPublicationToken: UInt64 = 0
    private var nextWaiterToken: UInt64 = 0
    private var pendingPublicationByExtensionID:
        [String: PendingPublication] = [:]

    init(
        admission: ExtensionContextLoadAdmission,
        makeSource: SourceFactory? = nil
    ) {
        self.admission = admission
        self.makeSource = makeSource ?? { sourceKind, sourceBundlePath, packageRoot in
            let created = try await SafariAppExtensionResources.makeWebExtension(
                sourceKind: sourceKind,
                sourceBundlePath: sourceBundlePath,
                packageRoot: packageRoot
            )
            return Resolution(
                webExtension: created.extension,
                loadSource: created.loadSource
            )
        }
    }

    var extensionIDs: Set<String> {
        Set(entriesByExtensionID.keys)
            .union(pendingPublicationByExtensionID.keys)
    }

    func entry(for extensionID: String) -> Entry? {
        entriesByExtensionID[extensionID]
    }

    func resolve(
        extensionID: String,
        sourceKind: WebExtensionSourceKind,
        sourceBundlePath: String,
        packageRoot: URL,
        claim: ExtensionContextLoadClaim,
        mutationLease: ExtensionRuntimeMutationLease?
    ) async throws -> Resolution {
        guard claim.key.extensionId == extensionID else {
            throw CancellationError()
        }
        try admission.validate(claim, mutationLease: mutationLease)

        let runtimeSourceKind: WebExtensionSourceKind =
            sourceKind == .safariAppExtension
                && SafariAppExtensionResources.installedAppexBundleURL(
                    sourceKind: sourceKind,
                    sourceBundlePath: sourceBundlePath
                ) == nil
            ? .directory
            : sourceKind
        let normalizedPackageRoot = packageRoot.standardizedFileURL
        let key = WebExtensionRuntimeSourceKey(
            sourceKind: runtimeSourceKind,
            sourceBundlePath: URL(
                fileURLWithPath: sourceBundlePath,
                isDirectory: true
            ).standardizedFileURL.path,
            packageRootPath: normalizedPackageRoot.path
        )

        if let entry = entriesByExtensionID[extensionID], entry.key == key {
            try admission.validate(claim, mutationLease: mutationLease)
            return entry.resolution
        }

        let wait = acquirePublication(
            for: extensionID,
            key: key,
            sourceKind: runtimeSourceKind,
            sourceBundlePath: sourceBundlePath,
            packageRoot: normalizedPackageRoot
        )
        defer {
            releaseWaiter(
                for: extensionID,
                publicationToken: wait.publicationToken,
                waiterToken: wait.waiterToken
            )
        }
        let candidate = try await waitForResolution(
            extensionID: extensionID,
            wait: wait
        )
        try Task.checkCancellation()
        try admission.validate(claim, mutationLease: mutationLease)

        if let entry = entriesByExtensionID[extensionID],
           entry.key == key,
           entry.publicationToken == wait.publicationToken {
            return entry.resolution
        }
        guard let current = pendingPublicationByExtensionID[extensionID],
              current.token == wait.publicationToken,
              current.key == key
        else {
            throw CancellationError()
        }

        entriesByExtensionID[extensionID] = Entry(
            key: key,
            resolution: candidate,
            publicationToken: wait.publicationToken
        )
        pendingPublicationByExtensionID.removeValue(forKey: extensionID)
        return candidate
    }

    func remove(extensionID: String) {
        entriesByExtensionID.removeValue(forKey: extensionID)
        cancelPublication(for: extensionID)
    }

    func removeAll() {
        for extensionID in Array(pendingPublicationByExtensionID.keys) {
            cancelPublication(for: extensionID)
        }
        entriesByExtensionID.removeAll()
    }

    private func acquirePublication(
        for extensionID: String,
        key: WebExtensionRuntimeSourceKey,
        sourceKind: WebExtensionSourceKind,
        sourceBundlePath: String,
        packageRoot: URL
    ) -> PublicationWait {
        nextWaiterToken &+= 1
        let waiterToken = nextWaiterToken
        if var pending = pendingPublicationByExtensionID[extensionID],
           pending.key == key {
            pending.waiterTokens.insert(waiterToken)
            pendingPublicationByExtensionID[extensionID] = pending
            return PublicationWait(
                key: key,
                publicationToken: pending.token,
                waiterToken: waiterToken
            )
        }

        cancelPublication(for: extensionID)
        entriesByExtensionID.removeValue(forKey: extensionID)
        nextPublicationToken &+= 1
        let token = nextPublicationToken
        let publication = PendingPublication(
            key: key,
            token: token,
            task: nil,
            result: nil,
            waiterTokens: [waiterToken],
            continuations: [:]
        )
        pendingPublicationByExtensionID[extensionID] = publication
        let task = Task { @MainActor [weak self, makeSource] in
            let result: Result<Resolution, Error>
            do {
                try Task.checkCancellation()
                let resolution = try await makeSource(
                    sourceKind,
                    sourceBundlePath,
                    packageRoot
                )
                try Task.checkCancellation()
                result = .success(resolution)
            } catch {
                result = .failure(error)
            }
            self?.completePublication(
                for: extensionID,
                publicationToken: token,
                result: result
            )
        }
        pendingPublicationByExtensionID[extensionID]?.task = task
        return PublicationWait(
            key: key,
            publicationToken: token,
            waiterToken: waiterToken
        )
    }

    private func waitForResolution(
        extensionID: String,
        wait: PublicationWait
    ) async throws -> Resolution {
        let publicationToken = wait.publicationToken
        let waiterToken = wait.waiterToken
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                register(
                    continuation,
                    extensionID: extensionID,
                    wait: wait
                )
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.releaseWaiter(
                    for: extensionID,
                    publicationToken: publicationToken,
                    waiterToken: waiterToken
                )
            }
        }
    }

    private func register(
        _ continuation: CheckedContinuation<Resolution, Error>,
        extensionID: String,
        wait: PublicationWait
    ) {
        guard var pending = pendingPublicationByExtensionID[extensionID],
              pending.token == wait.publicationToken,
              pending.key == wait.key,
              pending.waiterTokens.contains(wait.waiterToken)
        else {
            continuation.resume(throwing: CancellationError())
            return
        }
        if let result = pending.result {
            continuation.resume(with: result)
        } else {
            pending.continuations[wait.waiterToken] = continuation
            pendingPublicationByExtensionID[extensionID] = pending
        }
    }

    private func completePublication(
        for extensionID: String,
        publicationToken: UInt64,
        result: Result<Resolution, Error>
    ) {
        guard var pending = pendingPublicationByExtensionID[extensionID],
              pending.token == publicationToken
        else {
            return
        }
        pending.task = nil
        pending.result = result
        let continuations = Array(pending.continuations.values)
        pending.continuations.removeAll()
        pendingPublicationByExtensionID[extensionID] = pending
        for continuation in continuations {
            continuation.resume(with: result)
        }
    }

    private func releaseWaiter(
        for extensionID: String,
        publicationToken: UInt64,
        waiterToken: UInt64
    ) {
        guard var pending = pendingPublicationByExtensionID[extensionID],
              pending.token == publicationToken,
              pending.waiterTokens.remove(waiterToken) != nil
        else {
            return
        }
        let continuation = pending.continuations.removeValue(
            forKey: waiterToken
        )
        if pending.waiterTokens.isEmpty {
            pendingPublicationByExtensionID.removeValue(forKey: extensionID)
            pending.task?.cancel()
        } else {
            pendingPublicationByExtensionID[extensionID] = pending
        }
        continuation?.resume(throwing: CancellationError())
    }

    private func cancelPublication(for extensionID: String) {
        guard let pending = pendingPublicationByExtensionID.removeValue(
            forKey: extensionID
        ) else {
            return
        }
        pending.task?.cancel()
        for continuation in pending.continuations.values {
            continuation.resume(throwing: CancellationError())
        }
    }
}

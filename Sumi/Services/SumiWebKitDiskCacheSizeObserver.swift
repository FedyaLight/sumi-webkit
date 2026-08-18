import Foundation
import WebKit

/// Low-frequency, best-effort HTTP DiskCache measurement. The SPI is isolated
/// here so the storage policy never treats an unavailable result as zero bytes.
@MainActor
enum SumiWebKitDiskCacheSizeObserver {
    private static let timeout: TimeInterval = 15

    static func diskCacheBytes(in dataStore: WKWebsiteDataStore) async -> UInt64? {
        guard RuntimeDiagnostics.usesEphemeralPlatformStores == false else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            let result = DiskCacheSizeResult(continuation: continuation)
            let scheduled = SumiFetchWKWebsiteDataStoreDiskCacheSize(
                dataStore,
                timeout,
                { size in
                    result.finish(size?.uint64Value)
                }
            )
            if scheduled == false {
                result.finish(nil)
            }
        }
    }
}

private final class DiskCacheSizeResult: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<UInt64?, Never>?

    init(continuation: CheckedContinuation<UInt64?, Never>) {
        self.continuation = continuation
    }

    func finish(_ value: UInt64?) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: value)
    }
}

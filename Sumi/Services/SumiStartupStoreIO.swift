import CryptoKit
import Darwin
import Foundation
import OSLog

/// Mechanical filesystem primitives used only by startup store recovery.
enum SumiStartupStoreIO {
    private static let log = Logger.sumi(category: "StartupStoreRecoveryIO")

    final class LifetimeLock {
        private let descriptor: Int32

        init(storeURL: URL) throws {
            let lockURL = storeURL.deletingLastPathComponent().appendingPathComponent(
                ".sumi-startup-store.lock",
                isDirectory: false
            )
            let openedDescriptor = Darwin.open(
                lockURL.path,
                O_CREAT | O_RDWR | O_CLOEXEC | O_EXLOCK | O_NONBLOCK,
                S_IRUSR | S_IWUSR
            )
            guard openedDescriptor >= 0 else {
                throw IOError.storeLockUnavailable(lockURL, errno)
            }
            descriptor = openedDescriptor
        }

        deinit {
            Darwin.close(descriptor)
        }
    }

    enum IOError: Error {
        case atomicPublicationFailed(from: URL, to: URL, code: Int32)
        case durabilityBarrierFailed(URL, Int32)
        case storeLockUnavailable(URL, Int32)
    }

    static func atomicRename(from sourceURL: URL, to destinationURL: URL) throws {
        guard Darwin.rename(sourceURL.path, destinationURL.path) == 0 else {
            throw IOError.atomicPublicationFailed(
                from: sourceURL,
                to: destinationURL,
                code: errno
            )
        }
    }

    static func sha256Digest(at url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        do {
            var hasher = SHA256()
            while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
                hasher.update(data: data)
            }
            let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            try handle.close()
            return digest
        } catch {
            do {
                try handle.close()
            } catch let closeError {
                log.error(
                    "Failed to close startup-store digest input at \(url.path, privacy: .public): \(String(describing: closeError), privacy: .public)"
                )
            }
            throw error
        }
    }

    static func removeUnpublishedStagingArtifact(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            log.error(
                "Failed to remove unpublished startup-store staging artifact at \(url.path, privacy: .public): \(String(describing: error), privacy: .public)"
            )
        }
    }

    static func synchronizeFile(at url: URL) throws {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw IOError.durabilityBarrierFailed(url, errno)
        }
        defer { Darwin.close(descriptor) }

        if Darwin.fcntl(descriptor, F_FULLFSYNC) == -1, Darwin.fsync(descriptor) == -1 {
            throw IOError.durabilityBarrierFailed(url, errno)
        }
    }

    static func synchronizeDirectory(at url: URL) throws {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw IOError.durabilityBarrierFailed(url, errno)
        }
        defer { Darwin.close(descriptor) }

        if Darwin.fsync(descriptor) == -1 {
            throw IOError.durabilityBarrierFailed(url, errno)
        }
    }
}

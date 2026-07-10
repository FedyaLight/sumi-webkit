import Darwin
import Foundation

enum ContentBlockingItemExchange {
    /// Atomically exchanges two existing filesystem items on the same macOS volume.
    /// Each original item remains available at the other path, so callers can
    /// validate a publication and compensate without losing the previous value.
    static func swap(_ first: URL, _ second: URL) throws {
        let result = first.path.withCString { firstPath in
            second.path.withCString { secondPath in
                renamex_np(firstPath, secondPath, UInt32(RENAME_SWAP))
            }
        }
        guard result == 0 else {
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(errno),
                userInfo: [
                    NSLocalizedDescriptionKey: "Atomic filesystem exchange failed between \(first.path) and \(second.path)",
                ]
            )
        }
    }
}

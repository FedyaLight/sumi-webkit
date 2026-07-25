import Compression
import Foundation

/// Decodes Mozilla's `mozLz4` container, used by Firefox and Zen for
/// `sessionstore.jsonlz4`, `recovery.jsonlz4`, and `zen-sessions.jsonlz4`.
///
/// The container is an 8-byte magic, a little-endian `UInt32` of the
/// uncompressed size, then a raw LZ4 block. The declared size is written by the
/// producer and is not always trustworthy, so a short decode retries against a
/// grown buffer instead of failing the whole import.
enum SumiMozillaLZ4Decoder {
    private static let magic = Data([0x6D, 0x6F, 0x7A, 0x4C, 0x7A, 0x34, 0x30, 0x00])
    private static let headerLength = 12
    private static let maximumGrowthFactor = 16

    static func isMozillaLZ4(_ data: Data) -> Bool {
        data.count >= headerLength && Data(data.prefix(magic.count)) == magic
    }

    static func decode(_ data: Data) throws -> Data {
        guard isMozillaLZ4(data) else {
            throw SumiImportExportError.unsupportedFile("Session file is not Mozilla LZ4.")
        }
        let declaredSize = Int(
            data[8..<12].enumerated().reduce(UInt32(0)) { partial, item in
                partial | (UInt32(item.element) << UInt32(item.offset * 8))
            }
        )
        let compressed = Data(data.dropFirst(headerLength))

        // A truthful header decodes on the first attempt, filling the buffer
        // exactly. Anything else — a short write, or a buffer filled to the brim
        // by a payload that under-reported its size — retries against a grown
        // buffer, because `compression_decode_buffer` cannot distinguish
        // "finished" from "ran out of room" except by leaving space unused.
        var capacity = max(declaredSize, compressed.count, 1)
        var factor = 1
        while factor <= maximumGrowthFactor {
            let (written, output) = decodeBuffer(compressed, capacity: capacity)
            if written > 0, written < capacity || written == declaredSize {
                return output.prefix(written)
            }
            capacity *= 2
            factor *= 2
        }
        throw SumiImportExportError.unsupportedFile(
            "Sumi could not decode the LZ4 session data (declared \(declaredSize) bytes)."
        )
    }

    private static func decodeBuffer(_ compressed: Data, capacity: Int) -> (written: Int, output: Data) {
        guard capacity > 0, compressed.isEmpty == false else { return (0, Data()) }
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { outPtr -> Int in
            guard let outBase = outPtr.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compressed.withUnsafeBytes { inPtr -> Int in
                guard let inBase = inPtr.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(
                    outBase,
                    capacity,
                    inBase,
                    compressed.count,
                    nil,
                    COMPRESSION_LZ4_RAW
                )
            }
        }
        return (written, output)
    }
}

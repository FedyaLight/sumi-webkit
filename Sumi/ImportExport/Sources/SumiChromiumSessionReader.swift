import Foundation

/// A tab recovered from a Chromium session file.
struct SumiChromiumSessionTab: Equatable, Sendable {
    var tabID: Int32
    var windowID: Int32
    var indexInWindow: Int
    var isPinned: Bool
    var url: String
    var title: String
}

/// Reads Chromium's SNSS session files, which are the only place a Chromium
/// browser records which tabs are open and which of them are pinned. Bookmarks
/// are a different channel entirely — deriving the sidebar from bookmarks would
/// flood it with every bookmark the user has ever made.
///
/// The format is undocumented and versioned, so every failure here degrades to
/// "no tabs recovered". Callers must treat an empty result as normal and never
/// let it fail the surrounding import.
enum SumiChromiumSessionReader {
    private enum Command {
        static let setTabWindow: UInt8 = 0
        static let setTabIndexInWindow: UInt8 = 2
        static let updateTabNavigation: UInt8 = 6
        static let setSelectedNavigationIndex: UInt8 = 7
        static let setPinnedState: UInt8 = 12
        static let tabClosed: UInt8 = 16
        static let windowClosed: UInt8 = 17
    }

    /// Picks the newest `Sessions/Session_<timestamp>`, falling back to the
    /// legacy `Current Session` file.
    static func sessionFileURL(inProfile profileURL: URL) -> URL? {
        let sessionsDirectory = profileURL.appendingPathComponent("Sessions", isDirectory: true)
        let candidates = (try? FileManager.default.contentsOfDirectory(
            at: sessionsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        let sessions = candidates
            .filter { $0.lastPathComponent.hasPrefix("Session_") }
            .sorted { lhs, rhs in
                lhs.lastPathComponent.compare(rhs.lastPathComponent, options: .numeric) == .orderedAscending
            }
        if let newest = sessions.last { return newest }

        let legacy = profileURL.appendingPathComponent("Current Session")
        return FileManager.default.fileExists(atPath: legacy.path) ? legacy : nil
    }

    static func readTabs(from fileURL: URL) -> [SumiChromiumSessionTab] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return readTabs(data: data)
    }

    static func readTabs(data: Data) -> [SumiChromiumSessionTab] {
        guard data.count > 8,
              data[data.startIndex..<data.startIndex + 4].elementsEqual("SNSS".utf8)
        else { return [] }

        // Commands are replayed in order; later commands overwrite earlier ones,
        // which is how Chromium represents "this tab moved / was renamed".
        var tabs: [Int32: SumiChromiumSessionTab] = [:]
        var closedTabs: Set<Int32> = []
        var closedWindows: Set<Int32> = []
        var order: [Int32] = []

        func tab(_ id: Int32) -> SumiChromiumSessionTab {
            if let existing = tabs[id] { return existing }
            order.append(id)
            return SumiChromiumSessionTab(
                tabID: id,
                windowID: 0,
                indexInWindow: 0,
                isPinned: false,
                url: "",
                title: ""
            )
        }

        for (id, payload) in commands(in: data.dropFirst(8)) {
            switch id {
            case Command.setTabWindow:
                guard let pair = twoInt32(payload) else { continue }
                var record = tab(pair.1)
                record.windowID = pair.0
                tabs[pair.1] = record
            case Command.setTabIndexInWindow:
                guard let pair = twoInt32(payload) else { continue }
                var record = tab(pair.0)
                record.indexInWindow = Int(pair.1)
                tabs[pair.0] = record
            case Command.setPinnedState:
                guard let pair = twoInt32(payload) else { continue }
                var record = tab(pair.0)
                record.isPinned = pair.1 != 0
                tabs[pair.0] = record
            case Command.updateTabNavigation:
                guard let navigation = navigationEntry(payload) else { continue }
                var record = tab(navigation.tabID)
                record.url = navigation.url
                record.title = navigation.title.isEmpty ? record.title : navigation.title
                tabs[navigation.tabID] = record
            case Command.setSelectedNavigationIndex:
                continue
            case Command.tabClosed:
                if let closed = firstInt32(payload) { closedTabs.insert(closed) }
            case Command.windowClosed:
                if let closed = firstInt32(payload) { closedWindows.insert(closed) }
            default:
                continue
            }
        }

        return order
            .compactMap { tabs[$0] }
            .filter { closedTabs.contains($0.tabID) == false }
            .filter { closedWindows.contains($0.windowID) == false }
            .filter { $0.url.isEmpty == false }
    }

    /// Splits the body into `[uint16 size][uint8 id][size - 1 payload]` records.
    /// A truncated trailing record (the browser was mid-write) ends the walk
    /// rather than failing it.
    private static func commands(in body: Data) -> [(UInt8, Data)] {
        var output: [(UInt8, Data)] = []
        var cursor = body.startIndex
        while cursor + 3 <= body.endIndex {
            let size = Int(UInt16(body[cursor]) | (UInt16(body[cursor + 1]) << 8))
            guard size >= 1, cursor + 2 + size <= body.endIndex else { break }
            let id = body[cursor + 2]
            let payloadStart = cursor + 3
            let payloadEnd = cursor + 2 + size
            output.append((id, Data(body[payloadStart..<payloadEnd])))
            cursor = payloadEnd
        }
        return output
    }

    private static func firstInt32(_ payload: Data) -> Int32? {
        var reader = PickleReader(payload, hasSizeHeader: false)
        return reader.readInt32()
    }

    private static func twoInt32(_ payload: Data) -> (Int32, Int32)? {
        var reader = PickleReader(payload, hasSizeHeader: false)
        guard let first = reader.readInt32(), let second = reader.readInt32() else { return nil }
        return (first, second)
    }

    private static func navigationEntry(_ payload: Data) -> (tabID: Int32, url: String, title: String)? {
        var reader = PickleReader(payload, hasSizeHeader: true)
        guard let tabID = reader.readInt32(),
              reader.readInt32() != nil,
              let url = reader.readString()
        else { return nil }
        return (tabID, url, reader.readString16() ?? "")
    }
}

/// Minimal reader for `base::Pickle`, the serialization Chromium uses inside
/// session commands: little-endian fields each padded up to a 4-byte boundary.
private struct PickleReader {
    private let data: Data
    private var cursor: Int

    init(_ data: Data, hasSizeHeader: Bool) {
        self.data = data
        // Navigation payloads prefix the pickle with its own byte count.
        self.cursor = hasSizeHeader ? 4 : 0
    }

    mutating func readInt32() -> Int32? {
        guard cursor + 4 <= data.count else { return nil }
        let value = data.withUnsafeBytes { raw -> UInt32 in
            var bytes: UInt32 = 0
            for offset in 0..<4 {
                bytes |= UInt32(raw[data.startIndex + cursor + offset]) << UInt32(offset * 8)
            }
            return bytes
        }
        cursor += 4
        return Int32(bitPattern: value)
    }

    mutating func readString() -> String? {
        guard let length = readInt32(), length >= 0 else { return nil }
        let count = Int(length)
        guard cursor + count <= data.count else { return nil }
        let start = data.startIndex + cursor
        let value = String(decoding: data[start..<(start + count)], as: UTF8.self)
        cursor += paddedLength(count)
        return value
    }

    mutating func readString16() -> String? {
        // The length is a character count, not a byte count.
        guard let length = readInt32(), length >= 0 else { return nil }
        let byteCount = Int(length) * 2
        guard cursor + byteCount <= data.count else { return nil }
        let start = data.startIndex + cursor
        var scalars: [UInt16] = []
        scalars.reserveCapacity(Int(length))
        for offset in stride(from: 0, to: byteCount, by: 2) {
            scalars.append(UInt16(data[start + offset]) | (UInt16(data[start + offset + 1]) << 8))
        }
        cursor += paddedLength(byteCount)
        return String(decoding: scalars, as: UTF16.self)
    }

    private func paddedLength(_ count: Int) -> Int {
        count + ((4 - (count % 4)) % 4)
    }
}

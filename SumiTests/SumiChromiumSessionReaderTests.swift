import XCTest

@testable import Sumi

/// SNSS is an undocumented, versioned binary format, so these fixtures are
/// hand-assembled to the byte layout observed in real Chromium session files.
final class SumiChromiumSessionReaderTests: XCTestCase {
    func testRecoversPinnedAndUnpinnedTabsInOrder() throws {
        var session = SNSSBuilder()
        session.setTabWindow(window: 1, tab: 10)
        session.setTabIndexInWindow(tab: 10, index: 0)
        session.setPinnedState(tab: 10, pinned: true)
        session.updateTabNavigation(tab: 10, url: "https://pinned.example", title: "Pinned")

        session.setTabWindow(window: 1, tab: 11)
        session.setTabIndexInWindow(tab: 11, index: 1)
        session.updateTabNavigation(tab: 11, url: "https://open.example", title: "Open")

        let tabs = SumiChromiumSessionReader.readTabs(data: session.data)

        XCTAssertEqual(tabs.map(\.url), ["https://pinned.example", "https://open.example"])
        XCTAssertEqual(tabs.map(\.isPinned), [true, false])
        XCTAssertEqual(tabs.map(\.title), ["Pinned", "Open"])
        XCTAssertEqual(tabs.map(\.indexInWindow), [0, 1])
    }

    func testDropsClosedTabsAndWindows() throws {
        var session = SNSSBuilder()
        session.setTabWindow(window: 1, tab: 10)
        session.updateTabNavigation(tab: 10, url: "https://kept.example", title: "Kept")
        session.setTabWindow(window: 1, tab: 11)
        session.updateTabNavigation(tab: 11, url: "https://closed.example", title: "Closed")
        session.setTabWindow(window: 2, tab: 12)
        session.updateTabNavigation(tab: 12, url: "https://gone.example", title: "Gone")
        session.tabClosed(tab: 11)
        session.windowClosed(window: 2)

        let tabs = SumiChromiumSessionReader.readTabs(data: session.data)

        XCTAssertEqual(tabs.map(\.url), ["https://kept.example"])
    }

    /// A later navigation overwrites an earlier one for the same tab; that is
    /// how Chromium records the user navigating.
    func testLastNavigationWins() throws {
        var session = SNSSBuilder()
        session.setTabWindow(window: 1, tab: 10)
        session.updateTabNavigation(tab: 10, url: "https://first.example", title: "First")
        session.updateTabNavigation(tab: 10, url: "https://second.example", title: "Second")

        let tabs = SumiChromiumSessionReader.readTabs(data: session.data)

        XCTAssertEqual(tabs.map(\.url), ["https://second.example"])
        XCTAssertEqual(tabs.first?.title, "Second")
    }

    func testHandlesNonASCIITitles() throws {
        var session = SNSSBuilder()
        session.setTabWindow(window: 1, tab: 10)
        session.updateTabNavigation(tab: 10, url: "https://example.com", title: "Приве́т 🌍")

        let tabs = SumiChromiumSessionReader.readTabs(data: session.data)

        XCTAssertEqual(tabs.first?.title, "Приве́т 🌍")
    }

    // MARK: - Degradation

    func testRejectsNonSNSSPayload() {
        XCTAssertTrue(SumiChromiumSessionReader.readTabs(data: Data("not a session".utf8)).isEmpty)
    }

    func testStopsAtATruncatedTrailingCommand() throws {
        var session = SNSSBuilder()
        session.setTabWindow(window: 1, tab: 10)
        session.updateTabNavigation(tab: 10, url: "https://kept.example", title: "Kept")
        // The browser was killed mid-write: a length prefix with no body.
        var truncated = session.data
        truncated.append(contentsOf: [0x40, 0x00, 0x06, 0x01])

        let tabs = SumiChromiumSessionReader.readTabs(data: truncated)

        XCTAssertEqual(tabs.map(\.url), ["https://kept.example"])
    }

    func testIgnoresUnknownCommandIdentifiers() throws {
        var session = SNSSBuilder()
        session.setTabWindow(window: 1, tab: 10)
        session.appendRawCommand(id: 200, payload: Data([1, 2, 3, 4, 5, 6, 7, 8]))
        session.updateTabNavigation(tab: 10, url: "https://kept.example", title: "Kept")

        XCTAssertEqual(SumiChromiumSessionReader.readTabs(data: session.data).map(\.url), ["https://kept.example"])
    }
}

/// Assembles the byte layout Chromium writes: `"SNSS"`, an int32 version, then
/// `[uint16 size][uint8 id][payload]` records.
private struct SNSSBuilder {
    private(set) var data: Data

    init(version: Int32 = 3) {
        data = Data("SNSS".utf8)
        data.append(contentsOf: withUnsafeBytes(of: version.littleEndian, Array.init))
    }

    mutating func setTabWindow(window: Int32, tab: Int32) {
        appendRawCommand(id: 0, payload: int32(window) + int32(tab))
    }

    mutating func setTabIndexInWindow(tab: Int32, index: Int32) {
        appendRawCommand(id: 2, payload: int32(tab) + int32(index))
    }

    mutating func setPinnedState(tab: Int32, pinned: Bool) {
        appendRawCommand(id: 12, payload: int32(tab) + int32(pinned ? 1 : 0))
    }

    mutating func tabClosed(tab: Int32) {
        appendRawCommand(id: 16, payload: int32(tab) + int32(0))
    }

    mutating func windowClosed(window: Int32) {
        appendRawCommand(id: 17, payload: int32(window) + int32(0))
    }

    mutating func updateTabNavigation(tab: Int32, url: String, title: String) {
        var pickle = Data()
        pickle += int32(tab)
        pickle += int32(0) // navigation index
        pickle += pickleString(url)
        pickle += pickleString16(title)
        appendRawCommand(id: 6, payload: int32(Int32(pickle.count)) + pickle)
    }

    mutating func appendRawCommand(id: UInt8, payload: Data) {
        let size = UInt16(payload.count + 1)
        data.append(UInt8(size & 0xFF))
        data.append(UInt8(size >> 8))
        data.append(id)
        data.append(payload)
    }

    private func int32(_ value: Int32) -> Data {
        Data(withUnsafeBytes(of: value.littleEndian, Array.init))
    }

    private func pickleString(_ value: String) -> Data {
        let bytes = Data(value.utf8)
        return int32(Int32(bytes.count)) + bytes + padding(bytes.count)
    }

    private func pickleString16(_ value: String) -> Data {
        let units = Array(value.utf16)
        var bytes = Data()
        for unit in units {
            bytes.append(UInt8(unit & 0xFF))
            bytes.append(UInt8(unit >> 8))
        }
        return int32(Int32(units.count)) + bytes + padding(bytes.count)
    }

    private func padding(_ count: Int) -> Data {
        Data(repeating: 0, count: (4 - (count % 4)) % 4)
    }
}

import XCTest
@testable import Sumi

@MainActor
final class UserScriptsStrictAndBackupTests: XCTestCase {

    private func tempScriptsDir() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiUserscriptTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func writeScript(named filename: String, in dir: URL) throws {
        let body = """
        // ==UserScript==
        // @name Strict Gate Test
        // @namespace https://example.test/ns
        // @version 1.0
        // @match https://www.example.test/*
        // ==/UserScript==
        console.log('hi');
        """
        try body.write(to: dir.appendingPathComponent(filename), atomically: true, encoding: .utf8)
    }

    func testStrictOriginSkipsMatchUntilAllowed() throws {
        let dir = try tempScriptsDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try writeScript(named: "gate.user.js", in: dir)

        let store = UserScriptStore(directory: dir, context: nil)
        store.runMode = .strictOrigin

        let url = try XCTUnwrap(URL(string: "https://www.example.test/page"))
        XCTAssertTrue(store.scriptsForURL(url).isEmpty, "Without origin allow, strict mode must not inject")

        store.setOriginAllow(true, filename: "gate.user.js", for: url)
        XCTAssertEqual(store.scriptsForURL(url).count, 1)

        store.setOriginDeny(true, filename: "gate.user.js", for: url)
        XCTAssertTrue(store.scriptsForURL(url).isEmpty, "Deny must win after allow")
    }

    func testAlwaysMatchStillHonorsDeny() throws {
        let dir = try tempScriptsDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try writeScript(named: "deny.user.js", in: dir)

        let store = UserScriptStore(directory: dir, context: nil)
        store.runMode = .alwaysMatch

        let url = try XCTUnwrap(URL(string: "https://www.example.test/page"))
        XCTAssertEqual(store.scriptsForURL(url).count, 1)

        store.setOriginDeny(true, filename: "deny.user.js", for: url)
        XCTAssertTrue(store.scriptsForURL(url).isEmpty)
    }

    func testBackupZipRoundTripIncludesOriginRulesWhenRequested() throws {
        let dirA = try tempScriptsDir()
        let dirB = try tempScriptsDir()
        defer {
            try? FileManager.default.removeItem(at: dirA)
            try? FileManager.default.removeItem(at: dirB)
        }

        try writeScript(named: "pack.user.js", in: dirA)

        let storeA = UserScriptStore(directory: dirA, context: nil)
        storeA.runMode = .strictOrigin
        let page = try XCTUnwrap(URL(string: "https://www.example.test/x"))
        storeA.setOriginAllow(true, filename: "pack.user.js", for: page)
        storeA.setEnabled(false, for: "pack.user.js")

        let zip = FileManager.default.temporaryDirectory
            .appendingPathComponent("sumi-backup-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: zip) }

        try storeA.exportBackupArchive(to: zip, includeOriginRules: true)

        try writeScript(named: "pack.user.js", in: dirB)
        let storeB = UserScriptStore(directory: dirB, context: nil)
        _ = try storeB.importBackupArchive(from: zip)

        XCTAssertEqual(storeB.effectiveRunMode, .strictOrigin)
        XCTAssertTrue(storeB.isOriginAllowed(filename: "pack.user.js", for: page))
        let imported = storeB.scripts.first { $0.filename == "pack.user.js" }
        XCTAssertEqual(imported?.isEnabled, false)
    }

    func testLazyBodyLoadsFromDiskOnCodeAccess() throws {
        let dir = try tempScriptsDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try writeScript(named: "lazy.user.js", in: dir)

        let store = UserScriptStore(directory: dir, context: nil)
        store.lazyScriptBodyEnabled = true
        store.reload()

        let url = try XCTUnwrap(URL(string: "https://www.example.test/z"))
        store.runMode = .strictOrigin
        store.setOriginAllow(true, filename: "lazy.user.js", for: url)

        let script = try XCTUnwrap(store.scriptsForURL(url).first)
        XCTAssertTrue(script.metadata.code.isEmpty)
        XCTAssertNotNil(script.sourceFileURL)

        XCTAssertTrue(script.code.contains("console.log"))
        XCTAssertFalse(script.metadata.code.isEmpty)
    }

    func testAutoUpdateIntervalPersistsInManifestSettings() throws {
        let dir = try tempScriptsDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store1 = UserScriptStore(directory: dir, context: nil)
        store1.autoUpdateInterval = "daily"

        let store2 = UserScriptStore(directory: dir, context: nil)
        XCTAssertEqual(store2.autoUpdateInterval, "daily")
    }
}

import XCTest

@testable import Sumi

final class UserscriptsLibraryProtocolServiceTests: XCTestCase {
    func testNativeChecksAndInjectionUseSeparateFileLibrary() async throws {
        let fixture = try makeFixture()
        let script = """
        // ==UserScript==
        // @name Example Script
        // @match https://example.com/*
        // @run-at document-start
        // @grant GM.info
        // ==/UserScript==
        window.__userscriptsExample = true;
        """
        try Data(script.utf8).write(
            to: fixture.scripts.appendingPathComponent("Example Script.user.js")
        )

        let checks = await fixture.service.handle(
            message: .init(value: ["name": "NATIVE_CHECKS"]),
            scriptsURL: fixture.scripts,
            stateRootURL: fixture.state,
            extensionVersion: "5.0"
        )
        XCTAssertEqual(
            (checks.value as? [String: String])?["success"],
            "Native checks complete"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: fixture.state.appendingPathComponent("manifest.json").path
            )
        )

        let injection = await fixture.service.handle(
            message: .init(value: [
                "name": "REQ_USERSCRIPTS",
                "url": "https://example.com/page",
                "isTop": true,
            ]),
            scriptsURL: fixture.scripts,
            stateRootURL: fixture.state,
            extensionVersion: "5.0"
        )
        let payload = try XCTUnwrap(injection.value as? [String: Any])
        let files = try XCTUnwrap(payload["files"] as? [String: Any])
        let scripts = try XCTUnwrap(files["js"] as? [[String: Any]])
        XCTAssertEqual(scripts.count, 1)
        XCTAssertEqual(scripts[0]["type"] as? String, "js")
        XCTAssertTrue((scripts[0]["code"] as? String)?.contains("__userscriptsExample") == true)

        let noMatch = await fixture.service.handle(
            message: .init(value: [
                "name": "REQ_USERSCRIPTS",
                "url": "https://invalid.example/page",
                "isTop": true,
            ]),
            scriptsURL: fixture.scripts,
            stateRootURL: fixture.state,
            extensionVersion: "5.0"
        )
        let noMatchPayload = try XCTUnwrap(noMatch.value as? [String: Any])
        let noMatchFiles = try XCTUnwrap(noMatchPayload["files"] as? [String: Any])
        XCTAssertEqual((noMatchFiles["js"] as? [[String: Any]])?.count, 0)
    }

    func testSaveRenameToggleAndTrashMaintainManifest() async throws {
        let fixture = try makeFixture()
        let initial = """
        // ==UserScript==
        // @name First Name
        // @match https://example.com/*
        // ==/UserScript==
        console.log('first');
        """
        let saved = await fixture.service.handle(
            message: .init(value: [
                "name": "PAGE_SAVE",
                "item": ["filename": "New.user.js", "type": "js"],
                "content": initial,
            ]),
            scriptsURL: fixture.scripts,
            stateRootURL: fixture.state,
            extensionVersion: "5"
        )
        let savedItem = try XCTUnwrap(saved.value as? [String: Any])
        let filename = try XCTUnwrap(savedItem["filename"] as? String)
        XCTAssertEqual(filename, "First Name.user.js")

        let toggled = await fixture.service.handle(
            message: .init(value: [
                "name": "TOGGLE_ITEM",
                "item": ["filename": filename, "disabled": false],
            ]),
            scriptsURL: fixture.scripts,
            stateRootURL: fixture.state,
            extensionVersion: "5"
        )
        XCTAssertEqual((toggled.value as? [String: Any])?["success"] as? Bool, true)

        let all = await fixture.service.handle(
            message: .init(value: ["name": "PAGE_ALL_FILES"]),
            scriptsURL: fixture.scripts,
            stateRootURL: fixture.state,
            extensionVersion: "5"
        )
        let items = try XCTUnwrap(all.value as? [[String: Any]])
        XCTAssertEqual(items.first?["disabled"] as? Bool, true)

        let trashed = await fixture.service.handle(
            message: .init(value: [
                "name": "PAGE_TRASH",
                "item": ["filename": filename],
            ]),
            scriptsURL: fixture.scripts,
            stateRootURL: fixture.state,
            extensionVersion: "5"
        )
        XCTAssertEqual((trashed.value as? [String: Any])?["success"] as? Bool, true)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: fixture.scripts.appendingPathComponent(filename).path
            )
        )
    }

    func testPopupInstallAcceptsUserscripts486ContentOnlyPayload() async throws {
        let fixture = try makeFixture()
        let script = """
        // ==UserScript==
        // @name Popup Install
        // @match https://example.com/*
        // ==/UserScript==
        window.__popupInstall = true;
        """

        let installed = await fixture.service.handle(
            message: .init(value: [
                "name": "POPUP_INSTALL_SCRIPT",
                "content": script,
            ]),
            scriptsURL: fixture.scripts,
            stateRootURL: fixture.state,
            extensionVersion: "4.8.6"
        )

        let item = try XCTUnwrap(installed.value as? [String: Any])
        XCTAssertNil(item["error"] as? String)
        XCTAssertEqual(item["filename"] as? String, "Popup Install.user.js")
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: fixture.scripts.appendingPathComponent("Popup Install.user.js").path
            )
        )
    }

    func testRequestScriptsAndPathTraversalAreHandledFailClosed() async throws {
        let fixture = try makeFixture()
        let rules = """
        // ==UserScript==
        // @name Request Rules
        // @run-at request
        // ==/UserScript==
        [{"id":1,"action":{"type":"block"},"condition":{"urlFilter":"ads"}}]
        """
        try Data(rules.utf8).write(
            to: fixture.scripts.appendingPathComponent("Request Rules.user.js")
        )
        _ = await fixture.service.handle(
            message: .init(value: ["name": "NATIVE_CHECKS"]),
            scriptsURL: fixture.scripts,
            stateRootURL: fixture.state,
            extensionVersion: "5"
        )
        let response = await fixture.service.handle(
            message: .init(value: ["name": "REQ_REQUESTS"]),
            scriptsURL: fixture.scripts,
            stateRootURL: fixture.state,
            extensionVersion: "5"
        )
        XCTAssertEqual((response.value as? [[String: String]])?.count, 1)

        let outside = fixture.root.appendingPathComponent("outside.user.js")
        try Data("untouched".utf8).write(to: outside)
        let traversal = await fixture.service.handle(
            message: .init(value: [
                "name": "PAGE_TRASH",
                "item": ["filename": "../outside.user.js"],
            ]),
            scriptsURL: fixture.scripts,
            stateRootURL: fixture.state,
            extensionVersion: "5"
        )
        XCTAssertNotNil((traversal.value as? [String: String])?["error"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func testWebExtensionMatchingAndDisabledPopupStateFollowUserscriptsModel() async throws {
        let fixture = try makeFixture()
        let matched = """
        // ==UserScript==
        // @name Matched
        // @match https://*.example.com/*
        // ==/UserScript==
        window.__matched = true;
        """
        let unscoped = """
        // ==UserScript==
        // @name No Match Metadata
        // ==/UserScript==
        window.__mustNotRunEverywhere = true;
        """
        try Data(matched.utf8).write(
            to: fixture.scripts.appendingPathComponent("Matched.user.js")
        )
        try Data(unscoped.utf8).write(
            to: fixture.scripts.appendingPathComponent("No Match Metadata.user.js")
        )
        _ = await fixture.service.handle(
            message: .init(value: ["name": "NATIVE_CHECKS"]),
            scriptsURL: fixture.scripts,
            stateRootURL: fixture.state,
            extensionVersion: "5"
        )

        let beforeToggle = await fixture.service.handle(
            message: .init(value: [
                "name": "REQ_USERSCRIPTS",
                "url": "https://sub.example.com/page?query=1",
                "isTop": true,
            ]),
            scriptsURL: fixture.scripts,
            stateRootURL: fixture.state,
            extensionVersion: "5"
        )
        let beforePayload = try XCTUnwrap(beforeToggle.value as? [String: Any])
        let beforeFiles = try XCTUnwrap(beforePayload["files"] as? [String: Any])
        XCTAssertEqual((beforeFiles["js"] as? [[String: Any]])?.count, 1)

        _ = await fixture.service.handle(
            message: .init(value: [
                "name": "TOGGLE_ITEM",
                "item": ["filename": "Matched.user.js", "disabled": 0],
            ]),
            scriptsURL: fixture.scripts,
            stateRootURL: fixture.state,
            extensionVersion: "5"
        )
        let injection = await fixture.service.handle(
            message: .init(value: [
                "name": "REQ_USERSCRIPTS",
                "url": "https://example.com/page",
                "isTop": true,
            ]),
            scriptsURL: fixture.scripts,
            stateRootURL: fixture.state,
            extensionVersion: "5"
        )
        let injectionPayload = try XCTUnwrap(injection.value as? [String: Any])
        let injectionFiles = try XCTUnwrap(injectionPayload["files"] as? [String: Any])
        XCTAssertEqual((injectionFiles["js"] as? [[String: Any]])?.count, 0)

        let popup = await fixture.service.handle(
            message: .init(value: [
                "name": "POPUP_MATCHES",
                "url": "https://example.com/page",
                "frameUrls": ["https://example.com/page"],
            ]),
            scriptsURL: fixture.scripts,
            stateRootURL: fixture.state,
            extensionVersion: "5"
        )
        let popupPayload = try XCTUnwrap(popup.value as? [String: Any])
        let matches = try XCTUnwrap(popupPayload["matches"] as? [[String: Any]])
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?["disabled"] as? Bool, true)
    }

    private struct Fixture {
        let root: URL
        let scripts: URL
        let state: URL
        let service: UserscriptsLibraryProtocolService
    }

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("UserscriptsLibraryTests.\(UUID().uuidString)")
        let scripts = root.appendingPathComponent("scripts", isDirectory: true)
        let state = root.appendingPathComponent("state", isDirectory: true)
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return Fixture(
            root: root,
            scripts: scripts,
            state: state,
            service: UserscriptsLibraryProtocolService()
        )
    }
}

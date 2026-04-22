import Foundation
import SwiftData
import WebKit
import XCTest
@testable import Sumi

@available(macOS 15.5, *)
@MainActor
extension ExtensionManagerTests {
    func testNativeMessagingDelegateExportsWebKitSelectors() throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)

        let sendNativeMessageSelector = NSSelectorFromString(
            "webExtensionController:sendMessage:toApplicationWithIdentifier:forExtensionContext:replyHandler:"
        )
        let staleSendNativeMessageSelector = NSSelectorFromString(
            "webExtensionController:sendMessage:to:forExtensionContext:replyHandler:"
        )
        let connectNativeSelector = NSSelectorFromString(
            "webExtensionController:connectUsingMessagePort:forExtensionContext:completionHandler:"
        )

        XCTAssertTrue(manager.responds(to: sendNativeMessageSelector))
        XCTAssertFalse(manager.responds(to: staleSendNativeMessageSelector))
        XCTAssertTrue(manager.responds(to: connectNativeSelector))
    }

    func testNativeMessagingSingleShotTimesOut() async throws {
        let supportRoot = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: supportRoot) }

        let hostPath = try makeNativeHostScript(
            in: supportRoot,
            name: "timeout-host.sh",
            body: """
            import struct
            import sys
            import time

            length = sys.stdin.buffer.read(4)
            if len(length) == 4:
                size = struct.unpack('I', length)[0]
                sys.stdin.buffer.read(size)
            time.sleep(5)
            """
        )
        try writeNativeMessagingManifest(
            in: supportRoot,
            applicationId: "com.sumi.timeout",
            hostPath: hostPath
        )

        let handler = NativeMessagingHandler(
            applicationId: "com.sumi.timeout",
            browserSupportDirectory: supportRoot,
            appBundleURL: Bundle.main.bundleURL,
            responseTimeout: 0.2
        )

        let result = await sendNativeMessage(["ping": true], with: handler)
        switch result {
        case .success:
            XCTFail("Timed out native host should not succeed")
        case .failure(let error):
            XCTAssertTrue(error.localizedDescription.contains("timed out"))
        }
    }

    func testShowPopoverNativeMessageIsHandledWithoutHostLookup() async throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)
        let extensionRoot = try makeUnpackedExtensionDirectory(
            manifest: [
                "manifest_version": 3,
                "name": "Popover Fixture",
                "version": "1.0",
                "action": [
                    "default_popup": "popup.html",
                ],
            ]
        )
        defer { try? FileManager.default.removeItem(at: extensionRoot) }

        try "<html></html>".write(
            to: extensionRoot.appendingPathComponent("popup.html"),
            atomically: true,
            encoding: .utf8
        )

        let webExtension = try await WKWebExtension(resourceBaseURL: extensionRoot)
        let extensionContext = WKWebExtensionContext(for: webExtension)
        let controller = try requireRuntimeController(for: manager)

        let result: Result<Any?, Error> = await withCheckedContinuation { continuation in
            manager.webExtensionController(
                controller,
                sendMessage: ["command": "showPopover"],
                toApplicationWithIdentifier: "com.sumi.missing.native.host",
                for: extensionContext
            ) { response, error in
                if let error {
                    continuation.resume(returning: .failure(error))
                } else {
                    continuation.resume(returning: .success(response))
                }
            }
        }

        switch result {
        case .success(let response):
            XCTAssertEqual(response as? [String: Bool], ["success": true])
        case .failure(let error):
            XCTFail("showPopover should not hit native host lookup: \(error.localizedDescription)")
        }
    }

    func testSleepNativeMessageUsesControlledDelayedReplyWithoutHostLookup() async throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)
        let extensionRoot = try makeUnpackedExtensionDirectory(
            manifest: [
                "manifest_version": 3,
                "name": "Sleep Fixture",
                "version": "1.0",
            ]
        )
        defer { try? FileManager.default.removeItem(at: extensionRoot) }

        let webExtension = try await WKWebExtension(resourceBaseURL: extensionRoot)
        let extensionContext = WKWebExtensionContext(for: webExtension)
        let controller = try requireRuntimeController(for: manager)

        let startedAt = Date()
        let result: Result<Any?, Error> = await withCheckedContinuation { continuation in
            manager.webExtensionController(
                controller,
                sendMessage: ["command": "sleep"],
                toApplicationWithIdentifier: "com.sumi.missing.native.host",
                for: extensionContext
            ) { response, error in
                if let error {
                    continuation.resume(returning: .failure(error))
                } else {
                    continuation.resume(returning: .success(response))
                }
            }
        }

        switch result {
        case .success(let response):
            XCTAssertTrue(response is NSNull)
            XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(startedAt), 0.04)
        case .failure(let error):
            XCTFail("sleep should be handled by Safari router, not native host lookup: \(error.localizedDescription)")
        }
    }

    func testMissingNativeMessageHostUsesControlledDelayedReply() async throws {
        let harness = try makeExtensionRuntimeHarness()
        let manager = makeExtensionManager(in: harness)
        let extensionRoot = try makeUnpackedExtensionDirectory(
            manifest: [
                "manifest_version": 3,
                "name": "Missing Host Fixture",
                "version": "1.0",
            ]
        )
        defer { try? FileManager.default.removeItem(at: extensionRoot) }

        let webExtension = try await WKWebExtension(resourceBaseURL: extensionRoot)
        let extensionContext = WKWebExtensionContext(for: webExtension)
        let controller = try requireRuntimeController(for: manager)

        let startedAt = Date()
        let result: Result<Any?, Error> = await withCheckedContinuation { continuation in
            manager.webExtensionController(
                controller,
                sendMessage: ["command": "unknown"],
                toApplicationWithIdentifier: "com.sumi.missing.native.host",
                for: extensionContext
            ) { response, error in
                if let error {
                    continuation.resume(returning: .failure(error))
                } else {
                    continuation.resume(returning: .success(response))
                }
            }
        }

        switch result {
        case .success(let response):
            XCTAssertTrue(response is NSNull)
            XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(startedAt), 0.04)
        case .failure(let error):
            XCTFail("missing Safari native host should use delayed null reply: \(error.localizedDescription)")
        }
    }

    func testNativeMessagingManifestLookupIsSafariOnlyAndPrefersSumiLocal() throws {
        let supportRoot = try temporaryDirectory()
        let appBundleRoot = try temporaryDirectory()
        let homeRoot = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: supportRoot)
            try? FileManager.default.removeItem(at: appBundleRoot)
            try? FileManager.default.removeItem(at: homeRoot)
        }

        let applicationId = "com.sumi.lookup"
        let localManifestURL = supportRoot
            .appendingPathComponent("NativeMessagingHosts", isDirectory: true)
            .appendingPathComponent("\(applicationId).json")
        try FileManager.default.createDirectory(
            at: localManifestURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try ExtensionUtils.writeJSONObject(
            ["path": "/tmp/local-host"],
            to: localManifestURL
        )

        let bundleManifestURL = appBundleRoot
            .appendingPathComponent("Contents/Resources/NativeMessagingHosts", isDirectory: true)
            .appendingPathComponent("\(applicationId).json")
        try FileManager.default.createDirectory(
            at: bundleManifestURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try ExtensionUtils.writeJSONObject(
            ["path": "/tmp/bundle-host"],
            to: bundleManifestURL
        )

        let vendorManifestURL = homeRoot
            .appendingPathComponent(
                "Library/Application Support/Google/Chrome/NativeMessagingHosts",
                isDirectory: true
            )
            .appendingPathComponent("\(applicationId).json")
        try FileManager.default.createDirectory(
            at: vendorManifestURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try ExtensionUtils.writeJSONObject(
            ["path": "/tmp/vendor-host"],
            to: vendorManifestURL
        )

        let resolvedURL = NativeMessagingHandler.resolveManifestURL(
            applicationId: applicationId,
            browserSupportDirectory: supportRoot,
            appBundleURL: appBundleRoot,
            homeDirectory: homeRoot
        )
        XCTAssertEqual(
            resolvedURL?.standardizedFileURL,
            localManifestURL.standardizedFileURL
        )

        let candidatePaths = NativeMessagingHandler.manifestSearchURLs(
            applicationId: applicationId,
            browserSupportDirectory: supportRoot,
            appBundleURL: appBundleRoot,
            homeDirectory: homeRoot
        ).map(\.path)

        XCTAssertEqual(candidatePaths.first, localManifestURL.path)
        XCTAssertTrue(candidatePaths.contains(bundleManifestURL.path))
        XCTAssertFalse(candidatePaths.contains(vendorManifestURL.path))
        XCTAssertFalse(candidatePaths.contains { $0.contains("/Google/Chrome/") })
        XCTAssertFalse(candidatePaths.contains { $0.contains("/Chromium/") })
        XCTAssertFalse(candidatePaths.contains { $0.contains("/Microsoft Edge/") })
        XCTAssertFalse(candidatePaths.contains { $0.contains("/BraveSoftware/") })
        XCTAssertFalse(candidatePaths.contains { $0.contains("/Mozilla/") })
    }

    func testNativeMessagingSingleShotRejectsMalformedResponse() async throws {
        let supportRoot = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: supportRoot) }

        let hostPath = try makeNativeHostScript(
            in: supportRoot,
            name: "malformed-host.sh",
            body: """
            import struct
            import sys

            length = sys.stdin.buffer.read(4)
            if len(length) == 4:
                size = struct.unpack('I', length)[0]
                sys.stdin.buffer.read(size)

            payload = b'not-json'
            sys.stdout.buffer.write(struct.pack('I', len(payload)))
            sys.stdout.buffer.write(payload)
            sys.stdout.buffer.flush()
            """
        )
        try writeNativeMessagingManifest(
            in: supportRoot,
            applicationId: "com.sumi.malformed",
            hostPath: hostPath
        )

        let handler = NativeMessagingHandler(
            applicationId: "com.sumi.malformed",
            browserSupportDirectory: supportRoot,
            appBundleURL: Bundle.main.bundleURL,
            responseTimeout: 1
        )

        let result = await sendNativeMessage(["ping": true], with: handler)
        switch result {
        case .success:
            XCTFail("Malformed native host response should not succeed")
        case .failure:
            XCTAssertTrue(true)
        }
    }
}

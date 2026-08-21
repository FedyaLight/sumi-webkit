import Foundation
import WebKit
import XCTest

@testable import Sumi

/// Runs the real Speedometer 3.1 in a visible window against configurable
/// blocking-stack shapes so regressions can be measured, not guessed.
///
/// One configuration per process via `SUMI_SPEEDO_CONFIGS`:
/// - `clean` — bare WebKit
/// - `shards` — the installed generation's WebKit lists as-is
/// - `dnr` — the internal URL-cleaning DNR extension only
/// - `bootstrap` — the advanced-blocking bootstrap script only
/// - `extensions` — the real user extensions installed in the app container
/// - `newstack` — production shape: migrated (cosmetic-free) shards + DNR +
///   bootstrap
/// - `newstack+ext` — newstack plus the user extensions in one controller
///
/// Gated behind `SUMI_RUN_SPEEDOMETER=1`; each configuration takes minutes.
final class ContentBlockingOverheadBenchmarkTests: XCTestCase {
    @MainActor
    func testSpeedometer31WithAndWithoutBlockingStack() async throws {
        guard ProcessInfo.processInfo.environment["SUMI_RUN_SPEEDOMETER"] == "1" else {
            throw XCTSkip("Set SUMI_RUN_SPEEDOMETER=1 to run the live benchmark")
        }
        guard let store = WKContentRuleListStore.default() else {
            XCTFail("No default rule list store")
            return
        }
        let requested = ProcessInfo.processInfo.environment[
            "SUMI_SPEEDO_CONFIGS"
        ] ?? "clean"
        let names = requested.split(separator: ",").map(String.init)
        let supported = Set([
            "clean", "shards", "dnr", "bootstrap", "extensions",
            "newstack", "newstack+ext",
        ])
        guard names.count == 1, let name = names.first,
              supported.contains(name)
        else {
            throw Self.benchmarkError(
                "Choose exactly one supported SUMI_SPEEDO_CONFIGS value; got '\(requested)'"
            )
        }

        var generation: URL?
        if ["shards", "dnr", "newstack", "newstack+ext"].contains(name) {
            generation = try await Self.installedGenerationDirectory()
        }

        var stackRuleLists = [WKContentRuleList]()
        if name == "shards", let generation {
            stackRuleLists = try await Self.compileShardLists(
                from: generation,
                store: store,
                identifierPrefix: "speedo.shard"
            )
            print("BENCH speedo: attached \(stackRuleLists.count) production shards")
        }

        var extensionController: WKWebExtensionController?
        var dnrFixture: (
            WKWebExtensionController,
            WKWebExtensionContext,
            URL
        )?
        var loadedExtensionNames = [String]()
        if #available(macOS 15.5, *) {
            if ["dnr", "newstack", "newstack+ext"].contains(name) {
                guard let generation,
                      let fixture = try await Self.makeRealURLCleaningExtension(
                          generationDirectory: generation
                      )
                else {
                    throw Self.benchmarkError(
                        "The active generation has no usable URL-cleaning artifact"
                    )
                }
                dnrFixture = fixture
                extensionController = fixture.0
            }
            if name == "extensions" || name == "newstack+ext" {
                let rows = try await Self.installedExtensionRows().filter(\.enabled)
                let controller = extensionController ?? WKWebExtensionController()
                loadedExtensionNames = try await Self.loadUserExtensions(
                    rows,
                    into: controller
                )
                extensionController = controller
            }
        } else if ["dnr", "extensions", "newstack", "newstack+ext"].contains(name) {
            throw XCTSkip("Web-extension benchmark configurations require macOS 15.5+")
        }
        defer {
            if let dnrFixture {
                do {
                    try FileManager.default.removeItem(at: dnrFixture.2)
                } catch {
                    XCTFail("Could not remove URL-cleaning fixture: \(error)")
                }
            }
        }
        if name == "extensions" || name == "newstack+ext" {
            print(
                "BENCH speedo: loaded \(loadedExtensionNames.count) user extensions: \(loadedExtensionNames)"
            )
        }

        // Production shape: the cosmetic-shard migration runs on a copy of
        // the installed generation and its stripped shards are compiled.
        // NOTE: WebKit rejects single lists with >150_000 rules, which is why
        // generations shard their network rules in the first place.
        var migratedRuleLists = [WKContentRuleList]()
        var copyRoot: URL?
        defer {
            if let copyRoot {
                do {
                    try FileManager.default.removeItem(at: copyRoot)
                } catch {
                    XCTFail("Could not remove copied generation: \(error)")
                }
            }
        }
        if name == "newstack" || name == "newstack+ext" {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "RealAdblockBench-\(UUID().uuidString)",
                    isDirectory: true
                )
            try FileManager.default.copyItem(at: Self.installedAdblockRoot(), to: root)
            copyRoot = root
            let copyArchive = AdblockGenerationArchive(rootDirectory: root)
            guard let activeManifest = try await copyArchive.activeManifest() else {
                throw Self.benchmarkError("The copied profile has no active Adblock generation")
            }
            let migration = AdblockCosmeticShardMigration(archive: copyArchive)
            let migrated = await migration.migratedManifestIfPossible(
                for: activeManifest
            )
            guard migrated.advancedBlocking?.artifacts.contains(where: {
                $0.role == .domainCosmeticRules
            }) == true else {
                throw Self.benchmarkError("Cosmetic-shard migration did not complete")
            }
            let reader = AdblockArchivedShardReader(
                storageRoot: copyArchive.storageRoot
            )
            for shard in migrated.networkShards.sorted(by: { $0.id < $1.id }) {
                let data = try reader.validatedData(for: shard)
                if let list = try await store.compileContentRuleList(
                    forIdentifier: "speedo.migrated.\(shard.id)",
                    encodedContentRuleList: String(decoding: data, as: UTF8.self)
                ) {
                    migratedRuleLists.append(list)
                }
            }
        }
        print("BENCH speedo: migrated stack lists: \(migratedRuleLists.count)")

        let bootstrapScript = SumiAdvancedBlockingPageScript(
            runtimeSource: "",
            lookup: { _ in nil }
        )

        let score = try await Self.runSpeedometer31 {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            switch name {
            case "shards":
                for list in stackRuleLists {
                    configuration.userContentController.add(list)
                }
            case "newstack", "newstack+ext":
                for list in migratedRuleLists {
                    configuration.userContentController.add(list)
                }
                configuration.webExtensionController = extensionController
                let userScript = SumiPageScriptBuilder.makeWKUserScript(
                    from: bootstrapScript
                )
                configuration.userContentController.addUserScript(userScript)
                configuration.userContentController.add(
                    bootstrapScript,
                    contentWorld: .defaultClient,
                    name: SumiAdvancedBlockingPageScript.messageName
                )
            case "dnr", "extensions":
                configuration.webExtensionController = extensionController
            case "bootstrap":
                let userScript = SumiPageScriptBuilder.makeWKUserScript(
                    from: bootstrapScript
                )
                configuration.userContentController.addUserScript(userScript)
                configuration.userContentController.add(
                    bootstrapScript,
                    contentWorld: .defaultClient,
                    name: SumiAdvancedBlockingPageScript.messageName
                )
            default:
                break
            }
            return configuration
        }
        print("BENCH speedo [\(name)]: \(score)")
    }

    // MARK: - Measurement

    @MainActor
    private static func runSpeedometer31(
        makeConfiguration: @MainActor () -> WKWebViewConfiguration
    ) async throws -> String {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1100, height: 850),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.level = .modalPanel
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 1100, height: 850),
            configuration: makeConfiguration()
        )
        window.contentView?.addSubview(webView)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        defer {
            window.orderOut(nil)
        }

        webView.load(URLRequest(url: URL(string: "https://browserbench.org/Speedometer3.1/")!))
        try await Self.waitUntil(
            timeout: 60,
            webView: webView,
            probe: "!!window.benchmarkClient && !!document.querySelector('.start-tests-button')"
        )
        // The benchmark steps are driven by requestAnimationFrame, which
        // WebKit freezes for occluded views; wait until the page reports
        // itself visible and keep reasserting window visibility otherwise.
        var visibilityDeadline = Date().addingTimeInterval(120)
        var visibilityState = ""
        while Date() < visibilityDeadline {
            visibilityState = (try await webView.evaluateJavaScript(
                "document.visibilityState"
            )) as? String ?? "unknown"
            if visibilityState == "visible" { break }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        print("BENCH speedo visibility: \(visibilityState)")
        _ = try await webView.evaluateJavaScript(
            "window.benchmarkClient.start()"
        )

        var lastProgress = ""
        let started = Date()
        let deadline = started.addingTimeInterval(900)
        var finished = false
        while Date() < deadline, !finished {
            try await Task.sleep(nanoseconds: 15_000_000_000)
            let state = (try await webView.evaluateJavaScript(
                "JSON.stringify({running: !!(window.benchmarkClient && window.benchmarkClient._isRunning), progress: (document.getElementById('info-progress')||{}).textContent || '', done: !!((document.getElementById('result-number')||{}).textContent)})"
            )) as? String ?? "eval-failed"
            if state != lastProgress {
                print("BENCH speedo state[\(Int(-started.timeIntervalSinceNow))s]: \(state)")
                lastProgress = state
            }
            if let data = try JSONSerialization.jsonObject(
                with: Data(state.utf8)
            ) as? [String: Any] {
                finished = (data["done"] as? Bool) == true
            }
        }
        guard finished else {
            let finalState = (try await webView.evaluateJavaScript(
                "JSON.stringify({running: !!(window.benchmarkClient && window.benchmarkClient._isRunning), progress: (document.getElementById('info-progress')||{}).textContent || ''})"
            )) as? String ?? "eval-failed"
            XCTFail("Speedometer did not finish: \(finalState)")
            return ""
        }
        let score = try await webView.evaluateJavaScript(
            "document.getElementById('result-number').textContent"
        )
        return (score as? String) ?? String(describing: score)
    }

    @MainActor
    private static func waitUntil(
        timeout: TimeInterval,
        webView: WKWebView,
        probe: String
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            do {
                let value = try await webView.evaluateJavaScript(probe)
                if (value as? Bool) == true { return }
            } catch {}
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        XCTFail("Condition not met within \(timeout)s: \(probe)")
    }

    // MARK: - Installed artifacts

    private static func installedGenerationDirectory() async throws -> URL {
        let archive = AdblockGenerationArchive(rootDirectory: installedAdblockRoot())
        guard let manifest = try await archive.activeManifest() else {
            throw NSError(domain: "bench", code: 1)
        }
        return try archive.generationDirectoryURL(
            generationId: manifest.activeGenerationId
        )
    }

    private static func installedAdblockRoot() -> URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support")
            .appendingPathComponent("com.sumi.browser/Adblock")
    }

    @MainActor
    private static func compileShardLists(
        from generation: URL,
        store: WKContentRuleListStore,
        identifierPrefix: String
    ) async throws -> [WKContentRuleList] {
        var lists = [WKContentRuleList]()
        for shard in try FileManager.default.contentsOfDirectory(
            at: generation,
            includingPropertiesForKeys: nil
        ).filter({ $0.lastPathComponent.hasPrefix("network-") })
        .sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let json = try String(contentsOf: shard, encoding: .utf8)
            let identifier = "\(identifierPrefix).\(shard.lastPathComponent)"
            if let list = try await store.compileContentRuleList(
                forIdentifier: identifier,
                encodedContentRuleList: json
            ) {
                lists.append(list)
            }
        }
        return lists
    }

    struct InstalledExtensionRow {
        let name: String
        let packagePath: String
        let enabled: Bool
    }

    /// Reads enabled extensions from the app container database.
    static func installedExtensionRows() async throws -> [InstalledExtensionRow] {
        let container = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support")
            .appendingPathComponent("com.sumi.browser")
            .appendingPathComponent("Sumi.sqlite")
        guard FileManager.default.fileExists(atPath: container.path) else {
            return []
        }
        let output = try await Self.runProcess(
            "/usr/bin/sqlite3",
            arguments: [
                container.path,
                "SELECT name, package_path, is_enabled FROM extensions;",
            ]
        )
        return output.split(separator: "\n").compactMap { line in
            let parts = line.components(separatedBy: "|")
            guard parts.count >= 3 else { return nil }
            return InstalledExtensionRow(
                name: parts[0],
                packagePath: parts[1],
                enabled: parts[2] == "1"
            )
        }
    }

    private static func runProcess(
        _ launchPath: String,
        arguments: [String]
    ) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw benchmarkError(
                "\(launchPath) exited with status \(process.terminationStatus)"
            )
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func benchmarkError(_ description: String) -> NSError {
        NSError(
            domain: "ContentBlockingOverheadBenchmark",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: description]
        )
    }

    @available(macOS 15.5, *)
    @MainActor
    private static func loadUserExtensions(
        _ rows: [InstalledExtensionRow],
        into controller: WKWebExtensionController
    ) async throws -> [String] {
        var names = [String]()
        for row in rows {
            guard let context = try await makeUserExtensionContext(
                resourcesURL: URL(fileURLWithPath: row.packagePath)
            ) else {
                throw benchmarkError(
                    "Enabled extension '\(row.name)' is not a usable WebExtension"
                )
            }
            try controller.load(context)
            names.append(row.name)
        }
        return names
    }

    @available(macOS 15.5, *)
    @MainActor
    private static func makeUserExtensionContext(
        resourcesURL: URL
    ) async throws -> WKWebExtensionContext? {
        guard FileManager.default.fileExists(
            atPath: resourcesURL.appendingPathComponent("manifest.json").path
        ) else {
            return nil
        }
        let webExtension = try await WKWebExtension(resourceBaseURL: resourcesURL)
        guard webExtension.errors.isEmpty else { return nil }
        let context = WKWebExtensionContext(for: webExtension)
        for permission in webExtension.requestedPermissions {
            context.setPermissionStatus(.grantedExplicitly, for: permission)
        }
        for pattern in webExtension.requestedPermissionMatchPatterns
            .union(webExtension.allRequestedMatchPatterns) {
            context.setPermissionStatus(.grantedExplicitly, for: pattern)
        }
        context.hasAccessToPrivateData = true
        return context
    }

    @available(macOS 15.5, *)
    @MainActor
    private static func makeRealURLCleaningExtension(
        generationDirectory: URL
    ) async throws -> (
        WKWebExtensionController,
        WKWebExtensionContext,
        URL
    )? {
        let removeparamURL = generationDirectory
            .appendingPathComponent(".webext/removeparam.json")
        guard FileManager.default.fileExists(atPath: removeparamURL.path) else {
            return nil
        }
        return try await Self.makeURLCleaningExtension(rulesFileURL: removeparamURL)
    }

    @available(macOS 15.5, *)
    @MainActor
    private static func makeURLCleaningExtension(
        rulesFileURL: URL
    ) async throws -> (
        WKWebExtensionController,
        WKWebExtensionContext,
        URL
    )? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SumiBenchDNRExt-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        var retainDirectory = false
        defer {
            if retainDirectory == false {
                do {
                    try FileManager.default.removeItem(at: directory)
                } catch {
                    XCTFail("Could not remove incomplete DNR fixture: \(error)")
                }
            }
        }
        try FileManager.default.copyItem(
            at: rulesFileURL,
            to: directory.appendingPathComponent("rules.json")
        )

        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Bench URL Cleaning",
            "description": "Benchmark stand-in for the internal extension.",
            "version": "1.0.0",
            "permissions": [
                "declarativeNetRequest",
                "declarativeNetRequestWithHostAccess",
            ],
            "host_permissions": ["<all_urls>"],
            "declarative_net_request": [
                "rule_resources": [[
                    "id": "bench_url_cleaning",
                    "enabled": true,
                    "path": "rules.json",
                ]],
            ],
        ]
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
            .write(to: directory.appendingPathComponent("manifest.json"))

        let webExtension = try await WKWebExtension(resourceBaseURL: directory)
        guard webExtension.errors.isEmpty else { return nil }
        let context = WKWebExtensionContext(for: webExtension)
        for permission in webExtension.requestedPermissions {
            context.setPermissionStatus(.grantedExplicitly, for: permission)
        }
        let patterns = webExtension.requestedPermissionMatchPatterns
            .union(webExtension.allRequestedMatchPatterns)
        for pattern in patterns {
            context.setPermissionStatus(.grantedExplicitly, for: pattern)
        }
        context.hasRequestedOptionalAccessToAllHosts = true
        context.hasAccessToPrivateData = true

        let controller = WKWebExtensionController()
        try controller.load(context)
        retainDirectory = true
        return (controller, context, directory)
    }
}

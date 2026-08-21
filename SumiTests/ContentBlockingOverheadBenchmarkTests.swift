import Foundation
import WebKit
import XCTest

@testable import Sumi

/// Runs the real Speedometer 3.1 in a visible window against configurable
/// blocking-stack shapes so regressions can be measured, not guessed.
///
/// Configurations via `SUMI_SPEEDO_CONFIGS` (comma-separated):
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

        let generation = try Self.installedGenerationDirectory()
        let stackRuleLists = try await Self.compileShardLists(
            from: generation,
            store: store,
            identifierPrefix: "speedo.shard"
        )
        print("BENCH speedo: attached \(stackRuleLists.count) production shards")

        let urlCleaningController: (WKWebExtensionController, WKWebExtensionContext)?
        if #available(macOS 15.5, *) {
            urlCleaningController = try await Self.makeRealURLCleaningExtension(
                generationDirectory: generation
            )
        } else {
            urlCleaningController = nil
        }

        var userExtensionContexts = [(String, WKWebExtensionContext)]()
        if #available(macOS 15.5, *) {
            for row in try await Self.installedExtensionRows() where row.enabled {
                if let context = try? await Self.makeUserExtensionContext(
                    resourcesURL: URL(fileURLWithPath: row.packagePath)
                ) {
                    userExtensionContexts.append((row.name, context))
                }
            }
        }
        print(
            "BENCH speedo: loaded \(userExtensionContexts.count) user extensions: \(userExtensionContexts.map(\.0))"
        )
        if !userExtensionContexts.isEmpty, let base = urlCleaningController {
            for (_, context) in userExtensionContexts {
                do {
                    try base.0.load(context)
                } catch {
                    print("BENCH speedo: extension load failed: \(error.localizedDescription)")
                }
            }
        }

        // Production shape: the cosmetic-shard migration runs on a copy of
        // the installed generation and its stripped shards are compiled.
        // NOTE: WebKit rejects single lists with >150_000 rules, which is why
        // generations shard their network rules in the first place.
        var migratedRuleLists = [WKContentRuleList]()
        let sourceRoot = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support")
            .appendingPathComponent("com.sumi.browser/Adblock")
        let copyRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "RealAdblockBench-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.copyItem(at: sourceRoot, to: copyRoot)
        let copyArchive = AdblockGenerationArchive(rootDirectory: copyRoot)
        if let activeManifest = try await copyArchive.activeManifest() {
            let migration = AdblockCosmeticShardMigration(archive: copyArchive)
            let migrated = await migration.migratedManifestIfPossible(
                for: activeManifest
            )
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

        let requestedConfigs = ProcessInfo.processInfo.environment[
            "SUMI_SPEEDO_CONFIGS"
        ] ?? "clean,newstack+ext"
        var scores: [(String, String)] = []
        for name in requestedConfigs.split(separator: ",").map(String.init) {
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
                    if let urlCleaningController {
                        configuration.webExtensionController = urlCleaningController.0
                    }
                    let userScript = SumiPageScriptBuilder.makeWKUserScript(
                        from: bootstrapScript
                    )
                    configuration.userContentController.addUserScript(userScript)
                    configuration.userContentController.add(
                        bootstrapScript,
                        contentWorld: .defaultClient,
                        name: SumiAdvancedBlockingPageScript.messageName
                    )
                case "dnr":
                    if let urlCleaningController {
                        configuration.webExtensionController = urlCleaningController.0
                    }
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
                case "extensions":
                    if #available(macOS 15.5, *), !userExtensionContexts.isEmpty {
                        let controller = WKWebExtensionController()
                        for (_, context) in userExtensionContexts {
                            try? controller.load(context)
                        }
                        configuration.webExtensionController = controller
                    }
                default:
                    break
                }
                return configuration
            }
            scores.append((name, score))
            print("BENCH speedo [\(name)]: \(score)")
        }
        print("BENCH speedo summary: \(scores.map { "\($0.0)=\($0.1)" }.joined(separator: " "))")
    }

    /// End-to-end sanity check of the cosmetic-shard migration against a
    /// COPY of the really installed generation. Gated behind
    /// `SUMI_MIGRATE_REAL_COPY=1`.
    @MainActor
    func testRealGenerationMigrationProducesLightStack() async throws {
        guard ProcessInfo.processInfo.environment["SUMI_MIGRATE_REAL_COPY"] == "1" else {
            throw XCTSkip("Set SUMI_MIGRATE_REAL_COPY=1 to validate the real generation")
        }
        let sourceRoot = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support")
            .appendingPathComponent("com.sumi.browser.testhost/Adblock")
        let copyRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "RealAdblockCopy-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.copyItem(at: sourceRoot, to: copyRoot)
        let archive = AdblockGenerationArchive(rootDirectory: copyRoot)
        guard let manifest = try await archive.activeManifest() else {
            XCTFail("No active manifest in copied generation")
            return
        }
        let originalShardBytes = manifest.networkShards
            .map(\.jsonByteCount)
            .reduce(0, +)

        let migration = AdblockCosmeticShardMigration(archive: archive)
        let migrated = await migration.migratedManifestIfPossible(for: manifest)
        let migratedShardBytes = migrated.networkShards
            .map(\.jsonByteCount)
            .reduce(0, +)
        print(
            "BENCH migrate-real: id=\(migrated.activeGenerationId) shardBytes \(originalShardBytes) -> \(migratedShardBytes)"
        )

        let runtime = SumiAdvancedBlockingRuntime(archive: archive)
        let document = SumiAdvancedBlockingDocumentContext(
            pageURL: URL(string: "https://www.news.example/article")!,
            topURL: nil
        )
        let configuration = try await runtime.configuration(
            for: document,
            in: migrated
        )
        print(
            "BENCH migrate-real: sample configuration css count=\(configuration?.css.count ?? -1)"
        )
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
            visibilityState = (try? await webView.evaluateJavaScript(
                "document.visibilityState"
            )) as? String ?? "unknown"
            if visibilityState == "visible" { break }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        print("BENCH speedo visibility: \(visibilityState)")
        _ = try? await webView.evaluateJavaScript(
            "window.benchmarkClient.start()"
        )

        var lastProgress = ""
        let started = Date()
        let deadline = started.addingTimeInterval(900)
        var finished = false
        while Date() < deadline, !finished {
            try await Task.sleep(nanoseconds: 15_000_000_000)
            let state = (try? await webView.evaluateJavaScript(
                "JSON.stringify({running: !!(window.benchmarkClient && window.benchmarkClient._isRunning), progress: (document.getElementById('info-progress')||{}).textContent || '', done: !!((document.getElementById('result-number')||{}).textContent)})"
            )) as? String ?? "eval-failed"
            if state != lastProgress {
                print("BENCH speedo state[\(Int(-started.timeIntervalSinceNow))s]: \(state)")
                lastProgress = state
            }
            if let data = try? JSONSerialization.jsonObject(
                with: Data(state.utf8)
            ) as? [String: Any] {
                finished = (data["done"] as? Bool) == true
            }
        }
        guard finished else {
            let finalState = (try? await webView.evaluateJavaScript(
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

    private static func installedGenerationDirectory() throws -> URL {
        let generatedRoot = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support")
            .appendingPathComponent("com.sumi.browser.testhost/Adblock/Generated")
        let generations = try FileManager.default.contentsOfDirectory(
            at: generatedRoot,
            includingPropertiesForKeys: nil
        )
        guard let generation = generations.first else {
            throw NSError(domain: "bench", code: 1)
        }
        return generation
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
            .appendingPathComponent("com.sumi.browser.testhost")
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
        guard process.terminationStatus == 0 else { return "" }
        return String(decoding: data, as: UTF8.self)
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
    ) async throws -> (WKWebExtensionController, WKWebExtensionContext)? {
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
    ) async throws -> (WKWebExtensionController, WKWebExtensionContext)? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SumiBenchDNRExt-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
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
        return (controller, context)
    }
}

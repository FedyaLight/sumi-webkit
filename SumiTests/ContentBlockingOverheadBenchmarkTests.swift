import CryptoKit
import Foundation
import WebKit
import XCTest

@testable import Sumi

/// Measures the steady-state page overhead of the content-blocking stack so
/// optimization decisions are driven by numbers instead of guesses.
///
/// Each configuration loads a local page that runs a DOM workload and 200
/// same-origin fetches, then reports wall time, DOM time, and request time.
/// Configurations: baseline, native content rule lists, the internal-style
/// DNR web extension, and the advanced-blocking bootstrap script.
final class ContentBlockingOverheadBenchmarkTests: XCTestCase {
    private struct Metrics {
        let loadMs: Double
        let domMs: Double
        let xhrMs: Double
    }

    /// Diagnostic: compiles every installed network shard of the active
    /// generation through the real store to reveal OS-specific rejections.
    @MainActor
    func testInstalledGenerationShardCompilationDiagnostic() async throws {
        let generatedRoot = URL(
            fileURLWithPath: NSHomeDirectory()
        )
        .appendingPathComponent("Library/Application Support")
        .appendingPathComponent("com.sumi.browser/Adblock/Generated")
        guard let generations = try? FileManager.default.contentsOfDirectory(
            at: generatedRoot,
            includingPropertiesForKeys: nil
        ), let generation = generations.first else {
            print("BENCH diag: no installed generation found")
            return
        }
        guard let store = WKContentRuleListStore.default() else {
            print("BENCH diag: no default store")
            return
        }
        let shards = try FileManager.default.contentsOfDirectory(
            at: generation,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("network-") }
        var failures = 0
        for shard in shards {
            let json = try String(contentsOf: shard, encoding: .utf8)
            let identifier = "diag.\(generation.lastPathComponent).\(shard.lastPathComponent)"
            do {
                let list = try await store.compileContentRuleList(
                    forIdentifier: identifier,
                    encodedContentRuleList: json
                )
                print("BENCH diag \(shard.lastPathComponent): \(list == nil ? "nil" : "OK")")
                if let list {
                    try await store.removeContentRuleList(forIdentifier: identifier)
                }
            } catch {
                failures += 1
                print("BENCH diag \(shard.lastPathComponent): FAIL \(error.localizedDescription)")
            }
        }
        if failures > 0 {
            XCTFail("\(failures) of \(shards.count) installed shards failed to compile")
        }
    }

    /// Diagnostic: pinpoints exactly which trigger flag values this WebKit
    /// build rejects during content rule list compilation.
    @MainActor
    func testTriggerFlagCompilationMatrixDiagnostic() async throws {
        guard let store = WKContentRuleListStore.default() else { return }
        var failures = 0
        func probe(_ name: String, _ json: String) async {
            do {
                let list = try await store.compileContentRuleList(
                    forIdentifier: "matrix.\(name)",
                    encodedContentRuleList: json
                )
                print("BENCH matrix \(name): \(list == nil ? "nil" : "OK")")
            } catch {
                failures += 1
                print("BENCH matrix \(name): FAIL \(error.localizedDescription)")
            }
        }
        await probe("bare", #"{"trigger":{"url-filter":".*ads.*"},"action":{"type":"block"}}"#)
        await probe("rt-image", #"{"trigger":{"url-filter":".*ads.*","resource-type":["image"]},"action":{"type":"block"}}"#)
        await probe("rt-fetch", #"{"trigger":{"url-filter":".*ads.*","resource-type":["fetch"]},"action":{"type":"block"}}"#)
        await probe("rt-script", #"{"trigger":{"url-filter":".*ads.*","resource-type":["script"]},"action":{"type":"block"}}"#)
        await probe("rt-xhr-dashed", #"{"trigger":{"url-filter":".*ads.*","resource-type":["xml-http-request"]},"action":{"type":"block"}}"#)
        await probe("if-domain", #"{"trigger":{"url-filter":".*","if-domain":["*://example.com/*"]},"action":{"type":"block"}}"#)
        await probe("load-type", #"{"trigger":{"url-filter":".*ads.*","load-type":["third-party"]},"action":{"type":"block"}}"#)

        let generatedRoot = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support")
            .appendingPathComponent("com.sumi.browser/Adblock/Generated")
        if let generations = try? FileManager.default.contentsOfDirectory(
            at: generatedRoot, includingPropertiesForKeys: nil
        ), let generation = generations.first {
            let shard = generation.appendingPathComponent("network-0001.json")
            if let data = try? JSONSerialization.jsonObject(
                with: Data(contentsOf: shard)
            ) as? [[String: Any]] {
                let flagged = data.filter {
                    ($0["trigger"] as? [String: Any])?["resource-type"] != nil
                }
                print("BENCH matrix real-flagged-count: \(flagged.count)")
                if !flagged.isEmpty {
                    let head = Array(flagged.prefix(50))
                    if let json = try? String(
                        data: JSONSerialization.data(withJSONObject: head),
                        encoding: .utf8
                    ) {
                        await probe("real-head-50", json)
                    }
                    if let single = try? String(
                        data: JSONSerialization.data(
                            withJSONObject: [flagged[0]]
                        ),
                        encoding: .utf8
                    ) {
                        await probe("real-single", single)
                    }
                }
            }
        }
        if failures > 0 {
            XCTFail("\(failures) matrix probes failed")
        }
    }

    /// Runs the real Speedometer 3.1 in a visible window twice: clean and
    /// with the production content-blocking stack attached (the installed
    /// generation's actual shards, the URL-cleaning DNR extension built from
    /// its real removeparam artifact, and the advanced-blocking bootstrap).
    /// Gated behind SUMI_RUN_SPEEDOMETER=1 (TEST_RUNNER_ prefix when using
    /// xcodebuild) because each run takes minutes.
    /// Diagnostic: finds WebKit's per-list rule count cap by compiling
    /// increasing synthetic lists. Gated behind SUMI_PROBE_CAP=1.
    @MainActor
    func testRuleCountCapProbe() async throws {
        guard ProcessInfo.processInfo.environment["SUMI_PROBE_CAP"] == "1" else {
            throw XCTSkip("Set SUMI_PROBE_CAP=1 to probe the rule count cap")
        }
        guard let store = WKContentRuleListStore.default() else { return }
        func makeRules(_ n: Int) -> String {
            var parts = [String]()
            parts.reserveCapacity(n)
            for i in 0..<n {
                parts.append(
                    "{\"trigger\":{\"url-filter\":\"https?://r\(i)\\\\.bench\\\\.example/\"},\"action\":{\"type\":\"block\"}}"
                )
            }
            return "[" + parts.joined(separator: ",") + "]"
        }
        for n in [100_000, 140_000, 149_000, 149_999, 150_000, 150_001, 160_000] {
            do {
                let list = try await store.compileContentRuleList(
                    forIdentifier: "cap.\(n)",
                    encodedContentRuleList: makeRules(n)
                )
                print("BENCH cap \(n): \(list == nil ? "nil" : "OK")")
                if list != nil {
                    try await store.removeContentRuleList(forIdentifier: "cap.\(n)")
                }
            } catch {
                print("BENCH cap \(n): FAIL \(error.localizedDescription)")
                break
            }
        }
    }

    /// End-to-end validation of the cosmetic-shard migration plus the
    /// resulting blocking stack against a COPY of the real installed
    /// generation. Gated behind SUMI_MIGRATE_REAL_COPY=1.
    @MainActor
    func testRealGenerationMigrationProducesLightStack() async throws {
        guard ProcessInfo.processInfo.environment["SUMI_MIGRATE_REAL_COPY"] == "1" else {
            throw XCTSkip("Set SUMI_MIGRATE_REAL_COPY=1 to validate the real generation")
        }
        let sourceRoot = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support")
            .appendingPathComponent("com.sumi.browser/Adblock")
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

        // The advanced pipeline must now serve domain-matched cosmetics.
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

    @MainActor
    func testSpeedometer31WithAndWithoutBlockingStack() async throws {
        guard ProcessInfo.processInfo.environment["SUMI_RUN_SPEEDOMETER"] == "1" else {
            throw XCTSkip("Set SUMI_RUN_SPEEDOMETER=1 to run the live benchmark")
        }
        guard let store = WKContentRuleListStore.default() else {
            XCTFail("No default rule list store")
            return
        }

        let generatedRoot = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support")
            .appendingPathComponent("com.sumi.browser/Adblock/Generated")
        let generations = try FileManager.default.contentsOfDirectory(
            at: generatedRoot,
            includingPropertiesForKeys: nil
        )
        guard let generation = generations.first else {
            XCTFail("No installed generation to attach")
            return
        }

        var stackRuleLists: [WKContentRuleList] = []
        for shard in try FileManager.default.contentsOfDirectory(
            at: generation,
            includingPropertiesForKeys: nil
        ).filter({ $0.lastPathComponent.hasPrefix("network-") }) {
            let json = try String(contentsOf: shard, encoding: .utf8)
            let identifier = "speedo.\(shard.lastPathComponent)"
            if let list = try await store.compileContentRuleList(
                forIdentifier: identifier,
                encodedContentRuleList: json
            ) {
                stackRuleLists.append(list)
            }
        }
        print("BENCH speedo: attached \(stackRuleLists.count) production shards")

        // Cap-aware packing: WebKit rejects lists with >150_000 rules, so
        // rules are packed greedily into the fewest lists possible.
        func compilePackedRuleLists(
            identifierPrefix: String,
            ruleFilter: ([[String: Any]]) -> [[String: Any]]
        ) async throws -> [WKContentRuleList] {
            let cap = 149_500
            let shardFiles = try FileManager.default.contentsOfDirectory(
                at: generation,
                includingPropertiesForKeys: nil
            ).filter { $0.lastPathComponent.hasPrefix("network-") }
                .sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            var lists = [WKContentRuleList]()
            var currentPack = [[String: Any]]()
            var currentCount = 0
            for shardFile in shardFiles {
                let data = try Data(contentsOf: shardFile)
                guard let rules = try JSONSerialization.jsonObject(with: data)
                    as? [[String: Any]]
                else { continue }
                let filtered = ruleFilter(rules)
                if currentCount + filtered.count > cap, currentCount > 0 {
                    let json = String(
                        decoding: try JSONSerialization.data(withJSONObject: currentPack),
                        as: UTF8.self
                    )
                    if let list = try await store.compileContentRuleList(
                        forIdentifier: "\(identifierPrefix).\(lists.count)",
                        encodedContentRuleList: json
                    ) {
                        lists.append(list)
                    }
                    currentPack = []
                    currentCount = 0
                }
                currentPack.append(contentsOf: filtered)
                currentCount += filtered.count
            }
            if currentCount > 0 {
                let json = String(
                    decoding: try JSONSerialization.data(withJSONObject: currentPack),
                    as: UTF8.self
                )
                if let list = try await store.compileContentRuleList(
                    forIdentifier: "\(identifierPrefix).\(lists.count)",
                    encodedContentRuleList: json
                ) {
                    lists.append(list)
                }
            }
            return lists
        }

        var packedRuleLists: [WKContentRuleList] = []
        var packedNoCosmeticRuleLists: [WKContentRuleList] = []
        let requestedConfigsForPacking = ProcessInfo.processInfo.environment[
            "SUMI_SPEEDO_CONFIGS"
        ] ?? "clean,stack"
        let needsPacked = Set(requestedConfigsForPacking.split(separator: ",").map(String.init))

        // Production-shaped stack: run the cosmetic-shard migration on a copy
        // of the installed generation and compile its stripped shards.
        var migratedRuleLists: [WKContentRuleList] = []
        if needsPacked.contains("newstack") {
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
                    let data = try reader.rawValidatedData(for: shard)
                    if let list = try await store.compileContentRuleList(
                        forIdentifier: "speedo.migrated.\(shard.id)",
                        encodedContentRuleList: String(decoding: data, as: UTF8.self)
                    ) {
                        migratedRuleLists.append(list)
                    }
                }
            }
            print("BENCH speedo: migrated stack lists: \(migratedRuleLists.count)")
        }
        if needsPacked.contains("packed") || needsPacked.contains("stack") {
            packedRuleLists = try await compilePackedRuleLists(
                identifierPrefix: "speedo.packed"
            ) { rules in rules }
            print("BENCH speedo: packed into \(packedRuleLists.count) lists")
        }
        if needsPacked.contains("noblockcss") {
            var removedCosmetic = 0
            packedNoCosmeticRuleLists = try await compilePackedRuleLists(
                identifierPrefix: "speedo.nocos"
            ) { rules in
                rules.filter { rule in
                    guard let action = rule["action"] as? [String: Any],
                          let type = action["type"] as? String
                    else { return true }
                    if type == "css-display-none" {
                        removedCosmetic += 1
                        return false
                    }
                    return true
                }
            }
            print(
                "BENCH speedo: no-cosmetic variant \(packedNoCosmeticRuleLists.count) lists, removed \(removedCosmetic) css rules"
            )
        }

        let urlCleaningController: (WKWebExtensionController, WKWebExtensionContext)?
        if #available(macOS 15.5, *) {
            urlCleaningController = try await Self.makeRealURLCleaningExtension(
                generationDirectory: generation
            )
        } else {
            urlCleaningController = nil
        }

        // Real user extensions currently installed in the app container,
        // hosted in the SAME controller as the internal contribution exactly
        // like production does.
        var userExtensionContexts = [(String, WKWebExtensionContext)]()
        if #available(macOS 15.5, *) {
        let rows = try await Self.installedExtensionRows()
        let extensionFilter = ProcessInfo.processInfo.environment[
            "SUMI_SPEEDO_EXT_FILTER"
        ]
        for row in rows where row.enabled {
            if let extensionFilter,
               row.name.lowercased().contains(extensionFilter.lowercased())
                   == false {
                continue
            }
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
                    print("BENCH speedo: loaded extension into shared controller: ok")
                } catch {
                    print("BENCH speedo: extension load failed: \(error.localizedDescription)")
                }
            }
        }

        let bootstrapScript = SumiAdvancedBlockingPageScript(
            runtimeSource: "",
            lookup: { _ in nil }
        )

        let requestedConfigs = ProcessInfo.processInfo.environment[
            "SUMI_SPEEDO_CONFIGS"
        ] ?? "clean,stack"
        var scores: [(String, String)] = []
        for name in requestedConfigs.split(separator: ",").map(String.init) {
            let score = try await Self.runSpeedometer31 { includeStack in
                let configuration = WKWebViewConfiguration()
                configuration.websiteDataStore = .nonPersistent()
                var wantsShards = includeStack || name == "shards"
                var wantsDNR = includeStack || name == "dnr"
                var wantsBootstrap = includeStack || name == "bootstrap"
                if name == "packed" {
                    for list in packedRuleLists {
                        configuration.userContentController.add(list)
                    }
                }
                if name == "noblockcss" {
                    for list in packedNoCosmeticRuleLists {
                        configuration.userContentController.add(list)
                    }
                }
                if name == "newstack" || name == "newstack+ext"
                    || (includeStack && name == "fullprod") {
                    for list in migratedRuleLists {
                        configuration.userContentController.add(list)
                    }
                    wantsDNR = true
                    wantsBootstrap = true
                }
                let wantsUserExtensions = name == "extensions"
                    || name.hasSuffix("+ext")
                    || (includeStack && name == "fullprod")
                if wantsUserExtensions, wantsDNR == false {
                    // Extensions need a controller; host them alone when the
                    // internal DNR contribution is not part of this config.
                    if #available(macOS 15.5, *), !userExtensionContexts.isEmpty {
                        let controller = WKWebExtensionController()
                        for (_, context) in userExtensionContexts {
                            try? controller.load(context)
                        }
                        configuration.webExtensionController = controller
                    }
                }
                if wantsShards {
                    for list in stackRuleLists {
                        configuration.userContentController.add(list)
                    }
                }
                if wantsDNR, let urlCleaningController {
                    configuration.webExtensionController = urlCleaningController.0
                }
                if wantsBootstrap {
                    let userScript = SumiPageScriptBuilder.makeWKUserScript(
                        from: bootstrapScript
                    )
                    configuration.userContentController.addUserScript(userScript)
                    configuration.userContentController.add(
                        bootstrapScript,
                        contentWorld: .defaultClient,
                        name: SumiAdvancedBlockingPageScript.messageName
                    )
                }
                return configuration
            }
            scores.append((name, score))
            print("BENCH speedo [\(name)]: \(score)")
        }
        print("BENCH speedo summary: \(scores.map { "\($0.0)=\($0.1)" }.joined(separator: " "))")
    }

    @MainActor
    private static func runSpeedometer31(
        makeConfiguration: @MainActor (_ includeStack: Bool) -> WKWebViewConfiguration
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
            configuration: makeConfiguration(false)
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

    @available(macOS 15.5, *)
    @MainActor
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

    @MainActor
    func testContentBlockingStackOverheadMeasurement() async throws {
        let server = try BenchmarkHTTPServer()
        let port = try server.start()
        defer { server.stop() }
        let pageURL = URL(string: "http://127.0.0.1:\(port)/page")!

        let ruleListCount = Int(
            ProcessInfo.processInfo.environment["SUMI_BENCH_CB_RULES"] ?? ""
        ) ?? 25_000
        let dnrRuleCount = Int(
            ProcessInfo.processInfo.environment["SUMI_BENCH_DNR_RULES"] ?? ""
        ) ?? 5_000

        var compiledRuleList: WKContentRuleList?
        var dnrExtension: (WKWebExtensionController, WKWebExtensionContext)?
        if #available(macOS 15.5, *) {
            compiledRuleList = try await Self.compileAdblockRuleList(
                ruleCount: ruleListCount
            )
            dnrExtension = try await Self.makeURLCleaningExtension(
                ruleCount: dnrRuleCount
            )
        }

        var results: [(String, Metrics)] = []
        func record(_ name: String, _ metrics: Metrics) {
            results.append((name, metrics))
            print(
                String(
                    format: "BENCH [%@] load=%.0fms dom=%.0fms xhr=%.0fms",
                    name, metrics.loadMs, metrics.domMs, metrics.xhrMs
                )
            )
        }

        let bootstrapScript = SumiAdvancedBlockingPageScript(
            runtimeSource: "",
            lookup: { _ in nil }
        )

        func makeConfiguration(
            includeRuleLists: Bool,
            includeDNR: Bool,
            includeBootstrap: Bool
        ) -> WKWebViewConfiguration {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            if includeRuleLists, let compiledRuleList {
                configuration.userContentController.add(compiledRuleList)
            }
            if includeDNR, #available(macOS 15.5, *), let dnrExtension {
                configuration.webExtensionController = dnrExtension.0
            }
            if includeBootstrap {
                let userScript = SumiPageScriptBuilder.makeWKUserScript(
                    from: bootstrapScript
                )
                configuration.userContentController.addUserScript(userScript)
                configuration.userContentController.add(
                    bootstrapScript,
                    contentWorld: .defaultClient,
                    name: SumiAdvancedBlockingPageScript.messageName
                )
            }
            return configuration
        }

        record("baseline", try await measure(pageURL: pageURL) {
            makeConfiguration(
                includeRuleLists: false,
                includeDNR: false,
                includeBootstrap: false
            )
        })
        if compiledRuleList != nil {
            record("rule-lists", try await measure(pageURL: pageURL) {
                makeConfiguration(
                    includeRuleLists: true,
                    includeDNR: false,
                    includeBootstrap: false
                )
            })
        }
        if dnrExtension != nil {
            record("dnr-extension", try await measure(pageURL: pageURL) {
                makeConfiguration(
                    includeRuleLists: false,
                    includeDNR: true,
                    includeBootstrap: false
                )
            })
            record("rule-lists+dnr", try await measure(pageURL: pageURL) {
                makeConfiguration(
                    includeRuleLists: true,
                    includeDNR: true,
                    includeBootstrap: false
                )
            })
        }
        record("bootstrap", try await measure(pageURL: pageURL) {
            makeConfiguration(
                includeRuleLists: false,
                includeDNR: false,
                includeBootstrap: true
            )
        })
        if compiledRuleList != nil, dnrExtension != nil {
            record("full-stack", try await measure(pageURL: pageURL) {
                makeConfiguration(
                    includeRuleLists: true,
                    includeDNR: true,
                    includeBootstrap: true
                )
            })
        }

        print("BENCH summary")
        for (name, metrics) in results {
            print(
                String(
                    format: "BENCH   %-18@ load=%6.0f dom=%6.0f xhr=%6.0f",
                    name as NSString, metrics.loadMs, metrics.domMs,
                    metrics.xhrMs
                )
            )
        }
    }

    // MARK: - Measurement

    @MainActor
    private func measure(
        pageURL: URL,
        makeConfiguration: @MainActor () -> WKWebViewConfiguration
    ) async throws -> Metrics {
        let webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            configuration: makeConfiguration()
        )
        defer { webView.stopLoading() }

        let start = Date()
        webView.load(URLRequest(url: pageURL))
        try await Self.waitUntilDone(webView: webView, timeout: 60)
        let loadMs = Date().timeIntervalSince(start) * 1000

        func number(_ key: String) async throws -> Double {
            let raw = try await webView.evaluateJavaScript(
                "window.__results['\(key)']"
            )
            return (raw as? NSNumber)?.doubleValue ?? 0
        }
        let metrics = Metrics(
            loadMs: loadMs,
            domMs: try await number("domMs"),
            xhrMs: try await number("xhrMs")
        )
        return metrics
    }

    @MainActor
    private static func waitUntilDone(
        webView: WKWebView,
        timeout: TimeInterval
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            do {
                let done = try await webView.evaluateJavaScript(
                    "window.__results && window.__results.done === true"
                )
                if (done as? Bool) == true { return }
            } catch {}
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Benchmark page did not finish in \(timeout)s")
    }

    // MARK: - Native content rule list

    @MainActor
    private static func compileAdblockRuleList(
        ruleCount: Int
    ) async throws -> WKContentRuleList? {
        let storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SumiBenchRuleStore-\(UUID().uuidString)",
                isDirectory: true
            )
        guard let store = WKContentRuleListStore.default() else {
            return nil
        }
        // NOTE: macOS 27 WebKit currently rejects any trigger flags array
        // ("resource-type", "load-type", "if-domain") during compilation, so
        // the synthetic list uses bare url-filter regexes only.
        let rules = (0..<ruleCount).map { index -> [String: Any] in
            [
                "trigger": [
                    "url-filter":
                        "https?://ads\(index)\\.bench\\.example/",
                ],
                "action": ["type": "block"],
            ]
        }
        let json = String(
            data: try JSONSerialization.data(withJSONObject: rules),
            encoding: .utf8
        )!
        return try await store.compileContentRuleList(
            forIdentifier: "sumi.bench.rules",
            encodedContentRuleList: json
        )
    }

    // MARK: - Internal-style DNR extension

    @available(macOS 15.5, *)
    @MainActor
    private static func makeURLCleaningExtension(
        rulesFileURL: URL? = nil,
        ruleCount: Int = 0
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

        if let rulesFileURL {
            try FileManager.default.copyItem(
                at: rulesFileURL,
                to: directory.appendingPathComponent("rules.json")
            )
        } else {
            var rules: [[String: Any]] = []
            for index in 0..<ruleCount {
                rules.append([
                    "id": 1_500_000 + index,
                    "priority": 1,
                    "action": [
                        "type": "redirect",
                        "redirect": [
                            "transform": [
                                "queryTransform": [
                                    "removeParams": ["utm_source"],
                                ],
                            ],
                        ],
                    ],
                    "condition": [
                        "urlFilter": "[?&]param\(index)=",
                        "resourceTypes": [
                            "main_frame",
                            "sub_frame",
                            "xmlhttprequest",
                        ],
                    ],
                ])
            }
            try JSONSerialization.data(withJSONObject: rules, options: [.sortedKeys])
                .write(to: directory.appendingPathComponent("rules.json"))
        }

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

        let controller = WKWebExtensionController()
        try controller.load(context)
        return (controller, context)
    }
}

// MARK: - Local HTTP server

final class BenchmarkHTTPServer {
    private static let pageHTML = """
        <!doctype html>
        <html><head><meta charset="utf-8"></head>
        <body><div id="root"></div>
        <script>
        window.__results = {};
        function domBench() {
          const t0 = performance.now();
          const root = document.getElementById('root');
          for (let i = 0; i < 20000; i++) {
            const d = document.createElement('div');
            d.textContent = 'item ' + i;
            d.className = 'item';
            root.appendChild(d);
          }
          let x = 0;
          for (let i = 0; i < 200; i++) { x += root.offsetHeight; }
          window.__results.domMs = performance.now() - t0;
        }
        async function xhrBench() {
          const t0 = performance.now();
          await Promise.all(Array.from({length: 200}, (_, i) =>
            fetch('/res/' + i).then(r => r.text())));
          window.__results.xhrMs = performance.now() - t0;
        }
        window.addEventListener('load', async () => {
          try {
            domBench();
            await xhrBench();
          } catch (e) {
            window.__results.error = String(e);
          }
          window.__results.done = true;
        });
        </script></body></html>
        """

    private var serverFD: Int32 = -1
    private var boundPort: UInt16 = 0
    private let acceptQueue = DispatchQueue(label: "sumi.bench.http.accept")

    func start() throws -> UInt16 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw NSError(domain: "bench.http", code: 1)
        }
        var reuse: Int32 = 1
        setsockopt(
            fd, SOL_SOCKET, SO_REUSEADDR,
            &reuse, socklen_t(MemoryLayout<Int32>.size)
        )

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bindResult = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            close(fd)
            throw NSError(domain: "bench.http", code: 2)
        }
        guard listen(fd, 128) == 0 else {
            close(fd)
            throw NSError(domain: "bench.http", code: 3)
        }

        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        var resolved = sockaddr_in()
        getsockname(
            fd,
            withUnsafeMutablePointer(to: &resolved) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { $0 }
            },
            &length
        )
        boundPort = UInt16(bigEndian: resolved.sin_port)

        serverFD = fd
        acceptQueue.async { [weak self] in
            self?.acceptLoop()
        }
        return boundPort
    }

    func stop() {
        guard serverFD >= 0 else { return }
        close(serverFD)
        serverFD = -1
    }

    private func acceptLoop() {
        while serverFD >= 0 {
            let clientFD = accept(serverFD, nil, nil)
            guard clientFD >= 0 else { break }
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.serve(clientFD: clientFD)
            }
        }
    }

    private func serve(clientFD: Int32) {
        defer { close(clientFD) }
        var noSigPipe: Int32 = 1
        setsockopt(
            clientFD, SOL_SOCKET, SO_NOSIGPIPE,
            &noSigPipe, socklen_t(MemoryLayout<Int32>.size)
        )

        var received = Data()
        let bufferCapacity = 16_384
        while !received.contains(Data("\r\n\r\n".utf8)) {
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferCapacity)
            defer { buffer.deallocate() }
            let count = recv(clientFD, buffer, bufferCapacity, 0)
            guard count > 0 else { return }
            received.append(buffer, count: count)
            if received.count > 64_000 { break }
        }

        guard let requestHead = String(data: received.prefix(4_096), encoding: .utf8),
              let requestLine = requestHead.split(separator: "\r\n").first
        else { return }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return }
        let path = String(parts[1])

        let response: Data
        if path.hasPrefix("/res/") {
            response = Self.httpResponse(
                contentType: "text/plain",
                body: Data("ok-\(path)".utf8)
            )
        } else if path.hasPrefix("/page") {
            response = Self.httpResponse(
                contentType: "text/html; charset=utf-8",
                body: Data(Self.pageHTML.utf8)
            )
        } else {
            response = Self.httpResponse(
                status: "404 Not Found",
                contentType: "text/plain",
                body: Data("missing".utf8)
            )
        }
        response.withUnsafeBytes { raw in
            var sent = 0
            while sent < raw.count {
                let count = send(
                    clientFD, raw.baseAddress!.advanced(by: sent),
                    raw.count - sent, 0
                )
                guard count > 0 else { return }
                sent += count
            }
        }
    }

    private static func httpResponse(
        status: String = "200 OK",
        contentType: String,
        body: Data
    ) -> Data {
        var head = "HTTP/1.1 \(status)\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n\r\n"
        return Data(head.utf8) + body
    }
}

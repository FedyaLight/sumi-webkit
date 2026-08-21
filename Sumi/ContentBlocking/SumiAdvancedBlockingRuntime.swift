import ContentBlockerConverter
import FilterEngine
import Foundation
import JavaScriptCore

struct SumiAdvancedBlockingDocumentContext: Hashable, Sendable {
    let pageURL: URL
    let topURL: URL?
}

struct SumiAdvancedBlockingConfiguration: Equatable, Sendable {
    let css: [String]
    let extendedCSS: [String]
    let pageWorldScripts: [String]

    func pageBridgeValue(extendedRuntimeSource: String) -> [String: Any] {
        [
            "css": css,
            "extendedCss": extendedCSS,
            "extendedRuntime": extendedCSS.isEmpty ? "" : extendedRuntimeSource,
        ]
    }

    var pageWorldSource: String? {
        let sources = pageWorldScripts.filter {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
        guard sources.isEmpty == false else { return nil }
        return sources.map { "try { \($0) } catch {}" }.joined(separator: "\n")
    }
}

enum SumiAdvancedBlockingRuntimeError: Error, LocalizedError {
    case incompatibleRuntimeVersion(String)
    case missingScriptletCompiler
    case scriptletCompilerInitializationFailed
    case scriptletCompilationFailed(String)

    var errorDescription: String? {
        switch self {
        case .incompatibleRuntimeVersion(let version):
            return "Unsupported advanced-blocking runtime version: \(version)"
        case .missingScriptletCompiler:
            return "Advanced-blocking scriptlet compiler resource is missing."
        case .scriptletCompilerInitializationFailed:
            return "Advanced-blocking scriptlet compiler failed to initialize."
        case .scriptletCompilationFailed(let name):
            return "Advanced-blocking scriptlet failed to compile: \(name)"
        }
    }
}

/// Deep runtime module for the advanced half of one active blocker generation.
/// Its interface accepts a document and returns an inert configuration value;
/// storage layout, engine lifetime, scriptlet compilation and cache policy stay
/// inside the implementation.
actor SumiAdvancedBlockingRuntime {
    typealias ScriptletCompilerSourceProvider = @Sendable () throws -> String

    private struct LoadedGeneration {
        let id: String
        let engine: WebExtension
    }

    private enum CachedConfiguration {
        case empty
        case value(SumiAdvancedBlockingConfiguration)
    }

    private static let supportedRuntimeVersion = "4.3.0"
    private static let configurationCacheLimit = 40
    private static let warmUpDocument = SumiAdvancedBlockingDocumentContext(
        pageURL: URL(string: "https://block.invalid/")!,
        topURL: nil
    )

    nonisolated static func supports(
        _ descriptor: AdvancedBlockingGenerationDescriptor?
    ) -> Bool {
        descriptor?.runtimeVersion == supportedRuntimeVersion
    }

    private let archive: AdblockGenerationArchive
    private let scriptletCompilerSourceProvider: ScriptletCompilerSourceProvider
    private var loadedGeneration: LoadedGeneration?
    private var scriptletCompiler: SumiAdvancedBlockingScriptletCompiler?
    private var cosmeticDomainIndex: AdblockCosmeticDomainIndex?
    private var configurationCache: [
        SumiAdvancedBlockingDocumentContext: CachedConfiguration
    ] = [:]
    private var configurationCacheOrder: [SumiAdvancedBlockingDocumentContext] = []

    init(
        archive: AdblockGenerationArchive,
        scriptletCompilerSourceProvider: @escaping ScriptletCompilerSourceProvider = {
            try SumiAdvancedBlockingResourceLoader.scriptletCompilerSource()
        }
    ) {
        self.archive = archive
        self.scriptletCompilerSourceProvider = scriptletCompilerSourceProvider
    }

    func configuration(
        for document: SumiAdvancedBlockingDocumentContext,
        in manifest: AdblockCompiledGenerationManifest
    ) async throws -> SumiAdvancedBlockingConfiguration? {
        guard let descriptor = manifest.advancedBlocking else { return nil }
        guard Self.supports(descriptor) else {
            throw SumiAdvancedBlockingRuntimeError.incompatibleRuntimeVersion(
                descriptor.runtimeVersion
            )
        }

        let engine = try engine(for: manifest)
        if let cached = configurationCache[document] {
            refreshCachePosition(for: document)
            switch cached {
            case .empty:
                return nil
            case .value(let configuration):
                return configuration
            }
        }
        let domainCosmeticSelectors = cosmeticDomainIndex?
            .selectors(forHost: (document.topURL ?? document.pageURL).host) ?? []
        guard let result = engine.lookup(
            pageUrl: document.pageURL,
            topUrl: document.topURL
        ) else {
            if domainCosmeticSelectors.isEmpty {
                cache(.empty, for: document)
                return nil
            }
            let configuration = SumiAdvancedBlockingConfiguration(
                css: domainCosmeticSelectors,
                extendedCSS: [],
                pageWorldScripts: []
            )
            cache(.value(configuration), for: document)
            return configuration
        }
        let scriptletCompiler = try? compiler()
        let compiledScriptlets: [String] = result.scriptlets.compactMap { scriptlet in
            guard let scriptletCompiler,
                  let code = try? scriptletCompiler.compile(
                    name: scriptlet.name,
                    arguments: scriptlet.args
                  )
            else {
                return nil
            }
            return code
        }
        guard result.css.isEmpty == false
                || domainCosmeticSelectors.isEmpty == false
                || result.extendedCss.isEmpty == false
                || result.js.isEmpty == false
                || compiledScriptlets.isEmpty == false
        else {
            cache(.empty, for: document)
            return nil
        }
        let configuration = SumiAdvancedBlockingConfiguration(
            css: result.css + domainCosmeticSelectors,
            extendedCSS: result.extendedCss,
            pageWorldScripts: compiledScriptlets + result.js
        )
        cache(.value(configuration), for: document)
        return configuration
    }

    func prepare(
        for manifest: AdblockCompiledGenerationManifest
    ) async {
        _ = try? await configuration(
            for: Self.warmUpDocument,
            in: manifest
        )
        removeCachedConfiguration(for: Self.warmUpDocument)
    }

    func deactivate() {
        loadedGeneration = nil
        scriptletCompiler = nil
        cosmeticDomainIndex = nil
        configurationCache.removeAll(keepingCapacity: false)
        configurationCacheOrder.removeAll(keepingCapacity: false)
    }

    private func engine(
        for manifest: AdblockCompiledGenerationManifest
    ) throws -> WebExtension {
        if let loadedGeneration,
           loadedGeneration.id == manifest.activeGenerationId {
            return loadedGeneration.engine
        }
        configurationCache.removeAll(keepingCapacity: true)
        configurationCacheOrder.removeAll(keepingCapacity: true)
        let generationDirectory = try archive.generationDirectoryURL(
            generationId: manifest.activeGenerationId
        )
        let engine = try WebExtension(
            containerURL: generationDirectory,
            version: SafariVersion.autodetect()
        )
        cosmeticDomainIndex = try Self.loadCosmeticDomainIndex(
            manifest: manifest,
            archive: archive
        )
        loadedGeneration = LoadedGeneration(
            id: manifest.activeGenerationId,
            engine: engine
        )
        return engine
    }

    private static func loadCosmeticDomainIndex(
        manifest: AdblockCompiledGenerationManifest,
        archive: AdblockGenerationArchive
    ) throws -> AdblockCosmeticDomainIndex? {
        guard let artifact = manifest.advancedBlocking?.artifacts.first(where: {
            $0.role == .domainCosmeticRules
        }) else {
            return nil
        }
        let url = try archive.advancedArtifactURL(
            generationID: manifest.activeGenerationId,
            relativePath: artifact.relativePath
        )
        return try AdblockCosmeticDomainIndex(
            data: Data(contentsOf: url)
        )
    }

    private func cache(
        _ configuration: CachedConfiguration,
        for document: SumiAdvancedBlockingDocumentContext
    ) {
        configurationCache[document] = configuration
        refreshCachePosition(for: document)
        if configurationCacheOrder.count > Self.configurationCacheLimit {
            let evicted = configurationCacheOrder.removeFirst()
            configurationCache.removeValue(forKey: evicted)
        }
    }

    private func refreshCachePosition(
        for document: SumiAdvancedBlockingDocumentContext
    ) {
        configurationCacheOrder.removeAll { $0 == document }
        configurationCacheOrder.append(document)
    }

    private func removeCachedConfiguration(
        for document: SumiAdvancedBlockingDocumentContext
    ) {
        configurationCache.removeValue(forKey: document)
        configurationCacheOrder.removeAll { $0 == document }
    }

    private func compiler() throws -> SumiAdvancedBlockingScriptletCompiler {
        if let scriptletCompiler { return scriptletCompiler }
        let source = try scriptletCompilerSourceProvider()
        guard source.isEmpty == false else {
            throw SumiAdvancedBlockingRuntimeError.missingScriptletCompiler
        }
        let compiler = try SumiAdvancedBlockingScriptletCompiler(source: source)
        scriptletCompiler = compiler
        return compiler
    }
}

private final class SumiAdvancedBlockingScriptletCompiler {
    private let context: JSContext
    private let function: JSValue

    init(source: String) throws {
        guard let context = JSContext() else {
            throw SumiAdvancedBlockingRuntimeError
                .scriptletCompilerInitializationFailed
        }
        context.exceptionHandler = { _, _ in }
        context.evaluateScript(source)
        guard context.exception == nil,
              let function = context.objectForKeyedSubscript(
                "sumiCompileScriptlet"
              ),
              function.isObject
        else {
            throw SumiAdvancedBlockingRuntimeError
                .scriptletCompilerInitializationFailed
        }
        self.context = context
        self.function = function
    }

    func compile(name: String, arguments: [String]) throws -> String {
        context.exception = nil
        guard let result = function.call(withArguments: [name, arguments]),
              context.exception == nil,
              result.isString,
              let code = result.toString(),
              code.isEmpty == false
        else {
            throw SumiAdvancedBlockingRuntimeError
                .scriptletCompilationFailed(name)
        }
        return code
    }
}

enum SumiAdvancedBlockingResourceLoader {
    static func pageRuntimeSource(in bundle: Bundle = .main) throws -> String {
        try source(named: "sumi-advanced-blocking", in: bundle)
    }

    static func scriptletCompilerSource(
        in bundle: Bundle = .main
    ) throws -> String {
        try source(named: "sumi-scriptlet-compiler", in: bundle)
    }

    private static func source(named name: String, in bundle: Bundle) throws -> String {
        let candidates = [
            bundle.url(
                forResource: name,
                withExtension: "js",
                subdirectory: "ContentBlocking"
            ),
            bundle.url(forResource: name, withExtension: "js"),
        ]
        guard let url = candidates.compactMap({ $0 }).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}

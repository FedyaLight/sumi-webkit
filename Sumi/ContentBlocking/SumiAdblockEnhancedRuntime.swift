import WebKit

struct AdblockResourceLicenseNotice: Codable, Equatable, Sendable {
    let resourceName: String
    let text: String
}

struct AdblockTrustedScriptletResource: Equatable, Sendable {
    enum ContentWorldPolicy: String, Sendable {
        case isolatedDOM
        case pageWorld
    }

    let canonicalName: String
    let aliases: [String]
    let contentWorldPolicy: ContentWorldPolicy
    let requiredParameterCount: ClosedRange<Int>
    let licenseNotice: AdblockResourceLicenseNotice
}

struct AdblockEnhancedRuntimeScript: Equatable, Sendable {
    let source: String
    let requiresPageWorld: Bool
}

struct AdblockResourceAliasMap: Equatable, Sendable {
    private let canonicalNamesByRequestedName: [String: String]

    init(resources: [AdblockTrustedScriptletResource]) {
        var names = [String: String]()
        for resource in resources {
            names[resource.canonicalName] = resource.canonicalName
            for alias in resource.aliases {
                names[alias] = resource.canonicalName
            }
        }
        canonicalNamesByRequestedName = names
    }

    func canonicalName(for requestedName: String) -> String? {
        canonicalNamesByRequestedName[requestedName]
            ?? canonicalNamesByRequestedName["\(requestedName).js"]
    }
}

struct AdblockEnhancedResourceBundle: Equatable, Sendable {
    let scriptlets: [AdblockTrustedScriptletResource]
    let aliasMap: AdblockResourceAliasMap

    init(scriptlets: [AdblockTrustedScriptletResource]) {
        self.scriptlets = scriptlets
        aliasMap = AdblockResourceAliasMap(resources: scriptlets)
    }

    func trustedScriptlet(for requestedName: String) -> AdblockTrustedScriptletResource? {
        guard let canonicalName = aliasMap.canonicalName(for: requestedName) else { return nil }
        return scriptlets.first { $0.canonicalName == canonicalName }
    }
}

struct AdblockEnhancedRuntimeResolver: Equatable, Sendable {
    let trustedBundle: AdblockEnhancedResourceBundle
    let maxScriptletsPerPage: Int

    init(
        trustedBundle: AdblockEnhancedResourceBundle = SumiAdblockEnhancedRuntime.makeTrustedResourceBundle(),
        maxScriptletsPerPage: Int = 8
    ) {
        self.trustedBundle = trustedBundle
        self.maxScriptletsPerPage = maxScriptletsPerPage
    }

    func resolve(
        runtimeBundle: AdblockEnhancedRuntimeBundle,
        pageURL: URL?
    ) -> AdblockEnhancedRuntimeScript? {
        guard let host = pageURL?.host(percentEncoded: false)?.lowercased(),
              SumiAdblockEnhancedRuntime.isEligibleWebURL(pageURL)
        else { return nil }

        var sources = [String]()
        var usedKeys = Set<String>()
        for invocation in runtimeBundle.scriptletInvocations {
            guard applies(invocation, to: host),
                  let resource = trustedBundle.trustedScriptlet(for: invocation.resourceName),
                  resource.contentWorldPolicy == .isolatedDOM,
                  resource.requiredParameterCount.contains(invocation.parameters.count),
                  let invocationSource = Self.source(for: resource, invocation: invocation)
            else { continue }

            let key = "\(resource.canonicalName):\(invocation.parameters.joined(separator: "\u{1f}"))"
            guard usedKeys.insert(key).inserted else { continue }
            sources.append(invocationSource)
            if sources.count >= maxScriptletsPerPage { break }
        }

        guard !sources.isEmpty else { return nil }
        return AdblockEnhancedRuntimeScript(
            source: Self.wrap(invocations: sources),
            requiresPageWorld: false
        )
    }

    private func applies(_ invocation: AdblockScriptletInvocation, to host: String) -> Bool {
        if invocation.excludeDomains.contains(where: { domainMatches(host: host, domain: $0) }) {
            return false
        }
        guard !invocation.includeDomains.isEmpty else { return true }
        return invocation.includeDomains.contains { domainMatches(host: host, domain: $0) }
    }

    private func domainMatches(host: String, domain: String) -> Bool {
        let normalized = domain.lowercased()
        return host == normalized || host.hasSuffix(".\(normalized)")
    }

    private static func source(
        for resource: AdblockTrustedScriptletResource,
        invocation: AdblockScriptletInvocation
    ) -> String? {
        switch resource.canonicalName {
        case SumiAdblockEnhancedRuntime.hideBySelectorScriptletName:
            guard let selector = invocation.parameters.first,
                  selector.count <= 512,
                  let encodedSelector = jsonStringLiteral(selector)
            else { return nil }
            return "hideBySelector(\(encodedSelector));"
        default:
            return nil
        }
    }

    private static func wrap(invocations: [String]) -> String {
        """
        // \(SumiAdblockEnhancedRuntime.sourceMarker)
        (() => {
          const namespace = '\(SumiAdblockEnhancedRuntime.messageNamespace)';
          if (globalThis.__sumiAdblockEnhancedRuntime === namespace) { return; }
          globalThis.__sumiAdblockEnhancedRuntime = namespace;
          const maxElements = 50;
          const hideBySelector = (selector) => {
            if (typeof selector !== 'string' || selector.length === 0 || selector.length > 512) { return; }
            let nodes;
            try {
              nodes = document.querySelectorAll(selector);
            } catch (_) {
              return;
            }
            const limit = Math.min(nodes.length, maxElements);
            for (let index = 0; index < limit; index += 1) {
              const element = nodes[index];
              if (element instanceof Element) {
                element.setAttribute('hidden', '');
                element.setAttribute('data-sumi-adblock-enhanced-applied', 'true');
              }
            }
          };
          \(invocations.joined(separator: "\n          "))
        })();
        """
    }

    private static func jsonStringLiteral(_ value: String) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

enum SumiAdblockEnhancedRuntime {
    static let sourceMarker = "SUMI_ADBLOCK_ENHANCED_RUNTIME"
    static let messageNamespace = "sumi.adblock.enhanced"
    static let hideBySelectorScriptletName = "sumi-hide.js"

    static let bundledResource = AdblockEnhancedResource(
        name: hideBySelectorScriptletName,
        kind: .scriptlet,
        sourceRule: "sumi.local##+js(sumi-hide, [data-sumi-adblock-enhanced-cleanup=\"hide\"])"
    )

    static func makeBundledBundle() -> AdblockEnhancedRuntimeBundle {
        AdblockEnhancedRuntimeBundle(
            resources: [bundledResource],
            scriptletInvocations: [
                AdblockScriptletInvocation(
                    resourceName: "sumi-hide",
                    parameters: ["[data-sumi-adblock-enhanced-cleanup=\"hide\"]"],
                    includeDomains: ["sumi.local"],
                    excludeDomains: [],
                    sourceRule: bundledResource.sourceRule,
                    diagnosticSource: "Sumi bundled fixture"
                ),
            ],
            unsupportedDiagnostics: []
        )
    }

    static func makeTrustedResourceBundle() -> AdblockEnhancedResourceBundle {
        AdblockEnhancedResourceBundle(
            scriptlets: [
                AdblockTrustedScriptletResource(
                    canonicalName: hideBySelectorScriptletName,
                    aliases: ["sumi-hide"],
                    contentWorldPolicy: .isolatedDOM,
                    requiredParameterCount: 1...1,
                    licenseNotice: AdblockResourceLicenseNotice(
                        resourceName: hideBySelectorScriptletName,
                        text: "Sumi fixture resource, Brave adblock-resources metadata-compatible; not copied from Brave."
                    )
                ),
            ]
        )
    }

    static func isEligibleWebURL(_ url: URL?) -> Bool {
        guard let scheme = url?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    @MainActor
    static func makeScript(
        bundle: AdblockEnhancedRuntimeBundle,
        pageURL: URL?,
        resolver: AdblockEnhancedRuntimeResolver = AdblockEnhancedRuntimeResolver()
    ) -> SumiUserScript? {
        guard let runtimeScript = resolver.resolve(runtimeBundle: bundle, pageURL: pageURL),
              runtimeScript.requiresPageWorld == false
        else { return nil }
        return SumiAdblockEnhancedRuntimeUserScript(source: runtimeScript.source)
    }
}

@MainActor
final class SumiAdblockEnhancedRuntimeUserScript: NSObject, SumiUserScript {
    let injectionTime: WKUserScriptInjectionTime = .atDocumentEnd
    let forMainFrameOnly = false
    let messageNames: [String] = []
    let requiresRunInPageContentWorld = false

    let source: String

    init(source: String) {
        self.source = source
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {}
}

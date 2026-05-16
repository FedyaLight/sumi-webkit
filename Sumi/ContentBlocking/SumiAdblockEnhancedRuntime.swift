import Foundation
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

struct AdblockTrustedRedirectResource: Equatable, Sendable {
    let canonicalName: String
    let aliases: [String]
    let resourceKind: AdblockRedirectResourceKind
    let mimeType: String
    let contentBytes: Data?
    let licenseNotice: AdblockResourceLicenseNotice
    let canBeDeliveredInWebKit: Bool
    let requiresEnhancedRuntime: Bool
    let requiresPageWorldExecution: Bool
    let unsupportedReason: String?
}

struct AdblockEnhancedRuntimeScript: Equatable, Sendable {
    let source: String
    let requiresPageWorld: Bool
}

struct AdblockResolvedRedirectResource: Equatable, Sendable {
    let candidate: AdblockRedirectResourceCandidate
    let trustedResource: AdblockTrustedRedirectResource
}

struct AdblockEnhancedRuntimeResolution: Equatable, Sendable {
    let script: AdblockEnhancedRuntimeScript?
    let redirectResources: [AdblockResolvedRedirectResource]
    let diagnostics: [AdblockUnsupportedRuleDiagnostic]
}

struct AdblockResourceAliasMap: Equatable, Sendable {
    private let canonicalNamesByRequestedName: [String: String]

    init(scriptlets: [AdblockTrustedScriptletResource], redirectResources: [AdblockTrustedRedirectResource]) {
        var names = [String: String]()
        for resource in scriptlets {
            names[resource.canonicalName] = resource.canonicalName
            for alias in resource.aliases {
                names[alias] = resource.canonicalName
            }
        }
        for resource in redirectResources {
            names[resource.canonicalName] = resource.canonicalName
            for alias in resource.aliases {
                names[alias] = resource.canonicalName
            }
        }
        canonicalNamesByRequestedName = names
    }

    func canonicalName(
        for requestedName: String,
        allowJavaScriptExtensionFallback: Bool = false
    ) -> String? {
        canonicalNamesByRequestedName[requestedName]
            ?? (
                allowJavaScriptExtensionFallback
                    ? canonicalNamesByRequestedName["\(requestedName).js"]
                    : nil
            )
    }
}

struct AdblockEnhancedResourceBundle: Equatable, Sendable {
    let scriptlets: [AdblockTrustedScriptletResource]
    let redirectResources: [AdblockTrustedRedirectResource]
    let aliasMap: AdblockResourceAliasMap

    init(
        scriptlets: [AdblockTrustedScriptletResource],
        redirectResources: [AdblockTrustedRedirectResource] = []
    ) {
        self.scriptlets = scriptlets
        self.redirectResources = redirectResources
        aliasMap = AdblockResourceAliasMap(
            scriptlets: scriptlets,
            redirectResources: redirectResources
        )
    }

    func trustedScriptlet(for requestedName: String) -> AdblockTrustedScriptletResource? {
        guard let canonicalName = aliasMap.canonicalName(
            for: requestedName,
            allowJavaScriptExtensionFallback: true
        ) else { return nil }
        return scriptlets.first { $0.canonicalName == canonicalName }
    }

    func trustedRedirectResource(for requestedName: String) -> AdblockTrustedRedirectResource? {
        guard let canonicalName = aliasMap.canonicalName(for: requestedName) else { return nil }
        return redirectResources.first { $0.canonicalName == canonicalName }
    }
}

struct AdblockEnhancedRuntimeResolver: Equatable, Sendable {
    let trustedBundle: AdblockEnhancedResourceBundle
    let maxScriptletsPerPage: Int
    let maxRedirectResourcesPerPage: Int

    init(
        trustedBundle: AdblockEnhancedResourceBundle = SumiAdblockEnhancedRuntime.makeTrustedResourceBundle(),
        maxScriptletsPerPage: Int = 8,
        maxRedirectResourcesPerPage: Int = 8
    ) {
        self.trustedBundle = trustedBundle
        self.maxScriptletsPerPage = maxScriptletsPerPage
        self.maxRedirectResourcesPerPage = maxRedirectResourcesPerPage
    }

    func resolve(
        runtimeBundle: AdblockEnhancedRuntimeBundle,
        pageURL: URL?
    ) -> AdblockEnhancedRuntimeScript? {
        resolveDetailed(runtimeBundle: runtimeBundle, pageURL: pageURL).script
    }

    func resolveDetailed(
        runtimeBundle: AdblockEnhancedRuntimeBundle,
        pageURL: URL?
    ) -> AdblockEnhancedRuntimeResolution {
        guard let host = pageURL?.host(percentEncoded: false)?.lowercased(),
              SumiAdblockEnhancedRuntime.isEligibleWebURL(pageURL)
        else {
            return AdblockEnhancedRuntimeResolution(
                script: nil,
                redirectResources: [],
                diagnostics: []
            )
        }

        var sources = [String]()
        var usedKeys = Set<String>()
        var diagnostics = [AdblockUnsupportedRuleDiagnostic]()
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

        let redirectResources = resolveRedirectResources(
            runtimeBundle.redirectResourceCandidates,
            host: host,
            diagnostics: &diagnostics
        )

        return AdblockEnhancedRuntimeResolution(
            script: sources.isEmpty
                ? nil
                : AdblockEnhancedRuntimeScript(
                    source: Self.wrap(invocations: sources),
                    requiresPageWorld: false
                ),
            redirectResources: redirectResources,
            diagnostics: diagnostics
        )
    }

    private func resolveRedirectResources(
        _ candidates: [AdblockRedirectResourceCandidate],
        host: String,
        diagnostics: inout [AdblockUnsupportedRuleDiagnostic]
    ) -> [AdblockResolvedRedirectResource] {
        var resolved = [AdblockResolvedRedirectResource]()
        var consideredCount = 0
        for candidate in candidates {
            guard applies(candidate, to: host) else { continue }
            consideredCount += 1
            guard consideredCount <= maxRedirectResourcesPerPage else {
                diagnostics.append(
                    AdblockUnsupportedRuleDiagnostic(
                        rule: candidate.sourceRule,
                        reason: "redirect/noop resource cap reached"
                    )
                )
                continue
            }
            guard let resource = trustedBundle.trustedRedirectResource(for: candidate.requestedName) else {
                diagnostics.append(
                    AdblockUnsupportedRuleDiagnostic(
                        rule: candidate.sourceRule,
                        reason: "unknown redirect/noop resource '\(candidate.requestedName)' rejected"
                    )
                )
                continue
            }
            guard resource.canBeDeliveredInWebKit else {
                diagnostics.append(
                    AdblockUnsupportedRuleDiagnostic(
                        rule: candidate.sourceRule,
                        reason: resource.unsupportedReason
                            ?? candidate.unsupportedReason
                            ?? "redirect/noop resource cannot be delivered in WKWebView"
                    )
                )
                continue
            }
            resolved.append(
                AdblockResolvedRedirectResource(
                    candidate: candidate,
                    trustedResource: resource
                )
            )
        }
        return resolved
    }

    private func applies(_ invocation: AdblockScriptletInvocation, to host: String) -> Bool {
        if invocation.excludeDomains.contains(where: { domainMatches(host: host, domain: $0) }) {
            return false
        }
        guard !invocation.includeDomains.isEmpty else { return true }
        return invocation.includeDomains.contains { domainMatches(host: host, domain: $0) }
    }

    private func applies(_ candidate: AdblockRedirectResourceCandidate, to host: String) -> Bool {
        if candidate.excludeDomains.contains(where: { domainMatches(host: host, domain: $0) }) {
            return false
        }
        guard !candidate.includeDomains.isEmpty else { return true }
        return candidate.includeDomains.contains { domainMatches(host: host, domain: $0) }
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
    static let webKitRedirectReplacementUnsupportedReason =
        "WKWebView content blockers cannot replace http/https response bodies; custom URL scheme handlers cannot intercept WebKit-handled http/https schemes"

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
            ],
            redirectResources: [
                trustedUnsupportedRedirectResource(
                    canonicalName: "noopjs",
                    aliases: ["noop.js"],
                    resourceKind: .script,
                    mimeType: "application/javascript"
                ),
                trustedUnsupportedRedirectResource(
                    canonicalName: "noopcss",
                    aliases: ["noop.css"],
                    resourceKind: .stylesheet,
                    mimeType: "text/css"
                ),
                trustedUnsupportedRedirectResource(
                    canonicalName: "1x1-transparent.gif",
                    aliases: ["1x1.gif"],
                    resourceKind: .image,
                    mimeType: "image/gif"
                ),
                trustedUnsupportedRedirectResource(
                    canonicalName: "noopframe",
                    aliases: ["noop.html"],
                    resourceKind: .document,
                    mimeType: "text/html"
                ),
                trustedUnsupportedRedirectResource(
                    canonicalName: "noop.txt",
                    aliases: ["nooptext"],
                    resourceKind: .text,
                    mimeType: "text/plain"
                ),
            ]
        )
    }

    private static func trustedUnsupportedRedirectResource(
        canonicalName: String,
        aliases: [String],
        resourceKind: AdblockRedirectResourceKind,
        mimeType: String
    ) -> AdblockTrustedRedirectResource {
        AdblockTrustedRedirectResource(
            canonicalName: canonicalName,
            aliases: aliases,
            resourceKind: resourceKind,
            mimeType: mimeType,
            contentBytes: nil,
            licenseNotice: AdblockResourceLicenseNotice(
                resourceName: canonicalName,
                text: "Sumi-owned uBO-compatible redirect resource metadata; no Brave/uBO resource content is vendored."
            ),
            canBeDeliveredInWebKit: false,
            requiresEnhancedRuntime: true,
            requiresPageWorldExecution: false,
            unsupportedReason: webKitRedirectReplacementUnsupportedReason
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

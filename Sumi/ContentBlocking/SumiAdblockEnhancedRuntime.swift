import WebKit

enum SumiAdblockEnhancedRuntime {
    static let sourceMarker = "SUMI_ADBLOCK_ENHANCED_RUNTIME"
    static let messageNamespace = "sumi.adblock.enhanced"

    static let bundledResource = AdblockEnhancedResource(
        name: "sumi-enhanced-cleanup",
        kind: .cosmeticCleanup,
        sourceRule: "sumi.local##sumi-enhanced-cleanup"
    )

    static func makeBundledBundle() -> AdblockEnhancedRuntimeBundle {
        AdblockEnhancedRuntimeBundle(
            resources: [bundledResource],
            unsupportedDiagnostics: []
        )
    }

    static func isEligibleWebURL(_ url: URL?) -> Bool {
        guard let scheme = url?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    @MainActor
    static func makeScript(bundle: AdblockEnhancedRuntimeBundle = makeBundledBundle()) -> SumiUserScript? {
        guard bundle.resources.contains(where: { $0.name == bundledResource.name && $0.kind == .cosmeticCleanup }) else {
            return nil
        }
        return SumiAdblockEnhancedRuntimeUserScript()
    }
}

@MainActor
final class SumiAdblockEnhancedRuntimeUserScript: NSObject, SumiUserScript {
    let injectionTime: WKUserScriptInjectionTime = .atDocumentEnd
    let forMainFrameOnly = false
    let messageNames: [String] = []
    let requiresRunInPageContentWorld = false

    let source = """
    // SUMI_ADBLOCK_ENHANCED_RUNTIME
    (() => {
      const namespace = 'sumi.adblock.enhanced';
      if (globalThis.__sumiAdblockEnhancedRuntime === namespace) { return; }
      globalThis.__sumiAdblockEnhancedRuntime = namespace;
      const selector = '[data-sumi-adblock-enhanced-cleanup="hide"]';
      const maxElements = 50;
      const nodes = document.querySelectorAll(selector);
      const limit = Math.min(nodes.length, maxElements);
      for (let index = 0; index < limit; index += 1) {
        const element = nodes[index];
        if (element instanceof Element) {
          element.setAttribute('hidden', '');
          element.setAttribute('data-sumi-adblock-enhanced-applied', 'true');
        }
      }
    })();
    """

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {}
}

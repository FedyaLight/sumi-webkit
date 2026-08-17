import Foundation
import WebKit

@MainActor
final class SumiAdvancedBlockingPageScript: NSObject, SumiPageScript {
    typealias Lookup = @MainActor (
        SumiAdvancedBlockingDocumentContext
    ) async -> SumiAdvancedBlockingConfiguration?

    static let messageName = "sumiAdvancedBlocking"

    let source: String
    let injectionTime = WKUserScriptInjectionTime.atDocumentStart
    let forMainFrameOnly = false
    let requiresRunInPageContentWorld = false
    let messageNames = [messageName]

    private let lookup: Lookup
    private let extendedRuntimeSource: String

    private static let applyConfigurationSource = #"""
        if (globalThis.__sumiAdvancedBlockingRequestID !== requestID || location.href !== expectedPageURL) return;
        const css=(configuration.css||[]).map(rule=>rule.trim()).filter(Boolean).map(rule=>rule.endsWith("}")?rule:`${rule} {display:none!important;}`);
        if(css.length)try{if("adoptedStyleSheets"in document&&typeof CSSStyleSheet==="function"){const sheet=new CSSStyleSheet;sheet.replaceSync(css.join("\n"));document.adoptedStyleSheets=[...document.adoptedStyleSheets,sheet]}else{const style=document.createElement("style");style.type="text/css";(document.head||document.documentElement).appendChild(style);if(style.sheet)for(const rule of css)style.sheet.insertRule(rule)}}catch{}
        if(configuration.extendedCss?.length&&configuration.extendedRuntime)try{Function("configuration",configuration.extendedRuntime)({extendedCss:configuration.extendedCss})}catch{}
        """#

    init(runtimeSource: String, lookup: @escaping Lookup) {
        self.lookup = lookup
        extendedRuntimeSource = runtimeSource
        source = #"""
            (()=>{"use strict";const handler=window.webkit?.messageHandlers?.sumiAdvancedBlocking;if(!handler)return;const requestID=`${Date.now()}:${Math.random()}`;globalThis.__sumiAdvancedBlockingRequestID=requestID;const pageURL=location.href;let topURL=null;if(top!==window){try{topURL=top.location.href}catch{topURL=document.referrer||null}}try{handler.postMessage({requestID,pageURL,topURL})}catch{}})();
            """#
        super.init()
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        _ = userContentController
        guard message.name == Self.messageName,
              let document = Self.documentContext(
                messageBody: message.body,
                pageURL: message.frameInfo.request.url,
                topURL: message.webView?.url,
                isMainFrame: message.frameInfo.isMainFrame
              ),
              let webView = message.webView,
              let requestID = (message.body as? [String: Any])?["requestID"] as? String,
              let expectedPageURL = (message.body as? [String: Any])?["pageURL"] as? String
        else {
            return
        }
        let frameInfo = message.frameInfo
        Task { @MainActor [weak webView, lookup, extendedRuntimeSource] in
            guard let configuration = await lookup(document),
                  let webView
            else { return }
            _ = try? await webView.callAsyncJavaScript(
                Self.applyConfigurationSource,
                arguments: [
                    "configuration": configuration.pageBridgeValue(
                        extendedRuntimeSource: extendedRuntimeSource
                    ),
                    "expectedPageURL": expectedPageURL,
                    "requestID": requestID,
                ],
                in: frameInfo,
                contentWorld: .defaultClient
            )
            if let source = configuration.pageWorldSource {
                _ = try? await webView.callAsyncJavaScript(
                    source,
                    arguments: [:],
                    in: frameInfo,
                    contentWorld: .page
                )
            }
        }
    }

    static func documentContext(
        messageBody: Any,
        pageURL: URL?,
        topURL: URL?,
        isMainFrame: Bool
    ) -> SumiAdvancedBlockingDocumentContext? {
        let bootstrapPageURL = (messageBody as? [String: Any])
            .flatMap { $0["pageURL"] as? String }
            .flatMap(URL.init(string:))
        let bootstrapTopURL = (messageBody as? [String: Any])
            .flatMap { $0["topURL"] as? String }
            .flatMap(URL.init(string:))
        return documentContext(
            pageURL: bootstrapPageURL ?? pageURL,
            topURL: bootstrapTopURL ?? topURL,
            isMainFrame: isMainFrame
        )
    }

    static func documentContext(
        pageURL: URL?,
        topURL: URL?,
        isMainFrame: Bool
    ) -> SumiAdvancedBlockingDocumentContext? {
        if let pageURL, isWebDocumentURL(pageURL) {
            return SumiAdvancedBlockingDocumentContext(
                pageURL: pageURL,
                topURL: isMainFrame ? nil : topURL
            )
        }
        guard isMainFrame == false,
              let topURL,
              isWebDocumentURL(topURL)
        else {
            return nil
        }
        return SumiAdvancedBlockingDocumentContext(
            pageURL: topURL,
            topURL: topURL
        )
    }

    private static func isWebDocumentURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}

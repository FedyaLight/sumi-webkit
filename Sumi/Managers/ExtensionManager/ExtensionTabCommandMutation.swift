import Foundation
import NaturalLanguage
import SumiWebRuntime
import WebKit

@available(macOS 15.5, *)
@MainActor
protocol ExtensionTabWindowLocationQuery: AnyObject {
    func preferredExtensionWindowState(
        containing tab: Tab
    ) -> BrowserWindowState?
}

@available(macOS 15.5, *)
@MainActor
final class ExtensionTabCommandMutation {
    private let evidence: ExtensionTabCurrentPublicationEvidence
    private let projection: ExtensionTabReadProjection
    private weak var windowQuery: (any ExtensionTabWindowLocationQuery)?
    private weak var tabMutation: (any ExtensionTabCommandRouting)?
    private weak var webViewHosting: (any ExtensionTabReloadHosting)?
    private weak var auxiliaryWindows: (any ExtensionAuxiliaryTabClosing)?

    init(
        evidence: ExtensionTabCurrentPublicationEvidence,
        projection: ExtensionTabReadProjection,
        windowQuery: any ExtensionTabWindowLocationQuery,
        tabMutation: any ExtensionTabCommandRouting,
        webViewHosting: any ExtensionTabReloadHosting,
        auxiliaryWindows: any ExtensionAuxiliaryTabClosing
    ) {
        self.evidence = evidence
        self.projection = projection
        self.windowQuery = windowQuery
        self.tabMutation = tabMutation
        self.webViewHosting = webViewHosting
        self.auxiliaryWindows = auxiliaryWindows
    }

    private var tabUnavailableUntilReloadError: NSError {
        ExtensionBridgeAdapterCallbackError.tabUnavailableUntilReload.nsError()
    }

    private var tabUnavailableError: NSError {
        if evidence.currentTab != nil {
            return tabUnavailableUntilReloadError
        }
        return ExtensionBridgeAdapterCallbackError.tabUnavailable.nsError()
    }

    private func complete(
        _ completion: @escaping (Error?) -> Void,
        error: Error?
    ) {
        ExtensionBridgeCallbackSupport.complete(
            completion,
            api: .tabAdapterCompletion,
            error: error
        )
    }

    func activate(
        for context: WKWebExtensionContext,
        completion: @escaping (Error?) -> Void
    ) {
        guard let tabMutation,
              let publication = evidence.currentPublication(visibleTo: context)
        else { complete(completion, error: tabUnavailableError); return }
        let tab = publication.tab
        guard let window = windowQuery?.preferredExtensionWindowState(
            containing: tab
        ) else {
            complete(
                completion,
                error: ExtensionBridgeAdapterCallbackError.tabWindowUnavailable
                    .nsError()
            )
            return
        }
        _ = tabMutation.promoteTransientExtensionTab(tab)
        guard evidence.isCurrent(publication, visibleTo: context),
              windowQuery?.preferredExtensionWindowState(containing: tab)
                === window
        else {
            complete(completion, error: tabUnavailableUntilReloadError)
            return
        }
        tabMutation.selectExtensionTab(tab, in: window)
        complete(completion, error: nil)
    }

    func close(
        for context: WKWebExtensionContext,
        completion: @escaping (Error?) -> Void
    ) {
        guard let publication = evidence.currentPublication(visibleTo: context)
        else {
            complete(completion, error: tabUnavailableUntilReloadError)
            return
        }
        if publication.isAuxiliary {
            guard let auxiliaryWindows,
                  let session = auxiliaryWindows.auxiliaryWindowSession(
                    for: publication.tab
                  ),
                  session.tab === publication.tab,
                  let receipt = auxiliaryWindows
                    .auxiliaryWindowSessionReceipt(for: session)
            else {
                complete(completion, error: tabUnavailableUntilReloadError)
                return
            }
            auxiliaryWindows.closeAuxiliaryWindowSession(receipt)
            complete(completion, error: nil)
            return
        }
        publication.tab.closeTab()
        complete(completion, error: nil)
    }

    func reload(
        fromOrigin: Bool,
        for context: WKWebExtensionContext,
        completion: @escaping (Error?) -> Void
    ) {
        guard let publication = evidence.currentPublication(visibleTo: context)
        else {
            complete(completion, error: tabUnavailableUntilReloadError)
            return
        }
        let tab = publication.tab
        guard let webView = projection.webView(for: context) else {
            complete(
                completion,
                error: ExtensionBridgeAdapterCallbackError.tabWebViewUnavailable
                    .nsError()
            )
            return
        }
        guard evidence.isCurrent(publication, visibleTo: context) else {
            complete(completion, error: tabUnavailableUntilReloadError)
            return
        }
        guard let webViewHosting else {
            complete(completion, error: tabUnavailableError)
            return
        }
        let outcome = webViewHosting.reloadExtensionTab(
            tab,
            webView: webView,
            in: windowQuery?.preferredExtensionWindowState(containing: tab),
            policy: fromOrigin ? .fromOrigin : .standard
        )
        guard outcome != .failed else {
            complete(
                completion,
                error: ExtensionBridgeAdapterCallbackError.tabReloadFailed
                    .nsError()
            )
            return
        }
        complete(completion, error: nil)
    }

    func loadURL(
        _ url: URL,
        for context: WKWebExtensionContext,
        completion: @escaping (Error?) -> Void
    ) {
        guard let publication = evidence.currentPublication(visibleTo: context)
        else {
            complete(completion, error: tabUnavailableUntilReloadError)
            return
        }
        let tab = publication.tab
        if ExtensionURLIdentity.isOwned(url) == false {
            _ = tabMutation?.promoteTransientExtensionTab(tab)
            guard evidence.isCurrent(publication, visibleTo: context) else {
                complete(completion, error: tabUnavailableUntilReloadError)
                return
            }
        }
        tab.loadURL(url)
        complete(completion, error: nil)
    }

    func setMuted(
        _ muted: Bool,
        for context: WKWebExtensionContext,
        completion: @escaping (Error?) -> Void
    ) {
        guard let tab = evidence.currentPublication(visibleTo: context)?.tab
        else {
            complete(completion, error: tabUnavailableUntilReloadError)
            return
        }
        tab.setMuted(muted)
        complete(completion, error: nil)
    }

    func setZoomFactor(
        _ zoomFactor: Double,
        for context: WKWebExtensionContext,
        completion: @escaping (Error?) -> Void
    ) {
        guard let publication = evidence.currentPublication(visibleTo: context),
              let webView = projection.webView(for: context)
        else {
            complete(completion, error: tabUnavailableError)
            return
        }
        guard evidence.isCurrent(publication, visibleTo: context) else {
            complete(completion, error: tabUnavailableUntilReloadError)
            return
        }
        webView.pageZoom = zoomFactor
        complete(completion, error: nil)
    }

    func detectWebpageLocale(
        for context: WKWebExtensionContext,
        completion: @escaping (Locale?, Error?) -> Void
    ) {
        guard let publication = evidence.currentPublication(visibleTo: context),
              let webView = projection.webView(for: context) else {
            completion(nil, tabUnavailableError)
            return
        }

        Task { @MainActor [weak self] in
            guard let self,
                  self.evidence.isCurrent(
                      publication,
                      visibleTo: context
                  ) else {
                completion(nil, self?.tabUnavailableUntilReloadError)
                return
            }
            do {
                let value = try await webView.callAsyncJavaScript(
                    """
                    const root = document.documentElement;
                    const declared = (root?.lang ||
                        document.querySelector('meta[http-equiv="content-language"]')?.content ||
                        '').trim();
                    const text = (document.body?.innerText || '').slice(0, 65536);
                    return { declared, text };
                    """,
                    arguments: [:],
                    in: nil,
                    contentWorld: .defaultClient
                )
                let payload = value as? [String: Any] ?? [:]
                let declared = (payload["declared"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let text = payload["text"] as? String ?? ""
                let identifier = await Self.localeIdentifier(
                    declared: declared,
                    text: text
                )
                guard self.evidence.isCurrent(
                    publication,
                    visibleTo: context
                ) else {
                    completion(nil, self.tabUnavailableUntilReloadError)
                    return
                }
                completion(
                    identifier.map {
                        Locale(identifier: $0.replacingOccurrences(of: "-", with: "_"))
                    },
                    nil
                )
            } catch {
                completion(
                    nil,
                    SumiWebExtensionCallbackErrorMapper
                        .webExtensionCallbackError(from: error)
                )
            }
        }
    }

    private nonisolated static func localeIdentifier(
        declared: String?,
        text: String
    ) async -> String? {
        if let declared, declared.isEmpty == false {
            return declared
        }
        guard text.isEmpty == false else { return nil }
        return await Task.detached(priority: .utility) {
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(text)
            return recognizer.dominantLanguage?.rawValue
        }.value
    }
}

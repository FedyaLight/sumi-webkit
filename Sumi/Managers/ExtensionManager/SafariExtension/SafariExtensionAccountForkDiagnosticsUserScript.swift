//
//  SafariExtensionAccountForkDiagnosticsUserScript.swift
//  Sumi
//
//  Debug-only page-world probe for the Proton account login-fork handshake.
//
//  The field failure "Invalid selector" means the single-use fork selector was
//  already unknown/consumed on the server by the time the extension's content
//  script pulled it. Sumi cannot observe extension-internal messaging or
//  content-script fetches, but the *page* side of the handshake is fully
//  observable from the page world:
//
//  - how many times an account page instance loads for one tab (a zombie
//    double-load double-produces forks and the newer fork can invalidate the
//    visible page's selector),
//  - every fork produce/pull request the page itself issues
//    (`/auth/v4/sessions/forks`),
//  - every `runtime.sendMessage` dispatch to the extension and the response
//    (silent drops surface as `undefined` responses after a random delay).
//
//  Events are posted to a script message handler and mirrored to the unified
//  log (category `ProtonForkDiagnostics`) so one failing login in a debug
//  build pinpoints the broken hop. Only 8-char prefixes of selectors/states
//  are logged — never the full single-use credentials.
//

import Foundation
import WebKit

@MainActor
final class SafariExtensionAccountForkDiagnosticsUserScript: NSObject, SumiPageScript {
    static let messageName = "sumiAccountForkDiagnostics"

    var messageNames: [String] { [Self.messageName] }
    var injectionTime: WKUserScriptInjectionTime { .atDocumentStart }
    var forMainFrameOnly: Bool { true }
    var requiresRunInPageContentWorld: Bool { true }

    func userContentController(
        _: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == Self.messageName else { return }
        let line: String
        if let body = message.body as? [String: Any] {
            do {
                let data = try JSONSerialization.data(
                    withJSONObject: body,
                    options: [.sortedKeys]
                )
                line = String(decoding: data, as: UTF8.self)
            } catch {
                RuntimeDiagnostics.debug(category: "ProtonForkDiagnostics") {
                    "ProtonForkDiag encode failed: \(error.localizedDescription)"
                }
                line = String(describing: message.body)
            }
        } else {
            line = String(describing: message.body)
        }
        // .notice persists to the unified log store (unlike .info), so a
        // field run can be read back afterwards with
        // `log show --predicate 'category == "ProtonForkDiagnostics"'`.
        RuntimeDiagnostics.logger(category: "ProtonForkDiagnostics")
            .notice("ProtonForkDiag \(line, privacy: .public)")
    }

    let source: String = SafariExtensionAccountForkDiagnosticsUserScript.makeSource()

    private static func makeSource() -> String { """
    (() => {
      'use strict';
      const HOSTS = [
        'account.proton.me',
        'account.proton.black',
        'account.proton.pink',
        'account.proton.dev',
        'account.protontech.ch'
      ];
      if (!HOSTS.includes(location.hostname)) { return; }
      const bridge = window.webkit
        && window.webkit.messageHandlers
        && window.webkit.messageHandlers.\(Self.messageName);
      if (!bridge) { return; }

      const instanceId = Math.random().toString(36).slice(2, 10);
      const post = (event, detail) => {
        try {
          bridge.postMessage({
            event,
            instanceId,
            href: String(location.href).slice(0, 220),
            visibility: document.visibilityState,
            t: Date.now(),
            ...(detail || {})
          });
        } catch (_) {}
      };
      const prefix = (value) =>
        typeof value === 'string' && value.length > 0 ? value.slice(0, 8) : null;
      const runtimeAvailability = () => ({
        browserRuntime: !!(window.browser && window.browser.runtime
          && typeof window.browser.runtime.sendMessage === 'function'),
        chromeRuntime: !!(window.chrome && window.chrome.runtime
          && typeof window.chrome.runtime.sendMessage === 'function')
      });

      post('pageStart', {
        referrer: String(document.referrer || '').slice(0, 120),
        ...runtimeAvailability()
      });

      // The account app falls back to window.postMessage when the page-world
      // runtime binding is missing (`sendExtensionMessage`); in the Safari
      // build of Pass nothing answers that fallback, so seeing it here is a
      // diagnosis by itself.
      window.addEventListener('message', (event) => {
        try {
          const data = event && event.data;
          if (!data || typeof data !== 'object') { return; }
          const isForkDispatch = data.type === 'fork';
          const isFallbackReply = !!data.token
            && (data.type === 'success' || data.type === 'error');
          if (!isForkDispatch && !isFallbackReply) { return; }
          post('fallbackPostMessage', {
            type: String(data.type),
            from: data.from ? String(data.from).slice(0, 40) : null,
            hasToken: !!data.token,
            selectorPrefix: data.payload && typeof data.payload.selector === 'string'
              ? prefix(data.payload.selector)
              : null,
            error: data.error ? String(data.error).slice(0, 140) : null
          });
        } catch (_) {}
      });
      window.addEventListener('pagehide', () => post('pageHide', {}));
      window.addEventListener('pageshow', (event) => {
        post('pageShow', { persisted: !!event.persisted });
      });

      // --- Fork API traffic issued by the page itself -----------------------
      const FORK_ENDPOINT = /\\/auth\\/v4\\/sessions\\/forks/;
      const PULL_SELECTOR = /forks\\/([^\\/?#]+)/;
      const originalFetch = window.fetch;
      if (typeof originalFetch === 'function') {
        window.fetch = function (input, init) {
          let url = '';
          let method = 'GET';
          try {
            url = typeof input === 'string' ? input : String((input && input.url) || input || '');
            method = String((init && init.method) || (input && input.method) || 'GET').toUpperCase();
          } catch (_) {}
          const result = originalFetch.apply(this, arguments);
          if (FORK_ENDPOINT.test(url)) {
            // The fork produce always precedes the extension send; use it as
            // a timer-free last chance to wrap a late-injected runtime binding.
            wrapRuntimeBindings('forkApiRequest');
            const pullMatch = url.match(PULL_SELECTOR);
            const kind = pullMatch ? 'pull' : 'produce';
            const requestSelector = pullMatch
              ? prefix(decodeURIComponent(pullMatch[1]))
              : null;
            post('forkApiRequest', {
              kind,
              method,
              selectorPrefix: requestSelector,
              ...runtimeAvailability()
            });
            result.then(async (response) => {
              let producedSelector = null;
              try {
                if (!pullMatch && response.ok) {
                  const body = await response.clone().json();
                  if (body && typeof body.Selector === 'string') {
                    producedSelector = prefix(body.Selector);
                  }
                }
              } catch (_) {}
              post('forkApiResponse', {
                kind,
                method,
                status: response.status,
                selectorPrefix: producedSelector || requestSelector
              });
            }).catch((error) => {
              post('forkApiFailure', {
                kind,
                method,
                error: String(error).slice(0, 140)
              });
            });
          }
          return result;
        };
      }

      // --- Page → extension messaging ---------------------------------------
      // Function declarations: hoisted so the fetch wrapper above can retry
      // wrapping without timers.
      function wrapRuntime(apiName) {
        const api = window[apiName];
        if (!api || !api.runtime || typeof api.runtime.sendMessage !== 'function') {
          return false;
        }
        if (api.runtime.__sumiForkDiagnosticsWrapped) { return true; }
        api.runtime.__sumiForkDiagnosticsWrapped = true;
        const originalSendMessage = api.runtime.sendMessage.bind(api.runtime);
        api.runtime.sendMessage = function (extensionId, message, callback) {
          const sendId = Math.random().toString(36).slice(2, 8);
          const payload = (message && message.payload) || {};
          post('extensionSend', {
            sendId,
            api: apiName,
            extensionId: String(extensionId).slice(0, 72),
            type: message && message.type ? String(message.type).slice(0, 40) : typeof message,
            selectorPrefix: prefix(payload.selector),
            statePrefix: prefix(payload.state)
          });
          const started = Date.now();
          let reported = false;
          const report = (response, via, extra) => {
            if (reported) { return; }
            reported = true;
            let summary;
            try {
              if (response && typeof response === 'object') {
                summary = {
                  type: response.type || null,
                  error: response.error ? String(response.error).slice(0, 140) : null
                };
              } else {
                summary = { raw: response === undefined ? 'undefined' : String(response).slice(0, 80) };
              }
            } catch (_) { summary = { raw: 'unserializable' }; }
            post('extensionResponse', {
              sendId,
              via,
              elapsedMs: Date.now() - started,
              response: summary,
              ...(extra || {})
            });
          };
          let forwardedCallback = callback;
          if (typeof callback === 'function') {
            forwardedCallback = function (response) {
              let lastError = null;
              try {
                lastError = api.runtime.lastError
                  ? String(api.runtime.lastError.message || api.runtime.lastError).slice(0, 140)
                  : null;
              } catch (_) {}
              report(response, 'callback', { lastError });
              return callback.apply(this, arguments);
            };
          }
          const returned = forwardedCallback === undefined
            ? originalSendMessage(extensionId, message)
            : originalSendMessage(extensionId, message, forwardedCallback);
          if (returned && typeof returned.then === 'function') {
            returned.then(
              (response) => report(response, 'promise'),
              (error) => report({ error: String(error).slice(0, 140) }, 'promise-reject')
            );
          }
          return returned;
        };
        return true;
      }

      let runtimeWrapped = false;
      function wrapRuntimeBindings(origin) {
        if (runtimeWrapped) { return; }
        const wrappedBrowser = wrapRuntime('browser');
        const wrappedChrome = wrapRuntime('chrome');
        if (wrappedBrowser || wrappedChrome) {
          runtimeWrapped = true;
          post('runtimeBindingWrapped', {
            origin,
            browser: wrappedBrowser,
            chrome: wrappedChrome
          });
        } else if (origin === 'forkApiRequest') {
          // A produce without a wrappable binding means the account app is
          // about to take the postMessage fallback path.
          post('runtimeBindingMissing', { origin });
        }
      }

      // WebKit may expose the page-world runtime binding after document
      // start; retry at bounded lifecycle events (no timers) — the fork
      // produce request above is the final, always-in-time chance.
      wrapRuntimeBindings('documentStart');
      document.addEventListener('DOMContentLoaded', () => {
        wrapRuntimeBindings('domContentLoaded');
      }, { once: true });
      window.addEventListener('pageshow', () => {
        wrapRuntimeBindings('pageshow');
      });
    })();
    """
    }
}

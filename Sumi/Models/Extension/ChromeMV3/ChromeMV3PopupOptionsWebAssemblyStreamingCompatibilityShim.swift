//
//  ChromeMV3PopupOptionsWebAssemblyStreamingCompatibilityShim.swift
//  Sumi
//
//  Generic controlled-popup compatibility for local packaged WebAssembly
//  loaded through file-backed `fetch()` + `instantiateStreaming`. WebKit serves
//  sibling `file:` resources without `application/wasm`, so streaming compile
//  rejects them even when `allowFileAccessFromFileURLs` restored fetch access.
//

import Foundation

#if canImport(WebKit)
import WebKit
#endif

enum ChromeMV3PopupOptionsWebAssemblyStreamingCompatibilityShim {
    static func shouldInstall(
        loadingMode: ChromeMV3ProductPopupOptionsLoadingMode
    ) -> Bool {
        loadingMode == .fileBacked
    }

    #if canImport(WebKit)
    static func installIfNeeded(
        into userContentController: WKUserContentController,
        loadingMode: ChromeMV3ProductPopupOptionsLoadingMode
    ) {
        guard shouldInstall(loadingMode: loadingMode) else { return }
        let userScript = WKUserScript(
            source: source(),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: .page
        )
        userContentController.addUserScript(userScript)
    }
    #endif

    static func source() -> String {
        #if DEBUG
        let debugLoggingSource = debugLoggingSource()
        #else
        let debugLoggingSource = ""
        #endif
        return """
        (() => {
          "use strict";
          const wasm = globalThis.WebAssembly;
          if (!wasm || typeof wasm.instantiateStreaming !== "function") {
            return;
          }
          if (String(location.protocol || "") !== "file:") {
            return;
          }

          const originalInstantiateStreaming =
            wasm.instantiateStreaming.bind(wasm);

          \(debugLoggingSource)

          function isMimeMismatchError(error) {
            const message = String(
              error && (error.message || error) || ""
            );
            return message.indexOf("Unexpected response MIME type") !== -1
              || message.indexOf("Expected 'application/wasm'") !== -1
              || message.indexOf('Expected "application/wasm"') !== -1;
          }

          function isLocalPackagedWasmResponse(response) {
            if (!response || typeof response.url !== "string") {
              return false;
            }
            try {
              const url = new URL(response.url);
              if (url.protocol !== "file:") {
                return false;
              }
              return /\\.wasm$/i.test(url.pathname || "");
            } catch (_) {
              return false;
            }
          }

          async function resolveStreamingSource(source) {
            if (source instanceof Response) {
              return source;
            }
            if (source && typeof source.then === "function") {
              return await source;
            }
            return null;
          }

          async function readWasmBytes(response) {
            try {
              if (!response.bodyUsed) {
                return await response.arrayBuffer();
              }
            } catch (_) {
            }
            const refetch = await fetch(response.url);
            if (!refetch.ok) {
              throw new TypeError("local packaged wasm refetch failed");
            }
            return await refetch.arrayBuffer();
          }

          wasm.instantiateStreaming = async function instantiateStreaming(
            source,
            importObject
          ) {
            try {
              return await originalInstantiateStreaming(source, importObject);
            } catch (error) {
              if (!isMimeMismatchError(error)) {
                throw error;
              }
              const response = await resolveStreamingSource(source);
              if (!isLocalPackagedWasmResponse(response)) {
                throw error;
              }
              debugWasmStreamingFallbackUsed("mimeMismatch", "localPackagedWasm");
              try {
                const bytes = await readWasmBytes(response);
                const result = await wasm.instantiate(bytes, importObject);
                debugWasmStreamingFallbackUsed(
                  "fallbackSucceeded",
                  "localPackagedWasm"
                );
                return result;
              } catch (fallbackError) {
                debugWasmStreamingFallbackUsed(
                  "fallbackFailed",
                  "localPackagedWasm"
                );
                throw fallbackError;
              }
            }
          };
        })();
        """
    }

    #if DEBUG
    private static func debugLoggingSource() -> String {
        """
          function debugWasmStreamingFallbackUsed(category, scope) {
            const queue = globalThis.__sumiControlledPopupWasmShimDiagnostics
              || (globalThis.__sumiControlledPopupWasmShimDiagnostics = []);
            if (!Array.isArray(queue)) {
              return;
            }
            queue.push({
              category: String(category || "unknown"),
              scope: String(scope || "unknown"),
              protocol: "file"
            });
          }
        """
    }
    #else
    private static func debugLoggingSource() -> String {
        """
          function debugWasmStreamingFallbackUsed() {}
        """
    }
    #endif
}

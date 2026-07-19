import Foundation
import WebKit

@available(macOS 15.5, *)
enum ExtensionBackgroundReadinessRoute: Equatable {
    case webKitLoadCompletion
    case serviceWorkerActivationBarrier
}

@available(macOS 15.5, *)
@MainActor
protocol ExtensionBackgroundReadinessAwaiting: AnyObject {
    func waitUntilReady(
        webExtension: WKWebExtension,
        context: WKWebExtensionContext
    ) async throws -> ExtensionBackgroundReadinessRoute
}

/// Completes WebKit's MV3 background-load boundary. WebKit reports
/// `loadBackgroundContent()` after service-worker registration, while extension
/// pages may already begin importing modules from that worker. Waiting for the
/// worker's activation event prevents those imports from racing registration.
///
/// The private WebView lookup is isolated here because WebKit currently exposes
/// no public service-worker activation handle for a `WKWebExtensionContext`.
/// All JavaScript runs in WebKit's own hidden background page and installs no
/// timer, observer, or persistent browser-side state.
@available(macOS 15.5, *)
@MainActor
final class ExtensionBackgroundReadinessAwaiter:
    ExtensionBackgroundReadinessAwaiting {
    private static let backgroundWebViewSelector = NSSelectorFromString(
        "_backgroundWebView"
    )

    func waitUntilReady(
        webExtension: WKWebExtension,
        context: WKWebExtensionContext
    ) async throws -> ExtensionBackgroundReadinessRoute {
        guard requiresServiceWorkerActivationBarrier(webExtension) else {
            return .webKitLoadCompletion
        }
        guard let backgroundWebView = backgroundWebView(for: context) else {
            return .webKitLoadCompletion
        }

        do {
            _ = try await backgroundWebView.callAsyncJavaScript(
                Self.activationBarrierScript,
                arguments: [:],
                in: nil,
                contentWorld: .page
            )
            return .serviceWorkerActivationBarrier
        } catch {
            // WebKit's private background page can be present before its
            // service-worker registration surface is exposed. The public
            // context load completion is still the authoritative readiness
            // boundary; do not turn an optional activation probe into a
            // failed extension load.
            return .webKitLoadCompletion
        }
    }

    private func requiresServiceWorkerActivationBarrier(
        _ webExtension: WKWebExtension
    ) -> Bool {
        webExtension.supportsManifestVersion(3)
            && webExtension.hasBackgroundContent
            && webExtension.hasPersistentBackgroundContent == false
    }

    private func backgroundWebView(
        for context: WKWebExtensionContext
    ) -> WKWebView? {
        let selector = Self.backgroundWebViewSelector
        guard context.responds(to: selector),
              let result = context.perform(selector)
        else { return nil }
        return result.takeUnretainedValue() as? WKWebView
    }

    private static let activationBarrierScript =
        """
        const registrations = await navigator.serviceWorker.getRegistrations();
        const registration = registrations[0];
        if (!registration)
            throw new Error("Service worker registration is unavailable");

        const worker = registration.active
            || registration.waiting
            || registration.installing;
        if (!worker)
            throw new Error("Service worker instance is unavailable");
        if (worker.state === "activated")
            return true;

        await new Promise((resolve, reject) => {
            const stateDidChange = () => {
                if (worker.state === "activated") {
                    worker.removeEventListener("statechange", stateDidChange);
                    resolve();
                } else if (worker.state === "redundant") {
                    worker.removeEventListener("statechange", stateDidChange);
                    reject(new Error("Service worker became redundant"));
                }
            };
            worker.addEventListener("statechange", stateDidChange);
            stateDidChange();
        });
        return true;
        """
}

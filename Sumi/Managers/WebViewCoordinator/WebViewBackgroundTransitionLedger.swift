import Foundation
import SumiWebRuntime
import WebKit

struct WebViewBackgroundTransitionLease: Equatable {
    let id: UUID
    let webViewID: ObjectIdentifier
}

/// Process-wide coordinator for the temporary `drawsBackground = false` gate.
/// A WKWebView may move between window host owners, so a lease stored on one
/// window cannot decide whether a later window's transition is still active.
@MainActor
final class WebViewBackgroundTransitionLedger {
    private final class Entry {
        let webViewReference: WebViewIdentityWitness
        let lease: WebViewBackgroundTransitionLease
        var restoreTask: Task<Void, Never>?

        init(webView: WKWebView, lease: WebViewBackgroundTransitionLease) {
            webViewReference = WebViewIdentityWitness(webView)
            self.lease = lease
        }
    }

    private var entries: [ObjectIdentifier: Entry] = [:]

    func begin(for webView: WKWebView) -> WebViewBackgroundTransitionLease {
        let webViewID = ObjectIdentifier(webView)
        entries.removeValue(forKey: webViewID)?.restoreTask?.cancel()
        let lease = WebViewBackgroundTransitionLease(
            id: UUID(),
            webViewID: webViewID
        )
        entries[webViewID] = Entry(webView: webView, lease: lease)
        return lease
    }

    func scheduleRestore(
        matching lease: WebViewBackgroundTransitionLease,
        delay: Duration = .milliseconds(150),
        isStillValid: @escaping @MainActor () -> Bool
    ) {
        guard let entry = currentEntry(matching: lease) else { return }
        entry.restoreTask?.cancel()
        entry.restoreTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard Task.isCancelled == false,
                  let self,
                  isStillValid(),
                  let entry = self.currentEntry(matching: lease),
                  let webView = entry.webViewReference.resolve() else {
                return
            }
            self.entries.removeValue(forKey: lease.webViewID)
            webView.sumiSetDrawsBackground(true)
        }
    }

    @discardableResult
    func finish(matching lease: WebViewBackgroundTransitionLease) -> Bool {
        guard let entry = currentEntry(matching: lease),
              let webView = entry.webViewReference.resolve() else {
            return false
        }
        entry.restoreTask?.cancel()
        entries.removeValue(forKey: lease.webViewID)
        webView.sumiSetDrawsBackground(true)
        return true
    }

    func isCurrent(_ lease: WebViewBackgroundTransitionLease) -> Bool {
        currentEntry(matching: lease) != nil
    }

    private func currentEntry(
        matching lease: WebViewBackgroundTransitionLease
    ) -> Entry? {
        guard let entry = entries[lease.webViewID] else { return nil }
        guard entry.webViewReference.resolve() != nil else {
            entries.removeValue(forKey: lease.webViewID)
            return nil
        }
        return entry.lease == lease ? entry : nil
    }
}

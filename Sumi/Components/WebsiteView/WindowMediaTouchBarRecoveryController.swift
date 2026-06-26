import Combine
import Foundation
import WebKit

@MainActor
final class WindowMediaTouchBarRecoveryController {
    private static let retryDelays: [TimeInterval] = [0, 0.2, 0.5]

    private let windowID: UUID
    private let recover: (UUID?, WKWebView) -> Void
    private var recoveryCancellable: AnyCancellable?

    init(
        windowID: UUID,
        recover: @escaping (UUID?, WKWebView) -> Void
    ) {
        self.windowID = windowID
        self.recover = recover
    }

    func start() {
        guard recoveryCancellable == nil else { return }
        recoveryCancellable = NotificationCenter.default
            .publisher(for: .sumiWebViewNeedsMediaTouchBarRecovery)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleMediaTouchBarRecoveryRequest(notification)
            }
    }

    func stop() {
        recoveryCancellable?.cancel()
        recoveryCancellable = nil
    }

    private func handleMediaTouchBarRecoveryRequest(_ notification: Notification) {
        guard let webView = notification.object as? WKWebView,
              let notificationWindowID = notification.userInfo?[SumiMediaTouchBarRecoveryNotificationKey.windowID] as? UUID,
              notificationWindowID == windowID
        else {
            return
        }

        let tabID = notification.userInfo?[SumiMediaTouchBarRecoveryNotificationKey.tabID] as? UUID
        recover(tabID, webView)
        for delay in Self.retryDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak webView] in
                guard let webView else { return }
                self?.recover(tabID, webView)
            }
        }
    }
}

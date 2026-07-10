import Combine
import Foundation

final class TabProfileWebViewCreationGate {
    private let currentProfileUpdates: @MainActor () -> AnyPublisher<Profile?, Never>?
    private let currentProfileAwaitCancellable: @MainActor () -> AnyCancellable?
    private let setCurrentProfileAwaitCancellable: @MainActor (AnyCancellable?) -> Void
    private let hasCurrentWebView: @MainActor () -> Bool
    private let ensureUntrackedNormalWebView: @MainActor () -> Void

    init(
        currentProfileUpdates: @escaping @MainActor () -> AnyPublisher<Profile?, Never>?,
        currentProfileAwaitCancellable: @escaping @MainActor () -> AnyCancellable?,
        setCurrentProfileAwaitCancellable: @escaping @MainActor (AnyCancellable?) -> Void,
        hasCurrentWebView: @escaping @MainActor () -> Bool,
        ensureUntrackedNormalWebView: @escaping @MainActor () -> Void
    ) {
        self.currentProfileUpdates = currentProfileUpdates
        self.currentProfileAwaitCancellable = currentProfileAwaitCancellable
        self.setCurrentProfileAwaitCancellable = setCurrentProfileAwaitCancellable
        self.hasCurrentWebView = hasCurrentWebView
        self.ensureUntrackedNormalWebView = ensureUntrackedNormalWebView
    }

    convenience init(
        tab: Tab,
        currentProfileUpdates: @escaping @MainActor () -> AnyPublisher<Profile?, Never>?
    ) {
        self.init(
            currentProfileUpdates: currentProfileUpdates,
            currentProfileAwaitCancellable: { [weak tab] in
                tab?.profileAwaitCancellable
            },
            setCurrentProfileAwaitCancellable: { [weak tab] cancellable in
                tab?.profileAwaitCancellable = cancellable
            },
            hasCurrentWebView: { [weak tab] in
                tab?.hasCurrentWebView ?? false
            },
            ensureUntrackedNormalWebView: { [weak tab] in
                _ = tab?.ensureUntrackedNormalWebView(
                    reason: "TabProfileWebViewCreationGate"
                )
            }
        )
    }

    @MainActor
    func deferCreationUntilProfileAvailable() -> Bool {
        guard currentProfileAwaitCancellable() == nil else { return true }

        RuntimeDiagnostics.emit(
            "[Tab] No profile resolved yet; deferring WebView creation and observing currentProfile..."
        )

        guard let currentProfileUpdates = currentProfileUpdates() else {
            return false
        }
        let cancellable = currentProfileUpdates
            .receive(on: RunLoop.main)
            .sink { [weak self] profile in
                Task { @MainActor [weak self] in
                    self?.handleCurrentProfileUpdate(profile)
                }
            }
        setCurrentProfileAwaitCancellable(cancellable)
        return true
    }

    @MainActor
    private func handleCurrentProfileUpdate(_ profile: Profile?) {
        guard profile != nil,
              hasCurrentWebView() == false
        else {
            return
        }

        currentProfileAwaitCancellable()?.cancel()
        setCurrentProfileAwaitCancellable(nil)
        ensureUntrackedNormalWebView()
    }
}

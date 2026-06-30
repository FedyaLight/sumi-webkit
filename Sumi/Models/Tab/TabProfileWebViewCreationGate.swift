import Combine
import Foundation

final class TabProfileWebViewCreationGate {
    struct Dependencies {
        let currentProfileUpdates: @MainActor () -> AnyPublisher<Profile?, Never>?
        let currentProfileAwaitCancellable: @MainActor () -> AnyCancellable?
        let setCurrentProfileAwaitCancellable: @MainActor (AnyCancellable?) -> Void
        let hasCurrentWebView: @MainActor () -> Bool
        let setupWebView: @MainActor () -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    @MainActor
    func deferCreationUntilProfileAvailable() {
        guard dependencies.currentProfileAwaitCancellable() == nil else { return }

        RuntimeDiagnostics.emit(
            "[Tab] No profile resolved yet; deferring WebView creation and observing currentProfile..."
        )

        guard let currentProfileUpdates = dependencies.currentProfileUpdates() else { return }
        let cancellable = currentProfileUpdates
            .receive(on: RunLoop.main)
            .sink { [weak self] profile in
                Task { @MainActor [weak self] in
                    self?.handleCurrentProfileUpdate(profile)
                }
            }
        dependencies.setCurrentProfileAwaitCancellable(cancellable)
    }

    @MainActor
    private func handleCurrentProfileUpdate(_ profile: Profile?) {
        guard profile != nil,
              dependencies.hasCurrentWebView() == false
        else {
            return
        }

        dependencies.currentProfileAwaitCancellable()?.cancel()
        dependencies.setCurrentProfileAwaitCancellable(nil)
        dependencies.setupWebView()
    }
}

extension TabProfileWebViewCreationGate.Dependencies {
    @MainActor
    static func live(tab: Tab) -> Self {
        Self(
            currentProfileUpdates: { [weak tab] in
                tab?.browserManager?.$currentProfile.eraseToAnyPublisher()
            },
            currentProfileAwaitCancellable: { [weak tab] in
                tab?.profileAwaitCancellable
            },
            setCurrentProfileAwaitCancellable: { [weak tab] cancellable in
                tab?.profileAwaitCancellable = cancellable
            },
            hasCurrentWebView: { [weak tab] in
                tab?.hasCurrentWebView ?? false
            },
            setupWebView: { [weak tab] in
                tab?.setupWebView()
            }
        )
    }
}

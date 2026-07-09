import Combine
import Foundation

@MainActor
final class SumiMenuFaviconInvalidator: ObservableObject {
    @Published private(set) var revision: UInt = 0
    private var cancellable: AnyCancellable?

    init() {
        cancellable = NotificationCenter.default
            .publisher(for: .faviconCacheUpdated)
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.revision &+= 1
            }
    }
}

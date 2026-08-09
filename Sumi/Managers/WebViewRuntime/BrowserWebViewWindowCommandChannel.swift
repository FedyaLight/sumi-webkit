import Combine
import Foundation

enum BrowserWebViewWindowCommand {
    case selectTab(tabID: UUID, windowID: UUID)
    case refreshCompositor(windowID: UUID)
    case retryPageMaterialization(windowID: UUID)
}

@MainActor
final class BrowserWebViewWindowCommandChannel {
    private let subject = PassthroughSubject<BrowserWebViewWindowCommand, Never>()

    var publisher: AnyPublisher<BrowserWebViewWindowCommand, Never> {
        subject.eraseToAnyPublisher()
    }

    func selectTab(_ tabID: UUID, in windowID: UUID) {
        subject.send(.selectTab(tabID: tabID, windowID: windowID))
    }

    func refreshCompositor(in windowID: UUID) {
        subject.send(.refreshCompositor(windowID: windowID))
    }

    func retryPageMaterialization(in windowID: UUID) {
        subject.send(.retryPageMaterialization(windowID: windowID))
    }
}

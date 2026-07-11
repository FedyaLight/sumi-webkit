import Combine
import Foundation

/// Typed invalidation stream for one browser window's split presentation.
/// It carries no model or command surface; consumers re-read their concrete
/// query/preview services only when their own window ID is emitted.
@MainActor
final class SplitWindowUpdateStream {
    @MainActor
    struct Emitter {
        fileprivate let subject: PassthroughSubject<UUID, Never>

        func publish(windowID: UUID) {
            subject.send(windowID)
        }
    }

    private let subject: PassthroughSubject<UUID, Never>

    private init(subject: PassthroughSubject<UUID, Never>) {
        self.subject = subject
    }

    static func makeChannel() -> (stream: SplitWindowUpdateStream, emitter: Emitter) {
        let subject = PassthroughSubject<UUID, Never>()
        return (
            SplitWindowUpdateStream(subject: subject),
            Emitter(subject: subject)
        )
    }

    func updates(for windowID: UUID) -> AnyPublisher<Void, Never> {
        subject
            .filter { $0 == windowID }
            .map { _ in () }
            .eraseToAnyPublisher()
    }
}

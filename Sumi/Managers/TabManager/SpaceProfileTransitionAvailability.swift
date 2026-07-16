@MainActor
class SpaceProfileTransitionAvailability {
    @MainActor
    final class Observation {
        fileprivate weak var source: SpaceProfileTransitionAvailability?
        fileprivate let callback: @MainActor () -> Void

        fileprivate init(
            source: SpaceProfileTransitionAvailability,
            callback: @escaping @MainActor () -> Void
        ) {
            self.source = source
            self.callback = callback
        }

        func cancel() {
            source?.cancel(self)
            source = nil
        }

        deinit {
            MainActor.assumeIsolated { source?.cancel(self) }
        }
    }

    private var observer: Observation?
    private(set) var revision: UInt64 = 0

    func observeNext(
        after expectedRevision: UInt64,
        _ callback: @escaping @MainActor () -> Void
    ) -> Observation? {
        guard revision == expectedRevision else { return nil }
        precondition(observer == nil)
        let observation = Observation(source: self, callback: callback)
        observer = observation
        return observation
    }

    func publish() {
        revision &+= 1
        let observation = observer
        observer = nil
        observation?.source = nil
        observation?.callback()
    }

    private func cancel(_ observation: Observation) {
        guard observer === observation else { return }
        observer = nil
    }
}

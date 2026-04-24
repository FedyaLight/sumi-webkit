import Foundation

enum SumiMemoryPressureLevel: String {
    case warning
    case critical
}

@MainActor
protocol SumiMemoryPressureMonitoring: AnyObject {
    var eventHandler: ((SumiMemoryPressureLevel) -> Void)? { get set }

    func start()
    func stop()
}

@MainActor
final class SumiMemoryPressureMonitor: SumiMemoryPressureMonitoring {
    var eventHandler: ((SumiMemoryPressureLevel) -> Void)?

    private var source: DispatchSourceMemoryPressure?

    deinit {
        source?.cancel()
    }

    func start() {
        guard source == nil else { return }

        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        source.setEventHandler { [weak self, weak source] in
            guard let self, let source else { return }
            let event = source.data
            Task { @MainActor in
                self.handle(event)
            }
        }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    private func handle(_ event: DispatchSource.MemoryPressureEvent) {
        if event.contains(.critical) {
            eventHandler?(.critical)
        } else if event.contains(.warning) {
            eventHandler?(.warning)
        }
    }

#if DEBUG
    func processMemoryPressureEventForTesting(_ event: DispatchSource.MemoryPressureEvent) {
        handle(event)
    }
#endif
}

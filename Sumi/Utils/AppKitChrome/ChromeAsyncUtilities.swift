import AppKit
import Foundation

@MainActor
final class MainActorDebouncedTask {
    private var task: Task<Void, Never>?

    deinit {
        task?.cancel()
    }

    func schedule(
        delayNanoseconds: UInt64,
        operation: @escaping @MainActor () async -> Void
    ) {
        task?.cancel()
        task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }
            await operation()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

@MainActor
final class ChromeLocalEventMonitor {
    private var monitor: Any?

    isolated deinit {
        remove()
    }

    var isInstalled: Bool {
        monitor != nil
    }

    func install(
        matching mask: NSEvent.EventTypeMask,
        handler: @escaping (NSEvent) -> NSEvent?
    ) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: handler)
    }

    func remove() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }
}

import Foundation
@testable import Sumi

@MainActor
final class ManualMainActorDelayedActionScheduler {
    private struct Entry {
        let id: UUID
        let delay: TimeInterval
        let action: @MainActor () -> Void
        var isCancelled = false
    }

    private var entries: [Entry] = []

    var scheduler: MainActorDelayedActionScheduler {
        MainActorDelayedActionScheduler { [weak self] delay, action in
            guard let self else { return {} }
            let id = UUID()
            entries.append(Entry(id: id, delay: delay, action: action))
            return { [weak self] in
                guard let index = self?.entries.firstIndex(where: { $0.id == id }) else {
                    return
                }
                self?.entries[index].isCancelled = true
            }
        }
    }

    var scheduledDelays: [TimeInterval] {
        entries.map(\.delay)
    }

    var pendingActionCount: Int {
        entries.count(where: { !$0.isCancelled })
    }

    func runNext() {
        while !entries.isEmpty {
            let entry = entries.removeFirst()
            guard !entry.isCancelled else { continue }
            entry.action()
            return
        }
    }

    func runAll() {
        while !entries.isEmpty {
            runNext()
        }
    }
}

import Foundation

actor RuntimeStateCoalescer {
    typealias RuntimeTabState = TabSnapshotRepository.RuntimeTabState
    typealias PersistBatch = @Sendable ([RuntimeTabState]) async -> Void

    private enum Command: Sendable {
        case enqueue(RuntimeTabState)
        case cancel(UUID)
        case flushImmediately(CheckedContinuation<Int, Never>)
        case shutdownAndFlush(CheckedContinuation<Int, Never>)
    }

    private let debounceNanoseconds: UInt64
    private let persistBatch: PersistBatch
    private let commandContinuation: AsyncStream<Command>.Continuation

    private var scheduledFlushTask: Task<Void, Never>?
    private var scheduledDeadline: UInt64?
    private var pendingByTabID: [UUID: RuntimeTabState] = [:]
    private var isShutdown = false

    init(
        debounceNanoseconds: UInt64,
        persistBatch: @escaping PersistBatch
    ) {
        let streamPair = AsyncStream<Command>.makeStream(
            of: Command.self,
            bufferingPolicy: .unbounded
        )
        self.debounceNanoseconds = debounceNanoseconds
        self.persistBatch = persistBatch
        self.commandContinuation = streamPair.continuation

        Task { [weak self, stream = streamPair.stream] in
            for await command in stream {
                guard let self else { break }
                await self.handle(command)
            }
        }
    }

    deinit {
        commandContinuation.finish()
        scheduledFlushTask?.cancel()
    }

    nonisolated func enqueue(_ runtimeState: RuntimeTabState) {
        commandContinuation.yield(.enqueue(runtimeState))
    }

    nonisolated func cancel(tabID: UUID) {
        commandContinuation.yield(.cancel(tabID))
    }

    @discardableResult
    nonisolated func flushImmediately() async -> Int {
        await withCheckedContinuation { continuation in
            commandContinuation.yield(.flushImmediately(continuation))
        }
    }

    @discardableResult
    nonisolated func shutdownAndFlush() async -> Int {
        await withCheckedContinuation { continuation in
            commandContinuation.yield(.shutdownAndFlush(continuation))
        }
    }

    private func handle(_ command: Command) async {
        switch command {
        case .enqueue(let runtimeState):
            enqueueOnActor(runtimeState)
        case .cancel(let tabID):
            cancelOnActor(tabID: tabID)
        case .flushImmediately(let continuation):
            let count = await flushPending(
                signpostName: "RuntimeStateCoalescer.immediateRuntimeStateFlush"
            )
            continuation.resume(returning: count)
        case .shutdownAndFlush(let continuation):
            isShutdown = true
            let count = await flushPending(
                signpostName: "RuntimeStateCoalescer.immediateRuntimeStateFlush"
            )
            continuation.resume(returning: count)
        }
    }

    private func enqueueOnActor(_ runtimeState: RuntimeTabState) {
        guard isShutdown == false else { return }

        pendingByTabID[runtimeState.id] = runtimeState
        scheduledDeadline = DispatchTime.now().uptimeNanoseconds &+ debounceNanoseconds
        ensureScheduledFlushTask()
    }

    private func cancelOnActor(tabID: UUID) {
        pendingByTabID.removeValue(forKey: tabID)
        guard pendingByTabID.isEmpty else { return }

        scheduledDeadline = nil
        scheduledFlushTask?.cancel()
        scheduledFlushTask = nil
    }

    private func ensureScheduledFlushTask() {
        guard scheduledFlushTask == nil else { return }

        scheduledFlushTask = Task { [weak self] in
            await self?.runScheduledFlushLoop()
        }
    }

    private func runScheduledFlushLoop() async {
        while Task.isCancelled == false {
            guard let deadline = scheduledDeadline else {
                scheduledFlushTask = nil
                return
            }

            let now = DispatchTime.now().uptimeNanoseconds
            if deadline > now {
                do {
                    try await Task.sleep(nanoseconds: deadline - now)
                } catch {
                    return
                }
                continue
            }

            scheduledDeadline = nil
            scheduledFlushTask = nil
            _ = await flushPending(
                signpostName: "RuntimeStateCoalescer.coalescedBatchFlush"
            )
            return
        }
    }

    private func flushPending(signpostName: StaticString) async -> Int {
        scheduledDeadline = nil
        scheduledFlushTask?.cancel()
        scheduledFlushTask = nil

        let batch = pendingByTabID.values.sorted {
            $0.id.uuidString < $1.id.uuidString
        }
        pendingByTabID.removeAll(keepingCapacity: true)

        let signpostState = PerformanceTrace.beginInterval(signpostName)
        defer {
            PerformanceTrace.endInterval(signpostName, signpostState)
        }

        guard batch.isEmpty == false else { return 0 }
        await persistBatch(batch)
        return batch.count
    }
}

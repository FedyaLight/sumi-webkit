import Darwin
import Foundation
import OSLog
import WebKit

@MainActor
enum WebContentProcessResourceProbe {
    private static let logger = Logger.sumi(category: "TabSuspension")
    private static var pendingBeforeByProcess: [pid_t: UInt64] = [:]
    private static var measurementTask: Task<Void, Never>?

    static func residentBytesByProcess(
        for webViews: [WKWebView]
    ) -> [pid_t: UInt64] {
        let processIDs = Set(
            webViews.compactMap(SumiWebKitPageStateAdapter.webProcessIdentifier)
        )
        return Dictionary(
            uniqueKeysWithValues: processIDs.compactMap { processID in
                residentBytes(for: processID).map { (processID, $0) }
            }
        )
    }

    static func measureReclaimedMemory(
        afterSuspending processesBefore: [pid_t: UInt64]
    ) {
        guard processesBefore.isEmpty == false else { return }
        for (processID, residentBytes) in processesBefore {
            pendingBeforeByProcess[processID] = max(
                pendingBeforeByProcess[processID] ?? 0,
                residentBytes
            )
        }
        guard measurementTask == nil else { return }

        measurementTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard Task.isCancelled == false else { return }
            let snapshot = pendingBeforeByProcess
            pendingBeforeByProcess.removeAll(keepingCapacity: true)
            measurementTask = nil
            let before = snapshot.values.reduce(0, +)
            let after = snapshot.keys.reduce(into: UInt64(0)) {
                $0 += residentBytes(for: $1) ?? 0
            }
            let reclaimed = before > after ? before - after : 0
            logger.debug(
                "WebContent suspension before_bytes=\(before, privacy: .public) after_bytes=\(after, privacy: .public) reclaimed_bytes=\(reclaimed, privacy: .public)"
            )
        }
    }

    nonisolated private static func residentBytes(
        for processID: pid_t
    ) -> UInt64? {
        var taskInfo = proc_taskinfo()
        let expectedSize = Int32(MemoryLayout<proc_taskinfo>.size)
        let result = proc_pidinfo(
            processID,
            PROC_PIDTASKINFO,
            0,
            &taskInfo,
            expectedSize
        )
        guard result == expectedSize else { return nil }
        return taskInfo.pti_resident_size
    }
}

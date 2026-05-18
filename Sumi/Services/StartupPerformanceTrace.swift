import Foundation
import OSLog

#if DEBUG
import Darwin
#endif

@MainActor
enum StartupPerformanceTrace {
#if DEBUG
    private static let logger = Logger.sumi(category: "Startup")
    private static var didRecordAppLaunchStart = false
    private static var didRecordFirstWindowVisible = false
    private static var didRecordFirstSelectedTabResolved = false
    private static var didRecordFirstTabsClickable = false
    private static var didRecordFirstNavigationStart = false
    private static var didRecordFirstNavigationCommit = false
    private static var didRecordFirstNavigationFinish = false
    private static var didRecordPostStartupIdlePoint = false
    private static var didBeginFirstWebViewCreation = false
    private static var didBeginFirstContentBlockingAttach = false

    static func appLaunchStarted() {
        emitFirstEvent(
            flag: &didRecordAppLaunchStart,
            name: "Startup.appLaunchStart",
            memoryLabel: "appLaunchStart"
        )
    }

    static func browserManagerInitStarted() -> OSSignpostIntervalState? {
        PerformanceTrace.beginInterval("Startup.browserManagerInit")
    }

    static func browserManagerInitFinished(_ state: OSSignpostIntervalState?) {
        endInterval("Startup.browserManagerInit", state, memoryLabel: "browserManagerInitFinished")
    }

    static func protectionRestoreStarted() -> OSSignpostIntervalState? {
        PerformanceTrace.beginInterval("Startup.protectionRestore")
    }

    static func protectionRestoreFinished(_ state: OSSignpostIntervalState?) {
        endInterval("Startup.protectionRestore", state, memoryLabel: "protectionRestoreFinished")
    }

    static func sessionRestoreStarted() -> OSSignpostIntervalState? {
        PerformanceTrace.beginInterval("Startup.sessionRestore")
    }

    static func sessionRestoreFinished(_ state: OSSignpostIntervalState?) {
        endInterval("Startup.sessionRestore", state, memoryLabel: "sessionRestoreFinished")
    }

    static func firstWindowVisible() {
        emitFirstEvent(
            flag: &didRecordFirstWindowVisible,
            name: "Startup.firstWindowVisible",
            memoryLabel: "firstWindowVisible"
        )
    }

    static func firstSelectedTabResolved() {
        emitFirstEvent(
            flag: &didRecordFirstSelectedTabResolved,
            name: "Startup.firstSelectedTabResolved",
            memoryLabel: "firstSelectedTabResolved"
        )
    }

    static func firstTabsClickable() {
        emitFirstEvent(
            flag: &didRecordFirstTabsClickable,
            name: "Startup.firstTabsClickable",
            memoryLabel: "firstTabsClickable"
        )
    }

    static func firstWebViewCreationStarted() -> OSSignpostIntervalState? {
        beginFirstInterval(
            flag: &didBeginFirstWebViewCreation,
            name: "Startup.firstWebViewCreation"
        )
    }

    static func firstWebViewCreationFinished(_ state: OSSignpostIntervalState?) {
        endInterval("Startup.firstWebViewCreation", state, memoryLabel: "firstWebViewCreationFinished")
    }

    static func firstContentBlockingAttachStarted() -> OSSignpostIntervalState? {
        beginFirstInterval(
            flag: &didBeginFirstContentBlockingAttach,
            name: "Startup.firstContentBlockingAttach"
        )
    }

    static func firstContentBlockingAttachFinished(_ state: OSSignpostIntervalState?) {
        endInterval(
            "Startup.firstContentBlockingAttach",
            state,
            memoryLabel: "firstContentBlockingAttachFinished"
        )
    }

    static func firstNavigationStarted() {
        emitFirstEvent(
            flag: &didRecordFirstNavigationStart,
            name: "Startup.firstNavigationStart",
            memoryLabel: nil
        )
    }

    static func firstNavigationCommitted() {
        emitFirstEvent(
            flag: &didRecordFirstNavigationCommit,
            name: "Startup.firstNavigationDidCommit",
            memoryLabel: nil
        )
    }

    static func firstNavigationFinished() {
        emitFirstEvent(
            flag: &didRecordFirstNavigationFinish,
            name: "Startup.firstNavigationDidFinish",
            memoryLabel: "firstNavigationDidFinish"
        )
    }

    static func postStartupIdlePoint() {
        emitFirstEvent(
            flag: &didRecordPostStartupIdlePoint,
            name: "Startup.postStartupIdlePoint",
            memoryLabel: "postStartupIdlePoint"
        )
    }

    private static func beginFirstInterval(
        flag: inout Bool,
        name: StaticString
    ) -> OSSignpostIntervalState? {
        guard !flag else { return nil }
        flag = true
        return PerformanceTrace.beginInterval(name)
    }

    private static func endInterval(
        _ name: StaticString,
        _ state: OSSignpostIntervalState?,
        memoryLabel: StaticString?
    ) {
        guard let state else { return }
        PerformanceTrace.endInterval(name, state)
        if let memoryLabel {
            logResidentMemorySnapshot(label: memoryLabel)
        }
    }

    private static func emitFirstEvent(
        flag: inout Bool,
        name: StaticString,
        memoryLabel: StaticString?
    ) {
        guard !flag else { return }
        flag = true
        PerformanceTrace.emitEvent(name)
        if let memoryLabel {
            logResidentMemorySnapshot(label: memoryLabel)
        }
    }

    private static func logResidentMemorySnapshot(label: StaticString) {
        guard let residentBytes = residentMemoryBytes() else { return }
        let residentMB = Double(residentBytes) / 1_048_576
        logger.debug(
            "startupMemory label=\(String(describing: label), privacy: .public) residentMB=\(residentMB, format: .fixed(precision: 1), privacy: .public)"
        )
    }

    private static func residentMemoryBytes() -> UInt64? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { infoPointer in
            infoPointer.withMemoryRebound(
                to: integer_t.self,
                capacity: Int(count)
            ) { reboundPointer in
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    reboundPointer,
                    &count
                )
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return UInt64(info.resident_size)
    }
#else
    static func appLaunchStarted() {}
    static func browserManagerInitStarted() -> OSSignpostIntervalState? { nil }
    static func browserManagerInitFinished(_: OSSignpostIntervalState?) {}
    static func protectionRestoreStarted() -> OSSignpostIntervalState? { nil }
    static func protectionRestoreFinished(_: OSSignpostIntervalState?) {}
    static func sessionRestoreStarted() -> OSSignpostIntervalState? { nil }
    static func sessionRestoreFinished(_: OSSignpostIntervalState?) {}
    static func firstWindowVisible() {}
    static func firstSelectedTabResolved() {}
    static func firstTabsClickable() {}
    static func firstWebViewCreationStarted() -> OSSignpostIntervalState? { nil }
    static func firstWebViewCreationFinished(_: OSSignpostIntervalState?) {}
    static func firstContentBlockingAttachStarted() -> OSSignpostIntervalState? { nil }
    static func firstContentBlockingAttachFinished(_: OSSignpostIntervalState?) {}
    static func firstNavigationStarted() {}
    static func firstNavigationCommitted() {}
    static func firstNavigationFinished() {}
    static func postStartupIdlePoint() {}
#endif
}

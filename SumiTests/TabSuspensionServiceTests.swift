import WebKit
import XCTest

@testable import Sumi

@MainActor
final class TabSuspensionServiceTests: XCTestCase {
    func testEvaluationContextUsesInjectedRuntimePolicyAndVisibility() {
        let harness = TabSuspensionHarness()
        let windowID = UUID()
        let visibleTabID = UUID()
        let splitTabID = UUID()
        let selectedTabID = UUID()
        harness.memoryMode = .custom
        harness.customDeactivationDelay = 90 * 60
        harness.energySaverActive = true
        harness.visibleTabIDsByWindow = [windowID: [visibleTabID, splitTabID]]
        harness.selectedTabIDs = [selectedTabID]

        let context = harness.service.suspensionEvaluationContext()

        XCTAssertEqual(context.visibleTabIDs, [visibleTabID, splitTabID])
        XCTAssertEqual(context.selectedTabIDs, [selectedTabID])
        XCTAssertEqual(context.policy.memoryMode, .custom)
        XCTAssertEqual(context.policy.proactiveDeactivationDelay, 60 * 60)
        XCTAssertEqual(context.policy.revisitProtectionLimit, TabSuspensionPolicy.customRevisitProtectionLimit)
    }

    func testAttachRefreshesLazyRestoreQueueThroughRuntime() {
        let harness = TabSuspensionHarness(attachImmediately: false)
        let visibleTabID = UUID()
        let selectedTabID = UUID()
        harness.visibleTabIDsByWindow = [UUID(): [visibleTabID]]
        harness.selectedTabIDs = [selectedTabID]

        harness.attach()

        XCTAssertEqual(harness.refreshedLazyRestoreContexts.count, 1)
        XCTAssertEqual(harness.refreshedLazyRestoreContexts[0].visibleTabIDs, [visibleTabID])
        XCTAssertEqual(harness.refreshedLazyRestoreContexts[0].selectedTabIDs, [selectedTabID])
    }

    func testMemoryPressureWithoutCoordinatorDoesNotReadBroadRuntimeSnapshots() {
        let harness = TabSuspensionHarness()
        harness.resetReadCounts()

        harness.service.handleMemoryPressure(.warning)

        XCTAssertEqual(harness.webViewCoordinatorReadCount, 1)
        XCTAssertEqual(harness.memoryModeReadCount, 0)
        XCTAssertEqual(harness.customDeactivationDelayReadCount, 0)
        XCTAssertEqual(harness.energySaverActiveReadCount, 0)
        XCTAssertEqual(harness.allKnownTabsReadCount, 0)
        XCTAssertEqual(harness.selectedTabIDsReadCount, 0)
        XCTAssertEqual(harness.visibleTabIDsByWindowReadCount, 0)
        XCTAssertEqual(harness.refreshedLazyRestoreContexts.count, 0)
    }
}

@MainActor
private final class TabSuspensionHarness {
    let service: TabSuspensionService
    var coordinator: WebViewCoordinator?
    var memoryMode: SumiMemoryMode = .balanced
    var customDeactivationDelay: TimeInterval = SumiMemorySaverCustomDelay.defaultDelay
    var energySaverActive = false
    var tabs: [Tab] = []
    var selectedTabIDs: Set<UUID> = []
    var visibleTabIDsByWindow: [UUID: Set<UUID>] = [:]
    private(set) var refreshedLazyRestoreContexts: [TabSuspensionEvaluationContext] = []
    private(set) var webViewCoordinatorReadCount = 0
    private(set) var memoryModeReadCount = 0
    private(set) var customDeactivationDelayReadCount = 0
    private(set) var energySaverActiveReadCount = 0
    private(set) var allKnownTabsReadCount = 0
    private(set) var selectedTabIDsReadCount = 0
    private(set) var visibleTabIDsByWindowReadCount = 0

    init(attachImmediately: Bool = true) {
        service = TabSuspensionService(
            memoryMonitor: nil,
            timerSleep: { _ in /* No-op. */ }
        )
        if attachImmediately {
            attach()
        }
    }

    func attach() {
        service.attach(runtime: makeRuntime())
    }

    func resetReadCounts() {
        refreshedLazyRestoreContexts.removeAll()
        webViewCoordinatorReadCount = 0
        memoryModeReadCount = 0
        customDeactivationDelayReadCount = 0
        energySaverActiveReadCount = 0
        allKnownTabsReadCount = 0
        selectedTabIDsReadCount = 0
        visibleTabIDsByWindowReadCount = 0
    }

    private func makeRuntime() -> TabSuspensionRuntime {
        TabSuspensionRuntime(
            webViewCoordinator: { [weak self] in
                self?.webViewCoordinatorReadCount += 1
                return self?.coordinator
            },
            memoryMode: { [weak self] in
                self?.memoryModeReadCount += 1
                return self?.memoryMode ?? .balanced
            },
            customDeactivationDelay: { [weak self] in
                self?.customDeactivationDelayReadCount += 1
                return self?.customDeactivationDelay ?? SumiMemorySaverCustomDelay.defaultDelay
            },
            energySaverActive: { [weak self] in
                self?.energySaverActiveReadCount += 1
                return self?.energySaverActive ?? false
            },
            allKnownTabs: { [weak self] in
                self?.allKnownTabsReadCount += 1
                return self?.tabs ?? []
            },
            selectedTabIDs: { [weak self] in
                self?.selectedTabIDsReadCount += 1
                return self?.selectedTabIDs ?? []
            },
            visibleTabIDsByWindow: { [weak self] in
                self?.visibleTabIDsByWindowReadCount += 1
                return self?.visibleTabIDsByWindow ?? [:]
            },
            refreshLazyRestoreQueue: { [weak self] context in
                self?.refreshedLazyRestoreContexts.append(context)
            }
        )
    }
}

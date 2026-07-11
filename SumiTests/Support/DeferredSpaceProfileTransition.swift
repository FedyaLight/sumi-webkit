import Foundation
@testable import Sumi
import SumiWebRuntime

@MainActor
final class DeferredSpaceProfileTransition {
    private(set) var assignmentCount = 0
    private(set) var intent: DeferredWebViewSpaceProfileAssignmentIntent?
    private(set) var validateModel: (@MainActor @Sendable () -> Bool)?
    private(set) var stageModel: (@MainActor @Sendable () -> Bool)?
    private(set) var finishModel: (() -> Void)?
    private(set) var rollbackModel: (() -> Void)?
    private(set) var settlement: ProfileTransitionService.Settlement?
    private(set) var tabIntent: DeferredWebViewProfileAssignmentIntent?
    private(set) var tabSettlement: ProfileTransitionService.Settlement?

    func makeLifecycle() -> TabManagerWebViewLifecycleService {
        TabManagerWebViewLifecycleService(
            materializeVisibleTabWebViewIfNeeded: { _, _ in /* No-op. */ },
            loadTab: { _ in /* No-op. */ },
            unloadTab: { _ in /* No-op. */ },
            requireRemoveAllWebViews: { _, _ in /* No-op. */ },
            windowIDsTrackingWebViews: { _ in [] },
            primaryTrackedWindowId: { _ in nil },
            rebuildLiveWebViews: { _, _, _ in /* No-op. */ },
            prepareTab: { _ in /* No-op. */ },
            anyLiveWebView: { $0.resolvedCurrentWebView() },
            hasUntrackedOwnedWebView: { _ in false },
            executeProfileTransition: { [weak self] _, _, intent, settlement in
                self?.tabIntent = intent
                self?.tabSettlement = settlement
                return .deferred
            },
            executeSpaceProfileTransition: { [weak self] _, _, intent, validate, stage, finish, rollback, settle in
                self?.assignmentCount += 1
                self?.intent = intent
                self?.validateModel = validate
                self?.stageModel = stage
                self?.finishModel = finish
                self?.rollbackModel = rollback
                self?.settlement = settle
                return .deferred
            }
        )
    }
}

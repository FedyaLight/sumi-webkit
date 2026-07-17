import Combine
import Foundation
import SumiWebRuntime

@MainActor
enum BrowserTabRuntimeCompositionService {
    static func attach(
        tabSuspension: TabSuspensionController,
        tabSuspensionRuntime: TabSuspensionRuntimePorts,
        backgroundMedia: SumiBackgroundMediaOptimizationService,
        backgroundMediaRuntime: SumiBackgroundMediaOptimizationRuntime,
        structuralObserver: BrowserTabStructuralRuntimeObserver
    ) -> AnyCancellable {
        tabSuspension.install(runtime: tabSuspensionRuntime)
        backgroundMedia.attach(runtime: backgroundMediaRuntime)
        return structuralObserver.attach()
    }
}

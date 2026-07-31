import Combine
import Foundation
import SumiWebRuntime

@MainActor
enum BrowserTabRuntimeCompositionService {
    static func attach(
        tabSuspension: TabSuspensionController,
        tabSuspensionRuntime: TabSuspensionRuntimePorts,
        structuralObserver: BrowserTabStructuralRuntimeObserver
    ) -> AnyCancellable {
        tabSuspension.install(runtime: tabSuspensionRuntime)
        return structuralObserver.attach()
    }
}

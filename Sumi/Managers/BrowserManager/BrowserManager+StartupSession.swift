import Foundation

extension BrowserManager {
    func reconcileStartupSessionIfPossible() {
        startupSessionReconciliation.reconcileIfReady()
    }
}

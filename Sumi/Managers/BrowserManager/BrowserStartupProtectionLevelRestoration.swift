import Foundation
import SumiDomain

@MainActor
final class BrowserStartupProtectionLevelRestoration {
    private let protectionCoordinator: SumiProtectionCoordinator

    init(protectionCoordinator: SumiProtectionCoordinator) {
        self.protectionCoordinator = protectionCoordinator
    }

    var appliedProtectionLevel: SumiProtectionLevel {
        protectionCoordinator.settings.appliedLevel
    }

    func restoreAppliedProtectionLevelForStartup() async throws {
        _ = try await protectionCoordinator.restoreAppliedLevelForStartup()
    }
}

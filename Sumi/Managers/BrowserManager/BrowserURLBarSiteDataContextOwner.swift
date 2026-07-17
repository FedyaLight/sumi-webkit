import Combine

@MainActor
final class BrowserURLBarSiteDataContextOwner {
    let protection: SumiProtectionCoordinator
    let adblockZapperStore: SumiAdblockZapperStore
    let dataServices: BrowserManagerDataServices

    init(
        protection: SumiProtectionCoordinator,
        adblockZapperStore: SumiAdblockZapperStore,
        dataServices: BrowserManagerDataServices
    ) {
        self.protection = protection
        self.adblockZapperStore = adblockZapperStore
        self.dataServices = dataServices
    }
}

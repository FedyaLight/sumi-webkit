import Combine
import Foundation
import ObjectiveC
import WebKit

struct SumiNormalTabContentBlockingAssetSummary: Equatable, Sendable {
    let isInstalled: Bool
    let globalRuleListCount: Int
    let updateRuleCount: Int
    let isContentBlockingFeatureEnabled: Bool
    let globalRuleListIdentifiers: [String]
    let lookupSucceededIdentifiers: [String]
    let lookupFailedIdentifiers: [String]
    let addedToUserContentControllerIdentifiers: [String]
    let ruleListLookupDuration: TimeInterval?
    let tabAttachmentDuration: TimeInterval?

    init(
        isInstalled: Bool,
        globalRuleListCount: Int,
        updateRuleCount: Int,
        isContentBlockingFeatureEnabled: Bool,
        globalRuleListIdentifiers: [String] = [],
        lookupSucceededIdentifiers: [String] = [],
        lookupFailedIdentifiers: [String] = [],
        addedToUserContentControllerIdentifiers: [String] = [],
        ruleListLookupDuration: TimeInterval? = nil,
        tabAttachmentDuration: TimeInterval? = nil
    ) {
        self.isInstalled = isInstalled
        self.globalRuleListCount = globalRuleListCount
        self.updateRuleCount = updateRuleCount
        self.isContentBlockingFeatureEnabled = isContentBlockingFeatureEnabled
        self.globalRuleListIdentifiers = globalRuleListIdentifiers.sorted()
        self.lookupSucceededIdentifiers = lookupSucceededIdentifiers.sorted()
        self.lookupFailedIdentifiers = lookupFailedIdentifiers.sorted()
        self.addedToUserContentControllerIdentifiers = addedToUserContentControllerIdentifiers.sorted()
        self.ruleListLookupDuration = ruleListLookupDuration
        self.tabAttachmentDuration = tabAttachmentDuration
    }
}

@MainActor
protocol SumiNormalTabUserContentControlling: AnyObject {
    var wkUserContentController: WKUserContentController { get }
    var normalTabUserScriptsProvider: SumiNormalTabUserScripts? { get }
    var contentBlockingAssetSummary: SumiNormalTabContentBlockingAssetSummary { get }
    var hasInstalledInitialUserContent: Bool { get }
#if DEBUG
    var contentBlockingAssetSummaryPublisher: AnyPublisher<SumiNormalTabContentBlockingAssetSummary, Never> { get }
#endif

    func replaceNormalTabUserScripts(with provider: SumiNormalTabUserScripts) async
    func waitForContentBlockingAssetsInstalled() async
    func cleanUpBeforeClosing()
}

extension SumiNormalTabUserContentControlling {
    func waitForInitialUserContentInstallation() async {
        let signpostState = PerformanceTrace.beginInterval("ContentBlocking.assetsInstallWait")
        await waitForContentBlockingAssetsInstalled()
        PerformanceTrace.endInterval("ContentBlocking.assetsInstallWait", signpostState)
    }
}

@MainActor
private enum SumiNormalTabAssociatedKeys {
    static var scriptsProvider: UInt8 = 0
    static var marker: UInt8 = 0
}

extension WKUserContentController {
    @MainActor
    var sumiNormalTabUserScriptsProvider: SumiNormalTabUserScripts? {
        get {
            objc_getAssociatedObject(self, &SumiNormalTabAssociatedKeys.scriptsProvider) as? SumiNormalTabUserScripts
        }
        set {
            objc_setAssociatedObject(
                self,
                &SumiNormalTabAssociatedKeys.scriptsProvider,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }

    @MainActor
    var sumiUsesNormalTabSumiUserContentController: Bool {
        get {
            (objc_getAssociatedObject(self, &SumiNormalTabAssociatedKeys.marker) as? Bool) == true
        }
        set {
            objc_setAssociatedObject(
                self,
                &SumiNormalTabAssociatedKeys.marker,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }

    @MainActor
    var sumiNormalTabUserContentController: SumiNormalTabUserContentControlling? {
        self as? SumiNormalTabUserContentControlling
    }
}

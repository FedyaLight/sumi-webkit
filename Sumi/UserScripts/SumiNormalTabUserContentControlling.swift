import Combine
import Foundation
import ObjectiveC
import WebKit

struct SumiNormalTabContentBlockingAssetSummary: Equatable {
    let isInstalled: Bool
    let globalRuleListCount: Int
    let updateRuleCount: Int
    let isContentBlockingFeatureEnabled: Bool
}

@MainActor
protocol SumiNormalTabUserContentControlling: AnyObject {
    var wkUserContentController: WKUserContentController { get }
    var normalTabUserScriptsProvider: SumiNormalTabUserScripts? { get }
    var contentBlockingAssetSummary: SumiNormalTabContentBlockingAssetSummary { get }
#if DEBUG
    var contentBlockingAssetSummaryPublisher: AnyPublisher<SumiNormalTabContentBlockingAssetSummary, Never> { get }
#endif

    func replaceNormalTabUserScripts(with provider: SumiNormalTabUserScripts) async
    func waitForContentBlockingAssetsInstalled() async
    func cleanUpBeforeClosing()
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
    var sumiUsesNormalTabBrowserServicesKitUserContentController: Bool {
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
        sumiNormalTabUserContentControllerBridge ?? (self as? SumiNormalTabUserContentControlling)
    }
}

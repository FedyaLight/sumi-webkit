import BrowserServicesKit
import Combine
import Foundation
import ObjectiveC
import PrivacyConfig
import UserScript
import WebKit

private struct SumiFaviconUserContent: UserContentControllerNewContent {
    typealias SourceProvider = SumiDDGFaviconUserScripts
    typealias UserScripts = SumiDDGFaviconUserScripts

    let rulesUpdate = ContentBlockerRulesManager.UpdateEvent(
        rules: [],
        changes: [:],
        completionTokens: []
    )
    let sourceProvider: SumiDDGFaviconUserScripts
    let makeUserScripts: @MainActor (SumiDDGFaviconUserScripts) -> SumiDDGFaviconUserScripts = { $0 }
}

private enum SumiDDGFaviconAssociatedKeys {
    static var scriptsProvider = 0
    static var controllerDelegate = 0
    static var marker = 0
}

extension WKUserContentController {
    fileprivate var sumiFaviconControllerDelegate: SumiDDGFaviconUserContentControllerDelegate? {
        get {
            objc_getAssociatedObject(self, &SumiDDGFaviconAssociatedKeys.controllerDelegate) as? SumiDDGFaviconUserContentControllerDelegate
        }
        set {
            objc_setAssociatedObject(
                self,
                &SumiDDGFaviconAssociatedKeys.controllerDelegate,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }

    var sumiFaviconScriptsProvider: SumiDDGFaviconUserScripts? {
        get {
            objc_getAssociatedObject(self, &SumiDDGFaviconAssociatedKeys.scriptsProvider) as? SumiDDGFaviconUserScripts
        }
        set {
            objc_setAssociatedObject(
                self,
                &SumiDDGFaviconAssociatedKeys.scriptsProvider,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }

    var sumiUsesDDGFaviconUserContentController: Bool {
        get {
            (objc_getAssociatedObject(self, &SumiDDGFaviconAssociatedKeys.marker) as? Bool) == true
        }
        set {
            objc_setAssociatedObject(
                self,
                &SumiDDGFaviconAssociatedKeys.marker,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
}

private final class SumiDDGFaviconUserContentControllerDelegate: UserContentControllerDelegate {
    @MainActor
    func userContentController(
        _ userContentController: UserContentController,
        didInstallContentRuleLists contentRuleLists: [String: WKContentRuleList],
        userScripts: UserScriptsProvider,
        updateEvent: ContentBlockerRulesManager.UpdateEvent
    ) {
        _ = userContentController
        _ = contentRuleLists
        _ = userScripts
        _ = updateEvent
    }
}

@MainActor
enum SumiDDGFaviconUserContentControllerFactory {
    static func makeController() -> UserContentController {
        let scriptsProvider = SumiDDGFaviconUserScripts()
        let content = SumiFaviconUserContent(sourceProvider: scriptsProvider)
        let delegate = SumiDDGFaviconUserContentControllerDelegate()
        let controller = UserContentController(
            assetsPublisher: Just(content).eraseToAnyPublisher(),
            privacyConfigurationManager: SumiStaticPrivacyConfigurationManager()
        )
        controller.delegate = delegate
        controller.sumiFaviconControllerDelegate = delegate
        controller.sumiFaviconScriptsProvider = scriptsProvider
        controller.sumiUsesDDGFaviconUserContentController = true
        return controller
    }
}

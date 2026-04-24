import BrowserServicesKit
import Combine
import Foundation
import ObjectiveC
import PrivacyConfig
import UserScript
import WebKit

@MainActor
final class SumiNormalTabUserScripts {
    let faviconScripts = SumiDDGFaviconUserScripts()
    let additionalWKUserScripts: [WKUserScript]

    init(additionalWKUserScripts: [WKUserScript] = []) {
        self.additionalWKUserScripts = additionalWKUserScripts
    }
}

private struct SumiNormalTabUserContent: UserContentControllerNewContent {
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

private enum SumiNormalTabAssociatedKeys {
    static var scriptsProvider = 0
    static var controllerDelegate = 0
    static var marker = 0
}

extension WKUserContentController {
    fileprivate var sumiNormalTabControllerDelegate: SumiNormalTabUserContentControllerDelegate? {
        get {
            objc_getAssociatedObject(self, &SumiNormalTabAssociatedKeys.controllerDelegate) as? SumiNormalTabUserContentControllerDelegate
        }
        set {
            objc_setAssociatedObject(
                self,
                &SumiNormalTabAssociatedKeys.controllerDelegate,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }

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
}

private final class SumiNormalTabUserContentControllerDelegate: UserContentControllerDelegate {
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
enum SumiNormalTabUserContentControllerFactory {
    static func makeController(
        additionalUserScripts: [WKUserScript] = []
    ) -> UserContentController {
        let scriptsProvider = SumiNormalTabUserScripts(
            additionalWKUserScripts: additionalUserScripts
        )
        let content = SumiNormalTabUserContent(
            sourceProvider: scriptsProvider.faviconScripts
        )
        let delegate = SumiNormalTabUserContentControllerDelegate()
        let controller = UserContentController(
            assetsPublisher: Just(content).eraseToAnyPublisher(),
            privacyConfigurationManager: SumiStaticPrivacyConfigurationManager()
        )
        controller.delegate = delegate
        controller.sumiNormalTabControllerDelegate = delegate
        controller.sumiNormalTabUserScriptsProvider = scriptsProvider
        controller.sumiUsesNormalTabBrowserServicesKitUserContentController = true
        scriptsProvider.additionalWKUserScripts.forEach(controller.addUserScript)
        return controller
    }
}

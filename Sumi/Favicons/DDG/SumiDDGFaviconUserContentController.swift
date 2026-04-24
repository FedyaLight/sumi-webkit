import BrowserServicesKit
import Combine
import Foundation
import ObjectiveC
import PrivacyConfig
import UserScript
import WebKit

@MainActor
final class SumiNormalTabUserScripts: UserScriptsProvider {
    let faviconScripts = SumiDDGFaviconUserScripts()
    private var managedUserScripts: [UserScript]

    init(managedUserScripts: [UserScript] = []) {
        self.managedUserScripts = managedUserScripts
    }

    var userScripts: [UserScript] {
        faviconScripts.userScripts + managedUserScripts
    }

    func replaceManagedUserScripts(_ userScripts: [UserScript]) {
        managedUserScripts = userScripts
    }

    func loadWKUserScripts() async -> [WKUserScript] {
        var scripts: [WKUserScript] = []
        scripts.reserveCapacity(userScripts.count)
        for userScript in userScripts {
            let script = await userScript.makeWKUserScript()
            scripts.append(script.wkUserScript)
        }
        return scripts
    }
}

private struct SumiNormalTabUserContent: UserContentControllerNewContent {
    typealias SourceProvider = SumiNormalTabUserScripts
    typealias UserScripts = SumiNormalTabUserScripts

    let rulesUpdate = ContentBlockerRulesManager.UpdateEvent(
        rules: [],
        changes: [:],
        completionTokens: []
    )
    let sourceProvider: SumiNormalTabUserScripts
    let makeUserScripts: @MainActor (SumiNormalTabUserScripts) -> SumiNormalTabUserScripts = { $0 }
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
        scriptsProvider: SumiNormalTabUserScripts? = nil
    ) -> UserContentController {
        let scriptsProvider = scriptsProvider ?? SumiNormalTabUserScripts()
        let content = SumiNormalTabUserContent(
            sourceProvider: scriptsProvider
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
        return controller
    }
}

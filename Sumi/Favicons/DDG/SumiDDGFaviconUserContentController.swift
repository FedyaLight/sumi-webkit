import BrowserServicesKit
import Combine
import ContentBlocking
import Foundation
import ObjectiveC
import UserScript
import WebKit

@MainActor
final class SumiNormalTabUserScripts: UserScriptsProvider {
    let faviconScripts = SumiDDGFaviconUserScripts()
    private var contentBlockingUserScripts: [SumiUserScript]
    private var managedUserScripts: [SumiUserScript]
    private var bskUserScriptAdapters: [SumiBrowserServicesKitUserScriptAdapter] = []

    init(
        contentBlockingUserScripts: [SumiUserScript] = [],
        managedUserScripts: [SumiUserScript] = []
    ) {
        self.contentBlockingUserScripts = contentBlockingUserScripts
        self.managedUserScripts = managedUserScripts
        self.bskUserScriptAdapters = Self.makeBrowserServicesKitAdapters(
            from: contentBlockingUserScripts + faviconScripts.userScripts + managedUserScripts
        )
    }

    var sumiUserScripts: [SumiUserScript] {
        contentBlockingUserScripts + faviconScripts.userScripts + managedUserScripts
    }

    func replaceManagedUserScripts(_ userScripts: [SumiUserScript]) {
        managedUserScripts = userScripts
        bskUserScriptAdapters = Self.makeBrowserServicesKitAdapters(from: sumiUserScripts)
    }

    var userScripts: [UserScript] {
        bskUserScriptAdapters
    }

    func loadWKUserScripts() async -> [WKUserScript] {
        var scripts: [WKUserScript] = []
        scripts.reserveCapacity(sumiUserScripts.count)
        for userScript in sumiUserScripts {
            scripts.append(SumiUserScriptBuilder.makeWKUserScript(from: userScript))
        }
        return scripts
    }

    private static func makeBrowserServicesKitAdapters(
        from userScripts: [SumiUserScript]
    ) -> [SumiBrowserServicesKitUserScriptAdapter] {
        userScripts.map(SumiBrowserServicesKitUserScriptAdapter.init)
    }
}

private final class SumiBrowserServicesKitUserScriptAdapter: NSObject, UserScript, WKScriptMessageHandlerWithReply {
    private let userScript: SumiUserScript
    let source: String
    let injectionTime: WKUserScriptInjectionTime
    let forMainFrameOnly: Bool
    let requiresRunInPageContentWorld: Bool
    let messageNames: [String]

    @MainActor
    init(_ userScript: SumiUserScript) {
        self.userScript = userScript
        self.source = userScript.source
        self.injectionTime = userScript.injectionTime
        self.forMainFrameOnly = userScript.forMainFrameOnly
        self.requiresRunInPageContentWorld = userScript.requiresRunInPageContentWorld
        self.messageNames = userScript.messageNames
        super.init()
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) async -> (Any?, String?) {
        guard let handler = userScript as? WKScriptMessageHandlerWithReply else {
            await MainActor.run {
                userScript.userContentController(userContentController, didReceive: message)
            }
            return (nil, nil)
        }

        return await handler.userContentController(userContentController, didReceive: message)
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        _ = userContentController
        _ = message
    }
}

struct SumiNormalTabUserContent: UserContentControllerNewContent {
    typealias SourceProvider = SumiNormalTabUserScripts
    typealias UserScripts = SumiNormalTabUserScripts

    let rulesUpdate: ContentBlockerRulesManager.UpdateEvent
    let sourceProvider: SumiNormalTabUserScripts
    let makeUserScripts: @MainActor (SumiNormalTabUserScripts) -> SumiNormalTabUserScripts

    init(
        rulesUpdate: ContentBlockerRulesManager.UpdateEvent,
        sourceProvider: SumiNormalTabUserScripts,
        makeUserScripts: @escaping @MainActor (SumiNormalTabUserScripts) -> SumiNormalTabUserScripts = { $0 }
    ) {
        self.rulesUpdate = rulesUpdate
        self.sourceProvider = sourceProvider
        self.makeUserScripts = makeUserScripts
    }
}

@MainActor
struct SumiNormalTabContentBlockingAssetSource {
    let assetsPublisher: AnyPublisher<SumiNormalTabUserContent, Never>
    let privacyConfigurationManager: SumiContentBlockingPrivacyConfigurationManager

    static func disabledEmpty(
        scriptsProvider: SumiNormalTabUserScripts
    ) -> SumiNormalTabContentBlockingAssetSource {
        SumiNormalTabContentBlockingAssetSource(
            assetsPublisher: Just(
                SumiNormalTabUserContent(
                    rulesUpdate: disabledContentBlockingUpdate(),
                    sourceProvider: scriptsProvider
                )
            )
            .eraseToAnyPublisher(),
            privacyConfigurationManager: SumiContentBlockingPrivacyConfigurationManager(
                isContentBlockingEnabled: false
            )
        )
    }

    static func enabled(
        contentBlockingService: SumiContentBlockingService,
        scriptsProvider: SumiNormalTabUserScripts,
        profileId: UUID?
    ) -> SumiNormalTabContentBlockingAssetSource {
        SumiNormalTabContentBlockingAssetSource(
            assetsPublisher: contentBlockingService.userContentPublisher(
                for: scriptsProvider,
                profileId: profileId
            ),
            privacyConfigurationManager: contentBlockingService.privacyConfigurationManager
        )
    }

    private static func disabledContentBlockingUpdate() -> ContentBlockerRulesManager.UpdateEvent {
        ContentBlockerRulesManager.UpdateEvent(
            rules: [],
            changes: [:],
            completionTokens: []
        )
    }
}

@MainActor
private enum SumiNormalTabAssociatedKeys {
    static var scriptsProvider: UInt8 = 0
    static var controllerDelegate: UInt8 = 0
    static var marker: UInt8 = 0
}

extension WKUserContentController {
    @MainActor
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
        scriptsProvider: SumiNormalTabUserScripts? = nil,
        contentBlockingService: SumiContentBlockingService? = nil,
        profileId: UUID? = nil
    ) -> UserContentController {
        let scriptsProvider = scriptsProvider ?? SumiNormalTabUserScripts()
        let assetSource: SumiNormalTabContentBlockingAssetSource
        if let contentBlockingService {
            assetSource = .enabled(
                contentBlockingService: contentBlockingService,
                scriptsProvider: scriptsProvider,
                profileId: profileId
            )
        } else {
            assetSource = .disabledEmpty(
                scriptsProvider: scriptsProvider
            )
        }

        let delegate = SumiNormalTabUserContentControllerDelegate()
        let controller = UserContentController(
            assetsPublisher: assetSource.assetsPublisher,
            privacyConfigurationManager: assetSource.privacyConfigurationManager
        )
        controller.delegate = delegate
        controller.sumiNormalTabControllerDelegate = delegate
        controller.sumiNormalTabUserScriptsProvider = scriptsProvider
        controller.sumiUsesNormalTabBrowserServicesKitUserContentController = true
        return controller
    }
}

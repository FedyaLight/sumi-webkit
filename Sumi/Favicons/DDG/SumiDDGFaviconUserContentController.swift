import BrowserServicesKit
import Combine
import ContentBlocking
import Foundation
import ObjectiveC
import PrivacyConfig
import UserScript
import WebKit

@MainActor
final class SumiNormalTabUserScripts: UserScriptsProvider {
    let faviconScripts = SumiDDGFaviconUserScripts()
    private var contentBlockingUserScripts: [UserScript]
    private var managedUserScripts: [UserScript]

    init(
        contentBlockingUserScripts: [UserScript] = [],
        managedUserScripts: [UserScript] = []
    ) {
        self.contentBlockingUserScripts = contentBlockingUserScripts
        self.managedUserScripts = managedUserScripts
    }

    var userScripts: [UserScript] {
        contentBlockingUserScripts + faviconScripts.userScripts + managedUserScripts
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
    let privacyConfigurationManager: PrivacyConfigurationManaging

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

private enum SumiNormalTabAssociatedKeys {
    static let scriptsProvider: UInt8 = 0
    static let controllerDelegate: UInt8 = 0
    static let marker: UInt8 = 0

    static var scriptsProviderPointer: UnsafeRawPointer {
        withUnsafePointer(to: scriptsProvider) { UnsafeRawPointer($0) }
    }

    static var controllerDelegatePointer: UnsafeRawPointer {
        withUnsafePointer(to: controllerDelegate) { UnsafeRawPointer($0) }
    }

    static var markerPointer: UnsafeRawPointer {
        withUnsafePointer(to: marker) { UnsafeRawPointer($0) }
    }
}

extension WKUserContentController {
    fileprivate var sumiNormalTabControllerDelegate: SumiNormalTabUserContentControllerDelegate? {
        get {
            objc_getAssociatedObject(self, SumiNormalTabAssociatedKeys.controllerDelegatePointer) as? SumiNormalTabUserContentControllerDelegate
        }
        set {
            objc_setAssociatedObject(
                self,
                SumiNormalTabAssociatedKeys.controllerDelegatePointer,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }

    var sumiNormalTabUserScriptsProvider: SumiNormalTabUserScripts? {
        get {
            objc_getAssociatedObject(self, SumiNormalTabAssociatedKeys.scriptsProviderPointer) as? SumiNormalTabUserScripts
        }
        set {
            objc_setAssociatedObject(
                self,
                SumiNormalTabAssociatedKeys.scriptsProviderPointer,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }

    var sumiUsesNormalTabBrowserServicesKitUserContentController: Bool {
        get {
            (objc_getAssociatedObject(self, SumiNormalTabAssociatedKeys.markerPointer) as? Bool) == true
        }
        set {
            objc_setAssociatedObject(
                self,
                SumiNormalTabAssociatedKeys.markerPointer,
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

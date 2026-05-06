import BrowserServicesKit
import Combine
import ContentBlocking
import Foundation
import ObjectiveC
import UserScript
import WebKit

@MainActor
final class SumiBrowserServicesKitEmptyUserScriptsProvider: UserScriptsProvider {
    var userScripts: [UserScript] {
        []
    }

    func loadWKUserScripts() async -> [WKUserScript] {
        []
    }
}

@MainActor
private enum SumiNormalTabBrowserServicesKitAssociatedKeys {
    static var controllerDelegate: UInt8 = 0
    static var controllerBridge: UInt8 = 0
}

struct SumiNormalTabUserContent: UserContentControllerNewContent {
    typealias SourceProvider = SumiNormalTabUserScripts
    typealias UserScripts = SumiBrowserServicesKitEmptyUserScriptsProvider

    let rulesUpdate: ContentBlockerRulesManager.UpdateEvent
    let sourceProvider: SumiNormalTabUserScripts
    let makeUserScripts: @MainActor (SumiNormalTabUserScripts) -> SumiBrowserServicesKitEmptyUserScriptsProvider

    init(
        rulesUpdate: ContentBlockerRulesManager.UpdateEvent,
        sourceProvider: SumiNormalTabUserScripts,
        makeUserScripts: @escaping @MainActor (SumiNormalTabUserScripts) -> SumiBrowserServicesKitEmptyUserScriptsProvider = { _ in
            SumiBrowserServicesKitEmptyUserScriptsProvider()
        }
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

extension WKUserContentController {
    @MainActor
    fileprivate var sumiNormalTabControllerDelegate: SumiNormalTabUserContentControllerDelegate? {
        get {
            objc_getAssociatedObject(
                self,
                &SumiNormalTabBrowserServicesKitAssociatedKeys.controllerDelegate
            ) as? SumiNormalTabUserContentControllerDelegate
        }
        set {
            objc_setAssociatedObject(
                self,
                &SumiNormalTabBrowserServicesKitAssociatedKeys.controllerDelegate,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }

    @MainActor
    var sumiNormalTabUserContentControllerBridge: SumiNormalTabUserContentControllerBridge? {
        get {
            objc_getAssociatedObject(
                self,
                &SumiNormalTabBrowserServicesKitAssociatedKeys.controllerBridge
            ) as? SumiNormalTabUserContentControllerBridge
        }
        set {
            objc_setAssociatedObject(
                self,
                &SumiNormalTabBrowserServicesKitAssociatedKeys.controllerBridge,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
}

@MainActor
final class SumiNormalTabUserContentControllerBridge: SumiNormalTabUserContentControlling {
    private unowned let controller: UserContentController
    private let messageHandlerRegistry: SumiUserScriptMessageHandlerRegistry

    init(controller: UserContentController) {
        self.controller = controller
        self.messageHandlerRegistry = SumiUserScriptMessageHandlerRegistry(userContentController: controller)
    }

    var wkUserContentController: WKUserContentController {
        controller
    }

    var normalTabUserScriptsProvider: SumiNormalTabUserScripts? {
        controller.sumiNormalTabUserScriptsProvider
    }

    var contentBlockingAssetSummary: SumiNormalTabContentBlockingAssetSummary {
        SumiNormalTabContentBlockingAssetSummary(
            isInstalled: controller.contentBlockingAssetsInstalled,
            globalRuleListCount: controller.contentBlockingAssets?.globalRuleLists.count ?? 0,
            updateRuleCount: controller.contentBlockingAssets?.updateEvent.rules.count ?? 0,
            isContentBlockingFeatureEnabled: controller.privacyConfigurationManager.privacyConfig.isEnabled(featureKey: .contentBlocking)
        )
    }

#if DEBUG
    var contentBlockingAssetSummaryPublisher: AnyPublisher<SumiNormalTabContentBlockingAssetSummary, Never> {
        controller.$contentBlockingAssets
            .compactMap { [weak controller] assets -> SumiNormalTabContentBlockingAssetSummary? in
                guard let controller, let assets else { return nil }
                return SumiNormalTabContentBlockingAssetSummary(
                    isInstalled: true,
                    globalRuleListCount: assets.globalRuleLists.count,
                    updateRuleCount: assets.updateEvent.rules.count,
                    isContentBlockingFeatureEnabled: controller.privacyConfigurationManager.privacyConfig.isEnabled(featureKey: .contentBlocking)
                )
            }
            .eraseToAnyPublisher()
    }
#endif

    func replaceNormalTabUserScripts(with provider: SumiNormalTabUserScripts) async {
        await messageHandlerRegistry.replaceUserScripts(with: provider)
    }

    func waitForContentBlockingAssetsInstalled() async {
        await controller.awaitContentBlockingAssetsInstalled()
        if let provider = normalTabUserScriptsProvider {
            await messageHandlerRegistry.replaceUserScripts(with: provider)
        }
    }

    func cleanUpBeforeClosing() {
        messageHandlerRegistry.cleanUpBeforeClosing()
        controller.cleanUpBeforeClosing()
    }
}

final class SumiNormalTabUserContentControllerDelegate: UserContentControllerDelegate {
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
    ) -> WKUserContentController {
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
        controller.sumiNormalTabUserContentControllerBridge = SumiNormalTabUserContentControllerBridge(controller: controller)
        return controller
    }
}

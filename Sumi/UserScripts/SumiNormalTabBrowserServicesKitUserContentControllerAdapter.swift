import BrowserServicesKit
import Combine
import ContentBlocking
import Foundation
import ObjectiveC
import UserScript
import WebKit

@MainActor
final class SumiBrowserServicesKitNormalTabUserScriptsProvider: UserScriptsProvider {
    unowned let sumiProvider: SumiNormalTabUserScripts
    private var bskUserScriptAdapters: [SumiBrowserServicesKitUserScriptAdapter]
    private var scriptsRevision: Int

    init(sumiProvider: SumiNormalTabUserScripts) {
        self.sumiProvider = sumiProvider
        self.bskUserScriptAdapters = Self.makeBrowserServicesKitAdapters(from: sumiProvider.userScripts)
        self.scriptsRevision = sumiProvider.scriptsRevision
    }

    var userScripts: [UserScript] {
        bskUserScriptAdapters
    }

    func loadWKUserScripts() async -> [WKUserScript] {
        await sumiProvider.loadWKUserScripts()
    }

    func refreshIfNeeded() {
        guard scriptsRevision != sumiProvider.scriptsRevision else { return }
        bskUserScriptAdapters = Self.makeBrowserServicesKitAdapters(from: sumiProvider.userScripts)
        scriptsRevision = sumiProvider.scriptsRevision
    }

    private static func makeBrowserServicesKitAdapters(
        from userScripts: [SumiUserScript]
    ) -> [SumiBrowserServicesKitUserScriptAdapter] {
        userScripts.map(SumiBrowserServicesKitUserScriptAdapter.init)
    }
}

@MainActor
private enum SumiNormalTabBrowserServicesKitAssociatedKeys {
    static var scriptsProviderAdapter: UInt8 = 0
    static var controllerDelegate: UInt8 = 0
}

extension SumiNormalTabUserScripts {
    @MainActor
    fileprivate var browserServicesKitUserScriptsProvider: SumiBrowserServicesKitNormalTabUserScriptsProvider {
        if let provider = objc_getAssociatedObject(
            self,
            &SumiNormalTabBrowserServicesKitAssociatedKeys.scriptsProviderAdapter
        ) as? SumiBrowserServicesKitNormalTabUserScriptsProvider {
            provider.refreshIfNeeded()
            return provider
        }

        let provider = SumiBrowserServicesKitNormalTabUserScriptsProvider(sumiProvider: self)
        objc_setAssociatedObject(
            self,
            &SumiNormalTabBrowserServicesKitAssociatedKeys.scriptsProviderAdapter,
            provider,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        return provider
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
    typealias UserScripts = SumiBrowserServicesKitNormalTabUserScriptsProvider

    let rulesUpdate: ContentBlockerRulesManager.UpdateEvent
    let sourceProvider: SumiNormalTabUserScripts
    let makeUserScripts: @MainActor (SumiNormalTabUserScripts) -> SumiBrowserServicesKitNormalTabUserScriptsProvider

    init(
        rulesUpdate: ContentBlockerRulesManager.UpdateEvent,
        sourceProvider: SumiNormalTabUserScripts,
        makeUserScripts: @escaping @MainActor (SumiNormalTabUserScripts) -> SumiBrowserServicesKitNormalTabUserScriptsProvider = {
            $0.browserServicesKitUserScriptsProvider
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
}

extension UserContentController: SumiNormalTabUserContentControlling {
    var wkUserContentController: WKUserContentController {
        self
    }

    var normalTabUserScriptsProvider: SumiNormalTabUserScripts? {
        sumiNormalTabUserScriptsProvider
    }

    var contentBlockingAssetSummary: SumiNormalTabContentBlockingAssetSummary {
        SumiNormalTabContentBlockingAssetSummary(
            isInstalled: contentBlockingAssetsInstalled,
            globalRuleListCount: contentBlockingAssets?.globalRuleLists.count ?? 0,
            updateRuleCount: contentBlockingAssets?.updateEvent.rules.count ?? 0,
            isContentBlockingFeatureEnabled: privacyConfigurationManager.privacyConfig.isEnabled(featureKey: .contentBlocking)
        )
    }

#if DEBUG
    var contentBlockingAssetSummaryPublisher: AnyPublisher<SumiNormalTabContentBlockingAssetSummary, Never> {
        $contentBlockingAssets
            .compactMap { [weak self] assets -> SumiNormalTabContentBlockingAssetSummary? in
                guard let self, let assets else { return nil }
                return SumiNormalTabContentBlockingAssetSummary(
                    isInstalled: true,
                    globalRuleListCount: assets.globalRuleLists.count,
                    updateRuleCount: assets.updateEvent.rules.count,
                    isContentBlockingFeatureEnabled: self.privacyConfigurationManager.privacyConfig.isEnabled(featureKey: .contentBlocking)
                )
            }
            .eraseToAnyPublisher()
    }
#endif

    func replaceNormalTabUserScripts(with provider: SumiNormalTabUserScripts) async {
        await replaceUserScripts(with: provider.browserServicesKitUserScriptsProvider)
    }

    func waitForContentBlockingAssetsInstalled() async {
        await awaitContentBlockingAssetsInstalled()
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
        return controller
    }
}

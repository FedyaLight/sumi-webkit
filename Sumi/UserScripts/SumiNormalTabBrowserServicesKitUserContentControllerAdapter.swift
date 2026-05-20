import Combine
import Foundation
import WebKit

struct SumiNormalTabContentBlockingUpdate {
    let globalRuleLists: [String: WKContentRuleList]
    let updateRuleCount: Int
    let lookupSucceededIdentifiers: [String]
    let lookupFailedIdentifiers: [String]
    let ruleListLookupDuration: TimeInterval?

    static let empty = SumiNormalTabContentBlockingUpdate(
        globalRuleLists: [:],
        updateRuleCount: 0,
        lookupSucceededIdentifiers: [],
        lookupFailedIdentifiers: [],
        ruleListLookupDuration: nil
    )
}

struct SumiNormalTabUserContent {
    let contentBlockingUpdate: SumiNormalTabContentBlockingUpdate
    let sourceProvider: SumiNormalTabUserScripts
}

@MainActor
struct SumiNormalTabContentBlockingAssetSource {
    let assetsPublisher: AnyPublisher<SumiNormalTabUserContent, Never>
    let initialContent: SumiNormalTabUserContent?
    let privacyConfigurationManager: SumiContentBlockingPrivacyConfigurationManager
    let retainedContentBlockingServices: [SumiContentBlockingService]

    static func disabledEmpty(
        scriptsProvider: SumiNormalTabUserScripts
    ) -> SumiNormalTabContentBlockingAssetSource {
        let content = SumiNormalTabUserContent(
            contentBlockingUpdate: .empty,
            sourceProvider: scriptsProvider
        )
        return SumiNormalTabContentBlockingAssetSource(
            assetsPublisher: Empty().eraseToAnyPublisher(),
            initialContent: content,
            privacyConfigurationManager: SumiContentBlockingPrivacyConfigurationManager(
                isContentBlockingEnabled: false
            ),
            retainedContentBlockingServices: []
        )
    }

    static func enabled(
        contentBlockingServices: [SumiContentBlockingService],
        scriptsProvider: SumiNormalTabUserScripts,
        profileId: UUID?
    ) -> SumiNormalTabContentBlockingAssetSource {
        let publishers = contentBlockingServices.map {
            $0.userContentPublisher(
                for: scriptsProvider,
                profileId: profileId
            )
        }
        let privacyConfigurationManager = contentBlockingServices.count == 1
            ? contentBlockingServices[0].privacyConfigurationManager
            : SumiContentBlockingPrivacyConfigurationManager(
                isContentBlockingEnabled: true
            )
        return SumiNormalTabContentBlockingAssetSource(
            assetsPublisher: Self.combinedAssetsPublisher(publishers),
            initialContent: Self.initialContent(
                from: contentBlockingServices,
                scriptsProvider: scriptsProvider
            ),
            privacyConfigurationManager: privacyConfigurationManager,
            retainedContentBlockingServices: contentBlockingServices
        )
    }

    private static func initialContent(
        from services: [SumiContentBlockingService],
        scriptsProvider: SumiNormalTabUserScripts
    ) -> SumiNormalTabUserContent? {
        guard !services.isEmpty else { return nil }
        let updates = services.compactMap(\.latestUpdate)
        guard updates.count == services.count else { return nil }

        return SumiNormalTabUserContent(
            contentBlockingUpdate: combinedUpdate(updates),
            sourceProvider: scriptsProvider
        )
    }

    private static func combinedUpdate(
        _ updates: [SumiContentBlockerRulesUpdate]
    ) -> SumiNormalTabContentBlockingUpdate {
        var globalRuleLists = [String: WKContentRuleList]()
        var updateRuleCount = 0
        var lookupSucceededIdentifiers = Set<String>()
        var lookupFailedIdentifiers = Set<String>()
        var ruleListLookupDuration: TimeInterval?

        for update in updates {
            updateRuleCount += update.rules.count
            for rules in update.rules {
                globalRuleLists[rules.storeIdentifier] = rules.rulesList
            }
            lookupSucceededIdentifiers.formUnion(update.lookupSucceededIdentifiers)
            lookupFailedIdentifiers.formUnion(update.lookupFailedIdentifiers)
            ruleListLookupDuration = combinedDuration(
                ruleListLookupDuration,
                update.ruleListLookupDuration
            )
        }

        return SumiNormalTabContentBlockingUpdate(
            globalRuleLists: globalRuleLists,
            updateRuleCount: updateRuleCount,
            lookupSucceededIdentifiers: lookupSucceededIdentifiers.sorted(),
            lookupFailedIdentifiers: lookupFailedIdentifiers.sorted(),
            ruleListLookupDuration: ruleListLookupDuration
        )
    }

    private static func combinedAssetsPublisher(
        _ publishers: [AnyPublisher<SumiNormalTabUserContent, Never>]
    ) -> AnyPublisher<SumiNormalTabUserContent, Never> {
        guard let first = publishers.first else {
            return Empty().eraseToAnyPublisher()
        }
        return publishers.dropFirst().reduce(first) { combined, next in
            combined.combineLatest(next)
                .map { lhs, rhs in
                    SumiNormalTabUserContent(
                        contentBlockingUpdate: SumiNormalTabContentBlockingUpdate(
                            globalRuleLists: lhs.contentBlockingUpdate.globalRuleLists.merging(
                                rhs.contentBlockingUpdate.globalRuleLists
                            ) { _, rhs in rhs },
                            updateRuleCount: lhs.contentBlockingUpdate.updateRuleCount
                                + rhs.contentBlockingUpdate.updateRuleCount,
                            lookupSucceededIdentifiers: Array(Set(
                                lhs.contentBlockingUpdate.lookupSucceededIdentifiers
                                + rhs.contentBlockingUpdate.lookupSucceededIdentifiers
                            )).sorted(),
                            lookupFailedIdentifiers: Array(Set(
                                lhs.contentBlockingUpdate.lookupFailedIdentifiers
                                + rhs.contentBlockingUpdate.lookupFailedIdentifiers
                            )).sorted(),
                            ruleListLookupDuration: Self.combinedDuration(
                                lhs.contentBlockingUpdate.ruleListLookupDuration,
                                rhs.contentBlockingUpdate.ruleListLookupDuration
                            )
                        ),
                        sourceProvider: lhs.sourceProvider
                    )
                }
                .eraseToAnyPublisher()
        }
    }

    private static func combinedDuration(
        _ lhs: TimeInterval?,
        _ rhs: TimeInterval?
    ) -> TimeInterval? {
        switch (lhs, rhs) {
        case (.none, .none):
            return nil
        case (.some(let lhs), .none):
            return lhs
        case (.none, .some(let rhs)):
            return rhs
        case (.some(let lhs), .some(let rhs)):
            return lhs + rhs
        }
    }
}

@MainActor
final class SumiNormalTabUserContentController: WKUserContentController, SumiNormalTabUserContentControlling {
    private struct ContentBlockingAssets {
        let globalRuleLists: [String: WKContentRuleList]
        let updateRuleCount: Int
        let isContentBlockingFeatureEnabled: Bool
        let lookupSucceededIdentifiers: [String]
        let lookupFailedIdentifiers: [String]
        let addedToUserContentControllerIdentifiers: [String]
        let ruleListLookupDuration: TimeInterval?
        let tabAttachmentDuration: TimeInterval?
    }

    private let privacyConfigurationManager: SumiContentBlockingPrivacyConfigurationManager
    private let retainedContentBlockingServices: [SumiContentBlockingService]
    private lazy var messageHandlerRegistry = SumiUserScriptMessageHandlerRegistry(userContentController: self)
    private var globalContentRuleLists = [String: WKContentRuleList]()
    private var assetsPublisherCancellable: AnyCancellable?
    private var assetWaiters = [UUID: CheckedContinuation<Void, Never>]()
    private var isCleanedUp = false

    @Published private var contentBlockingAssets: ContentBlockingAssets?

    init(assetSource: SumiNormalTabContentBlockingAssetSource) {
        privacyConfigurationManager = assetSource.privacyConfigurationManager
        retainedContentBlockingServices = assetSource.retainedContentBlockingServices
        super.init()

        if let initialContent = assetSource.initialContent {
            installContentBlockingUpdate(initialContent.contentBlockingUpdate)
        }

        assetsPublisherCancellable = assetSource.assetsPublisher.sink { [weak self] content in
            Task { @MainActor [weak self] in
                self?.installContentBlockingUpdate(content.contentBlockingUpdate)
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var wkUserContentController: WKUserContentController {
        self
    }

    var normalTabUserScriptsProvider: SumiNormalTabUserScripts? {
        sumiNormalTabUserScriptsProvider
    }

    var contentBlockingAssetSummary: SumiNormalTabContentBlockingAssetSummary {
        guard let contentBlockingAssets else {
            return SumiNormalTabContentBlockingAssetSummary(
                isInstalled: false,
                globalRuleListCount: 0,
                updateRuleCount: 0,
                isContentBlockingFeatureEnabled: isContentBlockingFeatureEnabled,
                globalRuleListIdentifiers: [],
                lookupSucceededIdentifiers: [],
                lookupFailedIdentifiers: [],
                addedToUserContentControllerIdentifiers: [],
                ruleListLookupDuration: nil,
                tabAttachmentDuration: nil
            )
        }

        return SumiNormalTabContentBlockingAssetSummary(
            isInstalled: true,
            globalRuleListCount: contentBlockingAssets.globalRuleLists.count,
            updateRuleCount: contentBlockingAssets.updateRuleCount,
            isContentBlockingFeatureEnabled: isContentBlockingFeatureEnabled,
            globalRuleListIdentifiers: Array(contentBlockingAssets.globalRuleLists.keys),
            lookupSucceededIdentifiers: contentBlockingAssets.lookupSucceededIdentifiers,
            lookupFailedIdentifiers: contentBlockingAssets.lookupFailedIdentifiers,
            addedToUserContentControllerIdentifiers: contentBlockingAssets.addedToUserContentControllerIdentifiers,
            ruleListLookupDuration: contentBlockingAssets.ruleListLookupDuration,
            tabAttachmentDuration: contentBlockingAssets.tabAttachmentDuration
        )
    }

#if DEBUG
    var contentBlockingAssetSummaryPublisher: AnyPublisher<SumiNormalTabContentBlockingAssetSummary, Never> {
        $contentBlockingAssets
            .compactMap { assets -> SumiNormalTabContentBlockingAssetSummary? in
                guard let assets else { return nil }
                return SumiNormalTabContentBlockingAssetSummary(
                    isInstalled: true,
                    globalRuleListCount: assets.globalRuleLists.count,
                    updateRuleCount: assets.updateRuleCount,
                    isContentBlockingFeatureEnabled: assets.isContentBlockingFeatureEnabled,
                    globalRuleListIdentifiers: Array(assets.globalRuleLists.keys),
                    lookupSucceededIdentifiers: assets.lookupSucceededIdentifiers,
                    lookupFailedIdentifiers: assets.lookupFailedIdentifiers,
                    addedToUserContentControllerIdentifiers: assets.addedToUserContentControllerIdentifiers,
                    ruleListLookupDuration: assets.ruleListLookupDuration,
                    tabAttachmentDuration: assets.tabAttachmentDuration
                )
            }
            .eraseToAnyPublisher()
    }
#endif

    func replaceNormalTabUserScripts(with provider: SumiNormalTabUserScripts) async {
        await messageHandlerRegistry.replaceUserScripts(with: provider)
    }

    func waitForContentBlockingAssetsInstalled() async {
        await awaitContentBlockingAssetsInstalled()
        if let provider = normalTabUserScriptsProvider {
            await messageHandlerRegistry.replaceUserScripts(with: provider)
        }
    }

    func cleanUpBeforeClosing() {
        guard !isCleanedUp else { return }

        isCleanedUp = true
        assetsPublisherCancellable?.cancel()
        assetsPublisherCancellable = nil
        messageHandlerRegistry.cleanUpBeforeClosing()
        removeAllUserScripts()
        removeAllContentRuleLists()
    }

    override func removeAllContentRuleLists() {
        globalContentRuleLists.removeAll(keepingCapacity: true)
        super.removeAllContentRuleLists()
    }

    private var isContentBlockingFeatureEnabled: Bool {
        privacyConfigurationManager.sumiPrivacyConfig.isEnabled(featureKey: .contentBlocking)
    }

    private func installContentBlockingUpdate(_ update: SumiNormalTabContentBlockingUpdate) {
        guard !isCleanedUp else { return }

        let startupTrace = StartupPerformanceTrace.firstContentBlockingAttachStarted()
        defer {
            StartupPerformanceTrace.firstContentBlockingAttachFinished(startupTrace)
        }

        let isContentBlockingFeatureEnabled = isContentBlockingFeatureEnabled
        if hasInstalledEquivalentUpdate(
            update,
            isContentBlockingFeatureEnabled: isContentBlockingFeatureEnabled
        ) {
            resumeAssetWaiters()
            return
        }

        let start = Date()
        let hadAttachedRuleLists = !globalContentRuleLists.isEmpty
        removeAllContentRuleLists()

        var addedIdentifiers = [String]()
        if isContentBlockingFeatureEnabled {
            for (identifier, ruleList) in update.globalRuleLists.sorted(by: { $0.key < $1.key }) {
                add(ruleList)
                globalContentRuleLists[identifier] = ruleList
                addedIdentifiers.append(identifier)
            }
        }
        let didTouchRuleLists = hadAttachedRuleLists || !addedIdentifiers.isEmpty
        contentBlockingAssets = ContentBlockingAssets(
            globalRuleLists: globalContentRuleLists,
            updateRuleCount: update.updateRuleCount,
            isContentBlockingFeatureEnabled: isContentBlockingFeatureEnabled,
            lookupSucceededIdentifiers: update.lookupSucceededIdentifiers,
            lookupFailedIdentifiers: update.lookupFailedIdentifiers,
            addedToUserContentControllerIdentifiers: addedIdentifiers,
            ruleListLookupDuration: update.ruleListLookupDuration,
            tabAttachmentDuration: didTouchRuleLists ? Date().timeIntervalSince(start) : nil
        )
        resumeAssetWaiters()
    }

    private func hasInstalledEquivalentUpdate(
        _ update: SumiNormalTabContentBlockingUpdate,
        isContentBlockingFeatureEnabled: Bool
    ) -> Bool {
        guard let contentBlockingAssets else { return false }
        return contentBlockingAssets.isContentBlockingFeatureEnabled == isContentBlockingFeatureEnabled
            && Set(contentBlockingAssets.globalRuleLists.keys) == Set(update.globalRuleLists.keys)
            && contentBlockingAssets.updateRuleCount == update.updateRuleCount
            && contentBlockingAssets.lookupSucceededIdentifiers == update.lookupSucceededIdentifiers.sorted()
            && contentBlockingAssets.lookupFailedIdentifiers == update.lookupFailedIdentifiers.sorted()
    }

    private func awaitContentBlockingAssetsInstalled() async {
        guard contentBlockingAssets == nil else { return }

        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if contentBlockingAssets != nil {
                    continuation.resume()
                } else {
                    assetWaiters[id] = continuation
                }
            }
        } onCancel: { [weak self, id] in
            Task { @MainActor [weak self, id] in
                self?.resumeAssetWaiter(id)
            }
        }
    }

    private func resumeAssetWaiter(_ id: UUID) {
        guard let waiter = assetWaiters.removeValue(forKey: id) else { return }
        waiter.resume()
    }

    private func resumeAssetWaiters() {
        let waiters = assetWaiters.values
        assetWaiters.removeAll(keepingCapacity: true)
        waiters.forEach { $0.resume() }
    }
}

@MainActor
enum SumiNormalTabUserContentControllerFactory {
    static func makeController(
        scriptsProvider: SumiNormalTabUserScripts? = nil,
        contentBlockingService: SumiContentBlockingService? = nil,
        contentBlockingServices: [SumiContentBlockingService] = [],
        profileId: UUID? = nil
    ) -> WKUserContentController {
        let scriptsProvider = scriptsProvider ?? SumiNormalTabUserScripts()
        let services = ([contentBlockingService].compactMap { $0 } + contentBlockingServices)
        let assetSource: SumiNormalTabContentBlockingAssetSource
        if !services.isEmpty {
            assetSource = .enabled(
                contentBlockingServices: services,
                scriptsProvider: scriptsProvider,
                profileId: profileId
            )
        } else {
            assetSource = .disabledEmpty(
                scriptsProvider: scriptsProvider
            )
        }

        let controller = SumiNormalTabUserContentController(assetSource: assetSource)
        controller.sumiNormalTabUserScriptsProvider = scriptsProvider
        controller.sumiUsesNormalTabSumiUserContentController = true
        return controller
    }
}

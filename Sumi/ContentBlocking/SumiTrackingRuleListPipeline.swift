import Combine
import Foundation
import TrackerRadarKit

struct SumiTrackingRuleListSet: Equatable, Sendable {
    let trackerDataSet: [SumiContentRuleListDefinition]
    let siteDataCookieBlocking: [SumiContentRuleListDefinition]

    init(
        trackerDataSet: [SumiContentRuleListDefinition] = [],
        siteDataCookieBlocking: [SumiContentRuleListDefinition] = []
    ) {
        self.trackerDataSet = trackerDataSet
        self.siteDataCookieBlocking = siteDataCookieBlocking
    }

    var allDefinitions: [SumiContentRuleListDefinition] {
        trackerDataSet + siteDataCookieBlocking
    }
}

@MainActor
protocol SumiContentRuleListSetProviding: AnyObject {
    var changesPublisher: AnyPublisher<Void, Never> { get }
    var hasProfileSpecificRuleLists: Bool { get }

    func ruleListSet(profileId: UUID?) throws -> SumiTrackingRuleListSet
}

@MainActor
final class SumiTrackingRuleListProvider: SumiContentRuleListSetProviding {
    private let settings: SumiTrackingProtectionSettings
    private let dataStore: SumiTrackingProtectionDataStore
    private let trackingRuleSource: SumiTrackingProtectionRuleProviding
    private let siteDataPolicyStore: SumiSiteDataPolicyStore?
    private let siteDataRuleSource: SumiSiteDataContentRuleProviding?

    init(
        settings: SumiTrackingProtectionSettings,
        dataStore: SumiTrackingProtectionDataStore,
        trackingRuleSource: SumiTrackingProtectionRuleProviding? = nil,
        siteDataPolicyStore: SumiSiteDataPolicyStore? = nil,
        siteDataRuleSource: SumiSiteDataContentRuleProviding? = nil
    ) {
        self.settings = settings
        self.dataStore = dataStore
        self.trackingRuleSource = trackingRuleSource
            ?? SumiEmbeddedDDGTrackerDataRuleSource(dataStore: dataStore)

        if let siteDataRuleSource {
            self.siteDataPolicyStore = siteDataPolicyStore
            self.siteDataRuleSource = siteDataRuleSource
        } else if let siteDataPolicyStore {
            self.siteDataPolicyStore = siteDataPolicyStore
            self.siteDataRuleSource = SumiSiteDataCookieBlockingRuleSource(
                policyStore: siteDataPolicyStore
            )
        } else {
            self.siteDataPolicyStore = nil
            self.siteDataRuleSource = nil
        }
    }

    var changesPublisher: AnyPublisher<Void, Never> {
        let siteDataChanges = siteDataPolicyStore?.changesPublisher
            ?? Empty().eraseToAnyPublisher()
        return Publishers.Merge3(
            settings.changesPublisher,
            dataStore.changesPublisher,
            siteDataChanges
        )
        .eraseToAnyPublisher()
    }

    var hasProfileSpecificRuleLists: Bool {
        siteDataRuleSource != nil
    }

    func ruleListSet(profileId: UUID?) throws -> SumiTrackingRuleListSet {
        try ruleListSet(for: settings.policy, profileId: profileId)
    }

    func ruleListSet(
        for policy: SumiTrackingProtectionPolicy,
        profileId: UUID?
    ) throws -> SumiTrackingRuleListSet {
        let trackerDataSet = policy.isFullyDisabled
            ? []
            : try trackingRuleSource.ruleLists(for: policy)
        let siteDataCookieBlocking = try siteDataRuleSource?.ruleLists(
            profileId: profileId
        ) ?? []

        return SumiTrackingRuleListSet(
            trackerDataSet: trackerDataSet,
            siteDataCookieBlocking: siteDataCookieBlocking
        )
    }

    func stagedRuleListSet(
        for policy: SumiTrackingProtectionPolicy,
        trackerData: TrackerData,
        profileId: UUID?
    ) throws -> SumiTrackingRuleListSet {
        let trackerDataSet = try trackingRuleLists(
            for: policy,
            trackerData: trackerData
        )
        let siteDataCookieBlocking = try siteDataRuleSource?.ruleLists(
            profileId: profileId
        ) ?? []

        return SumiTrackingRuleListSet(
            trackerDataSet: trackerDataSet,
            siteDataCookieBlocking: siteDataCookieBlocking
        )
    }

    func validationRuleLists(
        for policy: SumiTrackingProtectionPolicy,
        trackerData: TrackerData
    ) throws -> [SumiContentRuleListDefinition] {
        try trackingRuleLists(for: policy, trackerData: trackerData)
    }

    private func trackingRuleLists(
        for policy: SumiTrackingProtectionPolicy,
        trackerData: TrackerData
    ) throws -> [SumiContentRuleListDefinition] {
        try SumiEmbeddedDDGTrackerDataRuleSource.ruleLists(
            for: policy,
            trackerData: trackerData
        )
    }
}

@MainActor
final class SumiTrackingContentBlockingAssets {
    let ruleListProvider: SumiTrackingRuleListProvider
    let contentBlockingService: SumiContentBlockingService

    init(
        ruleListProvider: SumiTrackingRuleListProvider,
        compiler: SumiContentRuleListCompiling = SumiWKContentRuleListCompiler()
    ) {
        self.ruleListProvider = ruleListProvider
        self.contentBlockingService = SumiContentBlockingService(
            policy: .disabled,
            compiler: compiler,
            ruleListProvider: ruleListProvider
        )
    }

    init(
        ruleListProvider: SumiTrackingRuleListProvider,
        contentBlockingService: SumiContentBlockingService
    ) {
        self.ruleListProvider = ruleListProvider
        self.contentBlockingService = contentBlockingService
    }

    func prepareManualTrackingDataUpdate(
        dataSet: SumiTrackerDataSet,
        activePolicy: SumiTrackingProtectionPolicy,
        validationPolicy: SumiTrackingProtectionPolicy
    ) async throws -> SumiPreparedContentBlockingUpdate {
        let validationRuleLists = try ruleListProvider.validationRuleLists(
            for: validationPolicy,
            trackerData: dataSet.trackerData
        )
        try await contentBlockingService.validateRuleLists(validationRuleLists)

        let activeRuleListSet = try ruleListProvider.stagedRuleListSet(
            for: activePolicy,
            trackerData: dataSet.trackerData,
            profileId: nil
        )
        return try await contentBlockingService.prepareRuleListUpdate(
            ruleLists: activeRuleListSet.allDefinitions
        )
    }

    func commitPreparedManualTrackingDataUpdate(
        _ preparedUpdate: SumiPreparedContentBlockingUpdate
    ) {
        contentBlockingService.commitPreparedContentBlockingUpdate(preparedUpdate)
    }
}

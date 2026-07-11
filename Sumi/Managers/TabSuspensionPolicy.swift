import Foundation

struct TabSuspensionPolicy: Equatable {
    static let moderateProactiveDeactivationDelay: TimeInterval = 6 * 60 * 60
    static let balancedProactiveDeactivationDelay: TimeInterval = 4 * 60 * 60
    static let maximumProactiveDeactivationDelay: TimeInterval = 2 * 60 * 60
    static let moderateRevisitProtectionLimit = 5
    static let balancedRevisitProtectionLimit = 15
    static let maximumRevisitProtectionLimit = 15
    static let customRevisitProtectionLimit = 15
    static let recentlyAudibleProtectionInterval: TimeInterval = 60

    let memoryMode: SumiMemoryMode
    let proactiveDeactivationDelay: TimeInterval
    let revisitProtectionLimit: Int

    @MainActor
    init(settings: SumiSettingsService?) {
        self.init(
            memoryMode: settings?.memoryMode ?? .balanced,
            customDeactivationDelay: settings?.memorySaverCustomDeactivationDelay
                ?? SumiMemorySaverCustomDelay.defaultDelay,
            energySaverActive: settings?
                .energySaverApplies(.deactivateInactiveTabsSooner) ?? false
        )
    }

    init(
        memoryMode: SumiMemoryMode,
        customDeactivationDelay: TimeInterval = SumiMemorySaverCustomDelay.defaultDelay,
        energySaverActive: Bool = false
    ) {
        let proactiveDeactivationDelay: TimeInterval
        let revisitProtectionLimit: Int
        switch memoryMode {
        case .moderate:
            proactiveDeactivationDelay = Self.moderateProactiveDeactivationDelay
            revisitProtectionLimit = Self.moderateRevisitProtectionLimit
        case .balanced:
            proactiveDeactivationDelay = Self.balancedProactiveDeactivationDelay
            revisitProtectionLimit = Self.balancedRevisitProtectionLimit
        case .maximum:
            proactiveDeactivationDelay = Self.maximumProactiveDeactivationDelay
            revisitProtectionLimit = Self.maximumRevisitProtectionLimit
        case .custom:
            proactiveDeactivationDelay = SumiMemorySaverCustomDelay.clamped(customDeactivationDelay)
            revisitProtectionLimit = Self.customRevisitProtectionLimit
        }

        self.memoryMode = memoryMode
        self.proactiveDeactivationDelay = energySaverActive
            ? min(
                proactiveDeactivationDelay,
                SumiEnergySaverPolicy.maximumInactiveTabDeactivationDelay
            )
            : proactiveDeactivationDelay
        self.revisitProtectionLimit = revisitProtectionLimit
    }
}

struct TabSuspensionEvaluationContext: Equatable {
    let visibleTabIDs: Set<UUID>
    let selectedTabIDs: Set<UUID>
    let policy: TabSuspensionPolicy
}

enum TabSuspensionEligibility: Equatable {
    case eligible
    case ineligible(reason: Reason)

    enum Reason: Equatable {
        case selected
        case visible
        case loading
        case playingAudio
        case recentlyAudible
        case cameraCapture
        case microphoneCapture
        case fullscreen
        case pictureInPicture
        case pdfDocument
        case unsupportedURLScheme
        case pageVeto
        case noLiveWebView
        case alreadySuspended
        case popupHost
        case noPrimaryWebView
        case compositorProtected
        case documentEvidencePending
    }

    var isEligible: Bool {
        self == .eligible
    }
}

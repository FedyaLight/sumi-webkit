//
//  SumiUpdaterService.swift
//  Sumi
//

import Foundation

enum SumiUpdateChannel: String, CaseIterable, Equatable, Sendable {
    case alpha
    case stable

    var displayName: String {
        switch self {
        case .alpha:
            return "Alpha"
        case .stable:
            return "Stable"
        }
    }

    static func resolve(infoDictionary: [String: Any]) -> SumiUpdateChannel {
        guard let rawValue = infoDictionary["SumiReleaseChannel"] as? String else {
            return .stable
        }
        return SumiUpdateChannel(rawValue: rawValue) ?? .stable
    }

    static func resolve(bundle: Bundle = .main) -> SumiUpdateChannel {
        resolve(infoDictionary: bundle.infoDictionary ?? [:])
    }
}

enum SumiUpdateReleaseNotesURL {
    static let baseURL = URL(string: "https://sumi-browser.netlify.app/changelog/")!

    static func url(forDisplayVersion displayVersion: String) -> URL {
        guard !displayVersion.isEmpty, displayVersion != "Unknown" else {
            return baseURL
        }

        var components = URLComponents(
            url: baseURL,
            resolvingAgainstBaseURL: false
        )
        components?.fragment = displayVersion
        return components?.url ?? baseURL
    }
}

enum SumiExternalLinks {
    static let support = URL(string: "https://sumi-browser.netlify.app/support/")!
    static let issues = URL(string: "https://github.com/FedyaLight/sumi-webkit/issues")!
}

struct SumiAvailableUpdate: Equatable, Sendable {
    let displayVersion: String
    let buildVersion: String
    let title: String?
    let subtitle: String?
    let releaseNotesURL: URL?
    let isInformationOnly: Bool

    var noticeIdentifier: SumiUpdateNoticeIdentifier {
        SumiUpdateNoticeIdentifier(displayVersion: displayVersion, buildVersion: buildVersion)
    }

    var versionLine: String {
        "Sumi \(displayVersion)"
    }
}

struct SumiInstalledUpdate: Equatable, Sendable {
    let displayVersion: String
    let buildVersion: String

    var noticeIdentifier: SumiUpdateNoticeIdentifier {
        SumiUpdateNoticeIdentifier(displayVersion: displayVersion, buildVersion: buildVersion)
    }

    var versionLine: String {
        "Sumi \(displayVersion)"
    }
}

enum SumiUpdateAvailability: Equatable, Sendable {
    case none
    case available(SumiAvailableUpdate)
}

struct SumiUpdateOperationNotice: Equatable, Sendable {
    enum Stage: Equatable, Sendable {
        case checking
        case downloading
        case extracting
        case installing
        case readyToInstall
        case failed
    }

    let stage: Stage
    let title: String
    let detail: String
    let progress: Double?
}

struct SumiUpdateState: Equatable, Sendable {
    var channel: SumiUpdateChannel
    var availability: SumiUpdateAvailability
    var canCheckForUpdates: Bool
    var automaticallyChecksForUpdates: Bool
    var lastCheckedAt: Date?
    var isCheckingForUpdates: Bool
    var feedURL: URL?
    var isSparkleAvailable: Bool
    var isConfigured: Bool
    var diagnosticMessage: String?

    static func initial(channel: SumiUpdateChannel) -> SumiUpdateState {
        SumiUpdateState(
            channel: channel,
            availability: .none,
            canCheckForUpdates: false,
            automaticallyChecksForUpdates: false,
            lastCheckedAt: nil,
            isCheckingForUpdates: false,
            feedURL: nil,
            isSparkleAvailable: false,
            isConfigured: false,
            diagnosticMessage: nil
        )
    }
}

struct SumiUpdateNoticeIdentifier: RawRepresentable, Equatable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(displayVersion: String, buildVersion: String) {
        rawValue = "\(displayVersion)|\(buildVersion)"
    }

    var versionComponents: (displayVersion: String, buildVersion: String)? {
        let parts = rawValue.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        return (String(parts[0]), String(parts[1]))
    }
}

enum SumiUpdateVersionComparator {
    static func isNewer(
        current: SumiUpdateNoticeIdentifier,
        than previous: SumiUpdateNoticeIdentifier
    ) -> Bool {
        guard let currentComponents = current.versionComponents,
              let previousComponents = previous.versionComponents
        else {
            return current != previous
        }

        let versionOrder = compare(currentComponents.displayVersion, previousComponents.displayVersion)
        if versionOrder != .orderedSame {
            return versionOrder == .orderedDescending
        }

        return compare(currentComponents.buildVersion, previousComponents.buildVersion) == .orderedDescending
    }

    private static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        lhs.compare(rhs, options: [.numeric, .caseInsensitive])
    }
}

enum SumiUpdateSidebarProgressNotice: Equatable, Sendable {
    case available(SumiAvailableUpdate)
    case operation(SumiUpdateOperationNotice)

    var title: String {
        "New Sumi Version Available"
    }

    var sidebarActionTitle: String {
        switch self {
        case .available:
            return "Restart and Update"
        case .operation(let notice):
            switch notice.stage {
            case .checking:
                return "Checking for Update…"
            case .downloading:
                return percentageTitle(progress: notice.progress)
            case .extracting, .readyToInstall, .installing:
                return "Installing…"
            case .failed:
                return "Update Failed"
            }
        }
    }

    var sidebarActionAccessibilityLabel: String {
        switch self {
        case .operation(let notice) where notice.stage == .failed:
            return "\(sidebarActionTitle). \(notice.detail)"
        default:
            return sidebarActionTitle
        }
    }

    var showsPersistentStatus: Bool {
        switch self {
        case .available:
            return false
        case .operation:
            return true
        }
    }

    var primaryActionTitle: String? {
        switch self {
        case .available:
            return "Restart and Update"
        case .operation:
            return nil
        }
    }

    var isDismissible: Bool {
        switch self {
        case .available:
            return true
        case .operation(let notice):
            return notice.stage == .failed
        }
    }

    private func percentageTitle(progress: Double?) -> String {
        let progress = progress ?? 0
        let percentage = Int((min(max(progress, 0), 1) * 100).rounded(.down))
        return "\(percentage)%"
    }

}

enum SumiUpdateSidebarNotice: Equatable, Sendable {
    case progress(SumiUpdateSidebarProgressNotice)
    case installed(SumiInstalledUpdate)
}

protocol SumiUpdateNoticeDismissalPersisting: AnyObject {
    func dismissedNoticeIdentifier() -> SumiUpdateNoticeIdentifier?
    func dismissNotice(identifier: SumiUpdateNoticeIdentifier)
    func dismissedInstalledNoticeIdentifier() -> SumiUpdateNoticeIdentifier?
    func dismissInstalledNotice(identifier: SumiUpdateNoticeIdentifier)
}

final class SumiUpdateNoticeDismissalStore: SumiUpdateNoticeDismissalPersisting {
    private let userDefaults: UserDefaults
    private let key: String
    private let installedKey: String

    init(
        userDefaults: UserDefaults = .standard,
        key: String = "updates.sidebar.dismissedNoticeIdentifier",
        installedKey: String = "updates.sidebar.dismissedInstalledNoticeIdentifier"
    ) {
        self.userDefaults = userDefaults
        self.key = key
        self.installedKey = installedKey
    }

    func dismissedNoticeIdentifier() -> SumiUpdateNoticeIdentifier? {
        userDefaults.string(forKey: key).map(SumiUpdateNoticeIdentifier.init(rawValue:))
    }

    func dismissNotice(identifier: SumiUpdateNoticeIdentifier) {
        userDefaults.set(identifier.rawValue, forKey: key)
    }

    func dismissedInstalledNoticeIdentifier() -> SumiUpdateNoticeIdentifier? {
        userDefaults.string(forKey: installedKey).map(SumiUpdateNoticeIdentifier.init(rawValue:))
    }

    func dismissInstalledNotice(identifier: SumiUpdateNoticeIdentifier) {
        userDefaults.set(identifier.rawValue, forKey: installedKey)
    }
}

enum SumiUpdateNoticeVisibilityResolver {
    static func sidebarNotice(
        availability: SumiUpdateAvailability,
        operationNotice: SumiUpdateOperationNotice?,
        installedUpdate: SumiInstalledUpdate?,
        dismissalStore: SumiUpdateNoticeDismissalPersisting
    ) -> SumiUpdateSidebarNotice? {
        if let operationNotice {
            return .progress(.operation(operationNotice))
        }

        guard case .available(let update) = availability else {
            guard let installedUpdate else { return nil }
            guard dismissalStore.dismissedInstalledNoticeIdentifier() != installedUpdate.noticeIdentifier else {
                return nil
            }
            return .installed(installedUpdate)
        }
        guard dismissalStore.dismissedNoticeIdentifier() != update.noticeIdentifier else {
            return nil
        }
        return .progress(.available(update))
    }
}

protocol SumiInstalledUpdateNoticePersisting {
    func consumeInstalledUpdateNotice(current: SumiAppVersionMetadata) -> SumiInstalledUpdate?
}

final class SumiInstalledUpdateNoticeStore: SumiInstalledUpdateNoticePersisting {
    private let userDefaults: UserDefaults
    private let key: String

    init(
        userDefaults: UserDefaults = .standard,
        key: String = "updates.lastSeenInstalledVersionIdentifier"
    ) {
        self.userDefaults = userDefaults
        self.key = key
    }

    func consumeInstalledUpdateNotice(current: SumiAppVersionMetadata) -> SumiInstalledUpdate? {
        let currentIdentifier = SumiUpdateNoticeIdentifier(
            displayVersion: current.shortVersion,
            buildVersion: current.buildNumber
        )
        let previousIdentifier = userDefaults.string(forKey: key).map(SumiUpdateNoticeIdentifier.init(rawValue:))
        userDefaults.set(currentIdentifier.rawValue, forKey: key)

        guard let previousIdentifier,
              SumiUpdateVersionComparator.isNewer(current: currentIdentifier, than: previousIdentifier)
        else {
            return nil
        }

        return SumiInstalledUpdate(
            displayVersion: current.shortVersion,
            buildVersion: current.buildNumber
        )
    }
}

struct SumiAppVersionMetadata: Equatable, Sendable {
    let displayName: String
    let shortVersion: String
    let buildNumber: String

    var versionLine: String {
        "Version \(shortVersion)"
    }

    var buildLine: String {
        "Build \(buildNumber)"
    }

    var summaryLine: String {
        "Version \(shortVersion) / Build \(buildNumber)"
    }

    static func resolve(infoDictionary: [String: Any]) -> SumiAppVersionMetadata {
        SumiAppVersionMetadata(
            displayName: infoDictionary["CFBundleDisplayName"] as? String
                ?? infoDictionary["CFBundleName"] as? String
                ?? "Sumi",
            shortVersion: infoDictionary["CFBundleShortVersionString"] as? String
                ?? "Unknown",
            buildNumber: infoDictionary["CFBundleVersion"] as? String
                ?? "Unknown"
        )
    }

    static func resolve(bundle: Bundle = .main) -> SumiAppVersionMetadata {
        resolve(infoDictionary: bundle.infoDictionary ?? [:])
    }
}

struct SumiAboutUpdateViewModel {
    let metadata: SumiAppVersionMetadata
    let state: SumiUpdateState
    let checkForUpdates: () -> Void

    var channelDisplayName: String {
        state.channel.displayName
    }

    var checkButtonIsEnabled: Bool {
        state.canCheckForUpdates
    }

    var panelState: SumiAboutUpdatePanelState {
        if state.isCheckingForUpdates {
            return .checking
        }

        if case .available(let update) = state.availability {
            return .updateAvailable(update)
        }

        guard state.isSparkleAvailable, state.isConfigured else {
            return .unavailable(state.diagnosticMessage ?? "Updates are not available in this build.")
        }

        if let diagnosticMessage = state.diagnosticMessage, diagnosticMessage.isEmpty == false {
            return .checkFailed(diagnosticMessage)
        }

        if state.lastCheckedAt != nil {
            return .upToDate
        }

        return .ready
    }
}

enum SumiAboutUpdatePanelState: Equatable, Sendable {
    case ready
    case checking
    case upToDate
    case updateAvailable(SumiAvailableUpdate)
    case checkFailed(String)
    case unavailable(String)
}

@MainActor
protocol SumiUpdaterBackend: AnyObject {
    var canCheckForUpdates: Bool { get }
    var automaticallyChecksForUpdates: Bool { get }
    var lastUpdateCheckDate: Date? { get }
    var feedURL: URL? { get }
    var isSparkleAvailable: Bool { get }
    var isConfigured: Bool { get }

    func start()
    func checkForUpdateInformation()
    func installAvailableUpdate()
}

@MainActor
final class SumiUpdaterService: ObservableObject {
    @Published private(set) var state: SumiUpdateState
    @Published private(set) var sidebarNotice: SumiUpdateSidebarNotice?

    private let dismissalStore: SumiUpdateNoticeDismissalPersisting
    private let installedUpdateStore: SumiInstalledUpdateNoticePersisting
    private var installedUpdateNotice: SumiInstalledUpdate?
    private var operationNotice: SumiUpdateOperationNotice?
    private var backend: SumiUpdaterBackend?
    private let backendFactory: @MainActor (SumiUpdaterService) -> SumiUpdaterBackend?
    private var didStart = false

    private static func makeProductionBackend(service: SumiUpdaterService) -> SumiUpdaterBackend? {
        #if canImport(Sparkle)
        return SumiSparkleUpdaterBackend(service: service)
        #else
        return nil
        #endif
    }

    init(
        channel: SumiUpdateChannel = .resolve(),
        dismissalStore: SumiUpdateNoticeDismissalPersisting = SumiUpdateNoticeDismissalStore(),
        installedUpdateStore: SumiInstalledUpdateNoticePersisting = SumiInstalledUpdateNoticeStore(),
        currentVersion: SumiAppVersionMetadata = SumiAppVersionMetadata.resolve(),
        backend: SumiUpdaterBackend? = nil,
        backendFactory: @escaping @MainActor (SumiUpdaterService) -> SumiUpdaterBackend? = SumiUpdaterService.makeProductionBackend(service:)
    ) {
        self.dismissalStore = dismissalStore
        self.installedUpdateStore = installedUpdateStore
        self.installedUpdateNotice = installedUpdateStore.consumeInstalledUpdateNotice(current: currentVersion)
        self.operationNotice = nil
        self.backend = backend
        self.backendFactory = backendFactory
        self.state = SumiUpdateState.initial(channel: channel)
        self.sidebarNotice = nil
        syncStateFromBackend()

#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--sumi-debug-update-notice") {
            installedUpdateNotice = SumiInstalledUpdate(
                displayVersion: currentVersion.shortVersion,
                buildVersion: currentVersion.buildNumber
            )
            refreshSidebarNotice()
        }

        if ProcessInfo.processInfo.arguments.contains("--sumi-debug-available-update") {
            state.availability = .available(
                SumiAvailableUpdate(
                    displayVersion: currentVersion.shortVersion,
                    buildVersion: currentVersion.buildNumber,
                    title: nil,
                    subtitle: nil,
                    releaseNotesURL: nil,
                    isInformationOnly: false
                )
            )
            refreshSidebarNotice()
        }
#endif
    }

    func start() {
        guard !didStart else { return }
        didStart = true

        if backend == nil {
            backend = backendFactory(self)
        }

        guard let backend else {
            updateState {
                $0.isSparkleAvailable = false
                $0.isConfigured = false
                $0.canCheckForUpdates = false
                $0.automaticallyChecksForUpdates = false
                $0.diagnosticMessage = "Sparkle is not linked in this build."
            }
            return
        }

        backend.start()
        syncStateFromBackend()
    }

    func checkForUpdatesFromUserAction() {
        ensureBackendStarted()
        guard state.canCheckForUpdates else { return }
        recordUpdateCheckStarted()
        backend?.checkForUpdateInformation()
    }

    func checkForUpdatesFromAboutView() {
        ensureBackendStarted()
        guard state.canCheckForUpdates else { return }
        recordUpdateCheckStarted()
        backend?.checkForUpdateInformation()
    }

    func startUpdateFromSidebarNotice() {
        ensureBackendStarted()
        guard state.canCheckForUpdates else { return }
        backend?.installAvailableUpdate()
    }

    func dismissUpdateNotice(forVersion version: String) {
        guard case .available(let update) = state.availability,
              update.displayVersion == version || update.buildVersion == version
        else { return }
        dismissalStore.dismissNotice(identifier: update.noticeIdentifier)
        refreshSidebarNotice()
    }

    func dismissUpdateNotice(for update: SumiAvailableUpdate) {
        dismissalStore.dismissNotice(identifier: update.noticeIdentifier)
        refreshSidebarNotice()
    }

    func dismissSidebarNotice(_ notice: SumiUpdateSidebarNotice) {
        switch notice {
        case .installed(let update):
            dismissalStore.dismissInstalledNotice(identifier: update.noticeIdentifier)
            refreshSidebarNotice()
        case .progress(.available(let update)):
            dismissUpdateNotice(for: update)
        case .progress(.operation(let operation)) where operation.stage == .failed:
            operationNotice = nil
            refreshSidebarNotice()
        case .progress(.operation):
            break
        }
    }

    func recordAvailableUpdate(_ update: SumiAvailableUpdate) {
        operationNotice = nil
        updateState {
            $0.availability = .available(update)
            $0.isCheckingForUpdates = false
            $0.diagnosticMessage = nil
        }
    }

    func recordNoUpdateAvailable(lastCheckedAt: Date? = nil) {
        operationNotice = nil
        updateState {
            $0.availability = .none
            $0.isCheckingForUpdates = false
            if let lastCheckedAt {
                $0.lastCheckedAt = lastCheckedAt
            }
            $0.diagnosticMessage = nil
        }
    }

    func recordUpdateCheckFinished(errorMessage: String? = nil) {
        updateState {
            $0.lastCheckedAt = backend?.lastUpdateCheckDate ?? Date()
            $0.isCheckingForUpdates = false
            $0.diagnosticMessage = errorMessage
        }
    }

    func recordUpdateOperation(_ notice: SumiUpdateOperationNotice) {
        operationNotice = notice
        updateState {
            $0.isCheckingForUpdates = notice.stage == .checking
            $0.diagnosticMessage = notice.stage == .failed ? notice.detail : nil
        }
    }

    func recordUpdateInstallStarted() {
        guard case .available(let update) = state.availability else { return }
        operationNotice = SumiUpdateOperationNotice(
            stage: .downloading,
            title: "Updating Sumi",
            detail: "Downloading \(update.versionLine)...",
            progress: nil
        )
        updateState {
            $0.diagnosticMessage = nil
        }
    }

    func syncStateFromBackend() {
        guard let backend else {
            refreshSidebarNotice()
            return
        }

        updateState {
            $0.canCheckForUpdates = backend.canCheckForUpdates
            $0.automaticallyChecksForUpdates = backend.automaticallyChecksForUpdates
            $0.lastCheckedAt = backend.lastUpdateCheckDate
            $0.feedURL = backend.feedURL
            $0.isSparkleAvailable = backend.isSparkleAvailable
            $0.isConfigured = backend.isConfigured
        }
    }

    private func ensureBackendStarted() {
        if !didStart {
            start()
        }
    }

    private func recordUpdateCheckStarted() {
        updateState {
            $0.isCheckingForUpdates = true
            $0.diagnosticMessage = nil
        }
    }

    private func updateState(_ mutate: (inout SumiUpdateState) -> Void) {
        var newState = state
        mutate(&newState)
        state = newState
        refreshSidebarNotice()
    }

    private func refreshSidebarNotice() {
        sidebarNotice = SumiUpdateNoticeVisibilityResolver.sidebarNotice(
            availability: state.availability,
            operationNotice: operationNotice,
            installedUpdate: installedUpdateNotice,
            dismissalStore: dismissalStore
        )
    }
}

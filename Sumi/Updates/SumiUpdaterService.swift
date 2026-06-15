//
//  SumiUpdaterService.swift
//  Sumi
//

import Foundation

#if canImport(Combine)
import Combine
#endif

#if canImport(Sparkle)
import Sparkle
#endif

enum SumiUpdateChannel: String, CaseIterable, Equatable, Sendable {
    case alpha

    var displayName: String {
        switch self {
        case .alpha:
            return "Alpha"
        }
    }
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

enum SumiUpdateSidebarNoticeVisualStyle: Equatable, Sendable {
    case accent
    case success
    case progress
    case warning
}

enum SumiUpdateSidebarNotice: Equatable, Sendable {
    case available(SumiAvailableUpdate)
    case operation(SumiUpdateOperationNotice)
    case installed(SumiInstalledUpdate)

    var title: String {
        switch self {
        case .available:
            return "Update available"
        case .operation(let notice):
            return notice.title
        case .installed:
            return "Update complete"
        }
    }

    var detail: String {
        switch self {
        case .available(let update):
            return update.versionLine
        case .operation(let notice):
            return notice.detail
        case .installed(let update):
            return "\(update.versionLine) installed"
        }
    }

    var primaryActionTitle: String? {
        switch self {
        case .available:
            return "Update"
        case .operation, .installed:
            return nil
        }
    }

    var isDismissible: Bool {
        switch self {
        case .available, .installed:
            return true
        case .operation(let notice):
            return notice.stage == .failed
        }
    }

    var systemImageName: String {
        switch self {
        case .available:
            return "arrow.down.circle.fill"
        case .operation(let notice):
            switch notice.stage {
            case .checking:
                return "arrow.triangle.2.circlepath"
            case .downloading:
                return "arrow.down.circle.fill"
            case .extracting:
                return "archivebox.fill"
            case .installing:
                return "arrow.triangle.2.circlepath.circle.fill"
            case .readyToInstall:
                return "restart.circle.fill"
            case .failed:
                return "exclamationmark.triangle.fill"
            }
        case .installed:
            return "checkmark.circle.fill"
        }
    }

    var visualStyle: SumiUpdateSidebarNoticeVisualStyle {
        switch self {
        case .available:
            return .accent
        case .operation(let notice):
            return notice.stage == .failed ? .warning : .progress
        case .installed:
            return .success
        }
    }

    var progress: Double? {
        guard case .operation(let notice) = self else { return nil }
        return notice.progress
    }

    var availableUpdate: SumiAvailableUpdate? {
        guard case .available(let update) = self else { return nil }
        return update
    }

    var installedUpdate: SumiInstalledUpdate? {
        guard case .installed(let update) = self else { return nil }
        return update
    }
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
            return .operation(operationNotice)
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
        return .available(update)
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
    var automaticallyChecksForUpdates: Bool { get set }
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
    static let shared = SumiUpdaterService()

    @Published private(set) var state: SumiUpdateState
    @Published private(set) var sidebarNotice: SumiUpdateSidebarNotice?

    private let dismissalStore: SumiUpdateNoticeDismissalPersisting
    private let installedUpdateStore: SumiInstalledUpdateNoticePersisting
    private var installedUpdateNotice: SumiInstalledUpdate?
    private var operationNotice: SumiUpdateOperationNotice?
    private var backend: SumiUpdaterBackend?
    private let backendFactory: @MainActor (SumiUpdaterService) -> SumiUpdaterBackend?
    private var didStart = false

    init(
        channel: SumiUpdateChannel = .alpha,
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

    func checkForUpdatesInBackgroundIfAllowed() {
        ensureBackendStarted()
        guard state.automaticallyChecksForUpdates else { return }
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
        case .available(let update):
            dismissUpdateNotice(for: update)
        case .installed(let update):
            dismissalStore.dismissInstalledNotice(identifier: update.noticeIdentifier)
            refreshSidebarNotice()
        case .operation(let operation) where operation.stage == .failed:
            operationNotice = nil
            refreshSidebarNotice()
        case .operation:
            break
        }
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        ensureBackendStarted()
        backend?.automaticallyChecksForUpdates = enabled
        syncStateFromBackend()
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

#if canImport(Sparkle)
@MainActor
private final class SumiSparkleUpdaterBackend: SumiUpdaterBackend {
    private weak var service: SumiUpdaterService?
    private let delegate: SumiSparkleUpdaterDelegate
    private let userDriver: SumiSparkleUserDriver
    private let updater: SPUUpdater

    #if canImport(Combine)
    private var cancellables = Set<AnyCancellable>()
    #endif

    init(service: SumiUpdaterService) {
        self.service = service
        self.delegate = SumiSparkleUpdaterDelegate(service: service)
        self.userDriver = SumiSparkleUserDriver(service: service)
        self.updater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: userDriver,
            delegate: delegate
        )
        observeUpdaterState()
    }

    var canCheckForUpdates: Bool {
        updater.canCheckForUpdates
    }

    var automaticallyChecksForUpdates: Bool {
        get {
            updater.automaticallyChecksForUpdates
        }
        set {
            updater.automaticallyChecksForUpdates = newValue
        }
    }

    var lastUpdateCheckDate: Date? {
        updater.lastUpdateCheckDate
    }

    var feedURL: URL? {
        updater.feedURL
    }

    var isSparkleAvailable: Bool {
        true
    }

    var isConfigured: Bool {
        feedURL != nil
    }

    func start() {
        do {
            try updater.start()
        } catch {
            service?.recordUpdateOperation(
                SumiUpdateOperationNotice(
                    stage: .failed,
                    title: "Updates unavailable",
                    detail: error.localizedDescription,
                    progress: nil
                )
            )
        }
    }

    func checkForUpdateInformation() {
        updater.checkForUpdateInformation()
    }

    func installAvailableUpdate() {
        userDriver.installAvailableUpdate()
        updater.checkForUpdates()
    }

    private func observeUpdaterState() {
        #if canImport(Combine)
        updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak service] _ in
                Task { @MainActor in
                    service?.syncStateFromBackend()
                }
            }
            .store(in: &cancellables)

        updater.publisher(for: \.automaticallyChecksForUpdates)
            .sink { [weak service] _ in
                Task { @MainActor in
                    service?.syncStateFromBackend()
                }
            }
            .store(in: &cancellables)
        #endif
    }
}

private final class SumiSparkleUpdaterDelegate: NSObject, SPUUpdaterDelegate {
    private weak var service: SumiUpdaterService?

    init(service: SumiUpdaterService) {
        self.service = service
    }

    var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let availableUpdate = Self.availableUpdate(from: item)
        Task { @MainActor [weak service] in
            service?.recordAvailableUpdate(availableUpdate)
        }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        let lastUpdateCheckDate = updater.lastUpdateCheckDate
        Task { @MainActor [weak service] in
            service?.recordNoUpdateAvailable(lastCheckedAt: lastUpdateCheckDate)
        }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        let lastUpdateCheckDate = updater.lastUpdateCheckDate
        Task { @MainActor [weak service] in
            service?.recordNoUpdateAvailable(lastCheckedAt: lastUpdateCheckDate)
        }
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: (any Error)?
    ) {
        let errorMessage: String?
        if let error = error as NSError?,
           error.domain == SUSparkleErrorDomain && (error.code == SUError.noUpdateError.rawValue || error.code == 2 || error.code == 1001) {
            errorMessage = nil
        } else {
            errorMessage = error?.localizedDescription
        }
        Task { @MainActor [weak service] in
            service?.recordUpdateCheckFinished(errorMessage: errorMessage)
            service?.syncStateFromBackend()
        }
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        let errorMessage = error.localizedDescription
        Task { @MainActor [weak service] in
            service?.recordUpdateCheckFinished(errorMessage: errorMessage)
            service?.syncStateFromBackend()
        }
    }

    fileprivate static func availableUpdate(from item: SUAppcastItem) -> SumiAvailableUpdate {
        SumiAvailableUpdate(
            displayVersion: item.displayVersionString,
            buildVersion: item.versionString,
            title: item.title,
            subtitle: nil,
            releaseNotesURL: item.releaseNotesURL,
            isInformationOnly: item.isInformationOnlyUpdate
        )
    }
}

@MainActor
private final class SumiSparkleUserDriver: NSObject, SPUUserDriver {
    private weak var service: SumiUpdaterService?
    private var shouldInstallNextShownUpdate = false
    private var isInstallingFromSidebar = false
    private var readyToInstallReply: ((SPUUserUpdateChoice) -> Void)?

    init(service: SumiUpdaterService) {
        self.service = service
    }

    func installAvailableUpdate() {
        if let readyToInstallReply {
            self.readyToInstallReply = nil
            isInstallingFromSidebar = true
            readyToInstallReply(.install)
            return
        }

        shouldInstallNextShownUpdate = true
        isInstallingFromSidebar = true
        service?.recordUpdateInstallStarted()
    }

    func show(
        _ request: SPUUpdatePermissionRequest,
        reply: @escaping (SUUpdatePermissionResponse) -> Void
    ) {
        reply(
            SUUpdatePermissionResponse(
                automaticUpdateChecks: true,
                automaticUpdateDownloading: nil,
                sendSystemProfile: false
            )
        )
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        service?.syncStateFromBackend()
    }

    func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        let availableUpdate = SumiSparkleUpdaterDelegate.availableUpdate(from: appcastItem)
        service?.recordAvailableUpdate(availableUpdate)

        guard shouldInstallNextShownUpdate, appcastItem.isInformationOnlyUpdate == false else {
            isInstallingFromSidebar = false
            reply(.dismiss)
            return
        }

        shouldInstallNextShownUpdate = false
        reply(.install)
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        shouldInstallNextShownUpdate = false
        isInstallingFromSidebar = false
        service?.recordNoUpdateAvailable()
        acknowledgement()
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        shouldInstallNextShownUpdate = false
        isInstallingFromSidebar = false
        readyToInstallReply = nil
        service?.recordUpdateOperation(
            SumiUpdateOperationNotice(
                stage: .failed,
                title: "Update failed",
                detail: error.localizedDescription,
                progress: nil
            )
        )
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        service?.recordUpdateOperation(
            SumiUpdateOperationNotice(
                stage: .downloading,
                title: "Updating Sumi",
                detail: "Downloading update...",
                progress: nil
            )
        )
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}

    func showDownloadDidReceiveData(ofLength length: UInt64) {}

    func showDownloadDidStartExtractingUpdate() {
        service?.recordUpdateOperation(
            SumiUpdateOperationNotice(
                stage: .extracting,
                title: "Preparing update",
                detail: "Verifying and extracting the update...",
                progress: nil
            )
        )
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        service?.recordUpdateOperation(
            SumiUpdateOperationNotice(
                stage: .extracting,
                title: "Preparing update",
                detail: "Extracting update...",
                progress: progress
            )
        )
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        guard isInstallingFromSidebar else {
            readyToInstallReply = reply
            return
        }
        reply(.install)
    }

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {
        service?.syncStateFromBackend()
    }

    func showUpdateInstalledAndRelaunched(
        _ relaunched: Bool,
        acknowledgement: @escaping () -> Void
    ) {
        shouldInstallNextShownUpdate = false
        isInstallingFromSidebar = false
        readyToInstallReply = nil
        acknowledgement()
    }

    func dismissUpdateInstallation() {
        shouldInstallNextShownUpdate = false
        isInstallingFromSidebar = false
        readyToInstallReply = nil
    }

    func showUpdateInFocus() {
        service?.syncStateFromBackend()
    }
}
#endif

private extension SumiUpdaterService {
    static func makeProductionBackend(service: SumiUpdaterService) -> SumiUpdaterBackend? {
        #if canImport(Sparkle)
        return SumiSparkleUpdaterBackend(service: service)
        #else
        return nil
        #endif
    }
}

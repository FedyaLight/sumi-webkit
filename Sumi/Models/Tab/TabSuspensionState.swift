import Foundation
import SumiWebRuntime
import WebKit

enum PageSessionDataStoreIdentity: Equatable {
    case persistent(UUID)
    case runtime(ObjectIdentifier)

    @MainActor
    init(_ dataStore: WKWebsiteDataStore) {
        if let identifier = dataStore.identifier {
            self = .persistent(identifier)
        } else {
            self = .runtime(ObjectIdentifier(dataStore))
        }
    }
}

struct PageSessionSnapshot: Equatable {
    let residence: WebViewResidence
    let residenceGeneration: UInt64
    let profileID: UUID?
    let dataStoreIdentity: PageSessionDataStoreIdentity
    let committedRevision: UInt64
    let destination: URL
    let data: Data
}

struct PageSessionRestoreBinding: Equatable {
    let residence: WebViewResidence
    let webViewID: ObjectIdentifier
    let navigationID: ObjectIdentifier
}

enum PageSessionRestorePhase: Equatable {
    case inactive
    case available
    case restoring
    case committed
    case fallingBack
    case failed
}

struct TabSuspensionState {
    private(set) var phase: PageSessionRestorePhase = .inactive
    private(set) var isSuspended = false
    private(set) var lastSuspendedURL: URL?
    private(set) var snapshots: [WebViewResidence: PageSessionSnapshot] = [:]
    private(set) var binding: PageSessionRestoreBinding?
    private(set) var didAttemptFallback = false
    private var restoreResidenceGeneration: UInt64?
    private var restoreTraceState: PerformanceTrace.IntervalState?

    var isRestoreInProgress: Bool {
        phase == .restoring || phase == .fallingBack
    }

    mutating func markSuspended(
        url: URL,
        snapshots: [PageSessionSnapshot]
    ) {
        isSuspended = true
        lastSuspendedURL = url
        self.snapshots = Dictionary(
            snapshots.map { ($0.residence, $0) },
            uniquingKeysWith: { _, replacement in replacement }
        )
        binding = nil
        didAttemptFallback = false
        restoreResidenceGeneration = nil
        phase = .available
    }

    mutating func beginRestoreIfNeeded(residenceGeneration: UInt64) {
        guard isSuspended, phase == .available else { return }
        phase = .restoring
        restoreResidenceGeneration = residenceGeneration
        restoreTraceState = PerformanceTrace.beginInterval("TabSuspension.restore")
        PerformanceTrace.emitEvent("TabSuspension.restoreStart")
    }

    func candidate(
        residence: WebViewResidence,
        residenceGeneration: UInt64,
        profileID: UUID?,
        dataStoreIdentity: PageSessionDataStoreIdentity,
        intentRevision: UInt64,
        destination: URL
    ) -> PageSessionSnapshot? {
        guard phase == .restoring,
              restoreResidenceGeneration == residenceGeneration,
              binding == nil,
              let snapshot = snapshots[residence],
              snapshot.profileID == profileID,
              snapshot.dataStoreIdentity == dataStoreIdentity,
              snapshot.committedRevision == intentRevision,
              snapshot.destination == destination else {
            return nil
        }
        return snapshot
    }

    @discardableResult
    mutating func bind(
        _ snapshot: PageSessionSnapshot,
        webViewID: ObjectIdentifier,
        navigationID: ObjectIdentifier
    ) -> Bool {
        guard phase == .restoring,
              binding == nil,
              snapshots[snapshot.residence] == snapshot else {
            return false
        }
        // Session bytes become consumed only after WebKit returns a concrete
        // navigation and Sumi binds that exact navigation to the main-frame
        // transaction.
        snapshots.removeValue(forKey: snapshot.residence)
        binding = PageSessionRestoreBinding(
            residence: snapshot.residence,
            webViewID: webViewID,
            navigationID: navigationID
        )
        return true
    }

    @discardableResult
    mutating func beginFallback(
        webViewID: ObjectIdentifier,
        navigationID: ObjectIdentifier? = nil
    ) -> Bool {
        guard phase == .restoring, didAttemptFallback == false else {
            return false
        }
        if let binding {
            guard binding.webViewID == webViewID,
                  navigationID == nil || binding.navigationID == navigationID else {
                return false
            }
        }
        didAttemptFallback = true
        binding = nil
        restoreResidenceGeneration = nil
        phase = .fallingBack
        return true
    }

    mutating func commit(
        webViewID: ObjectIdentifier,
        navigationID: ObjectIdentifier
    ) -> Bool {
        switch phase {
        case .restoring:
            guard let binding,
                  binding.webViewID == webViewID,
                  binding.navigationID == navigationID else {
                return false
            }
        case .fallingBack:
            break
        default:
            return false
        }
        finishRestore(phase: .committed)
        return true
    }

    mutating func failFallback() -> Bool {
        guard phase == .fallingBack else { return false }
        finishRestore(phase: .failed)
        return true
    }

    mutating func cancelRestore() {
        guard isRestoreInProgress else { return }
        finishRestore(phase: .inactive)
    }

    private mutating func finishRestore(phase terminalPhase: PageSessionRestorePhase) {
        isSuspended = false
        phase = terminalPhase
        snapshots.removeAll()
        binding = nil
        if let restoreTraceState {
            PerformanceTrace.endInterval("TabSuspension.restore", restoreTraceState)
            self.restoreTraceState = nil
        }
        PerformanceTrace.emitEvent("TabSuspension.restoreEnd")
    }
}

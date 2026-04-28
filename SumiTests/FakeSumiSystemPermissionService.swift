import Foundation

@testable import Sumi

actor FakeSumiSystemPermissionService: SumiSystemPermissionService {
    private var states: [SumiSystemPermissionKind: SumiSystemPermissionAuthorizationState]
    private var requestResults: [SumiSystemPermissionKind: SumiSystemPermissionAuthorizationState]
    private let allowsRequestingResolvedStates: Bool
    private var settingsOpenRequests: [SumiSystemPermissionKind] = []
    private var authorizationStateCounts: [SumiSystemPermissionKind: Int] = [:]
    private var authorizationSnapshotCounts: [SumiSystemPermissionKind: Int] = [:]
    private var requestAuthorizationCounts: [SumiSystemPermissionKind: Int] = [:]

    init(
        states: [SumiSystemPermissionKind: SumiSystemPermissionAuthorizationState] = [:],
        requestResults: [SumiSystemPermissionKind: SumiSystemPermissionAuthorizationState] = [:],
        allowsRequestingResolvedStates: Bool = false
    ) {
        self.states = states
        self.requestResults = requestResults
        self.allowsRequestingResolvedStates = allowsRequestingResolvedStates
    }

    func authorizationState(
        for kind: SumiSystemPermissionKind
    ) async -> SumiSystemPermissionAuthorizationState {
        authorizationStateCounts[kind, default: 0] += 1
        return state(for: kind)
    }

    func authorizationSnapshot(for kind: SumiSystemPermissionKind) async -> SumiSystemPermissionSnapshot {
        authorizationSnapshotCounts[kind, default: 0] += 1
        return SumiSystemPermissionSnapshot(kind: kind, state: state(for: kind))
    }

    func requestAuthorization(
        for kind: SumiSystemPermissionKind
    ) async -> SumiSystemPermissionAuthorizationState {
        requestAuthorizationCounts[kind, default: 0] += 1
        let currentState = states[kind] ?? .notDetermined
        guard currentState == .notDetermined || allowsRequestingResolvedStates else {
            return currentState
        }

        let result = requestResults[kind] ?? .authorized
        states[kind] = result
        return result
    }

    @discardableResult
    func openSystemSettings(for kind: SumiSystemPermissionKind) async -> Bool {
        settingsOpenRequests.append(kind)
        return true
    }

    func setState(
        _ state: SumiSystemPermissionAuthorizationState,
        for kind: SumiSystemPermissionKind
    ) {
        states[kind] = state
    }

    func openedSettingsKinds() -> [SumiSystemPermissionKind] {
        settingsOpenRequests
    }

    func requestAuthorizationCallCount(for kind: SumiSystemPermissionKind? = nil) -> Int {
        guard let kind else {
            return requestAuthorizationCounts.values.reduce(0, +)
        }
        return requestAuthorizationCounts[kind] ?? 0
    }

    func authorizationStateCallCount(for kind: SumiSystemPermissionKind? = nil) -> Int {
        guard let kind else {
            return authorizationStateCounts.values.reduce(0, +)
        }
        return authorizationStateCounts[kind] ?? 0
    }

    func authorizationSnapshotCallCount(for kind: SumiSystemPermissionKind? = nil) -> Int {
        guard let kind else {
            return authorizationSnapshotCounts.values.reduce(0, +)
        }
        return authorizationSnapshotCounts[kind] ?? 0
    }

    private func state(for kind: SumiSystemPermissionKind) -> SumiSystemPermissionAuthorizationState {
        states[kind] ?? .notDetermined
    }
}

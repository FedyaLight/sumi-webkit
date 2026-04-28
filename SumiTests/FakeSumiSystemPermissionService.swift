import Foundation

@testable import Sumi

actor FakeSumiSystemPermissionService: SumiSystemPermissionService {
    private var states: [SumiSystemPermissionKind: SumiSystemPermissionAuthorizationState]
    private var requestResults: [SumiSystemPermissionKind: SumiSystemPermissionAuthorizationState]
    private let allowsRequestingResolvedStates: Bool
    private var settingsOpenRequests: [SumiSystemPermissionKind] = []

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
        states[kind] ?? .notDetermined
    }

    func requestAuthorization(
        for kind: SumiSystemPermissionKind
    ) async -> SumiSystemPermissionAuthorizationState {
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
}

//
//  StandardNativeMessagingHostBackend.swift
//  Sumi
//
//  Reusable backend for standard native-messaging hosts.
//

import Foundation

@available(macOS 15.5, *)
@MainActor
final class StandardNativeMessagingHostBackend: SumiNativeMessagingProtocolAdapter {
    static let backendIdentifier = "standard-native-messaging-host"

    let protocolIdentifier = StandardNativeMessagingHostBackend.backendIdentifier

    private let mappings: [StandardNativeMessagingHostMapping]
    private let resolver: any NativeMessagingHostManifestResolving
    private let transportFactory: () -> any NativeMessagingHostTransporting
    private let replyTimeout: Duration
    private var portSessions: [ObjectIdentifier: StandardNativeMessagingPortSessionState] = [:]

    init(
        mappings: [StandardNativeMessagingHostMapping],
        resolver: any NativeMessagingHostManifestResolving = NativeMessagingHostManifestResolver(),
        transportFactory: @escaping () -> any NativeMessagingHostTransporting = {
            NativeMessagingHostProcessTransport()
        },
        replyTimeout: Duration = SumiNativeMessagingConnection.defaultReplyTimeout
    ) {
        self.mappings = mappings
        self.resolver = resolver
        self.transportFactory = transportFactory
        self.replyTimeout = replyTimeout
    }

    func supports(hostBundleIdentifier: String) -> Bool {
        mappings.contains { $0.supports(hostBundleIdentifier: hostBundleIdentifier) }
    }

    func relayOneShotMessage(
        request: SumiNativeMessagingOneShotRequest,
        launcher: SumiHostApplicationLaunching,
        replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) {
        _ = launcher
        guard let mapping = mapping(
            applicationIdentifier: request.applicationIdentifier,
            hostBundleIdentifier: request.hostBundleIdentifier
        ) else {
            replyHandler(
                nil,
                NativeMessagingHostBackendErrorMapper.relayError(
                    for: .unsupportedHostKind,
                    hostName: request.applicationIdentifier ?? request.hostBundleIdentifier
                )
            )
            return
        }

        NativeMessagingHostBackendDiagnostics.log(
            outcome: .backendSelected,
            hostName: mapping.nativeHostName,
            backend: Self.backendIdentifier,
            sourceKind: nil
        )

        guard let payload = NativeMessagingJSONPayload.object(from: request.message) else {
            NativeMessagingHostBackendDiagnostics.log(
                outcome: .malformedExtensionMessage,
                hostName: mapping.nativeHostName,
                backend: Self.backendIdentifier,
                sourceKind: nil
            )
            replyHandler(
                nil,
                NativeMessagingHostBackendErrorMapper.relayError(
                    for: .malformedMessage,
                    hostName: mapping.nativeHostName
                )
            )
            return
        }

        let resolution = resolver.resolve(mapping: mapping)
        guard case .resolved(let hostExecutableURL, _, let sourceKind) = resolution else {
            replyHandler(
                nil,
                NativeMessagingHostBackendErrorMapper.relayError(for: resolution)
            )
            return
        }

        let transport = transportFactory()
        let relay = StandardNativeMessagingOneShotRelay(
            hostName: mapping.nativeHostName,
            sourceKind: sourceKind,
            transport: transport,
            payload: payload,
            replyTimeout: replyTimeout,
            replyHandler: replyHandler
        )
        relay.start(hostExecutableURL: hostExecutableURL)
    }

    func connectPort(
        session: SumiNativeMessagingPortSession,
        launcher: SumiHostApplicationLaunching,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        _ = launcher
        guard let mapping = mapping(
            applicationIdentifier: nil,
            hostBundleIdentifier: session.resolvedHostBundleIdentifier
        ) else {
            completionHandler(
                NativeMessagingHostBackendErrorMapper.relayError(
                    for: .unsupportedHostKind,
                    hostName: session.resolvedHostBundleIdentifier
                )
            )
            return
        }

        NativeMessagingHostBackendDiagnostics.log(
            outcome: .backendSelected,
            hostName: mapping.nativeHostName,
            backend: Self.backendIdentifier,
            sourceKind: nil
        )

        let resolution = resolver.resolve(mapping: mapping)
        guard case .resolved(let hostExecutableURL, _, let sourceKind) = resolution else {
            completionHandler(
                NativeMessagingHostBackendErrorMapper.relayError(for: resolution)
            )
            return
        }

        let sessionKey = ObjectIdentifier(session)
        let transport = transportFactory()
        let state = StandardNativeMessagingPortSessionState(
            hostName: mapping.nativeHostName,
            sourceKind: sourceKind,
            session: session,
            transport: transport
        )
        portSessions[sessionKey] = state
        SumiNativeMessagingRuntimeCounters.recordAdapterPortSessionOpened()

        let completion = StandardNativeMessagingCompletionBox(completionHandler)
        transport.onDisconnect = { [weak self] in
            guard let self else { return }
            let state = self.removePortSession(forKey: sessionKey)
            completion.call(
                NativeMessagingHostBackendErrorMapper.relayError(
                    for: .portDisconnected,
                    hostName: mapping.nativeHostName
                )
            )
            state?.disconnectAssociatedSession(
                throwing: NativeMessagingHostBackendErrorMapper.relayError(
                    for: .portDisconnected,
                    hostName: mapping.nativeHostName
                )
            )
        }

        Task { @MainActor [weak self] in
            guard let self else {
                completion.call(
                    SumiNativeMessagingErrorMapper.relayError(
                        code: .relayCancelled,
                        diagnostic: nil
                    )
                )
                return
            }
            do {
                try await transport.start(hostExecutableURL: hostExecutableURL)
                state.markTransportReady()
                NativeMessagingHostBackendDiagnostics.log(
                    outcome: .portOpened,
                    hostName: mapping.nativeHostName,
                    backend: Self.backendIdentifier,
                    sourceKind: sourceKind
                )
                completion.call(nil)
            } catch let error as NativeMessagingHostTransportError {
                let relayError = NativeMessagingHostBackendErrorMapper.relayError(
                    for: error,
                    hostName: mapping.nativeHostName
                )
                self.removePortSession(forKey: sessionKey)?.disconnectAssociatedSession(
                    throwing: relayError
                )
                completion.call(relayError)
            } catch {
                self.removePortSession(forKey: sessionKey)?.disconnectAssociatedSession(
                    throwing: error as NSError
                )
                completion.call(error)
            }
        }
    }

    @discardableResult
    func relayPortMessage(session: SumiNativeMessagingPortSession, message: Any) -> Bool {
        guard let state = portSessions[ObjectIdentifier(session)] else {
            return false
        }
        guard let payload = NativeMessagingJSONPayload.object(from: message) else {
            NativeMessagingHostBackendDiagnostics.log(
                outcome: .malformedExtensionMessage,
                hostName: state.hostName,
                backend: Self.backendIdentifier,
                sourceKind: state.sourceKind
            )
            return false
        }
        state.relayExtensionMessage(payload)
        return true
    }

    func disconnectPort(session: SumiNativeMessagingPortSession) {
        removePortSession(forKey: ObjectIdentifier(session))?.shutdown()
    }

    private func removePortSession(
        forKey sessionKey: ObjectIdentifier
    ) -> StandardNativeMessagingPortSessionState? {
        guard let state = portSessions.removeValue(forKey: sessionKey) else { return nil }
        state.shutdown()
        SumiNativeMessagingRuntimeCounters.recordAdapterPortSessionClosed()
        NativeMessagingHostBackendDiagnostics.log(
            outcome: .portClosed,
            hostName: state.hostName,
            backend: Self.backendIdentifier,
            sourceKind: state.sourceKind
        )
        return state
    }

    private func mapping(
        applicationIdentifier: String?,
        hostBundleIdentifier: String
    ) -> StandardNativeMessagingHostMapping? {
        if let byApplication = mappings.first(where: {
            $0.matches(applicationIdentifier: applicationIdentifier)
        }) {
            return byApplication
        }
        return mappings.first { $0.supports(hostBundleIdentifier: hostBundleIdentifier) }
    }
}

@available(macOS 15.5, *)
@MainActor
private final class StandardNativeMessagingPortSessionState {
    let hostName: String
    let sourceKind: NativeMessagingHostResolutionSourceKind

    private weak var session: SumiNativeMessagingPortSession?
    private let transport: any NativeMessagingHostTransporting
    private var transportReady = false
    private var queuedExtensionMessages: [[String: Any]] = []
    private var didShutdown = false

    init(
        hostName: String,
        sourceKind: NativeMessagingHostResolutionSourceKind,
        session: SumiNativeMessagingPortSession,
        transport: any NativeMessagingHostTransporting
    ) {
        self.hostName = hostName
        self.sourceKind = sourceKind
        self.session = session
        self.transport = transport
        transport.onReceive = { [weak self] incoming in
            self?.handleHostMessage(incoming)
        }
    }

    func markTransportReady() {
        guard transportReady == false else { return }
        transportReady = true
        flushQueuedExtensionMessages()
    }

    func relayExtensionMessage(_ payload: [String: Any]) {
        guard transportReady else {
            queuedExtensionMessages.append(payload)
            return
        }

        do {
            try transport.send(payload)
            NativeMessagingHostBackendDiagnostics.log(
                outcome: .hostRequestRelayed,
                hostName: hostName,
                backend: StandardNativeMessagingHostBackend.backendIdentifier,
                sourceKind: sourceKind
            )
        } catch {
            disconnectAssociatedSession(
                throwing: NativeMessagingHostBackendErrorMapper.relayError(
                    for: error as? NativeMessagingHostTransportError ?? .portDisconnected,
                    hostName: hostName
                )
            )
        }
    }

    func disconnectAssociatedSession(throwing error: NSError? = nil) {
        shutdown()
        session?.disconnect(throwing: error)
    }

    func shutdown() {
        guard didShutdown == false else { return }
        didShutdown = true
        queuedExtensionMessages.removeAll()
        transport.shutdown()
    }

    private func flushQueuedExtensionMessages() {
        let queued = queuedExtensionMessages
        queuedExtensionMessages.removeAll()
        for payload in queued {
            relayExtensionMessage(payload)
        }
    }

    private func handleHostMessage(_ incoming: [String: Any]) {
        session?.sendReplyToExtension(incoming)
    }
}

@available(macOS 15.5, *)
@MainActor
private final class StandardNativeMessagingOneShotRelay {
    private let hostName: String
    private let sourceKind: NativeMessagingHostResolutionSourceKind
    private let transport: any NativeMessagingHostTransporting
    private let payload: [String: Any]
    private let replyTimeout: Duration
    private var replyHandler: ((Any?, (any Error)?) -> Void)?
    private var timeoutTask: Task<Void, Never>?
    private var completed = false

    init(
        hostName: String,
        sourceKind: NativeMessagingHostResolutionSourceKind,
        transport: any NativeMessagingHostTransporting,
        payload: [String: Any],
        replyTimeout: Duration,
        replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) {
        self.hostName = hostName
        self.sourceKind = sourceKind
        self.transport = transport
        self.payload = payload
        self.replyTimeout = replyTimeout
        self.replyHandler = replyHandler

        transport.onReceive = { [weak self] incoming in
            self?.complete(incoming, nil)
        }
        transport.onDisconnect = { [weak self] in
            guard let self else { return }
            self.complete(
                nil,
                NativeMessagingHostBackendErrorMapper.relayError(
                    for: .portDisconnected,
                    hostName: self.hostName
                )
            )
        }
    }

    func start(hostExecutableURL: URL) {
        timeoutTask = Task { @MainActor in
            try? await Task.sleep(for: self.replyTimeout)
            NativeMessagingHostBackendDiagnostics.log(
                outcome: .messageTimedOut,
                hostName: self.hostName,
                backend: StandardNativeMessagingHostBackend.backendIdentifier,
                sourceKind: self.sourceKind
            )
            self.complete(
                nil,
                NativeMessagingHostBackendErrorMapper.relayError(
                    for: .timeout,
                    hostName: self.hostName
                )
            )
        }

        Task { @MainActor in
            do {
                try await self.transport.start(hostExecutableURL: hostExecutableURL)
                try self.transport.send(self.payload)
                NativeMessagingHostBackendDiagnostics.log(
                    outcome: .hostRequestRelayed,
                    hostName: self.hostName,
                    backend: StandardNativeMessagingHostBackend.backendIdentifier,
                    sourceKind: self.sourceKind
                )
            } catch let error as NativeMessagingHostTransportError {
                self.complete(
                    nil,
                    NativeMessagingHostBackendErrorMapper.relayError(
                        for: error,
                        hostName: self.hostName
                    )
                )
            } catch {
                self.complete(nil, error as NSError)
            }
        }
    }

    private func complete(_ value: Any?, _ error: (any Error)?) {
        guard completed == false else { return }
        completed = true
        timeoutTask?.cancel()
        timeoutTask = nil
        transport.shutdown()
        replyHandler?(value, error)
        replyHandler = nil
    }
}

@MainActor
private final class StandardNativeMessagingCompletionBox {
    private var completionHandler: (((any Error)?) -> Void)?

    init(_ completionHandler: @escaping ((any Error)?) -> Void) {
        self.completionHandler = completionHandler
    }

    func call(_ error: ((any Error)?) = nil) {
        guard let completionHandler else { return }
        self.completionHandler = nil
        completionHandler(error)
    }
}

enum NativeMessagingHostFailureCategory: String {
    case nativeHostNotInstalled
    case nativeHostManifestMissing
    case nativeHostExecutableMissing
    case unsupportedHostKind
    case permissionDenied
    case processLaunchFailed
    case malformedMessage
    case portDisconnected
    case timeout
}

@MainActor
enum NativeMessagingHostBackendErrorMapper {
    static let failureCategoryUserInfoKey = "SumiNativeMessagingNativeHostFailure"

    static func relayError(
        for resolution: NativeMessagingHostResolutionResult
    ) -> NSError {
        switch resolution {
        case .resolved:
            return relayError(for: .processLaunchFailed, hostName: nil)
        case .missingHostManifest(let hostName):
            return relayError(for: .hostManifestMissing, hostName: hostName)
        case .missingHostExecutable(let hostName, _, _):
            return relayError(for: .hostExecutableMissing, hostName: hostName)
        case .unsupportedHostKind(let hostName, _, _):
            return relayError(for: .unsupportedHostKind, hostName: hostName)
        case .permissionDenied(let hostName, _):
            return relayError(for: .permissionDenied, hostName: hostName)
        case .unknown(let hostName):
            return relayError(for: .processLaunchFailed, hostName: hostName)
        }
    }

    static func relayError(
        for error: NativeMessagingHostTransportError,
        hostName: String?
    ) -> NSError {
        let code: SumiNativeMessagingRelay.ErrorCode
        let category: NativeMessagingHostFailureCategory
        let description: String
        let hostDescription = hostName.map { " for \($0)" } ?? ""

        switch error {
        case .hostManifestMissing:
            code = .nativeHostManifestMissing
            category = .nativeHostManifestMissing
            description = "Native messaging host manifest\(hostDescription) was not found."
        case .hostExecutableMissing:
            code = .nativeHostExecutableMissing
            category = .nativeHostExecutableMissing
            description = "Native messaging host executable\(hostDescription) was not found."
        case .unsupportedHostKind:
            code = .nativeHostUnsupportedKind
            category = .unsupportedHostKind
            description = "Native messaging host\(hostDescription) is not a supported stdio host."
        case .permissionDenied:
            code = .nativeHostPermissionDenied
            category = .permissionDenied
            description = "Permission denied when starting native messaging host\(hostDescription)."
        case .processLaunchFailed:
            code = .hostLaunchFailed
            category = .processLaunchFailed
            description = "Native messaging host\(hostDescription) could not be launched."
        case .malformedMessage:
            code = .companionAppProtocolUnknown
            category = .malformedMessage
            description = "Native messaging payload\(hostDescription) is malformed."
        case .malformedHostResponse:
            code = .companionAppProtocolUnknown
            category = .malformedMessage
            description = "Native messaging host\(hostDescription) returned a malformed response."
        case .portDisconnected:
            code = .relayCancelled
            category = .portDisconnected
            description = "Native messaging host\(hostDescription) disconnected."
        case .timeout:
            code = .relayTimeout
            category = .timeout
            description = "Native messaging host\(hostDescription) did not respond in time."
        }

        let relayError = SumiNativeMessagingRelay.makeError(
            code: code,
            description: description,
            diagnostic: nil
        )
        var userInfo = relayError.userInfo
        userInfo[failureCategoryUserInfoKey] = category.rawValue
        if let hostName {
            userInfo["SumiNativeMessagingNativeHostName"] = hostName
        }
        return NSError(domain: relayError.domain, code: relayError.code, userInfo: userInfo)
    }
}

typealias SumiNativeMessagingBackendRegistry = SumiNativeMessagingAdapterRegistry

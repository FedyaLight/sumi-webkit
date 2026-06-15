//
//  CompanionApplicationMessageRouter.swift
//  Sumi
//
//  Context-scoped Safari containing-application message routing.
//

import Foundation

struct CompanionApplicationMessageContext {
    let applicationIdentifier: String
    let extensionId: String
    let profileId: UUID?
    let installedExtension: InstalledExtension
}

struct CompanionApplicationMessageRequest {
    let context: CompanionApplicationMessageContext
    /// Opaque WebKit payload. Backends must not log this value.
    let message: Any
}

@MainActor
protocol CompanionApplicationMessageBackend: AnyObject {
    var backendIdentifier: String { get }

    func supports(context: CompanionApplicationMessageContext) -> Bool

    /// Must call `replyHandler` exactly once.
    func handle(
        request: CompanionApplicationMessageRequest,
        replyHandler: @escaping (Any?, (any Error)?) -> Void
    )
}

@MainActor
final class CompanionApplicationBackendRegistry {
    static let shared = CompanionApplicationBackendRegistry(
        backends: CompanionApplicationBackendRegistry.defaultBackends()
    )

    private let backends: [CompanionApplicationMessageBackend]

    init(backends: [CompanionApplicationMessageBackend] = []) {
        self.backends = backends
    }

    func backend(
        for context: CompanionApplicationMessageContext
    ) -> CompanionApplicationMessageBackend? {
        backends.first { $0.supports(context: context) }
    }

    var registeredBackendIdentifiers: [String] {
        backends.map(\.backendIdentifier).sorted()
    }

    private static func defaultBackends() -> [CompanionApplicationMessageBackend] {
        [ProtonPassSafariApplicationIDAdapter()]
    }
}

@MainActor
final class CompanionApplicationMessageRouter {
    private let registry: CompanionApplicationBackendRegistry

    init(registry: CompanionApplicationBackendRegistry = .shared) {
        self.registry = registry
    }

    func canRoute(applicationIdentifier: String?) -> Bool {
        SafariExtensionNativeMessagingRoutingProbe
            .isSafariContainingApplicationRequest(applicationIdentifier)
    }

    func route(
        applicationIdentifier: String?,
        message: Any,
        extensionId: String,
        profileId: UUID?,
        installedExtension: InstalledExtension?,
        replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) -> Bool {
        guard canRoute(applicationIdentifier: applicationIdentifier) else {
            return false
        }

        guard let identifier = applicationIdentifier,
              let installedExtension
        else {
            replyHandler(
                nil,
                CompanionApplicationMessageError.unsupportedApplicationId
                    .relayError()
            )
            return true
        }

        let context = CompanionApplicationMessageContext(
            applicationIdentifier: identifier,
            extensionId: extensionId,
            profileId: profileId,
            installedExtension: installedExtension
        )

        guard let backend = registry.backend(for: context) else {
            replyHandler(
                nil,
                CompanionApplicationMessageError.unsupportedBackend
                    .relayError()
            )
            return true
        }

        let once = CompanionApplicationOnceReplyHandler(replyHandler)
        backend.handle(
            request: CompanionApplicationMessageRequest(
                context: context,
                message: message
            ),
            replyHandler: { value, error in
                once.call(value, error)
            }
        )
        return true
    }
}

private final class CompanionApplicationOnceReplyHandler {
    private let lock = NSLock()
    private var didReply = false
    private let replyHandler: (Any?, (any Error)?) -> Void

    init(_ replyHandler: @escaping (Any?, (any Error)?) -> Void) {
        self.replyHandler = replyHandler
    }

    func call(_ value: Any?, _ error: (any Error)?) {
        lock.lock()
        if didReply {
            lock.unlock()
            return
        }
        didReply = true
        lock.unlock()
        replyHandler(value, error)
    }
}

enum CompanionApplicationMessageError: Error, Equatable {
    case unsupportedApplicationId
    case unsupportedExtension
    case unsupportedBackend
    case invalidPayload
    case unsupportedMessageType(String?)
    case secureStoreFailure
    case exactlyOnceReplyViolation
    case secureStateMissing

    func relayError() -> NSError {
        let code: SumiNativeMessagingRelay.ErrorCode
        let message: String

        switch self {
        case .unsupportedApplicationId:
            code = .companionApplicationUnsupportedApplicationId
            message = "Safari containing-application messaging only supports application.id."
        case .unsupportedExtension:
            code = .companionApplicationUnsupportedExtension
            message = "Safari containing-application messaging is not supported for this extension."
        case .unsupportedBackend:
            code = .companionApplicationUnsupportedBackend
            message = "No Sumi companion application backend is registered for this extension."
        case .invalidPayload:
            code = .companionApplicationInvalidPayload
            message = "The companion application message payload is invalid."
        case .unsupportedMessageType:
            code = .companionApplicationUnsupportedMessageType
            message = "The companion application message type is unsupported."
        case .secureStoreFailure:
            code = .companionApplicationSecureStoreFailure
            message = "The companion application secure store operation failed."
        case .exactlyOnceReplyViolation:
            code = .companionApplicationExactlyOnceReplyViolation
            message = "The companion application backend attempted to reply more than once."
        case .secureStateMissing:
            code = .companionApplicationSecureStateMissing
            message = "The companion application secure state is missing."
        }

        return SumiNativeMessagingErrorMapper.relayError(
            code: code,
            description: message,
            diagnostic: nil
        )
    }
}

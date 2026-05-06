//
//  ExtensionManagerSupport+BrokerSubfeatures.swift
//  Sumi
//
//  Subfeature adapters that route SumiUserScriptMessageBroker messages
//  to the existing ExtensionManager handlers for externally_connectable.
//

import Foundation
import WebKit

// MARK: - Page-world subfeature (sendMessage + connect from web pages)

@available(macOS 15.5, *)
@MainActor
final class ExternallyConnectablePageSubfeature: NSObject, @MainActor SumiUserScriptSubfeature {
    let featureName = "runtime"
    let messageOriginPolicy: SumiUserScriptMessageOriginPolicy = .all

    weak var manager: ExtensionManager?

    init(manager: ExtensionManager) {
        self.manager = manager
        super.init()
    }

    func handler(forMethodNamed method: String) -> SumiUserScriptSubfeature.Handler? {
        switch method {
        case "runtime.sendMessage", "sendMessage":
            return { [weak self] _, original in
                try await self?.relay(message: original)
            }
        case "runtime.connect.open", "runtime.connect.postMessage",
             "runtime.connect.disconnect":
            return { [weak self] _, original in
                try await self?.relay(message: original)
            }
        default:
            return nil
        }
    }

    private func relay(message: WKScriptMessage) async throws -> SumiJSONValue {
        guard let manager else {
            throw ExternallyConnectableSubfeatureError.managerUnavailable
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<SumiJSONValue, Error>) in
            manager.handleExternallyConnectableNativeMessage(message) { reply, errorMessage in
                if let errorMessage {
                    continuation.resume(throwing: ExternallyConnectableSubfeatureError.nativeError(errorMessage))
                } else {
                    continuation.resume(returning: SumiJSONValue(foundationObject: reply))
                }
            }
        }
    }
}

private enum ExternallyConnectableSubfeatureError: LocalizedError {
    case managerUnavailable
    case nativeError(String)

    var errorDescription: String? {
        switch self {
        case .managerUnavailable:
            return "Extension manager is unavailable"
        case .nativeError(let message):
            return message
        }
    }
}

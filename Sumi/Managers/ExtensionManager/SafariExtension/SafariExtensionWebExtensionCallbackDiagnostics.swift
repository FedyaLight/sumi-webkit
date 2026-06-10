//
//  SafariExtensionWebExtensionCallbackDiagnostics.swift
//  Sumi
//
//  DEBUG-only ordered trace buckets for generic WebExtension callback contracts.
//  Never logs credentials, native message bodies, or storage payloads.
//

import Foundation
import WebKit

enum SafariExtensionWebExtensionCallbackAPI: String, Codable, CaseIterable, Sendable {
    case runtimeSendNativeMessage
    case connectNativePort
    case tabsSendMessage
    case scriptingExecuteScript
    case runtimeSendMessage
    case contentScriptReply
    case tabAdapterCompletion
    case windowAdapterCompletion
    case actionPopupPresentation
    case optionsPagePresentation
    case openNewTab
    case openNewWindow
}

enum SafariExtensionWebExtensionCallbackDiagnosticBucket: String, Codable, CaseIterable, Sendable {
    case failureApiRuntimeSendNativeMessage
    case failureApiConnectNativePort
    case failureApiTabsSendMessage
    case failureApiScriptingExecuteScript
    case failureApiRuntimeSendMessage
    case failureApiContentScriptReply
    case errorObjectNull
    case errorMessageMissing
    case successReturnedWhereErrorExpected
    case errorReturnedWhereSuccessExpected
    case replyHandlerWrongShape
    case callbackCalledTwice
    case callbackNeverCalled
    case unknownNeedsStackTrace
}

struct SafariExtensionWebExtensionCallbackDiagnosticSnapshot: Codable, Equatable, Sendable {
    let recordedAt: Date
    let bucketCounts: [String: Int]
    let lastBuckets: [String]
    let lastAPIs: [String]
}

@MainActor
enum SafariExtensionWebExtensionCallbackDiagnostics {
    private static var bucketCounts: [SafariExtensionWebExtensionCallbackDiagnosticBucket: Int] = [:]
    private static var recentBuckets: [SafariExtensionWebExtensionCallbackDiagnosticBucket] = []
    private static var recentAPIs: [SafariExtensionWebExtensionCallbackAPI] = []
    private static let recentLimit = 64

    static func resetForTesting() {
        bucketCounts = [:]
        recentBuckets = []
        recentAPIs = []
    }

    static func record(
        _ bucket: SafariExtensionWebExtensionCallbackDiagnosticBucket,
        api: SafariExtensionWebExtensionCallbackAPI,
        extensionId: String? = nil,
        note: String? = nil
    ) {
        guard RuntimeDiagnostics.isVerboseEnabled else { return }

        bucketCounts[bucket, default: 0] += 1
        recentBuckets.append(bucket)
        recentAPIs.append(api)
        if recentBuckets.count > recentLimit {
            recentBuckets.removeFirst(recentBuckets.count - recentLimit)
            recentAPIs.removeFirst(recentAPIs.count - recentLimit)
        }

        RuntimeDiagnostics.debug(category: "SafariWebExtCallback") {
            var line = "bucket=\(bucket.rawValue) api=\(api.rawValue)"
            if let extensionId {
                line += " ext=\(extensionId)"
            }
            if let note, note.isEmpty == false {
                line += " note=\(note)"
            }
            return line
        }
    }

    static func recordFailure(
        api: SafariExtensionWebExtensionCallbackAPI,
        extensionId: String?,
        error: (any Error)?
    ) {
        let failureBucket = failureBucket(for: api)
        record(failureBucket, api: api, extensionId: extensionId)

        guard let error else {
            record(.errorObjectNull, api: api, extensionId: extensionId)
            return
        }

        let nsError = error as NSError
        if SumiWebExtensionCallbackErrorMapper.hasSerializableMessage(nsError) == false {
            record(.errorMessageMissing, api: api, extensionId: extensionId)
        }
    }

    static func recordSuccess(
        api: SafariExtensionWebExtensionCallbackAPI,
        extensionId: String?,
        value: Any?
    ) {
        if value == nil, api.expectsNonNilSuccessValue {
            record(
                .successReturnedWhereErrorExpected,
                api: api,
                extensionId: extensionId,
                note: "nilSuccessValue"
            )
        }
    }

    static func snapshot() -> SafariExtensionWebExtensionCallbackDiagnosticSnapshot {
        SafariExtensionWebExtensionCallbackDiagnosticSnapshot(
            recordedAt: Date(),
            bucketCounts: Dictionary(
                uniqueKeysWithValues: bucketCounts.map { ($0.key.rawValue, $0.value) }
            ),
            lastBuckets: recentBuckets.map(\.rawValue),
            lastAPIs: recentAPIs.map(\.rawValue)
        )
    }

    private static func failureBucket(
        for api: SafariExtensionWebExtensionCallbackAPI
    ) -> SafariExtensionWebExtensionCallbackDiagnosticBucket {
        switch api {
        case .runtimeSendNativeMessage:
            return .failureApiRuntimeSendNativeMessage
        case .connectNativePort:
            return .failureApiConnectNativePort
        case .tabsSendMessage:
            return .failureApiTabsSendMessage
        case .scriptingExecuteScript:
            return .failureApiScriptingExecuteScript
        case .runtimeSendMessage:
            return .failureApiRuntimeSendMessage
        case .contentScriptReply:
            return .failureApiContentScriptReply
        case .tabAdapterCompletion,
             .windowAdapterCompletion,
             .actionPopupPresentation,
             .optionsPagePresentation,
             .openNewTab,
             .openNewWindow:
            return .unknownNeedsStackTrace
        }
    }
}

private extension SafariExtensionWebExtensionCallbackAPI {
    var expectsNonNilSuccessValue: Bool {
        switch self {
        case .runtimeSendNativeMessage, .connectNativePort:
            return false
        case .tabsSendMessage,
             .scriptingExecuteScript,
             .runtimeSendMessage,
             .contentScriptReply,
             .tabAdapterCompletion,
             .windowAdapterCompletion,
             .actionPopupPresentation,
             .optionsPagePresentation,
             .openNewTab,
             .openNewWindow:
            return false
        }
    }
}

@MainActor
enum SumiWebExtensionCallbackRelay {
    static func wrapNativeMessagingReplyHandler(
        api: SafariExtensionWebExtensionCallbackAPI,
        extensionId: String?,
        _ handler: @escaping (Any?, (any Error)?) -> Void
    ) -> (Any?, (any Error)?) -> Void {
        var fulfilled = false
        return { value, error in
            guard fulfilled == false else {
                SafariExtensionWebExtensionCallbackDiagnostics.record(
                    .callbackCalledTwice,
                    api: api,
                    extensionId: extensionId
                )
                return
            }
            fulfilled = true

            if let error {
                let mapped = SumiWebExtensionCallbackErrorMapper.webExtensionCallbackError(from: error)
                SafariExtensionWebExtensionCallbackDiagnostics.recordFailure(
                    api: api,
                    extensionId: extensionId,
                    error: mapped
                )
                handler(value, mapped)
                return
            }

            SafariExtensionWebExtensionCallbackDiagnostics.recordSuccess(
                api: api,
                extensionId: extensionId,
                value: value
            )
            handler(value, nil)
        }
    }

    static func wrapCompletionHandler(
        api: SafariExtensionWebExtensionCallbackAPI,
        extensionId: String?,
        _ handler: @escaping ((any Error)?) -> Void
    ) -> ((any Error)?) -> Void {
        var fulfilled = false
        return { error in
            guard fulfilled == false else {
                SafariExtensionWebExtensionCallbackDiagnostics.record(
                    .callbackCalledTwice,
                    api: api,
                    extensionId: extensionId
                )
                return
            }
            fulfilled = true

            if let error {
                let mapped = SumiWebExtensionCallbackErrorMapper.webExtensionCallbackError(from: error)
                SafariExtensionWebExtensionCallbackDiagnostics.recordFailure(
                    api: api,
                    extensionId: extensionId,
                    error: mapped
                )
                handler(mapped)
                return
            }

            SafariExtensionWebExtensionCallbackDiagnostics.recordSuccess(
                api: api,
                extensionId: extensionId,
                value: true
            )
            handler(nil)
        }
    }

    static func wrapTabResultCompletionHandler(
        api: SafariExtensionWebExtensionCallbackAPI,
        extensionId: String?,
        _ handler: @escaping ((any WKWebExtensionTab)?, (any Error)?) -> Void
    ) -> ((any WKWebExtensionTab)?, (any Error)?) -> Void {
        var fulfilled = false
        return { tab, error in
            guard fulfilled == false else {
                SafariExtensionWebExtensionCallbackDiagnostics.record(
                    .callbackCalledTwice,
                    api: api,
                    extensionId: extensionId
                )
                return
            }
            fulfilled = true

            if let error {
                let mapped = SumiWebExtensionCallbackErrorMapper.webExtensionCallbackError(from: error)
                SafariExtensionWebExtensionCallbackDiagnostics.recordFailure(
                    api: api,
                    extensionId: extensionId,
                    error: mapped
                )
                handler(nil, mapped)
                return
            }

            if tab == nil {
                SafariExtensionWebExtensionCallbackDiagnostics.record(
                    .errorReturnedWhereSuccessExpected,
                    api: api,
                    extensionId: extensionId,
                    note: "nilTab"
                )
            } else {
                SafariExtensionWebExtensionCallbackDiagnostics.recordSuccess(
                    api: api,
                    extensionId: extensionId,
                    value: tab
                )
            }
            handler(tab, nil)
        }
    }
}

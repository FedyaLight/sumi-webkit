//
//  ChromeMV3ScriptingExecuteScriptExecutor.swift
//  Sumi
//
//  Narrow controlled-path chrome.scripting.executeScript({ files }) executor
//  for enabled local unpacked MV3 extensions. Executes package-local JS into
//  an eligible normal-tab WKWebView isolated content world only.
//

import Foundation

#if canImport(WebKit)
import WebKit
#endif

struct ChromeMV3ScriptingExecuteScriptResolvedFile:
    Codable,
    Equatable,
    Sendable
{
    var relativePath: String
    var fileURL: URL
}

#if canImport(WebKit)
@MainActor
struct ChromeMV3ScriptingExecuteScriptWebViewTarget {
    weak var webView: WKWebView?
    var contentWorld: WKContentWorld
    var contentWorldName: String
    var frameID: Int
    var localTabID: Int
}

struct ChromeMV3ScriptingExecuteScriptExecutorRequest {
    var extensionID: String
    var profileID: String
    var tabID: Int
    var frameID: Int
    var documentID: String?
    var allFrames: Bool
    var frameIDs: [Int]?
    var world: String
    var injectImmediately: Bool
    var files: [ChromeMV3ScriptingExecuteScriptResolvedFile]
}

struct ChromeMV3ScriptingExecuteScriptExecutorResult:
    Codable,
    Equatable,
    Sendable
{
    var succeeded: Bool
    var lastError: ChromeMV3RuntimeLastErrorCase?
    var injectionResults: [ChromeMV3StorageValue]
    var diagnostics: [String]
    var executionClassifier: String
    var permissionClassifier: String
    var resultFrameCount: Int
}

@MainActor
enum ChromeMV3ScriptingExecuteScriptExecutor {
    static func execute(
        request: ChromeMV3ScriptingExecuteScriptExecutorRequest,
        target: ChromeMV3ScriptingExecuteScriptWebViewTarget?
    ) async -> ChromeMV3ScriptingExecuteScriptExecutorResult {
        let fileShapes = request.files.map(\.relativePath).sorted()
        var diagnostics = [
            "method=scripting.executeScript",
            "scripting.executeScript target.tabId=\(request.tabID).",
            "scripting.executeScript fileCount=\(fileShapes.count).",
            "scripting.executeScript fileShapes=\(fileShapes.joined(separator: ","))",
            "scripting.executeScript world=\(request.world)\(request.world == "ISOLATED" ? "(default)" : "").",
            "scripting.executeScript injectImmediately=\(request.injectImmediately).",
            "scripting.executeScript allFrames=\(request.allFrames).",
        ]
        if let frameIDs = request.frameIDs {
            diagnostics.append(
                "scripting.executeScript frameIds=\(frameIDs.sorted().map(String.init).joined(separator: ","))"
            )
        } else {
            diagnostics.append(
                "scripting.executeScript frameIds=\(request.frameID)"
            )
        }

        guard request.allFrames == false else {
            diagnostics.append(
                "scripting.executeScript allFrames=true is not supported in this controlled developer-preview executor."
            )
            return failure(
                .unsupportedAPI,
                diagnostics: diagnostics,
                executionClassifier: "allFramesUnsupported",
                permissionClassifier: "notEvaluated",
                resultFrameCount: 0
            )
        }

        let selectedFrameID: Int
        if let frameIDs = request.frameIDs {
            guard frameIDs.count == 1, frameIDs[0] == 0 else {
                diagnostics.append(
                    "scripting.executeScript requested frame targeting outside the supported top/main frame."
                )
                return failure(
                    frameIDs.isEmpty ? .targetFrameMissing : .unsupportedAPI,
                    diagnostics: diagnostics,
                    executionClassifier: "multiFrameUnsupported",
                    permissionClassifier: "notEvaluated",
                    resultFrameCount: 0
                )
            }
            selectedFrameID = 0
        } else {
            guard request.frameID == 0 else {
                diagnostics.append(
                    "scripting.executeScript requested a non-top frame outside the supported Raindrop/main-frame shape."
                )
                return failure(
                    .unsupportedAPI,
                    diagnostics: diagnostics,
                    executionClassifier: "nonTopFrameUnsupported",
                    permissionClassifier: "notEvaluated",
                    resultFrameCount: 0
                )
            }
            selectedFrameID = 0
        }
        _ = request.documentID

        guard let target else {
            diagnostics.append(
                "scripting.executeScript found no eligible normal-tab WKWebView target for the requested tab/frame."
            )
            diagnostics.append(
                "executionClassifier=targetWebViewUnavailable permissionClassifier=notEvaluated resultFrameCount=0"
            )
            return failure(
                .contextNotLoaded,
                diagnostics: diagnostics,
                executionClassifier: "targetWebViewUnavailable",
                permissionClassifier: "notEvaluated",
                resultFrameCount: 0
            )
        }
        guard let webView = target.webView else {
            diagnostics.append(
                "scripting.executeScript target WKWebView was released before execution."
            )
            diagnostics.append(
                "executionClassifier=webViewReleased permissionClassifier=notEvaluated resultFrameCount=0"
            )
            return failure(
                .contextNotLoaded,
                diagnostics: diagnostics,
                executionClassifier: "webViewReleased",
                permissionClassifier: "notEvaluated",
                resultFrameCount: 0
            )
        }
        guard target.localTabID == request.tabID,
              target.frameID == selectedFrameID
        else {
            diagnostics.append(
                "scripting.executeScript target lookup returned a mismatched tab/frame binding."
            )
            return failure(
                .targetTabMissing,
                diagnostics: diagnostics,
                executionClassifier: "targetBindingMismatch",
                permissionClassifier: "notEvaluated",
                resultFrameCount: 0
            )
        }

        diagnostics.append(
            "scripting.executeScript contentWorld=\(target.contentWorldName)."
        )
        diagnostics.append(
            "permissionClassifier=validatedBeforeExecution executionClassifier=pending"
        )

        var sources: [String] = []
        for file in request.files {
            guard let source = try? String(
                contentsOf: file.fileURL,
                encoding: .utf8
            ) else {
                diagnostics.append(
                    "scripting.executeScript could not read package-local file \(file.relativePath)."
                )
                return failure(
                    .unsupportedAPI,
                    diagnostics: diagnostics,
                    executionClassifier: "packageFileReadFailed",
                    permissionClassifier: "validatedBeforeExecution",
                    resultFrameCount: 0
                )
            }
            sources.append(source)
        }

        var lastResult: Any?
        do {
            for source in sources {
                lastResult = try await webView.evaluateJavaScript(
                    source,
                    in: nil,
                    contentWorld: target.contentWorld
                )
            }
        } catch {
            diagnostics.append(
                "scripting.executeScript WebKit evaluation failed: \(error.localizedDescription)"
            )
            diagnostics.append(
                "executionClassifier=evaluateJavaScriptFailed permissionClassifier=validatedBeforeExecution resultFrameCount=0"
            )
            return failure(
                .contextNotLoaded,
                diagnostics: diagnostics,
                executionClassifier: "evaluateJavaScriptFailed",
                permissionClassifier: "validatedBeforeExecution",
                resultFrameCount: 0
            )
        }

        let resultValue =
            ChromeMV3ScriptingExecuteScriptExecutor.storageValue(
                fromWebKitResult: lastResult
            ) ?? .null
        let injectionResult = ChromeMV3StorageValue.object([
            "documentId": .string("document-\(selectedFrameID)"),
            "frameId": .number(Double(selectedFrameID)),
            "result": resultValue,
        ])
        diagnostics.append(
            "scripting.executeScript executed package-local files[] in the eligible isolated content world."
        )
        diagnostics.append(
            "executionClassifier=filesExecuted permissionClassifier=validatedBeforeExecution resultFrameCount=1"
        )
        diagnostics.append(
            "scripting.executeScript resultShape=\(valueShape(resultValue))."
        )
        diagnostics.append(
            "Chrome-compatible executeScript must execute in an eligible target frame or reject; modeled no-op success is blocked."
        )
        diagnostics.append(
            "No fake executeScript success, fake content-script listener, fake runtime response, remote script, inline function, MAIN-world injection, or native host launch occurred."
        )
        return ChromeMV3ScriptingExecuteScriptExecutorResult(
            succeeded: true,
            lastError: nil,
            injectionResults: [injectionResult],
            diagnostics: uniqueSortedExecuteScript(diagnostics),
            executionClassifier: "filesExecuted",
            permissionClassifier: "validatedBeforeExecution",
            resultFrameCount: 1
        )
    }

    private static func failure(
        _ error: ChromeMV3RuntimeLastErrorCase,
        diagnostics: [String],
        executionClassifier: String,
        permissionClassifier: String,
        resultFrameCount: Int
    ) -> ChromeMV3ScriptingExecuteScriptExecutorResult {
        ChromeMV3ScriptingExecuteScriptExecutorResult(
            succeeded: false,
            lastError: error,
            injectionResults: [],
            diagnostics: uniqueSortedExecuteScript(diagnostics),
            executionClassifier: executionClassifier,
            permissionClassifier: permissionClassifier,
            resultFrameCount: resultFrameCount
        )
    }

    private static func storageValue(
        fromWebKitResult value: Any?
    ) -> ChromeMV3StorageValue? {
        guard let value else { return .null }
        if value is NSNull { return .null }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            let double = number.doubleValue
            guard double.isFinite else { return nil }
            return .number(double)
        }
        if let string = value as? String {
            return .string(string)
        }
        if let array = value as? [Any] {
            var values: [ChromeMV3StorageValue] = []
            for item in array {
                guard let converted = storageValue(fromWebKitResult: item)
                else { return nil }
                values.append(converted)
            }
            return .array(values)
        }
        if let object = value as? [String: Any] {
            var values: [String: ChromeMV3StorageValue] = [:]
            for (key, item) in object {
                guard let converted = storageValue(fromWebKitResult: item)
                else { return nil }
                values[key] = converted
            }
            return .object(values)
        }
        return nil
    }

    private static func valueShape(_ value: ChromeMV3StorageValue) -> String {
        switch value {
        case .array:
            return "array"
        case .bool:
            return "boolean"
        case .null:
            return "undefined"
        case .number:
            return "number"
        case .object:
            return "object"
        case .string:
            return "string"
        }
    }
}

private func uniqueSortedExecuteScript(_ values: [String]) -> [String] {
    Array(Set(values.filter { $0.isEmpty == false })).sorted()
}
#endif

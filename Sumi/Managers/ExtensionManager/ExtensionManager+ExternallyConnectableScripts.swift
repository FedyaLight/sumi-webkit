//
//  ExtensionManager+ExternallyConnectableScripts.swift
//  Sumi
//
//  Bundled runtime script assembly for externally_connectable and WebKit compatibility.
//

import Foundation

@available(macOS 15.5, *)
extension ExtensionManager {
    nonisolated static let externallyConnectablePageBridgeTemplateFilename =
        "externally_connectable_page_bridge.js"
    nonisolated static let externallyConnectableIsolatedBridgeTemplateFilename =
        "externally_connectable_isolated_bridge.js"
    nonisolated static let externallyConnectableBackgroundHelperTemplateFilename =
        "externally_connectable_background_helper.js"
    nonisolated static let externallyConnectableWorkerTemplateFilename =
        "externally_connectable_worker.js"
    nonisolated static let webKitRuntimeCompatibilityTemplateFilename =
        "webkit_runtime_compat.js"
    nonisolated static let webKitRuntimeCompatibilityWorkerTemplateFilename =
        "webkit_runtime_compat_worker.js"
    nonisolated static let selectiveContentScriptGuardTemplateFilename =
        "selective_content_script_guard.js"

    @MainActor
    static func pageWorldExternallyConnectableBridgeScript(
        configJSON: String,
        bridgeMarker: String
    ) -> String {
        renderedExtensionRuntimeTemplate(
            named: externallyConnectablePageBridgeTemplateFilename,
            replacements: [
                "__SUMI_BRIDGE_MARKER__": bridgeMarker,
                "__SUMI_BRIDGE_MARKER_STRING__": jsonStringLiteral(bridgeMarker),
                "__SUMI_CONFIG_JSON__": configJSON,
            ]
        )
    }

    nonisolated static func isolatedWorldExternallyConnectableBridgeScript() -> String {
        renderedExtensionRuntimeTemplate(
            named: externallyConnectableIsolatedBridgeTemplateFilename,
            replacements: [
                "__SUMI_DEBUG_LOGGING_ENABLED__":
                    externallyConnectableBridgeDebugLoggingLiteral
            ]
        )
    }

    nonisolated static func externallyConnectableBackgroundHelperScript() -> String {
        renderedExtensionRuntimeTemplate(
            named: externallyConnectableBackgroundHelperTemplateFilename
        )
    }

    nonisolated static func webKitRuntimeCompatibilityPreludeScript(
        browserSpecificSettings: [String: Any]?
    ) -> String {
        renderedExtensionRuntimeTemplate(
            named: webKitRuntimeCompatibilityTemplateFilename,
            replacements: [
                "__SUMI_BROWSER_SPECIFIC_SETTINGS_JSON__":
                    jsonObjectLiteral(browserSpecificSettings ?? [:])
            ]
        )
    }

    nonisolated static func webKitRuntimeCompatibilityServiceWorkerWrapperScript(
        originalServiceWorker: String,
        backgroundType: String?
    ) -> String {
        let mode = backgroundType == "module" ? "module" : "classic"
        let workerImports: String
        if backgroundType == "module" {
            workerImports = """
            import \(jsonStringLiteral(webKitRuntimeCompatibilityPreludeFilename));
            import \(jsonStringLiteral(originalServiceWorker));
            """
        } else {
            workerImports = """
            importScripts(\(jsonStringLiteral(webKitRuntimeCompatibilityPreludeFilename)), \(jsonStringLiteral(originalServiceWorker)));
            """
        }

        return renderedExtensionRuntimeTemplate(
            named: webKitRuntimeCompatibilityWorkerTemplateFilename,
            replacements: [
                "__SUMI_BACKGROUND_TYPE__": mode,
                "__SUMI_ORIGINAL_SERVICE_WORKER__": originalServiceWorker,
                "__SUMI_WORKER_IMPORTS__": workerImports,
            ]
        )
    }

    nonisolated static func externallyConnectableServiceWorkerWrapperScript(
        originalServiceWorker: String,
        backgroundType: String?
    ) -> String {
        let mode = backgroundType == "module" ? "module" : "classic"
        let workerImports: String
        if backgroundType == "module" {
            workerImports = """
            import \(jsonStringLiteral(externallyConnectableBackgroundHelperFilename));
            import \(jsonStringLiteral(originalServiceWorker));
            """
        } else {
            workerImports = """
            importScripts(\(jsonStringLiteral(externallyConnectableBackgroundHelperFilename)), \(jsonStringLiteral(originalServiceWorker)));
            """
        }

        return renderedExtensionRuntimeTemplate(
            named: externallyConnectableWorkerTemplateFilename,
            replacements: [
                "__SUMI_BACKGROUND_TYPE__": mode,
                "__SUMI_ORIGINAL_SERVICE_WORKER__": originalServiceWorker,
                "__SUMI_WORKER_IMPORTS__": workerImports,
            ]
        )
    }

    nonisolated static func selectiveContentScriptGuardScript(
        markerAttribute: String,
        originalScriptFilenames: [String]
    ) -> String {
        renderedExtensionRuntimeTemplate(
            named: selectiveContentScriptGuardTemplateFilename,
            replacements: [
                "__SUMI_MARKER_ATTRIBUTE_STRING__": jsonStringLiteral(markerAttribute),
                "__SUMI_ORIGINAL_SCRIPT_FILENAMES_JSON__":
                    jsonObjectLiteral(originalScriptFilenames),
            ]
        )
    }

    nonisolated static func jsonStringLiteral(_ value: String) -> String {
        let data = try? JSONSerialization.data(
            withJSONObject: [value],
            options: []
        )
        guard let data,
              let arrayLiteral = String(data: data, encoding: .utf8),
              arrayLiteral.count >= 2
        else {
            return "\"\""
        }

        return String(arrayLiteral.dropFirst().dropLast())
    }

    nonisolated static func jsonObjectLiteral(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(
                withJSONObject: value,
                options: [.sortedKeys]
              ),
              let literal = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }

        return literal
    }

    private nonisolated static func renderedExtensionRuntimeTemplate(
        named fileName: String,
        replacements: [String: String] = [:]
    ) -> String {
        guard let rendered = ExtensionRuntimeBundledScript.rendered(
            fileName: fileName,
            replacements: replacements
        ) else {
            assertionFailure("Missing bundled extension runtime template: \(fileName)")
            return ""
        }

        return rendered
    }
}

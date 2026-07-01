import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionRuntimeSessionOwner {
    var cachedWebExtensionsByID: [String: WKWebExtension] = [:]
    var cachedWebExtensionRuntimeSourceKeysByID:
        [String: ExtensionManager.WebExtensionRuntimeSourceKey] = [:]
    var lastExtensionLoadErrors: [String: Error] = [:]
    var extensionRuntimeResidencyState = ExtensionRuntimeResidencyState()
    var runtimeState: ExtensionManager.ExtensionRuntimeState = .idle
    var allowsRuntimeWithoutEnabledExtensions = false
    var runtimeInitializationTask: Task<Void, Never>?
    var loadedExtensionManifests: [String: [String: Any]] = [:]
    var runtimeMetricsByExtensionID:
        [String: ExtensionManager.ExtensionRuntimeMetrics] = [:]
    var extensionLoadGeneration: UInt64 = 0
    var tabOpenNotificationGeneration: UInt64 = 1

    func recordRuntimeMetric(
        for extensionId: String,
        update: (inout ExtensionManager.ExtensionRuntimeMetrics) -> Void
    ) {
        var metrics = runtimeMetricsByExtensionID[extensionId]
            ?? ExtensionManager.ExtensionRuntimeMetrics()
        update(&metrics)
        runtimeMetricsByExtensionID[extensionId] = metrics
    }
}

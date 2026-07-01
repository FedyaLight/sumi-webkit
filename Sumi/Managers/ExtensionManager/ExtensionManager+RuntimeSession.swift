import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    var cachedWebExtensionsByID: [String: WKWebExtension] {
        get { runtimeSessionOwner.cachedWebExtensionsByID }
        set { runtimeSessionOwner.cachedWebExtensionsByID = newValue }
    }

    var cachedWebExtensionRuntimeSourceKeysByID: [String: WebExtensionRuntimeSourceKey] {
        get { runtimeSessionOwner.cachedWebExtensionRuntimeSourceKeysByID }
        set { runtimeSessionOwner.cachedWebExtensionRuntimeSourceKeysByID = newValue }
    }

    var lastExtensionLoadErrors: [String: Error] {
        get { runtimeSessionOwner.lastExtensionLoadErrors }
        set { runtimeSessionOwner.lastExtensionLoadErrors = newValue }
    }

    var extensionRuntimeResidencyState: ExtensionRuntimeResidencyState {
        get { runtimeSessionOwner.extensionRuntimeResidencyState }
        set { runtimeSessionOwner.extensionRuntimeResidencyState = newValue }
    }

    var runtimeState: ExtensionRuntimeState {
        get { runtimeSessionOwner.runtimeState }
        set { runtimeSessionOwner.runtimeState = newValue }
    }

    var allowsRuntimeWithoutEnabledExtensions: Bool {
        get { runtimeSessionOwner.allowsRuntimeWithoutEnabledExtensions }
        set { runtimeSessionOwner.allowsRuntimeWithoutEnabledExtensions = newValue }
    }

    var runtimeInitializationTask: Task<Void, Never>? {
        get { runtimeSessionOwner.runtimeInitializationTask }
        set { runtimeSessionOwner.runtimeInitializationTask = newValue }
    }

    var loadedExtensionManifests: [String: [String: Any]] {
        get { runtimeSessionOwner.loadedExtensionManifests }
        set { runtimeSessionOwner.loadedExtensionManifests = newValue }
    }

    var runtimeMetricsByExtensionID: [String: ExtensionRuntimeMetrics] {
        get { runtimeSessionOwner.runtimeMetricsByExtensionID }
        set { runtimeSessionOwner.runtimeMetricsByExtensionID = newValue }
    }

    var extensionLoadGeneration: UInt64 {
        get { runtimeSessionOwner.extensionLoadGeneration }
        set { runtimeSessionOwner.extensionLoadGeneration = newValue }
    }

    var tabOpenNotificationGeneration: UInt64 {
        get { runtimeSessionOwner.tabOpenNotificationGeneration }
        set { runtimeSessionOwner.tabOpenNotificationGeneration = newValue }
    }

    func recordRuntimeMetric(
        for extensionId: String,
        update: (inout ExtensionRuntimeMetrics) -> Void
    ) {
        runtimeSessionOwner.recordRuntimeMetric(for: extensionId, update: update)
    }
}

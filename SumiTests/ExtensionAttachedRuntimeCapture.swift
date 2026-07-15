@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class ExtensionAttachedRuntimeCapture {
    private var installedRuntime: ExtensionAttachedBrowserRuntimeInspection?

    func install(_ runtime: ExtensionAttachedBrowserRuntimeInspection) {
        precondition(
            installedRuntime == nil,
            "Attached extension runtime must be installed exactly once"
        )
        installedRuntime = runtime
    }

    var hasInstalledRuntime: Bool { installedRuntime != nil }

    var runtime: ExtensionAttachedBrowserRuntimeInspection {
        guard let installedRuntime else {
            preconditionFailure(
                "Test requires an attached immutable extension browser graph"
            )
        }
        return installedRuntime
    }
}

@available(macOS 15.5, *)
@MainActor
final class ExtensionManagerInspectionCapture {
    private var assembledInspection: ExtensionManagerTestInspection?

    func install(_ inspection: ExtensionManagerTestInspection) {
        precondition(
            assembledInspection == nil,
            "Extension manager test inspection must be assembled exactly once"
        )
        assembledInspection = inspection
    }

    var inspection: ExtensionManagerTestInspection {
        guard let assembledInspection else {
            preconditionFailure(
                "Test requires explicit ExtensionManager assembly inspection"
            )
        }
        return assembledInspection
    }
}

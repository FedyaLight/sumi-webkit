import Foundation

@available(macOS 15.5, *)
@MainActor
struct ExtensionManagerBrowserAttachment {
    private let attacher: ExtensionBrowserRuntimeAttacher

    init(attacher: ExtensionBrowserRuntimeAttacher) {
        self.attacher = attacher
    }

    func attach(to browserManager: BrowserManager) {
        attacher.attach(browserManager: browserManager)
    }
}

/// Immutable product boundary published once by the extension composition
/// root. Module consumers retain these terminal roles instead of querying the
/// manager or recovering any of its six private graphs.
@available(macOS 15.5, *)
@MainActor
struct ExtensionManagerModuleResidence {
    let browserRuntime: ExtensionModuleBrowserRuntime
    let surfaceBinding: BrowserExtensionSurfaceBinding
    let lifetimeControl: ExtensionManagerLifetimeControl
    let websiteDataQuiescence: ExtensionWebsiteDataRuntimeQuiescence
    let profileRetirement: ExtensionProfileRuntimeRetirement
    let settingsCatalog: ExtensionSettingsCatalogBinding
    let toolbarRuntime: ExtensionToolbarRuntime
    let autofillRuntime: SafariExtensionAutofillRuntime
    let browserAttachment: ExtensionManagerBrowserAttachment

    private let runtimeTermination: ExtensionRuntimeTermination
    private let compatibilityDiagnostics:
        ExtensionCompatibilityDiagnosticsSnapshotProvider

    init(
        browserRuntime: ExtensionModuleBrowserRuntime,
        surfaceBinding: BrowserExtensionSurfaceBinding,
        lifetimeControl: ExtensionManagerLifetimeControl,
        websiteDataQuiescence: ExtensionWebsiteDataRuntimeQuiescence,
        profileRetirement: ExtensionProfileRuntimeRetirement,
        settingsCatalog: ExtensionSettingsCatalogBinding,
        toolbarRuntime: ExtensionToolbarRuntime,
        autofillRuntime: SafariExtensionAutofillRuntime,
        attachment: ExtensionBrowserRuntimeAttacher,
        runtimeTermination: ExtensionRuntimeTermination,
        compatibilityDiagnostics:
            ExtensionCompatibilityDiagnosticsSnapshotProvider
    ) {
        self.browserRuntime = browserRuntime
        self.surfaceBinding = surfaceBinding
        self.lifetimeControl = lifetimeControl
        self.websiteDataQuiescence = websiteDataQuiescence
        self.profileRetirement = profileRetirement
        self.settingsCatalog = settingsCatalog
        self.toolbarRuntime = toolbarRuntime
        self.autofillRuntime = autofillRuntime
        browserAttachment = ExtensionManagerBrowserAttachment(
            attacher: attachment
        )
        self.runtimeTermination = runtimeTermination
        self.compatibilityDiagnostics = compatibilityDiagnostics
    }

    func compatibilityDiagnosticsSnapshot()
        -> ExtensionCompatibilityDiagnosticsSnapshot {
        compatibilityDiagnostics.snapshot()
    }

    func shutDown(
        reason: String,
        admission: ExtensionRuntimeShutdown.Admission = .forced
    ) -> ExtensionRuntimeShutdown.Result {
        runtimeTermination.shutDown(reason: reason, admission: admission)
    }

    func executeRebuildPlan(
        _ plan: ExtensionRuntimeTabRebuildPlan,
        reason: String
    ) -> [ExtensionRuntimeTabRebuildPlan.Execution] {
        runtimeTermination.executeRebuildPlan(plan, reason: reason)
    }

    func retireBrowserAttachment() {
        runtimeTermination.retireBrowserAttachment()
    }
}

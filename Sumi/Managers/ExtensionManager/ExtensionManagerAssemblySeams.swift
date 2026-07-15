import Foundation

@available(macOS 15.5, *)
@MainActor
struct ExtensionManagerAssemblySeams {
    #if DEBUG
        let inspectionDidAssemble:
            ExtensionManagerTestInspection.DidAssemble?
        let assemblyOverrides: ExtensionManagerTestAssemblyOverrides?
        let attachedRuntimeDidInstall:
            ExtensionBrowserAttachmentAuthority.DidInstall?

        static let production = Self(
            inspectionDidAssemble: nil,
            assemblyOverrides: nil
        )

        private init(
            inspectionDidAssemble:
                ExtensionManagerTestInspection.DidAssemble?,
            assemblyOverrides: ExtensionManagerTestAssemblyOverrides?
        ) {
            self.inspectionDidAssemble = inspectionDidAssemble
            self.assemblyOverrides = assemblyOverrides
            attachedRuntimeDidInstall = nil
        }

        init(
            attachedRuntimeDidInstall:
                ExtensionBrowserAttachmentAuthority.DidInstall?,
            inspectionDidAssemble:
                ExtensionManagerTestInspection.DidAssemble?,
            assemblyOverrides: ExtensionManagerTestAssemblyOverrides?
        ) {
            self.attachedRuntimeDidInstall = attachedRuntimeDidInstall
            self.inspectionDidAssemble = inspectionDidAssemble
            self.assemblyOverrides = assemblyOverrides
        }
    #else
        static let production = Self()

        private init() {}
    #endif
}

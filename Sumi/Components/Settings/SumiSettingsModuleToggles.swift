import SwiftUI

extension EnvironmentValues {
    @Entry var sumiModuleRegistry: SumiModuleRegistry?
    @Entry var sumiProtectionCoordinator: SumiProtectionCoordinator?
    @Entry var sumiExtensionsModule: SumiExtensionsModule?
    @Entry var sumiBoostsModule: SumiBoostsModule?
}

struct SumiSettingsModuleToggleDescriptor: Identifiable, Equatable {
    let moduleID: SumiModuleID
    let toggleTitle: String
    var badgeTitle: String?

    var id: SumiModuleID { moduleID }

    static let extensions = SumiSettingsModuleToggleDescriptor(
        moduleID: .extensions,
        toggleTitle: "Extensions",
        badgeTitle: "EXPERIMENTAL"
    )
}

@MainActor
struct SumiSettingsModuleToggleModel {
    let descriptor: SumiSettingsModuleToggleDescriptor
    let registry: SumiModuleRegistry

    var isEnabled: Bool {
        registry.isEnabled(descriptor.moduleID)
    }

    func setEnabled(_ isEnabled: Bool) {
        registry.setEnabled(isEnabled, for: descriptor.moduleID)
    }
}

struct SumiSettingsModuleToggleGate<EnabledContent: View>: View {
    let descriptor: SumiSettingsModuleToggleDescriptor
    @ViewBuilder let enabledContent: () -> EnabledContent

    @Environment(\.sumiModuleRegistry) private var moduleRegistry
    @Environment(\.sumiExtensionsModule) private var extensionsModule
    @State private var cachedIsEnabled: Bool?

    init(
        descriptor: SumiSettingsModuleToggleDescriptor,
        @ViewBuilder enabledContent: @escaping () -> EnabledContent
    ) {
        self.descriptor = descriptor
        self.enabledContent = enabledContent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsFeatureToggleCard(
                title: descriptor.toggleTitle,
                badgeTitle: descriptor.badgeTitle,
                isEnabled: isEnabledBinding
            )
            .disabled(injectedIsEnabled == nil)

            if effectiveIsEnabled {
                enabledContent()
            }
        }
        .onAppear {
            cachedIsEnabled = injectedIsEnabled
        }
    }

    private var injectedIsEnabled: Bool? {
        if descriptor.moduleID == .extensions {
            return extensionsModule?.isEnabled
        }
        return moduleRegistry.map {
            SumiSettingsModuleToggleModel(descriptor: descriptor, registry: $0).isEnabled
        }
    }

    private var effectiveIsEnabled: Bool {
        cachedIsEnabled ?? injectedIsEnabled ?? false
    }

    private var isEnabledBinding: Binding<Bool> {
        Binding(
            get: { effectiveIsEnabled },
            set: { newValue in
                setModuleEnabled(newValue)
                cachedIsEnabled = newValue
            }
        )
    }

    private func setModuleEnabled(_ isEnabled: Bool) {
        if descriptor.moduleID == .extensions {
            extensionsModule?.setEnabled(isEnabled)
        } else if let moduleRegistry {
            SumiSettingsModuleToggleModel(
                descriptor: descriptor,
                registry: moduleRegistry
            ).setEnabled(isEnabled)
        }
    }
}

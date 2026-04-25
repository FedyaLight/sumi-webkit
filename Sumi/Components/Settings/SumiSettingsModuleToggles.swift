import SwiftUI

private struct SumiModuleRegistryEnvironmentKey: EnvironmentKey {
    static let defaultValue = SumiModuleRegistry.shared
}

extension EnvironmentValues {
    var sumiModuleRegistry: SumiModuleRegistry {
        get { self[SumiModuleRegistryEnvironmentKey.self] }
        set { self[SumiModuleRegistryEnvironmentKey.self] = newValue }
    }
}

struct SumiSettingsModuleToggleDescriptor: Identifiable, Equatable {
    let moduleID: SumiModuleID
    let title: String
    let subtitle: String
    let toggleTitle: String
    let detail: String

    var id: SumiModuleID { moduleID }

    static let trackingProtection = SumiSettingsModuleToggleDescriptor(
        moduleID: .trackingProtection,
        title: "Tracking Protection",
        subtitle: "Off by default",
        toggleTitle: "Enable Tracking Protection",
        detail: "When off, Sumi does not load tracker data, rule lists, update jobs, or protection scripts. Tracker data updates are manual only and do not run in the background."
    )

    static let adBlocking = SumiSettingsModuleToggleDescriptor(
        moduleID: .adBlocking,
        title: "Ad Blocking",
        subtitle: "Off by default, separate from Tracking Protection",
        toggleTitle: "Enable Ad Blocking",
        detail: "Ad Blocking is separate from Tracking Protection. The ad-blocking engine is planned for later; while off, Sumi does not load ad-block filter lists."
    )

    static let extensions = SumiSettingsModuleToggleDescriptor(
        moduleID: .extensions,
        title: "Extensions",
        subtitle: "Off by default",
        toggleTitle: "Enable Extensions",
        detail: "When off, Sumi does not scan manifests, attach extension scripts, start native messaging, or register extension message handlers."
    )

    static let userScripts = SumiSettingsModuleToggleDescriptor(
        moduleID: .userScripts,
        title: "Userscripts",
        subtitle: "Off by default",
        toggleTitle: "Enable Userscripts",
        detail: "When off, Sumi does not read the userscript store or attach WKUserScript."
    )

    static let all: [SumiSettingsModuleToggleDescriptor] = [
        .trackingProtection,
        .adBlocking,
        .extensions,
        .userScripts,
    ]
}

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
    @State private var cachedIsEnabled: Bool?

    init(
        descriptor: SumiSettingsModuleToggleDescriptor,
        @ViewBuilder enabledContent: @escaping () -> EnabledContent
    ) {
        self.descriptor = descriptor
        self.enabledContent = enabledContent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SumiSettingsModuleToggleCard(
                descriptor: descriptor,
                isEnabled: isEnabledBinding
            )

            if effectiveIsEnabled {
                enabledContent()
            }
        }
        .onAppear {
            cachedIsEnabled = model.isEnabled
        }
    }

    private var model: SumiSettingsModuleToggleModel {
        SumiSettingsModuleToggleModel(
            descriptor: descriptor,
            registry: moduleRegistry
        )
    }

    private var effectiveIsEnabled: Bool {
        cachedIsEnabled ?? model.isEnabled
    }

    private var isEnabledBinding: Binding<Bool> {
        Binding(
            get: { effectiveIsEnabled },
            set: { newValue in
                model.setEnabled(newValue)
                cachedIsEnabled = newValue
            }
        )
    }
}

extension SumiSettingsModuleToggleGate where EnabledContent == EmptyView {
    init(descriptor: SumiSettingsModuleToggleDescriptor) {
        self.init(descriptor: descriptor) {
            EmptyView()
        }
    }
}

private struct SumiSettingsModuleToggleCard: View {
    let descriptor: SumiSettingsModuleToggleDescriptor
    @Binding var isEnabled: Bool

    var body: some View {
        SettingsSectionCard(
            title: descriptor.title,
            subtitle: descriptor.subtitle
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(descriptor.toggleTitle, isOn: $isEnabled)
                    .toggleStyle(.switch)

                Text(descriptor.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

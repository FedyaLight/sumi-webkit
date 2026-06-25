import AppKit
import SwiftUI

enum NativeChromeMaterialRole {
    case sidebar
    case collapsedSidebar
    case windowChrome
    case nativeGlassChrome
    case popover

    var material: NSVisualEffectView.Material {
        switch self {
        case .sidebar:
            return .sidebar
        case .collapsedSidebar:
            return .sidebar
        case .windowChrome:
            return .underWindowBackground
        case .nativeGlassChrome:
            return .hudWindow
        case .popover:
            return .popover
        }
    }

    var blendingMode: NSVisualEffectView.BlendingMode {
        switch self {
        case .sidebar, .collapsedSidebar:
            return .withinWindow
        case .windowChrome, .nativeGlassChrome, .popover:
            return .behindWindow
        }
    }
}

struct NativeChromeMaterialBackground: View {
    let role: NativeChromeMaterialRole
    var colorScheme: ColorScheme? = nil
    @Environment(\.accessibilityReduceTransparency) private var accessibilityReduceTransparency
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    @ViewBuilder
    var body: some View {
        if accessibilityReduceTransparency || sumiSettings.shouldUseOpaqueChromeSurfaces {
            opaqueFallbackColor
        } else {
            NativeChromeVisualEffectBackground(
                role: role,
                colorScheme: colorScheme,
                themeContext: themeContext
            )
        }
    }

    private var opaqueFallbackColor: Color {
        let tokens = themeContext.tokens(settings: sumiSettings)
        switch role {
        case .popover:
            return tokens.floatingBarBackground
        case .sidebar, .collapsedSidebar, .windowChrome, .nativeGlassChrome:
            return tokens.windowBackground
        }
    }
}

private struct NativeChromeVisualEffectBackground: NSViewRepresentable {
    let role: NativeChromeMaterialRole
    let colorScheme: ColorScheme?
    let themeContext: ResolvedThemeContext

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        applyConfiguration(to: view)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        applyConfiguration(to: nsView, fallbackAppearance: nsView.window?.effectiveAppearance)
    }

    private func applyConfiguration(
        to view: NSVisualEffectView,
        fallbackAppearance: NSAppearance? = nil
    ) {
        let material = role.material
        if view.material != material {
            view.material = material
        }

        let blendingMode = role.blendingMode
        if view.blendingMode != blendingMode {
            view.blendingMode = blendingMode
        }

        if view.state != .followsWindowActiveState {
            view.state = .followsWindowActiveState
        }

        let scheme = colorScheme ?? themeContext.nativeSurfaceColorScheme
        let appearance = NSAppearance.sumiChromeAppearance(
            for: scheme,
            fallback: fallbackAppearance
        )
        if view.appearance?.name != appearance.name {
            view.appearance = appearance
        }
    }
}

extension NSAppearance {
    static func sumiChromeAppearance(
        for colorScheme: ColorScheme,
        fallback: NSAppearance? = nil
    ) -> NSAppearance {
        let appearanceName: NSAppearance.Name = colorScheme == .dark ? .darkAqua : .aqua
        if let appearance = NSAppearance(named: appearanceName) {
            return appearance
        }
        if let fallback {
            return fallback
        }
        return NSAppearance(named: .aqua)!
    }
}

extension ColorScheme {
    init(sumiChromeAppearance appearance: NSAppearance) {
        let bestMatch = appearance.bestMatch(from: [.darkAqua, .aqua])
        self = bestMatch == .darkAqua ? .dark : .light
    }
}

extension NSMenu {
    func sumiApplyAppearance(_ appearance: NSAppearance) {
        self.appearance = appearance
        for item in items {
            item.submenu?.sumiApplyAppearance(appearance)
        }
    }
}

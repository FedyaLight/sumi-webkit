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

struct NativeChromeMaterialBackground: NSViewRepresentable {
    let role: NativeChromeMaterialRole
    @Environment(\.resolvedThemeContext) private var themeContext

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = role.material
        view.blendingMode = role.blendingMode
        view.state = .followsWindowActiveState
        view.appearance = NSAppearance.sumiChromeAppearance(for: themeContext.nativeSurfaceColorScheme)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = role.material
        nsView.blendingMode = role.blendingMode
        nsView.state = .followsWindowActiveState
        nsView.appearance = NSAppearance.sumiChromeAppearance(
            for: themeContext.nativeSurfaceColorScheme,
            fallback: nsView.window?.effectiveAppearance
        )
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

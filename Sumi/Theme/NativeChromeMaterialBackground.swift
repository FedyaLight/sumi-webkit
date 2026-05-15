import AppKit
import SwiftUI

enum NativeChromeMaterialRole {
    case sidebar
    case collapsedSidebar
    case windowChrome
    case nativeGlassChrome

    var material: NSVisualEffectView.Material {
        switch self {
        case .sidebar:
            return .sidebar
        case .collapsedSidebar:
            return .hudWindow
        case .windowChrome:
            return .underWindowBackground
        case .nativeGlassChrome:
            return .hudWindow
        }
    }

    var blendingMode: NSVisualEffectView.BlendingMode {
        switch self {
        case .sidebar:
            return .withinWindow
        case .collapsedSidebar, .windowChrome, .nativeGlassChrome:
            return .behindWindow
        }
    }
}

struct NativeChromeMaterialBackground: NSViewRepresentable {
    let role: NativeChromeMaterialRole

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = role.material
        view.blendingMode = role.blendingMode
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = role.material
        nsView.blendingMode = role.blendingMode
        nsView.state = .followsWindowActiveState
    }
}

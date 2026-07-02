import AppKit
import SwiftUI
import WebKit

enum SumiElementZapperOverlayCommand {
    case setSelector(String)
    case togglePreview
    case create
    case cancel
    case selectParent
    case selectChild
}

@MainActor
final class SumiElementZapperOverlayState: ObservableObject {
    let title: String
    let createButtonTitle: String

    @Published var selector: String = ""
    @Published var status: String
    @Published var isError = false
    @Published var previewActive = false
    @Published var canCreate = false
    @Published var canSelectParent = false
    @Published var canSelectChild = false

    init(configuration: SumiElementZapperSession.Configuration) {
        title = configuration.title
        createButtonTitle = configuration.createButtonTitle
        status = configuration.initialStatus
    }
}

@MainActor
final class SumiElementZapperOverlayController {
    let state: SumiElementZapperOverlayState

    private var hostingView: NSHostingView<SumiElementZapperOverlayView>?
    private let onCommand: @MainActor (SumiElementZapperOverlayCommand) -> Void

    init(
        configuration: SumiElementZapperSession.Configuration,
        onCommand: @escaping @MainActor (SumiElementZapperOverlayCommand) -> Void
    ) {
        state = SumiElementZapperOverlayState(configuration: configuration)
        self.onCommand = onCommand
    }

    func install(in webView: WKWebView) {
        remove()

        let view = SumiElementZapperOverlayView(
            state: state,
            onCommand: onCommand
        )
        let hostingView = NSHostingView(rootView: view)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        hostingView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        webView.addSubview(hostingView, positioned: .above, relativeTo: nil)

        let preferredWidth = hostingView.widthAnchor.constraint(equalToConstant: 720)
        preferredWidth.priority = .defaultHigh

        NSLayoutConstraint.activate([
            hostingView.centerXAnchor.constraint(equalTo: webView.centerXAnchor),
            hostingView.bottomAnchor.constraint(equalTo: webView.bottomAnchor, constant: -24),
            hostingView.leadingAnchor.constraint(greaterThanOrEqualTo: webView.leadingAnchor, constant: 16),
            hostingView.trailingAnchor.constraint(lessThanOrEqualTo: webView.trailingAnchor, constant: -16),
            hostingView.widthAnchor.constraint(lessThanOrEqualToConstant: 720),
            preferredWidth,
        ])

        self.hostingView = hostingView
    }

    func applyState(_ body: [String: Any]) {
        if let selector = body["selector"] as? String {
            state.selector = selector
        }
        if let status = body["status"] as? String {
            state.status = status
        }
        if let isError = body["isError"] as? Bool {
            state.isError = isError
        }
        if let previewActive = body["previewActive"] as? Bool {
            state.previewActive = previewActive
        }
        if let canCreate = body["canCreate"] as? Bool {
            state.canCreate = canCreate
        }
        if let canSelectParent = body["canSelectParent"] as? Bool {
            state.canSelectParent = canSelectParent
        }
        if let canSelectChild = body["canSelectChild"] as? Bool {
            state.canSelectChild = canSelectChild
        }
    }

    func remove() {
        hostingView?.removeFromSuperview()
        hostingView = nil
    }
}

@MainActor
struct SumiElementZapperOverlayView: View {
    @ObservedObject var state: SumiElementZapperOverlayState
    let onCommand: @MainActor (SumiElementZapperOverlayCommand) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            controls
            status
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(SumiElementZapperVisualEffect(material: .hudWindow, blendingMode: .withinWindow))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.24), radius: 18, x: 0, y: 10)
        .fixedSize(horizontal: false, vertical: true)
        .onExitCommand {
            onCommand(.cancel)
        }
    }

    private var header: some View {
        Text(state.title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .lineLimit(1)
    }

    private var controls: some View {
        HStack(spacing: 8) {
            TextField("", text: selectorBinding)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)
                .accessibilityLabel("Selector")

            Button {
                onCommand(.selectParent)
            } label: {
                Image(systemName: "arrow.up")
                    .frame(width: 14, height: 14)
            }
            .help("Broader selection")
            .accessibilityLabel("Broader selection")
            .disabled(!state.canSelectParent)

            Button {
                onCommand(.selectChild)
            } label: {
                Image(systemName: "arrow.down")
                    .frame(width: 14, height: 14)
            }
            .help("Narrower selection")
            .accessibilityLabel("Narrower selection")
            .disabled(!state.canSelectChild)

            Button(state.previewActive ? "Unpreview" : "Preview") {
                onCommand(.togglePreview)
            }

            Button(state.createButtonTitle) {
                onCommand(.create)
            }
            .keyboardShortcut(.return, modifiers: .command)
            .buttonStyle(.borderedProminent)
            .disabled(!state.canCreate)

            Button("Cancel") {
                onCommand(.cancel)
            }
            .keyboardShortcut(.cancelAction)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var status: some View {
        Text(state.status)
            .font(.system(size: 11))
            .foregroundStyle(state.isError ? Color(nsColor: .systemRed) : .secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Element picker status")
    }

    private var selectorBinding: Binding<String> {
        Binding(
            get: { state.selector },
            set: { selector in
                guard state.selector != selector else { return }
                state.selector = selector
                onCommand(.setSelector(selector))
            }
        )
    }
}

private struct SumiElementZapperVisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: NSVisualEffectView) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = .followsWindowActiveState
    }
}

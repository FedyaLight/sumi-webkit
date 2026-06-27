import AppKit
import SwiftUI

struct SumiBoostEditorView: View {
    @ObservedObject var session: SumiBoostEditorSession
    @Environment(\.colorScheme) private var colorScheme
    @State private var navigationDirection: NavigationDirection = .forward
    @State private var isBoostMenuPresented = false

    private enum NavigationDirection {
        case forward
        case backward
    }

    private static let modeAnimation = Animation.spring(
        response: 0.3,
        dampingFraction: 0.88,
        blendDuration: 0.08
    )

    var body: some View {
        ZStack {
            if session.isCodeMode {
                codeRoot
                    .id("code")
                    .transition(modeTransition)
            } else {
                boostRoot
                    .id("boost")
                    .transition(modeTransition)
            }
        }
        .frame(
            width: session.isCodeMode ? SumiBoostEditorMetrics.codeWidth : SumiBoostEditorMetrics.normalWidth,
            height: SumiBoostEditorMetrics.height
        )
        .clipped()
        .background(SumiBoostEditorStyle.primaryBackground(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(SumiBoostEditorStyle.border(for: colorScheme), lineWidth: 1)
        }
        .animation(Self.modeAnimation, value: session.isCodeMode)
    }

    private var boostRoot: some View {
        VStack(spacing: 0) {
            header

            VStack(spacing: 14) {
                SumiBoostColorCanvas(session: session)
                    .frame(width: 166, height: 166)
                    .padding(.top, 6)

                colorControlRow

                SumiBoostFontGrid(session: session)

                HStack(spacing: 8) {
                    SumiBoostActionButton(title: session.sizeLabel) {
                        session.cycleSize()
                    }
                    SumiBoostActionButton(title: session.caseLabel) {
                        session.cycleCase()
                    }
                }

                SumiBoostActionButton(
                    title: "Zap",
                    trailingSystemImage: "bolt",
                    valueText: zapValue,
                    isActive: session.isZapActive
                ) {
                    toggleZap()
                }
                .contextMenu {
                    if session.boost.data.zapSelectors.isEmpty {
                        Text("No elements zapped")
                    } else {
                        ForEach(session.boost.data.zapSelectors, id: \.self) { selector in
                            Button("Remove \(selector)") {
                                session.removeZapSelector(selector)
                            }
                        }
                    }
                }

                SumiBoostActionButton(title: "Code", trailingText: "{ }") {
                    openCodeMode()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private var header: some View {
        // The whole bar is a drag handle: a full-bleed `SumiBoostPanelDragRegion`
        // sits behind the buttons so any empty header area — gaps, the strips
        // above/below the buttons, the side padding — moves the window, while the
        // buttons stay on top and keep working. The old layout only put drag
        // regions *between* the buttons, leaving dead zones (notably along the
        // top edge, where grabbing just above a button did nothing).
        ZStack {
            SumiBoostPanelDragRegion()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())

            HStack(spacing: 8) {
                Button(action: session.dismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(SumiBoostEditorStyle.secondaryText(for: colorScheme))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .help("Close")

                Spacer(minLength: 0)

                // The boost name. In the Zen reference this is a plain <p> text
                // element with a small down-arrow background glyph that opens a
                // separate popup on click. A SwiftUI Menu with a custom label
                // truncates to "…" here, so we render plain text + a chevron and
                // surface the actions via a popover instead.
                //
                // fixedSize + layoutPriority: the Spacers flanking this button
                // would otherwise starve the label of width, truncating "My Boost"
                // to "…". fixedSize lets the button claim its ideal content width;
                // layoutPriority(1) makes the spacers absorb any shortfall rather
                // than the name.
                Button {
                    isBoostMenuPresented.toggle()
                } label: {
                    HStack(spacing: 3) {
                        Text(session.boost.data.boostName.isEmpty ? "My Boost" : session.boost.data.boostName)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundStyle(SumiBoostEditorStyle.primaryText(for: colorScheme))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(SumiBoostEditorStyle.secondaryText(for: colorScheme))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
                .popover(isPresented: $isBoostMenuPresented, arrowEdge: .bottom) {
                    SumiBoostHeaderMenu(session: session, isPresented: $isBoostMenuPresented)
                }

                Spacer(minLength: 0)

                Button(action: session.shuffleBoost) {
                    Image(systemName: "die.face.5")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(SumiBoostEditorStyle.secondaryText(for: colorScheme))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .help("Shuffle Boost Settings")
            }
            .padding(.horizontal, 6)
        }
        .frame(height: 40)
        .background(SumiBoostEditorStyle.secondaryBackground(for: colorScheme))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SumiBoostEditorStyle.border(for: colorScheme))
                .frame(height: 1)
        }
    }

    private var colorControlRow: some View {
        HStack(spacing: 8) {
            SumiBoostIconButton(
                systemImage: "lightbulb",
                isActive: session.boost.data.smartInvert,
                help: "Smart Invert Colors"
            ) {
                session.toggleSmartInvert()
            }

            SumiBoostAdvancedColorButton(session: session)

            SumiBoostIconButton(
                systemImage: "circle.slash",
                isActive: !session.boost.data.enableColorBoost,
                help: "Disable Color Adjustments"
            ) {
                session.toggleColorBoost()
            }
        }
    }

    private var zapValue: String? {
        let count = session.boost.data.zapSelectors.count
        return count == 0 ? nil : "\(count)"
    }

    private var codeRoot: some View {
        VStack(spacing: 0) {
            // Same full-bleed drag handle as the boost header: the drag region
            // sits behind the Back/Code/Close controls so the whole bar drags.
            ZStack {
                SumiBoostPanelDragRegion()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())

                HStack(spacing: 8) {
                    Button {
                        closeCodeMode()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(SumiBoostEditorStyle.buttonBackground(for: colorScheme))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    Spacer(minLength: 0)

                    Text("Code")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SumiBoostEditorStyle.primaryText(for: colorScheme))

                    Spacer(minLength: 0)

                    Button(action: session.dismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(SumiBoostEditorStyle.secondaryText(for: colorScheme))
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(.plain)
                    .help("Close")
                }
                .padding(.horizontal, 10)
            }
            .frame(height: 40)
            .background(SumiBoostEditorStyle.secondaryBackground(for: colorScheme))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(SumiBoostEditorStyle.border(for: colorScheme))
                    .frame(height: 1)
            }

            TextEditor(
                text: Binding(
                    get: { session.boost.data.customCSS },
                    set: { session.setCustomCSS($0) }
                )
            )
            .font(.system(size: 12, design: .monospaced))
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 10) {
                SumiBoostActionButton(
                    title: "Zap",
                    trailingSystemImage: "bolt",
                    isActive: session.isZapActive
                ) {
                    toggleZap()
                }
                SumiBoostActionButton(title: "Inspector", trailingSystemImage: "scope") {
                    session.openInspector()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(height: 60)
            .background(SumiBoostEditorStyle.secondaryBackground(for: colorScheme))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(SumiBoostEditorStyle.border(for: colorScheme))
                    .frame(height: 1)
            }
        }
    }

    private var modeTransition: AnyTransition {
        switch navigationDirection {
        case .forward:
            return .asymmetric(
                insertion: Self.submenuInsertionTransition,
                removal: Self.rootRemovalTransition
            )
        case .backward:
            return .asymmetric(
                insertion: Self.rootInsertionTransition,
                removal: Self.submenuRemovalTransition
            )
        }
    }

    private static var submenuInsertionTransition: AnyTransition {
        .offset(x: 24, y: 0)
            .combined(with: .opacity)
            .combined(with: .scale(scale: 0.985, anchor: .trailing))
    }

    private static var rootRemovalTransition: AnyTransition {
        .offset(x: -14, y: 0)
            .combined(with: .opacity)
            .combined(with: .scale(scale: 0.995, anchor: .leading))
    }

    private static var rootInsertionTransition: AnyTransition {
        .offset(x: -18, y: 0)
            .combined(with: .opacity)
            .combined(with: .scale(scale: 0.99, anchor: .leading))
    }

    private static var submenuRemovalTransition: AnyTransition {
        .offset(x: 24, y: 0)
            .combined(with: .opacity)
            .combined(with: .scale(scale: 0.985, anchor: .trailing))
    }

    private func openCodeMode() {
        navigationDirection = .forward
        withAnimation(Self.modeAnimation) {
            session.isCodeMode = true
        }
    }

    private func closeCodeMode() {
        navigationDirection = .backward
        withAnimation(Self.modeAnimation) {
            session.isCodeMode = false
        }
    }

    private func toggleZap() {
        if session.isZapActive {
            session.stopZap()
        } else {
            session.startZap()
        }
    }
}

private struct SumiBoostHeaderMenu: View {
    @ObservedObject var session: SumiBoostEditorSession
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            menuButton("Rename Boost") {
                isPresented = false
                session.promptRename()
            }
            menuButton("Shuffle Boost") {
                isPresented = false
                session.shuffleBoost()
            }
            menuButton("Reset All Edits") {
                isPresented = false
                session.reset()
            }

            Divider().padding(.vertical, 4)

            menuButton("Import Boost...") {
                isPresented = false
                session.importJSON()
            }
            menuButton("Export Boost...") {
                isPresented = false
                session.exportJSON()
            }

            Divider().padding(.vertical, 4)

            menuButton("Delete Boost", role: .destructive) {
                isPresented = false
                session.delete()
            }
        }
        .padding(.vertical, 6)
        .frame(width: 200)
    }

    @ViewBuilder
    private func menuButton(
        _ title: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Text(title)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SumiBoostPanelDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        _ = context
        return SumiBoostPanelDragView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        _ = nsView
        _ = context
    }
}

private final class SumiBoostPanelDragView: NSView {
    override var acceptsFirstResponder: Bool { false }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

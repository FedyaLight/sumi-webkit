import SwiftUI
import SumiDomain

/// "Choose a Theme" row of the space-creation panel. The editor writes into
/// the window-local creation draft, whose owner previews the same theme through
/// the runtime workspace-theme coordinator before the Space is committed.
struct SidebarSpaceCreationThemeRow: View {
    @ObservedObject var session: SpaceCreationSession
    let tokens: ChromeThemeTokens
    let rowCornerRadius: CGFloat

    @State private var showsThemeEditor = false

    var body: some View {
        Button {
            showsThemeEditor = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "paintbrush")
                    .font(SidebarSpaceCreationThemeTokens.Typography.rowGlyph)
                    .foregroundStyle(tokens.secondaryText)
                    .frame(
                        width: SidebarSpaceCreationMetrics.iconWellSize,
                        height: SidebarSpaceCreationMetrics.iconWellSize
                    )

                Text("Choose a Theme")
                    .font(SidebarSpaceCreationThemeTokens.Typography.rowLabel)
                    .foregroundStyle(tokens.primaryText)

                Spacer(minLength: 0)

                themeMiniPreview(session.workspaceTheme)
            }
            .padding(.leading, SidebarRowLayout.leadingInset)
            .padding(.trailing, SidebarRowLayout.trailingInset)
            .frame(height: SidebarSpaceCreationMetrics.formRowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("sidebar-space-creation-theme")
        .popover(isPresented: $showsThemeEditor, arrowEdge: .trailing) {
            GradientEditorView(workspaceTheme: $session.workspaceTheme)
        }
    }

    private func themeMiniPreview(_ theme: WorkspaceTheme) -> some View {
        ZStack {
            Circle()
                .fill(tokens.fieldBackground)
            SpaceMeshGradientView(gradient: theme.gradient)
                .clipShape(Circle())
                .padding(1.5)
        }
        .frame(width: 18, height: 18)
        .overlay {
            Circle()
                .strokeBorder(tokens.separator.opacity(0.55), lineWidth: 1)
        }
    }

}

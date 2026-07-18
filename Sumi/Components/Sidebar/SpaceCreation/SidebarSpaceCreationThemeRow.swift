import SwiftUI
import SumiDomain

/// "Choose a Theme" row of the space-creation panel. Opens the full
/// gradient editor bound to the draft session's theme; the space does not
/// exist yet, so there is no live window preview — the row's mini swatch
/// is the feedback.
struct SidebarSpaceCreationThemeRow: View {
    @ObservedObject var session: SpaceCreationSession
    let defaultDraftTheme: @MainActor () -> WorkspaceTheme
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

                if let draftTheme = session.workspaceTheme {
                    themeMiniPreview(draftTheme)
                } else {
                    Image(systemName: "chevron.right")
                        .font(SidebarSpaceCreationThemeTokens.Typography.profileMenuChevron)
                        .foregroundStyle(tokens.secondaryText)
                }
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
            GradientEditorView(workspaceTheme: draftThemeBinding)
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

    /// Reads through to the would-be default so the editor opens on the theme
    /// the space gets when the user never touches this row; only an actual
    /// edit writes back, so open-then-close keeps `workspaceTheme` nil.
    private var draftThemeBinding: Binding<WorkspaceTheme> {
        Binding(
            get: { session.workspaceTheme ?? defaultDraftTheme() },
            set: { session.workspaceTheme = $0 }
        )
    }
}

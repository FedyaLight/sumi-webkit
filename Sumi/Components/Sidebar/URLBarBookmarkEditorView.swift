import SwiftUI

struct URLBarBookmarkEditorView: View {
    @EnvironmentObject private var browserManager: BrowserManager
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    let state: SumiBookmarkEditorState
    let currentTab: Tab?
    let folders: [SumiBookmarkFolder]
    let onClose: () -> Void
    let onDidMutate: () -> Void

    @State private var title: String
    @State private var folderID: String
    @State private var errorMessage: String?
    @FocusState private var isNameFocused: Bool

    init(
        state: SumiBookmarkEditorState,
        currentTab: Tab?,
        folders: [SumiBookmarkFolder],
        onClose: @escaping () -> Void,
        onDidMutate: @escaping () -> Void
    ) {
        self.state = state
        self.currentTab = currentTab
        self.folders = folders
        self.onClose = onClose
        self.onDidMutate = onDidMutate
        _title = State(initialValue: state.title)
        _folderID = State(
            initialValue: state.folderID
                ?? folders.first?.id
                ?? ""
        )
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 32) {
            faviconPreview

            VStack(alignment: .leading, spacing: 22) {
                Text(editorTitle)
                    .font(.system(size: 15.5, weight: .semibold))
                    .foregroundStyle(tokens.primaryText)
                    .lineLimit(1)

                formFields

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.red.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                }

                footer
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 34)
        .padding(.trailing, 34)
        .padding(.top, 34)
        .padding(.bottom, 36)
        .background(tokens.commandPaletteBackground)
        .onAppear {
            isNameFocused = true
        }
    }

    private var faviconPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
                .shadow(color: Color.black.opacity(0.06), radius: 1, x: 0, y: 1)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(tokens.separator.opacity(0.55), lineWidth: 1)
                }

            Group {
                if let currentTab {
                    currentTab.favicon
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "globe")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(tokens.secondaryText)
                }
            }
            .frame(width: 34, height: 34)
        }
        .frame(width: 102, height: 102)
    }

    private var formFields: some View {
        VStack(alignment: .leading, spacing: 20) {
            formRow(title: "Name") {
                TextField("", text: $title)
                    .modifier(URLBarBookmarkTextFieldChrome())
                    .focused($isNameFocused)
                    .onSubmit(saveAndClose)
            }

            if !folders.isEmpty {
                formRow(title: "Location") {
                    folderMenu
                }
            }
        }
    }

    private func formRow<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(tokens.primaryText)
                .frame(width: 72, alignment: .leading)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var folderMenu: some View {
        Menu {
            ForEach(folders) { folder in
                Button(folderMenuTitle(folder)) {
                    folderID = folder.id
                }
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "star.square.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(tokens.primaryText)

                Text(selectedFolderTitle)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(tokens.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tokens.secondaryText)
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(tokens.fieldBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .menuStyle(.button)
    }

    private var footer: some View {
        HStack(spacing: 18) {
            Spacer(minLength: 0)

            Button("Remove bookmark") {
                removeBookmark()
            }
            .buttonStyle(URLBarBookmarkFooterButtonStyle(role: .destructive))

            Button(state.mode.primaryActionTitle) {
                saveAndClose()
            }
            .buttonStyle(URLBarBookmarkFooterButtonStyle(role: .primary))
            .disabled(!canSave)
        }
        .padding(.top, 4)
    }

    private var editorTitle: String {
        switch state.mode {
        case .added:
            return "Bookmark added"
        case .edit:
            return "Edit bookmark"
        }
    }

    private var selectedFolderTitle: String {
        guard let selectedFolder = folders.first(where: { $0.id == folderID }) ?? folders.first else {
            return "Bookmarks"
        }
        return folderDisplayTitle(selectedFolder)
    }

    private var canSave: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && resolvedURL != nil
    }

    private var resolvedURL: URL? {
        URL(string: state.urlString.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func saveAndClose() {
        guard let url = resolvedURL else {
            errorMessage = SumiBookmarkError.invalidURL.localizedDescription
            return
        }

        do {
            _ = try browserManager.bookmarkManager.updateBookmark(
                id: state.bookmarkID,
                title: title,
                url: url,
                folderID: folderID
            )
            errorMessage = nil
            onDidMutate()
            onClose()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeBookmark() {
        do {
            try browserManager.bookmarkManager.removeBookmark(id: state.bookmarkID)
            errorMessage = nil
            onDidMutate()
            onClose()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func folderMenuTitle(_ folder: SumiBookmarkFolder) -> String {
        guard folder.depth > 0 else { return folderDisplayTitle(folder) }
        return String(repeating: "  ", count: folder.depth) + folderDisplayTitle(folder)
    }

    private func folderDisplayTitle(_ folder: SumiBookmarkFolder) -> String {
        folder.depth == 0 ? "Bookmarks" : folder.title
    }
}

private struct URLBarBookmarkTextFieldChrome: ViewModifier {
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.isEnabled) private var isEnabled

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    func body(content: Content) -> some View {
        content
            .font(.system(size: 13.5))
            .foregroundStyle(tokens.primaryText)
            .textFieldStyle(.plain)
            .padding(.horizontal, 9)
            .frame(height: 32)
            .background(tokens.fieldBackground)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(tokens.separator.opacity(0.85), lineWidth: 1)
            }
            .opacity(isEnabled ? 1 : 0.5)
    }
}

private struct URLBarBookmarkFooterButtonStyle: ButtonStyle {
    enum Role {
        case primary
        case destructive
    }

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    let role: Role

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, role == .primary ? 18 : 8)
            .frame(height: 32)
            .background(backgroundColor(isPressed: configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed && isEnabled ? 0.98 : 1)
            .onHover { isHovering = $0 }
    }

    private var foregroundColor: Color {
        switch role {
        case .primary:
            return tokens.buttonPrimaryText
        case .destructive:
            return tokens.primaryText
        }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        switch role {
        case .primary:
            return isPressed || isHovering
                ? tokens.buttonPrimaryBackground.opacity(0.92)
                : tokens.buttonPrimaryBackground
        case .destructive:
            return isPressed || isHovering
                ? tokens.fieldBackgroundHover
                : Color.clear
        }
    }
}

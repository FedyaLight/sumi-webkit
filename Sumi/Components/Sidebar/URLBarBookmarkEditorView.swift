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
        VStack(alignment: .leading, spacing: 18) {
            header
            formFields

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.red.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }

            footer
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .background(tokens.commandPaletteBackground)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            faviconBadge

            VStack(alignment: .leading, spacing: 3) {
                Text(editorTitle)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tokens.primaryText)
                    .lineLimit(1)

                if let pageSubtitle {
                    Text(pageSubtitle)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(tokens.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var faviconBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(tokens.commandPaletteChipBackground)
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(tokens.separator.opacity(0.5), lineWidth: 1)
                }

            faviconImage
                .frame(width: 23, height: 23)
        }
        .frame(width: 44, height: 44)
    }

    @ViewBuilder
    private var faviconImage: some View {
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

    private var formFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            fieldGroup(title: "Name") {
                TextField("", text: $title)
                    .modifier(URLBarBookmarkTextFieldChrome())
                    .onSubmit(saveAndClose)
            }

            if !folders.isEmpty {
                fieldGroup(title: "Location") {
                    folderMenu
                }
            }
        }
    }

    private func fieldGroup<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tokens.secondaryText)

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
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(tokens.secondaryText)

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
            .frame(height: 38)
            .background(tokens.fieldBackground)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .menuStyle(.button)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if state.mode == .edit {
                Button("Remove") {
                    removeBookmark()
                }
                .buttonStyle(URLBarBookmarkFooterButtonStyle(role: .destructive))
            }

            Spacer(minLength: 0)

            Button(state.mode.primaryActionTitle) {
                saveAndClose()
            }
            .buttonStyle(URLBarBookmarkFooterButtonStyle(role: .primary))
            .disabled(!canSave)
        }
        .padding(.top, 2)
    }

    private var editorTitle: String {
        switch state.mode {
        case .add:
            return "Add bookmark"
        case .edit:
            return "Edit bookmark"
        }
    }

    private var pageSubtitle: String? {
        let url = currentTab?.url ?? state.pageURL
        return url.host(percentEncoded: false) ?? url.absoluteString
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
            switch state.mode {
            case .add:
                _ = try browserManager.bookmarkManager.createBookmark(
                    url: url,
                    title: title,
                    folderID: folderID
                )
            case .edit:
                guard let bookmarkID = state.bookmarkID else {
                    throw SumiBookmarkError.missingBookmark
                }
                _ = try browserManager.bookmarkManager.updateBookmark(
                    id: bookmarkID,
                    title: title,
                    url: url,
                    folderID: folderID
                )
            }
            errorMessage = nil
            onDidMutate()
            onClose()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeBookmark() {
        do {
            guard let bookmarkID = state.bookmarkID else {
                throw SumiBookmarkError.missingBookmark
            }
            try browserManager.bookmarkManager.removeBookmark(id: bookmarkID)
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
            .padding(.horizontal, 11)
            .frame(height: 38)
            .background(tokens.fieldBackground)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(tokens.separator.opacity(0.6), lineWidth: 1)
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
            .frame(height: 34)
            .background(backgroundColor(isPressed: configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed && isEnabled ? 0.98 : 1)
            .onHover { isHovering = $0 }
    }

    private var foregroundColor: Color {
        switch role {
        case .primary:
            return tokens.buttonPrimaryText
        case .destructive:
            return tokens.secondaryText
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

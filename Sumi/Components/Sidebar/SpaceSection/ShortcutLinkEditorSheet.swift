//
//  ShortcutLinkEditorSheet.swift
//  Sumi
//

import SwiftUI

private enum ShortcutLinkEditorFocusedField: Hashable {
    case title
    case url
}

struct ShortcutLinkEditorSheet: View {
    let pin: ShortcutPin
    let onSave: (String, URL) -> Void
    /// Dismiss `DialogManager` overlay — use async when closing from `NSMenu`-related paths (`FolderIconPickerSheet`).
    let onRequestClose: () -> Void

    @State private var title: String
    @State private var urlText: String
    @FocusState private var focusedField: ShortcutLinkEditorFocusedField?
    init(
        pin: ShortcutPin,
        onSave: @escaping (String, URL) -> Void,
        onRequestClose: @escaping () -> Void
    ) {
        self.pin = pin
        self.onSave = onSave
        self.onRequestClose = onRequestClose
        _title = State(initialValue: pin.title)
        _urlText = State(initialValue: pin.launchURL.absoluteString)
    }

    var body: some View {
        DialogCard {
            VStack(alignment: .leading, spacing: 18) {
                DialogHeader(
                    icon: "link",
                    title: "Edit Launcher Link",
                    subtitle: previewSubtitle
                )

                ShortcutLinkEditorPreview(
                    pin: pin,
                    title: effectiveTitle,
                    url: previewURL
                )

                VStack(alignment: .leading, spacing: 14) {
                    ShortcutLinkEditorField(
                        label: "Display Name",
                        systemImage: "textformat",
                        placeholder: pin.preferredDisplayTitle,
                        text: $title,
                        isInvalid: false,
                        accessibilityIdentifier: "shortcut-link-editor-title-field",
                        focusedField: $focusedField,
                        focusValue: .title,
                        onSubmit: {
                            focusedField = .url
                        }
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        ShortcutLinkEditorField(
                            label: "Launcher URL",
                            systemImage: "link",
                            placeholder: "https://example.com",
                            text: $urlText,
                            isInvalid: urlValidationMessage != nil,
                            accessibilityIdentifier: "shortcut-link-editor-url-field",
                            focusedField: $focusedField,
                            focusValue: .url,
                            onSubmit: saveIfPossible
                        )

                        if let urlValidationMessage {
                            Label(urlValidationMessage, systemImage: "exclamationmark.circle.fill")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.red)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }

                DialogFooter(
                    rightButtons: [
                        DialogButton(
                            text: "Cancel",
                            variant: .secondary,
                            keyboardShortcut: .escape,
                            action: onRequestClose
                        ),
                        DialogButton(
                            text: "Save",
                            iconName: "checkmark",
                            variant: .primary,
                            keyboardShortcut: .return,
                            isEnabled: normalizedURL != nil,
                            action: saveIfPossible
                        )
                    ]
                )
            }
        }
        .frame(width: 480)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("shortcut-link-editor-sheet")
        .onAppear {
            focusedField = .title
        }
        .animation(.easeInOut(duration: 0.14), value: urlValidationMessage)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var effectiveTitle: String {
        trimmedTitle.isEmpty ? pin.preferredDisplayTitle : trimmedTitle
    }

    private var normalizedURL: URL? {
        normalizedLaunchURL(from: urlText)
    }

    private var previewURL: URL {
        normalizedURL ?? pin.launchURL
    }

    private var previewSubtitle: String {
        if let host = previewURL.host(percentEncoded: false), !host.isEmpty {
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }

        if let scheme = previewURL.scheme, !scheme.isEmpty {
            return scheme
        }

        return previewURL.absoluteString
    }

    private var urlValidationMessage: String? {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Enter a launcher URL."
        }
        if normalizedURL == nil {
            return "Enter a valid URL."
        }
        return nil
    }

    private func saveIfPossible() {
        guard let resolvedURL = normalizedURL else { return }
        onRequestClose()
        onSave(effectiveTitle, resolvedURL)
    }

    private func normalizedLaunchURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let direct = URL(string: trimmed), direct.scheme != nil {
            return direct
        }
        return URL(string: "https://\(trimmed)")
    }
}

private struct ShortcutLinkEditorPreview: View {
    let pin: ShortcutPin
    let title: String
    let url: URL

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    var body: some View {
        HStack(spacing: 12) {
            ShortcutLinkEditorIcon(pin: pin)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tokens.primaryText)
                    .lineLimit(1)

                Text(url.absoluteString)
                    .font(.system(size: 12))
                    .foregroundStyle(tokens.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }
}

private struct ShortcutLinkEditorIcon: View {
    let pin: ShortcutPin

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tokens.floatingBarChipBackground)

            icon
                .frame(width: 22, height: 22)
        }
        .frame(width: 38, height: 38)
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(tokens.separator.opacity(0.55), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var icon: some View {
        if let iconAsset = pin.iconAsset,
           SumiPersistentGlyph.presentsAsEmoji(iconAsset)
        {
            Text(iconAsset)
                .font(.system(size: 20))
        } else if let iconAsset = pin.iconAsset {
            Image(systemName: SumiPersistentGlyph.resolvedLauncherSystemImageName(iconAsset))
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(tokens.primaryText)
        } else if let templateName = pin.storedChromeTemplateSystemImageName {
            Image(systemName: templateName)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(tokens.primaryText)
        } else {
            pin.storedFavicon
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }
}

private struct ShortcutLinkEditorField: View {
    let label: String
    let systemImage: String
    let placeholder: String
    @Binding var text: String
    let isInvalid: Bool
    let accessibilityIdentifier: String
    let focusedField: FocusState<ShortcutLinkEditorFocusedField?>.Binding
    let focusValue: ShortcutLinkEditorFocusedField
    let onSubmit: () -> Void

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tokens.primaryText)

            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isInvalid ? Color.red : tokens.secondaryText)
                    .frame(width: 16, height: 16)

                ZStack(alignment: .leading) {
                    if text.isEmpty {
                        Text(placeholder)
                            .font(fieldFont)
                            .foregroundStyle(tokens.secondaryText)
                            .lineLimit(1)
                            .allowsHitTesting(false)
                    }

                    TextField("", text: $text)
                        .textFieldStyle(.plain)
                        .font(fieldFont)
                        .foregroundStyle(tokens.primaryText)
                        .tint(tokens.accent)
                        .lineLimit(1)
                        .autocorrectionDisabled()
                        .focused(focusedField, equals: focusValue)
                        .onSubmit(onSubmit)
                        .accessibilityIdentifier(accessibilityIdentifier)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(tokens.floatingBarChipBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(borderColor, lineWidth: isFocused || isInvalid ? 1.5 : 1)
            }
        }
        .animation(.easeInOut(duration: 0.14), value: isFocused)
        .animation(.easeInOut(duration: 0.14), value: isInvalid)
    }

    private var fieldFont: Font {
        .system(size: 13)
    }

    private var isFocused: Bool {
        focusedField.wrappedValue == focusValue
    }

    private var borderColor: Color {
        if isInvalid {
            return .red.opacity(0.82)
        }
        if isFocused {
            return tokens.accent.opacity(0.82)
        }
        return tokens.separator.opacity(0.65)
    }

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }
}

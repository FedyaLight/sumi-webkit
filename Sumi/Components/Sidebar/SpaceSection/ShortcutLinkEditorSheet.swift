//
//  ShortcutLinkEditorSheet.swift
//  Sumi
//

import SwiftUI

private enum ShortcutLinkEditorFocusedField: Hashable {
    case title
    case url
}

@MainActor
final class ShortcutLinkEditorSession: ObservableObject, Identifiable {
    let id = UUID()
    let pin: ShortcutPin

    @Published var title: String
    @Published var urlText: String
    @Published var iconAsset: String?
    var cancelsOnDismiss = false

    init(pin: ShortcutPin) {
        self.pin = pin
        self.title = pin.title
        self.urlText = pin.launchURL.absoluteString
        self.iconAsset = pin.iconAsset
    }

    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var effectiveTitle: String {
        trimmedTitle.isEmpty ? pin.preferredDisplayTitle : trimmedTitle
    }

    var normalizedURL: URL? {
        SumiURLNormalization.normalizedShortcutURL(from: urlText)
    }

    var urlValidationMessage: String? {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Enter a URL."
        }
        if normalizedURL == nil {
            return "Enter a valid URL."
        }
        return nil
    }

    var hasChanges: Bool {
        guard let normalizedURL else {
            return effectiveTitle != pin.title || iconAsset != pin.iconAsset
        }

        return effectiveTitle != pin.title
            || normalizedURL != pin.launchURL
            || iconAsset != pin.iconAsset
    }
}

struct ShortcutLinkEditorSheet: View {
    @ObservedObject var session: ShortcutLinkEditorSession
    let onDone: () -> Void
    let onCancel: () -> Void

    @FocusState private var focusedField: ShortcutLinkEditorFocusedField?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ShortcutLinkEditorIconButton(
                    pin: session.pin,
                    iconAsset: $session.iconAsset
                )

                TextField("Name", text: $session.title)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .title)
                    .onSubmit {
                        focusedField = .url
                    }
                    .accessibilityIdentifier("shortcut-link-editor-title-field")
            }

            TextField("URL", text: $session.urlText)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .url)
                .onSubmit(doneIfPossible)
                .accessibilityIdentifier("shortcut-link-editor-url-field")

            HStack(alignment: .center, spacing: 8) {
                if let urlValidationMessage = session.urlValidationMessage {
                    Label(urlValidationMessage, systemImage: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.escape, modifiers: [])

                Button("Done", action: doneIfPossible)
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(session.normalizedURL == nil)
            }
        }
        .padding(14)
        .frame(width: ShortcutEditorPopoverPresenter.Metrics.contentSize.width)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("shortcut-link-editor-popover")
        .onAppear {
            focusedField = .title
        }
    }

    private func doneIfPossible() {
        guard session.normalizedURL != nil else { return }
        onDone()
    }
}

private struct ShortcutLinkEditorIconButton: View {
    let pin: ShortcutPin
    @Binding var iconAsset: String?

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @StateObject private var emojiManager = EmojiPickerManager()

    var body: some View {
        Button {
            toggleIconPicker()
        } label: {
            ShortcutLinkEditorIcon(pin: pin, iconAsset: iconAsset)
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .background(EmojiPickerAnchor(manager: emojiManager))
        .help("Change Icon")
        .accessibilityLabel("Change Icon")
    }

    private func toggleIconPicker() {
        emojiManager.selectedEmoji = iconAsset.flatMap { value in
            SumiPersistentGlyph.presentsAsEmoji(value) ? value : nil
        } ?? ""
        emojiManager.toggle(
            settings: sumiSettings,
            themeContext: themeContext
        ) { picked in
            let trimmed = picked.trimmingCharacters(in: .whitespacesAndNewlines)
            iconAsset = trimmed.isEmpty
                ? nil
                : SumiPersistentGlyph.normalizedLauncherIconValue(trimmed)
        }
    }
}

private struct ShortcutLinkEditorIcon: View {
    let pin: ShortcutPin
    let iconAsset: String?

    var body: some View {
        ZStack {
            icon
                .frame(width: 18, height: 18)
        }
        .frame(width: 26, height: 26)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var icon: some View {
        if let iconAsset,
           SumiPersistentGlyph.presentsAsEmoji(iconAsset)
        {
            Text(iconAsset)
                .font(.system(size: 17))
        } else if let iconAsset {
            Image(systemName: SumiPersistentGlyph.resolvedLauncherSystemImageName(iconAsset))
                .font(.system(size: 17, weight: .medium))
                .symbolRenderingMode(.monochrome)
        } else if let templateName = pin.storedChromeTemplateSystemImageName {
            Image(systemName: templateName)
                .font(.system(size: 17, weight: .medium))
                .symbolRenderingMode(.monochrome)
        } else {
            pin.storedFavicon
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
    }
}

//
//  MiniWindowToolbar.swift
//  Sumi
//
//  Created by Jonathan Caudill on 26/08/2025.
//

import SwiftUI
import AppKit

struct MiniWindowToolbar: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.sumiSettings) private var sumiSettings
    @ObservedObject var session: MiniWindowSession
    let adoptAction: () -> Void
    let window: NSWindow?
    
    private var cleanedTargetSpaceName: String {
        session.targetSpaceName.replacingOccurrences(of: "space", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        HStack(spacing: 12) {
            trafficLights
            profilePill
            Spacer(minLength: 12)
            VStack(spacing: 2) {
                Text(hostLabel)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(primaryTextColor)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)

            MiniWindowShareButtonContainer(
                session: session,
                backgroundColor: controlBackgroundColor,
                borderColor: controlBorderColor,
                tintColor: shareButtonTintColor
            )
            
            Button(action: adoptAction) {
                    HStack(spacing: 5) {
                        Text("\u{2318} O") // ⌘O as symbols
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(subtleTextColor)
                        HStack(spacing: 0) {
                            Text("move into ")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(subduedTextColor)
                            Text("\(cleanedTargetSpaceName)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(accentColor.opacity(0.8))
                        }
                        .padding(.vertical, 0)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(controlBackgroundColor)
                            .shadow(radius: 1, x: 1, y: 1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(controlBorderColor, lineWidth: 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .keyboardShortcut("o", modifiers: .command)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 7)
        .background(toolbarBackgroundColor)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(separatorColor)
                .frame(height: 1)
                .blur(radius: 0.8)
        }
        .contentShape(Rectangle())
    }

    private var hostLabel: String {
        session.currentURL.host ?? session.currentURL.absoluteString
    }

    private var profilePill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(avatarBackgroundColor)
                .frame(width: 20, height: 20)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(primaryTextColor)
                )
            Text(session.originName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(subduedTextColor)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(controlBackgroundColor)
                .shadow(radius: 1, x: 1, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(controlBorderColor, lineWidth: 1)
        )
    }

    private var accentColor: Color {
        Color(nsColor: .controlAccentColor)
    }

    private var toolbarBackgroundColor: Color {
        ThemeChromeRecipeBuilder.neutralChromeBackground(
            for: colorScheme,
            settings: sumiSettings
        )
    }

    private var primaryTextColor: Color {
        switch colorScheme {
        case .light:
            return Color.black.opacity(0.84)
        case .dark:
            return Color.white.opacity(0.92)
        @unknown default:
            return .primary
        }
    }

    private var subduedTextColor: Color {
        switch colorScheme {
        case .light:
            return Color.black.opacity(0.7)
        case .dark:
            return Color.white.opacity(0.8)
        @unknown default:
            return primaryTextColor.opacity(0.8)
        }
    }

    private var subtleTextColor: Color {
        switch colorScheme {
        case .light:
            return Color.black.opacity(0.55)
        case .dark:
            return Color.white.opacity(0.62)
        @unknown default:
            return primaryTextColor.opacity(0.6)
        }
    }

    private var controlBackgroundColor: Color {
        switch colorScheme {
        case .light:
            return toolbarBackgroundColor.mixed(with: .black, amount: 0.04)
        case .dark:
            return toolbarBackgroundColor.mixed(with: .white, amount: 0.09)
        @unknown default:
            return toolbarBackgroundColor
        }
    }

    private var controlBorderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.1)
    }

    private var avatarBackgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.1)
    }

    private var separatorColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.08)
    }

    private var shareButtonTintColor: NSColor {
        colorScheme == .dark ? .white : .black
    }
}

// MARK: - Traffic Lights

private extension MiniWindowToolbar {
    var trafficLights: some View {
        BrowserWindowTrafficLights(window: window)
            .frame(
                width: BrowserWindowTrafficLightMetrics.sidebarReservedWidth,
                height: BrowserWindowTrafficLightMetrics.clusterHeight,
                alignment: .leading
            )
    }
}

// MARK: - Share Button Container

private struct MiniWindowShareButtonContainer: View {
    @ObservedObject var session: MiniWindowSession
    let backgroundColor: Color
    let borderColor: Color
    let tintColor: NSColor

    var body: some View {
        MiniWindowShareButton(session: session, tintColor: tintColor)
            .frame(width: 26, height: 29)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(backgroundColor)
                    .shadow(radius: 1, x: 1, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
    }
}

private struct MiniWindowShareButton: NSViewRepresentable {
    var session: MiniWindowSession
    let tintColor: NSColor

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 34, height: 34))
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        button.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)?.withSymbolConfiguration(config)
        button.imagePosition = .imageOnly
        button.contentTintColor = tintColor
        button.target = context.coordinator
        button.action = #selector(Coordinator.share(_:))
        button.setButtonType(.momentaryChange)
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.session = session
        nsView.contentTintColor = tintColor
    }

    final class Coordinator: NSObject {
        var session: MiniWindowSession

        init(session: MiniWindowSession) {
            self.session = session
        }

        @MainActor @objc func share(_ sender: NSButton) {
            let picker = NSSharingServicePicker(items: [session.currentURL])
            picker.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }
}

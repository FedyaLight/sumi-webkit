//
//  SidebarMenuDownloadsTab.swift
//  Sumi
//
//  Created by Maciek Bagiński on 23/09/2025.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SidebarMenuDownloadsTab: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @State private var isHovering: Bool = false
    @State private var text: String = ""
    @FocusState private var isSearchFocused: Bool

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    private var filteredDownloads: [Download] {
        if text.isEmpty {
            return browserManager.downloadManager.allDownloads
        } else {
            return browserManager.downloadManager.allDownloads.filter { download in
                download.suggestedFilename.localizedCaseInsensitiveContains(text) ||
                    download.originalURL.absoluteString.localizedCaseInsensitiveContains(text)
            }
        }
    }

    var body: some View {
        VStack {
            HStack {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(searchSecondaryTextColor)
                    .frame(width: 16, height: 16)
                TextField("Search downloads...", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(searchPrimaryTextColor)
                    .focused($isSearchFocused)

                if !text.isEmpty {
                    Button(action: {
                        text = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(tokens.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(height: 38)
            .frame(maxWidth: .infinity)
            .background(searchBackgroundColor)
            .animation(.easeInOut(duration: 0.1), value: isHovering)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .onHover { state in
                isHovering = state
            }
            .onTapGesture {
                isSearchFocused = true
            }

            ScrollView {
                VStack(spacing: 8) {
                    if filteredDownloads.isEmpty && !text.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 24))
                                .foregroundStyle(tokens.tertiaryText)
                            Text("No downloads found")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(tokens.secondaryText)
                            Text("Try searching with a different term")
                                .font(.system(size: 12))
                                .foregroundStyle(tokens.tertiaryText)
                        }
                        .padding(.vertical, 40)
                    } else {
                        ForEach(filteredDownloads.indices, id: \.self) { index in
                            let entry = filteredDownloads[index]
                            DownloadItem(download: entry)
                        }
                    }
                }
            }
        }
        .padding(8)
    }

    private var searchPrimaryTextColor: Color {
        tokens.primaryText
    }

    private var searchSecondaryTextColor: Color {
        tokens.secondaryText
    }

    private var searchBackgroundColor: Color {
        isHovering ? tokens.fieldBackgroundHover : tokens.fieldBackground
    }
}

struct DownloadItem: View {
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @State private var isHovering: Bool = false
    @State private var isIconHovered: Bool = false
    var download: Download

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    private var canDrag: Bool {
        guard download.state == .completed,
              let destinationURL = download.destinationURL
        else {
            return false
        }
        return FileManager.default.fileExists(atPath: destinationURL.path)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: download.downloadThumbnail ?? download.icon!)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(download.suggestedFilename)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(primaryTextColor)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(download.originalURL.absoluteString)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()

            if isHovering {
                Menu {
                    Button(action: openFile) {
                        Label("Open", systemImage: "doc")
                    }
                    Button(action: copyFile) {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    Button(action: showInFinder) {
                        Label("Show in Finder", systemImage: "folder")
                    }
                    Divider()
                    Button(action: showInFinder) {
                        Label("Move to Trash", systemImage: "trash")
                    }
                } label: {
                    Button {} label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(secondaryTextColor)
                            .frame(width: 16, height: 16)
                    }
                    .padding(8)
                    .background(isIconHovered ? iconHoverBackground : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .buttonStyle(PlainButtonStyle())
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
                .onHover { state in
                    isIconHovered = state
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(isHovering ? rowHoverBackground : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .animation(.easeInOut(duration: 0.1), value: isHovering)
        .onHover { state in
            isHovering = state
        }
        .onTapGesture {
            openFile()
        }
        .onDrag {
            guard canDrag,
                  let destinationURL = download.destinationURL,
                  FileManager.default.fileExists(atPath: destinationURL.path)
            else {
                return NSItemProvider()
            }

            let provider = NSItemProvider(contentsOf: destinationURL)

            if let fileData = try? Data(contentsOf: destinationURL) {
                let fileExtension = destinationURL.pathExtension.lowercased()

                if let utType = UTType(filenameExtension: fileExtension) {
                    provider?.registerDataRepresentation(
                        forTypeIdentifier: utType.identifier,
                        visibility: .all
                    ) { completion in
                        Task { @MainActor in
                            completion(fileData, nil)
                        }
                        return nil
                    }
                }
            }

            return provider ?? NSItemProvider()
        }
    }

    private func openFile() {
        guard let destinationURL = download.destinationURL else {
            RuntimeDiagnostics.emit(
                "No destination URL available for download: \(download.suggestedFilename)"
            )
            return
        }

        guard FileManager.default.fileExists(atPath: destinationURL.path) else {
            RuntimeDiagnostics.emit("File does not exist at path: \(destinationURL.path)")
            return
        }

        NSWorkspace.shared.open(destinationURL)
    }

    private func copyFile() {
        guard let destinationURL = download.destinationURL else {
            RuntimeDiagnostics.emit(
                "No destination URL available for download: \(download.suggestedFilename)"
            )
            return
        }

        guard FileManager.default.fileExists(atPath: destinationURL.path) else {
            RuntimeDiagnostics.emit("File does not exist at path: \(destinationURL.path)")
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([destinationURL as NSURL])
    }

    private func showInFinder() {
        guard let destinationURL = download.destinationURL else {
            RuntimeDiagnostics.emit(
                "No destination URL available for download: \(download.suggestedFilename)"
            )
            return
        }

        guard FileManager.default.fileExists(atPath: destinationURL.path) else {
            RuntimeDiagnostics.emit("File does not exist at path: \(destinationURL.path)")
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
    }

    private var primaryTextColor: Color {
        tokens.primaryText
    }

    private var secondaryTextColor: Color {
        tokens.secondaryText
    }

    private var rowHoverBackground: Color {
        tokens.sidebarRowHover
    }

    private var iconHoverBackground: Color {
        tokens.fieldBackgroundHover
    }
}

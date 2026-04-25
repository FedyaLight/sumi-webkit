//
//  SumiEmojiPickerPanel.swift
//  Sumi
//

import AppKit
import SwiftUI

@MainActor
final class EmojiPickerViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var debouncedSearch = ""
    @Published var currentGlyph: String = ""

    private var debounceTask: Task<Void, Never>?

    func resetForOpen(currentGlyph: String) {
        debounceTask?.cancel()
        debounceTask = nil
        searchText = ""
        debouncedSearch = ""
        self.currentGlyph = currentGlyph
    }

    func setSearchText(_ value: String) {
        searchText = value
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == debouncedSearch {
            debounceTask?.cancel()
            debounceTask = nil
            return
        }
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: SumiEmojiPickerMetrics.searchDebounce)
            guard !Task.isCancelled else { return }
            debouncedSearch = normalized
        }
    }
}

struct SumiEmojiPickerPanel: View {
    @ObservedObject var model: EmojiPickerViewModel
    let onEmojiSelected: (String) -> Void

    @State private var displayedEntries: [SumiEmojiCatalog.Entry] = SumiEmojiCatalog.allEntries

    private let columns = [GridItem(.adaptive(minimum: 36), spacing: 4)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(
                "",
                text: Binding(
                    get: { model.searchText },
                    set: { model.setSearchText($0) }
                ),
                prompt: Text("Search emojis...")
                    .foregroundStyle(.secondary)
            )
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 13))
            .accessibilityIdentifier("emoji-picker-search")

            ScrollView {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(displayedEntries) { entry in
                        SumiEmojiGridCell(
                            glyph: entry.glyph,
                            isSelected: entry.glyph == model.currentGlyph,
                            onTap: {
                                model.currentGlyph = entry.glyph
                                onEmojiSelected(entry.glyph)
                            }
                        )
                    }
                }
                .padding(.bottom, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(12)
        .frame(width: SumiEmojiPickerMetrics.popoverWidth, height: SumiEmojiPickerMetrics.popoverHeight)
        .background(FloatingChromeSurfaceFill(.panel))
        .modifier(SumiEmojiPickerAppearModifier())
        .accessibilityIdentifier("emoji-picker-panel")
        .onAppear {
            displayedEntries = SumiEmojiCatalog.entries(
                matching: model.debouncedSearch,
                in: SumiEmojiCatalog.allEntries
            )
        }
        .onChange(of: model.debouncedSearch) { _, newValue in
            displayedEntries = SumiEmojiCatalog.entries(
                matching: newValue,
                in: SumiEmojiCatalog.allEntries
            )
        }
    }
}

/// Coordinates with `NSPopover.animates`: quick fade-out on dismiss, spring-in on show.
private struct SumiEmojiPickerAppearModifier: ViewModifier {
    @State private var presented = false

    func body(content: Content) -> some View {
        content
            .opacity(presented ? 1 : 0)
            .scaleEffect(presented ? 1 : SumiEmojiPickerMetrics.appearScale, anchor: .top)
            .offset(y: presented ? 0 : SumiEmojiPickerMetrics.appearOffsetY)
            .onAppear {
                presented = false
                DispatchQueue.main.async {
                    withAnimation(
                        .spring(
                            response: SumiEmojiPickerMetrics.appearSpringResponse,
                            dampingFraction: SumiEmojiPickerMetrics.appearSpringDamping
                        )
                    ) {
                        presented = true
                    }
                }
            }
            .onDisappear {
                withAnimation(.easeOut(duration: SumiEmojiPickerMetrics.disappearEaseDuration)) {
                    presented = false
                }
            }
    }
}

private struct SumiEmojiGridCell: View {
    let glyph: String
    let isSelected: Bool
    let onTap: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            Text(glyph)
                .font(.system(size: 22))
                .frame(width: 34, height: 34)
                .background(cellBackground)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(glyph)
    }

    private var cellBackground: Color {
        if isSelected {
            Color(nsColor: .selectedContentBackgroundColor).opacity(0.55)
        } else if hovering {
            Color(nsColor: .quaternaryLabelColor).opacity(0.45)
        } else {
            Color.clear
        }
    }
}

import Foundation

/// Declarative single source of truth for the web page context menu, modeled
/// on DuckDuckGo's per-context item set plus Sumi's own additions. Each
/// context concern reads top-down; the produced rules are plain data that
/// `SumiWebPageMenuRewriteEngine` applies mechanically.
struct SumiWebPageMenuBlueprint {
    let context: SumiWebPageMenuContext

    enum Entry: Equatable {
        case command(SumiWebPageMenuCommand)
        case separator
    }

    struct Rule: Equatable {
        enum Operation: Equatable {
            case remove
            case retitle(String)
            case replace([Entry])
            case insertBefore([Entry])
            case insertAfter([Entry])
        }

        let anchor: SumiWebKitMenuItemIdentifier
        let operations: [Operation]
    }

    func rules() -> [Rule] {
        var rules: [Rule] = []
        appendLinkRules(to: &rules)
        appendImageRules(to: &rules)
        appendMediaRules(to: &rules)
        appendSelectionRules(to: &rules)
        appendInspectElementRule(to: &rules)
        return rules
    }

    /// Owned section replacing WebKit's bare Back/Forward/Reload on the page
    /// background (and on subframe hits, next to the native frame item).
    func pageBackgroundSection() -> [Entry] {
        guard context.isPageBackground else { return [] }
        return [
            .command(.back),
            .command(.forward),
            .command(context.isLoading ? .stop : .reload),
            .separator,
            .command(.bookmarkPage),
            .command(.copyPageAddress),
            .command(.printPage),
        ]
    }

    /// Selection commands for menus without a native Copy anchor (WebKit
    /// omits selection items on interactive-element hits).
    func selectionFallbackSection() -> [Entry] {
        guard context.selectedText != nil,
              !context.hasLinkContext,
              !context.identifiers.contains(.copy)
        else { return [] }

        var entries: [Entry] = [.command(.copySelection)]
        entries.append(contentsOf: selectionExtraEntries())
        return entries
    }

    // MARK: - Link

    private func appendLinkRules(to rules: inout [Rule]) {
        guard context.hasLinkContext else { return }

        guard context.linkURL != nil else {
            // No trusted DOM snapshot: keep every native link action intact.
            // Only "Open Link" goes — it duplicates a plain click.
            rules.append(Rule(anchor: .openLink, operations: [.remove]))
            return
        }

        if context.isMailtoLink {
            rules.append(Rule(anchor: .openLink, operations: [.remove]))
            rules.append(Rule(anchor: .openLinkInNewWindow, operations: [.remove]))
            rules.append(Rule(anchor: .downloadLinkedFile, operations: [.remove]))
            rules.append(Rule(
                anchor: .copyLink,
                operations: [.replace([.command(.copyEmailAddress)])] + linkSelectionOperations()
            ))
            return
        }

        guard context.isWebSchemeLink else {
            // Non-web schemes (javascript:, custom protocols) cannot be
            // routed into a tab/window or downloaded; only copying is useful.
            rules.append(Rule(anchor: .openLink, operations: [.remove]))
            rules.append(Rule(anchor: .openLinkInNewWindow, operations: [.remove]))
            rules.append(Rule(anchor: .downloadLinkedFile, operations: [.remove]))
            rules.append(Rule(
                anchor: .copyLink,
                operations: [.replace([.command(.copyLink)])] + linkSelectionOperations()
            ))
            return
        }

        rules.append(
            Rule(
                anchor: .openLink,
                operations: [
                    .replace([
                        .command(.openLinkInNewTab),
                        .command(.openLinkInSplitView),
                    ])
                ]
            )
        )
        rules.append(Rule(
            anchor: .openLinkInNewWindow,
            operations: [.replace([.command(.openLinkInNewWindow)])]
        ))
        rules.append(Rule(
            anchor: .downloadLinkedFile,
            operations: [.retitle(SumiWebPageMenuStrings.downloadLinkedFileAs)]
        ))
        rules.append(Rule(
            anchor: .copyLink,
            operations: [
                .insertBefore([.command(.addLinkToBookmarks)]),
                .replace([.command(.copyLink)]),
            ] + linkSelectionOperations()
        ))
    }

    /// Selection block appended after Copy Link on link-with-selection menus.
    private func linkSelectionOperations() -> [Rule.Operation] {
        guard context.selectedText != nil else { return [] }

        var entries: [Entry] = []
        if !context.identifiers.contains(.copy) {
            entries.append(.command(.copySelection))
        }
        entries.append(contentsOf: selectionExtraEntries(includeSearchWhenNativePresent: true))
        guard !entries.isEmpty else { return [] }
        return [.insertAfter([.separator] + entries + [.separator])]
    }

    // MARK: - Image

    private func appendImageRules(to rules: inout [Rule]) {
        guard context.hasImageContext else { return }

        rules.append(Rule(
            anchor: .downloadImage,
            operations: [.retitle(SumiWebPageMenuStrings.saveImageAs)]
        ))

        guard context.isWebSchemeImage else { return }
        rules.append(Rule(
            anchor: .openImageInNewWindow,
            operations: [
                .insertBefore([.command(.openImageInNewTab)]),
                .replace([.command(.openImageInNewWindow)]),
            ]
        ))
        rules.append(Rule(
            anchor: .copyImage,
            operations: [.insertBefore([.separator, .command(.copyImageAddress)])]
        ))
    }

    // MARK: - Media

    private func appendMediaRules(to rules: inout [Rule]) {
        guard context.identifiers.contains(.downloadMedia),
              context.isWebSchemeMedia
        else { return }

        rules.append(Rule(
            anchor: .downloadMedia,
            operations: [.replace([.command(.downloadMedia)])]
        ))
    }

    // MARK: - Selection

    private func appendSelectionRules(to rules: inout [Rule]) {
        guard context.selectedText != nil else { return }

        if context.identifiers.contains(.searchWeb) {
            rules.append(Rule(
                anchor: .searchWeb,
                operations: context.hasLinkContext
                    ? [.remove]
                    : [.replace([.command(.searchSelection)])]
            ))
        }

        // Link menus place the selection block next to Copy Link instead.
        guard !context.hasLinkContext else { return }

        if context.identifiers.contains(.copy) {
            let entries = selectionExtraEntries()
            if !entries.isEmpty {
                rules.append(Rule(anchor: .copy, operations: [.insertAfter(entries)]))
            }
        }
    }

    private func selectionExtraEntries(
        includeSearchWhenNativePresent: Bool = false
    ) -> [Entry] {
        var entries: [Entry] = []
        if context.canCopyLinkToSelectedText,
           !context.identifiers.contains(.copyLinkWithHighlight) {
            entries.append(.command(.copyLinkToSelectedText))
        }
        if includeSearchWhenNativePresent || !context.identifiers.contains(.searchWeb) {
            entries.append(.command(.searchSelection))
        }
        return entries
    }

    // MARK: - Inspect Element

    private func appendInspectElementRule(to rules: inout [Rule]) {
        guard context.identifiers.contains(.inspectElement) else { return }

        if context.isDeveloperInspectionEnabled {
            rules.append(Rule(
                anchor: .inspectElement,
                operations: [.retitle(SumiWebPageMenuStrings.inspectElement)]
            ))
        } else {
            rules.append(Rule(anchor: .inspectElement, operations: [.remove]))
        }
    }
}

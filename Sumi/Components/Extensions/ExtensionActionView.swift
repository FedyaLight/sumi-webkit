//
//  ExtensionActionView.swift
//  Sumi
//
//  Browser extension action strip.
//

import AppKit
import SwiftUI

enum ExtensionActionLayout {
    case compactStrip
    case sidebarGrid
    case hubTiles
}

enum ExtensionActionPlacement: Equatable {
    case hidden
    case urlBar
    case sidebarGrid

    static let sidebarGridThreshold = 3

    static func resolve(totalActions: Int) -> Self {
        if totalActions <= 0 {
            return .hidden
        }
        if totalActions >= sidebarGridThreshold {
            return .sidebarGrid
        }
        return .urlBar
    }
}

@MainActor
final class ExtensionIconCache {
    typealias Key = String

    private struct Entry {
        let modificationDate: Date?
        let image: NSImage
        var lastChecked: Double
    }

    private static let maxEntries = 128
    var imageLoader: (String) -> NSImage? = { path in
        NSImage(contentsOfFile: path)
    }

    private var entries: [Key: Entry] = [:]
    private var entryOrder: [Key] = []

    init() {}

    func image(extensionId: String, iconPath: String) -> NSImage? {
        let key = Self.cacheKey(extensionId: extensionId, iconPath: iconPath)
        let now = Date.timeIntervalSinceReferenceDate

        if var entry = entries[key] {
            if now - entry.lastChecked < 5.0 {
                touch(key)
                return entry.image
            }

            let modificationDate = Self.modificationDate(for: iconPath)
            if entry.modificationDate == modificationDate {
                entry.lastChecked = now
                entries[key] = entry
                touch(key)
                return entry.image
            }
        }

        let modificationDate = Self.modificationDate(for: iconPath)
        guard let image = imageLoader(iconPath) else {
            entries.removeValue(forKey: key)
            entryOrder.removeAll { $0 == key }
            return nil
        }

        entries[key] = Entry(
            modificationDate: modificationDate,
            image: image,
            lastChecked: now
        )
        touch(key)
        evictIfNeeded()
        return image
    }

    private func touch(_ key: Key) {
        entryOrder.removeAll { $0 == key }
        entryOrder.append(key)
    }

    private func evictIfNeeded() {
        while entries.count > Self.maxEntries, let key = entryOrder.first {
            entryOrder.removeFirst()
            entries.removeValue(forKey: key)
        }
    }

    private static func cacheKey(extensionId: String, iconPath: String) -> Key {
        "\(extensionId)\u{0}\(iconPath)"
    }

    private static func modificationDate(for path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate])
            as? Date
    }
}

@available(macOS 15.5, *)
struct ExtensionActionView: View {
    let extensions: [BrowserExtensionToolbarDisplayRecord]
    var layout: ExtensionActionLayout = .compactStrip
    var visibleActionLimit: Int?
    var profileId: UUID?
    let browserContext: ExtensionActionBrowserContext

    var body: some View {
        switch layout {
        case .compactStrip:
            CompactExtensionActionStrip(
                extensions: extensions,
                visibleActionLimit: visibleActionLimit,
                profileId: profileId,
                browserContext: browserContext
            )
        case .sidebarGrid:
            SidebarExtensionActionGrid(
                extensions: extensions,
                profileId: profileId,
                browserContext: browserContext
            )
        case .hubTiles:
            HubExtensionTilesGrid(
                extensions: extensions,
                profileId: profileId,
                browserContext: browserContext
            )
        }
    }
}
@available(macOS 15.5, *)
#Preview {
    ExtensionActionView(
        extensions: [],
        browserContext: ExtensionActionBrowserContext.unavailable(
            extensionsModule: SumiExtensionsModule(
                compiledRuleListCatalog: SumiCompiledContentRuleListCatalog()
            ),
            windowState: BrowserWindowState()
        )
    )
}

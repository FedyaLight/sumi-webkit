//
//  ZenBundledIconSupport.swift
//  Sumi
//

import AppKit
import SwiftUI

enum SumiZenFolderIconCatalog {
    static let folderValuePrefix = "zen:"
    private static let bundledFolderManifest: [String] = [
        "airplane",
        "american-football",
        "baseball",
        "basket",
        "bed",
        "bell",
        "book",
        "bookmark",
        "briefcase",
        "brush",
        "bug",
        "build",
        "cafe",
        "call",
        "card",
        "chat",
        "checkbox",
        "circle",
        "cloud",
        "code",
        "coins",
        "construct",
        "cutlery",
        "egg",
        "extension-puzzle",
        "eye",
        "fast-food",
        "fish",
        "flag",
        "flame",
        "flask",
        "folder",
        "game-controller",
        "globe",
        "globe-1",
        "grid-2x2",
        "grid-3x3",
        "heart",
        "ice-cream",
        "image",
        "inbox",
        "key",
        "layers",
        "leaf",
        "lightning",
        "location",
        "lock-closed",
        "logo-github",
        "logo-rss",
        "logo-usd",
        "mail",
        "map",
        "megaphone",
        "moon",
        "music",
        "navigate",
        "nuclear",
        "page",
        "palette",
        "paw",
        "people",
        "pizza",
        "planet",
        "present",
        "rocket",
        "school",
        "shapes",
        "shirt",
        "skull",
        "square",
        "squares",
        "star",
        "star-1",
        "stats-chart",
        "sun",
        "tada",
        "terminal",
        "ticket",
        "time",
        "trash",
        "triangle",
        "video",
        "volume-high",
        "wallet",
        "warning",
        "water",
        "weight",
    ]
    private static let folderIconResourceSubdirectory = "ZenFolderIcons"
    private static let chromeIconResourceSubdirectory = "ZenChromeIcons"
    private static let knownChromeIconNames: Set<String> = [
        "permissions",
        "permissions-fill",
        "share",
        "reader-mode",
        "camera",
        "bookmark",
        "bookmark-chrome",
        "bookmark-hollow",
        "autoplay-media",
        "autoplay-media-blocked",
        "autoplay-media-fill",
        "tracking-protection",
        "tracking-protection-fill",
        "cookies-fill",
        "security",
        "security-broken",
        "menu",
        "extension",
        "extension-fill",
        "plus",
        "unpin",
        "algorithm",
    ]
    private static let appSourceRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    private static let sourceResourceRoot = appSourceRoot
        .appendingPathComponent("Resources", isDirectory: true)
    private static let workspaceSourceRoot = appSourceRoot
        .deletingLastPathComponent()
    private static let projectSourceRoot = workspaceSourceRoot
        .deletingLastPathComponent()
    private static var imageCache: [String: NSImage] = [:]
    private static var bundledFolderNameCache: Set<String>?

    static func normalizedFolderIconValue(_ rawValue: String?) -> String {
        let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return "" }
        guard trimmed.hasPrefix(folderValuePrefix) else { return "" }

        let bundledName = String(trimmed.dropFirst(folderValuePrefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard isKnownBundledFolderIconName(bundledName) else {
            return ""
        }
        return storageValue(for: bundledName)
    }

    static func storageValue(for bundledIconName: String) -> String {
        "\(folderValuePrefix)\(bundledIconName)"
    }

    static func bundledFolderIconNames() -> [String] {
        if let cached = bundledFolderNameCache {
            return cached.sorted()
        }

        let resolvedNames = resolveBundledFolderIconNames()
        bundledFolderNameCache = Set(resolvedNames)
        return resolvedNames
    }

    private static func resolveBundledFolderIconNames() -> [String] {
        let directNames = Set(
            folderIconDirectoryCandidates()
                .flatMap(resourceNames(in:))
        )
        if !directNames.isEmpty {
            return directNames.sorted()
        }

        guard let bundleRoot = Bundle.main.resourceURL else {
            return bundledFolderManifest
        }

        let flattenedBundleNames = Set(resourceNames(in: bundleRoot))
            .subtracting(knownChromeIconNames)
        if !flattenedBundleNames.isEmpty {
            return flattenedBundleNames.sorted()
        }

        return bundledFolderManifest
    }

    static func resolveFolderIcon(_ rawValue: String?) -> ResolvedFolderIcon {
        let normalized = normalizedFolderIconValue(rawValue)
        guard !normalized.isEmpty else {
            return .none
        }
        return .bundled(String(normalized.dropFirst(folderValuePrefix.count)))
    }

    static func bundledFolderImage(named name: String) -> NSImage? {
        image(
            key: "folder:\(name)",
            resourceNames: [name],
            candidateDirectories: folderIconDirectoryCandidates(),
            bundledSubdirectory: folderIconResourceSubdirectory,
            allowedExtensions: ["png"],
            useCache: true
        )
    }

    static func chromeImage(named name: String) -> NSImage? {
        image(
            key: "chrome:v2:\(name)",
            resourceNames: chromeResourceNames(for: name),
            candidateDirectories: chromeIconDirectoryCandidates(),
            bundledSubdirectory: chromeIconResourceSubdirectory,
            allowedExtensions: ["png", "svg"],
            useCache: true
        )
    }

    private static func folderIconDirectoryCandidates() -> [URL] {
        var candidates: [URL] = []
        if let bundleURL = Bundle.main.resourceURL?.appendingPathComponent(folderIconResourceSubdirectory, isDirectory: true) {
            candidates.append(bundleURL)
        }
        candidates.append(sourceResourceRoot.appendingPathComponent(folderIconResourceSubdirectory, isDirectory: true))
        candidates.append(
            workspaceSourceRoot
                .appendingPathComponent("references/Zen/src/browser/themes/shared/zen-icons/common/selectable", isDirectory: true)
        )
        candidates.append(
            projectSourceRoot
                .appendingPathComponent("references/Zen/src/browser/themes/shared/zen-icons/common/selectable", isDirectory: true)
        )
        return candidates
    }

    private static func chromeIconDirectoryCandidates() -> [URL] {
        var candidates: [URL] = []
        if let bundleURL = Bundle.main.resourceURL?.appendingPathComponent(chromeIconResourceSubdirectory, isDirectory: true) {
            candidates.append(bundleURL)
        }
        candidates.append(sourceResourceRoot.appendingPathComponent(chromeIconResourceSubdirectory, isDirectory: true))
        candidates.append(
            workspaceSourceRoot
                .appendingPathComponent("references/Zen/src/browser/themes/shared/zen-icons/nucleo", isDirectory: true)
        )
        candidates.append(
            projectSourceRoot
                .appendingPathComponent("references/Zen/src/browser/themes/shared/zen-icons/nucleo", isDirectory: true)
        )
        return candidates
    }

    private static func image(
        key: String,
        resourceNames: [String],
        candidateDirectories: [URL],
        bundledSubdirectory: String,
        allowedExtensions: [String],
        useCache: Bool
    ) -> NSImage? {
        if useCache, let cached = imageCache[key] {
            return cached
        }
        guard let url = resourceURL(
            for: resourceNames,
            candidateDirectories: candidateDirectories,
            bundledSubdirectory: bundledSubdirectory,
            allowedExtensions: allowedExtensions
        ),
              let loadedImage = loadImage(from: url) else {
            return nil
        }
        loadedImage.isTemplate = true
        if useCache {
            imageCache[key] = loadedImage
        }
        return loadedImage
    }

    private static func resourceURL(
        for resourceNames: [String],
        candidateDirectories: [URL],
        bundledSubdirectory: String,
        allowedExtensions: [String]
    ) -> URL? {
        for directory in candidateDirectories {
            for resourceName in resourceNames {
                for fileExtension in allowedExtensions {
                    let url = directory.appendingPathComponent(
                        "\(resourceName).\(fileExtension)",
                        isDirectory: false
                    )
                    if FileManager.default.fileExists(atPath: url.path) {
                        return url
                    }
                }
            }
        }

        for fileExtension in allowedExtensions {
            for resourceName in resourceNames {
                if let bundleURL = Bundle.main.url(
                    forResource: resourceName,
                    withExtension: fileExtension,
                    subdirectory: bundledSubdirectory
                ) {
                    return bundleURL
                }

                if let bundleURL = Bundle.main.url(
                    forResource: resourceName,
                    withExtension: fileExtension
                ) {
                    return bundleURL
                }
            }
        }

        return nil
    }

    private static func loadImage(from url: URL) -> NSImage? {
        if url.pathExtension.lowercased() == "svg",
           let source = try? String(contentsOf: url, encoding: .utf8)
        {
            return nsImageFromZenSVGSource(source)
        }
        return NSImage(contentsOf: url)
    }

    /// Zen nucleo SVGs use Mozilla's `context-fill` / `context-fill-opacity`; AppKit does not resolve those, so strokes render empty.
    private static func nsImageFromZenSVGSource(_ source: String) -> NSImage? {
        let sanitizedSource = source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.hasPrefix("#") }
            .joined(separator: "\n")

        let appKitReady = sanitizedSource
            .replacingOccurrences(of: "context-fill-opacity", with: "1")
            .replacingOccurrences(of: "context-fill", with: "#000000")

        guard let data = appKitReady.data(using: .utf8) else {
            return nil
        }

        return NSImage(data: data)
    }

    private static func resourceNames(in directory: URL) -> [String] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        return urls
            .filter {
                let ext = $0.pathExtension.lowercased()
                return ext == "svg" || ext == "png"
            }
            .map { $0.deletingPathExtension().lastPathComponent }
    }

    private static func chromeResourceNames(for name: String) -> [String] {
        switch name {
        case "bookmark":
            return ["bookmark-chrome", "bookmark"]
        default:
            return [name]
        }
    }

    private static func isKnownBundledFolderIconName(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        if let cached = bundledFolderNameCache {
            return cached.contains(name)
        }

        let resolvedNames = resolveBundledFolderIconNames()
        let resolvedSet = Set(resolvedNames)
        bundledFolderNameCache = resolvedSet
        return resolvedSet.contains(name)
    }
}

enum ResolvedFolderIcon: Equatable {
    case none
    case bundled(String)
}

struct SumiZenBundledIconView: View {
    let image: NSImage?
    let size: CGFloat
    var tint: Color? = nil

    var body: some View {
        if let image {
            Image(nsImage: image)
                .renderingMode(tint == nil ? .original : .template)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .foregroundStyle(tint ?? .primary)
        }
    }
}

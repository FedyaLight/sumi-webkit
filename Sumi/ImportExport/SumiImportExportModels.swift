import Foundation
import UniformTypeIdentifiers

enum SumiImportCategory: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case profiles
    case spaces
    case themes
    case bookmarks
    case essentials
    case pinnedLaunchers
    case folders
    case regularTabs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .profiles: return "Profiles"
        case .spaces: return "Spaces"
        case .themes: return "Themes"
        case .bookmarks: return "Bookmarks"
        case .essentials: return "Essentials"
        case .pinnedLaunchers: return "Pinned"
        case .folders: return "Folders"
        case .regularTabs: return "Regular Tabs"
        }
    }
}

enum SumiImportApplyMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case merge
    case replace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .merge: return "Merge"
        case .replace: return "Replace"
        }
    }
}

enum SumiImportSourceKind: String, Codable, Sendable {
    case arc
    case zen
    case browser2zen
    case sumiBackup
    case sumiTransfer
}

struct SumiImportPreview: Identifiable, Sendable {
    let id = UUID()
    var title: String
    var sourceKind: SumiImportSourceKind
    var data: SumiPortableData
    var suggestedCategories: Set<SumiImportCategory>
    var warnings: [String]
    var defaultMode: SumiImportApplyMode

    var summary: SumiImportSummary {
        SumiImportSummary(data: data)
    }
}

struct SumiImportSummary: Equatable, Sendable {
    var profiles: Int
    var spaces: Int
    var folders: Int
    var essentials: Int
    var pinnedLaunchers: Int
    var regularTabs: Int
    var bookmarks: Int

    init(data: SumiPortableData) {
        profiles = data.profiles.count
        spaces = data.spaces.count
        folders = data.folders.count
        essentials = data.essentials.count
        pinnedLaunchers = data.pinnedLaunchers.count
        regularTabs = data.regularTabs.count
        bookmarks = data.bookmarks.reduce(0) { $0 + $1.totalBookmarkCount }
    }
}

struct SumiPortableArchive: Codable, Sendable {
    static let currentVersion = 1
    static let format = "com.sumi.browser.backup"

    var format: String
    var version: Int
    var createdAt: Date
    var appBundleIdentifier: String
    var appVersion: String
    var includedCategories: [SumiImportCategory]
    var warnings: [String]
    var settings: [String: String]
    var data: SumiPortableData

    init(
        createdAt: Date = Date(),
        appBundleIdentifier: String = SumiAppIdentity.runtimeBundleIdentifier,
        appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
        includedCategories: [SumiImportCategory],
        warnings: [String] = [],
        settings: [String: String] = [:],
        data: SumiPortableData
    ) {
        self.format = Self.format
        self.version = Self.currentVersion
        self.createdAt = createdAt
        self.appBundleIdentifier = appBundleIdentifier
        self.appVersion = appVersion
        self.includedCategories = includedCategories
        self.warnings = warnings
        self.settings = settings
        self.data = data
    }
}

struct SumiPortableData: Codable, Equatable, Sendable {
    var profiles: [SumiPortableProfile]
    var spaces: [SumiPortableSpace]
    var folders: [SumiPortableFolder]
    var essentials: [SumiPortableLauncher]
    var pinnedLaunchers: [SumiPortableLauncher]
    var regularTabs: [SumiPortableRegularTab]
    var bookmarks: [SumiPortableBookmarkNode]

    init(
        profiles: [SumiPortableProfile] = [],
        spaces: [SumiPortableSpace] = [],
        folders: [SumiPortableFolder] = [],
        essentials: [SumiPortableLauncher] = [],
        pinnedLaunchers: [SumiPortableLauncher] = [],
        regularTabs: [SumiPortableRegularTab] = [],
        bookmarks: [SumiPortableBookmarkNode] = []
    ) {
        self.profiles = profiles
        self.spaces = spaces
        self.folders = folders
        self.essentials = essentials
        self.pinnedLaunchers = pinnedLaunchers
        self.regularTabs = regularTabs
        self.bookmarks = bookmarks
    }

    var nonEmptyCategories: Set<SumiImportCategory> {
        var categories: Set<SumiImportCategory> = []
        if profiles.isEmpty == false { categories.insert(.profiles) }
        if spaces.isEmpty == false { categories.insert(.spaces) }
        if spaces.contains(where: { $0.themeDataBase64 != nil || $0.color != nil }) { categories.insert(.themes) }
        if bookmarks.isEmpty == false { categories.insert(.bookmarks) }
        if essentials.isEmpty == false { categories.insert(.essentials) }
        if pinnedLaunchers.isEmpty == false { categories.insert(.pinnedLaunchers) }
        if folders.isEmpty == false { categories.insert(.folders) }
        if regularTabs.isEmpty == false { categories.insert(.regularTabs) }
        return categories
    }
}

struct SumiPortableProfile: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var icon: String
    var index: Int
}

struct SumiPortableSpace: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var icon: String
    var index: Int
    var profileId: String?
    var themeDataBase64: String?
    var color: SumiPortableRGBColor?
}

struct SumiPortableFolder: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var icon: String
    var colorHex: String
    var spaceId: String
    var isOpen: Bool
    var index: Int
    var sourcePath: [String]
}

struct SumiPortableLauncher: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var urlString: String
    var index: Int
    var profileId: String?
    var executionProfileId: String?
    var spaceId: String?
    var folderId: String?
    var iconAsset: String?
    var sourceSpaceId: String?
}

struct SumiPortableRegularTab: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var urlString: String
    var index: Int
    var spaceId: String
    var profileId: String?
    var folderId: String?
}

struct SumiPortableRGBColor: Codable, Equatable, Sendable {
    var r: Double
    var g: Double
    var b: Double

    init(r: Double, g: Double, b: Double) {
        self.r = min(max(r, 0), 1)
        self.g = min(max(g, 0), 1)
        self.b = min(max(b, 0), 1)
    }

    var hex: String {
        let red = Int((r * 255).rounded())
        let green = Int((g * 255).rounded())
        let blue = Int((b * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

struct SumiPortableBookmarkNode: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case bookmark
        case favorite
        case folder
    }

    var name: String
    var kind: Kind
    var urlString: String?
    var children: [SumiPortableBookmarkNode]

    var totalBookmarkCount: Int {
        switch kind {
        case .bookmark, .favorite:
            return urlString == nil ? 0 : 1
        case .folder:
            return children.reduce(0) { $0 + $1.totalBookmarkCount }
        }
    }
}

extension UTType {
    static let sumiBackup = UTType(exportedAs: "com.sumi.browser.backup", conformingTo: .json)
    static let sumiTransfer = UTType(exportedAs: "com.sumi.browser.transfer", conformingTo: .json)
}

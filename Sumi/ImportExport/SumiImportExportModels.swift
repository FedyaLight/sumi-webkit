import Foundation
import UniformTypeIdentifiers

enum SumiImportCategory: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case profiles
    case spaces
    case themes
    case bookmarks
    case favorite
    case pinnedLaunchers
    case folders
    case regularTabs

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        if value == "essentials" {
            self = .favorite
            return
        }
        guard let category = Self(rawValue: value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported import category: \(value)"
            )
        }
        self = category
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .profiles: return "Profiles"
        case .spaces: return "Spaces"
        case .themes: return "Themes"
        case .bookmarks: return "Bookmarks"
        case .favorite: return "Favorite"
        case .pinnedLaunchers: return "Pinned"
        case .folders: return "Folders"
        case .regularTabs: return "Regular Tabs"
        }
    }
}

enum SumiBackupV1ExcludedDataFamily: String, CaseIterable, Sendable {
    case history
    case permissionDecisions
    case extensionMetadataAndPayloads
    case cookies
    case passwords
    case webKitWebsiteData
    case caches
    case downloads
    case preferencesAndSessionSettings

    var warningLabel: String {
        switch self {
        case .history: return "history"
        case .permissionDecisions: return "permission decisions"
        case .extensionMetadataAndPayloads: return "extension metadata and payloads"
        case .cookies: return "cookies"
        case .passwords: return "passwords"
        case .webKitWebsiteData: return "WebKit website data"
        case .caches: return "caches"
        case .downloads: return "downloads"
        case .preferencesAndSessionSettings: return "preferences and session settings"
        }
    }
}

enum SumiBackupV1Scope {
    static let portableCategories = SumiImportCategory.allCases
    static let excludedDataFamilies = SumiBackupV1ExcludedDataFamily.allCases

    static var warning: String {
        let exclusions = excludedDataFamilies.map(\.warningLabel).joined(separator: ", ")
        return "Backup v1 contains logical Sumi data only. \(exclusions) are not included."
    }
}

enum SumiImportApplyMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case merge
    case replace

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .merge: return "Merge"
        case .replace: return "Replace"
        }
    }
}

enum SumiImportSourceKind: String, Codable, Sendable {
    case arc
    case zen
    case chromium
    case firefox
    case safari
    case browser2zen
    case sumiBackup
    case sumiTransfer

    var allowsReplaceMode: Bool {
        switch self {
        case .sumiBackup, .sumiTransfer:
            return true
        case .arc, .zen, .chromium, .firefox, .safari, .browser2zen:
            return false
        }
    }
}

struct SumiImportPreview: Identifiable, Sendable {
    let id = UUID()
    var title: String
    var sourceKind: SumiImportSourceKind
    var data: SumiPortableData
    var suggestedCategories: Set<SumiImportCategory>
    var warnings: [String]
    var defaultMode: SumiImportApplyMode
    /// Bulk payloads already staged on disk, described by counts only. The
    /// payloads themselves never enter `SumiPortableData`.
    var bulkStaging: SumiImportBulkStagingManifest?

    var summary: SumiImportSummary {
        SumiImportSummary(data: data)
    }
}

struct SumiImportSummary: Equatable, Sendable {
    var profiles: Int
    var spaces: Int
    var folders: Int
    var favorite: Int
    var pinnedLaunchers: Int
    var regularTabs: Int
    var bookmarks: Int

    init(data: SumiPortableData) {
        profiles = data.profiles.count
        spaces = data.spaces.count
        folders = data.folders.count
        favorite = data.favorite.count
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
    var favorite: [SumiPortableLauncher]
    var pinnedLaunchers: [SumiPortableLauncher]
    var regularTabs: [SumiPortableRegularTab]
    var bookmarks: [SumiPortableBookmarkNode]

    private enum CodingKeys: String, CodingKey {
        case profiles
        case spaces
        case folders
        case favorite
        case legacyEssentials = "essentials"
        case pinnedLaunchers
        case regularTabs
        case bookmarks
    }

    init(
        profiles: [SumiPortableProfile] = [],
        spaces: [SumiPortableSpace] = [],
        folders: [SumiPortableFolder] = [],
        favorite: [SumiPortableLauncher] = [],
        pinnedLaunchers: [SumiPortableLauncher] = [],
        regularTabs: [SumiPortableRegularTab] = [],
        bookmarks: [SumiPortableBookmarkNode] = []
    ) {
        self.profiles = profiles
        self.spaces = spaces
        self.folders = folders
        self.favorite = favorite
        self.pinnedLaunchers = pinnedLaunchers
        self.regularTabs = regularTabs
        self.bookmarks = bookmarks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedFavorite = try container.decodeIfPresent(
            [SumiPortableLauncher].self,
            forKey: .favorite
        )
        let legacyFavorite = try container.decodeIfPresent(
            [SumiPortableLauncher].self,
            forKey: .legacyEssentials
        )
        let favorite = decodedFavorite ?? legacyFavorite ?? []
        self.init(
            profiles: try container.decode([SumiPortableProfile].self, forKey: .profiles),
            spaces: try container.decode([SumiPortableSpace].self, forKey: .spaces),
            folders: try container.decode([SumiPortableFolder].self, forKey: .folders),
            favorite: favorite,
            pinnedLaunchers: try container.decode([SumiPortableLauncher].self, forKey: .pinnedLaunchers),
            regularTabs: try container.decode([SumiPortableRegularTab].self, forKey: .regularTabs),
            bookmarks: try container.decode([SumiPortableBookmarkNode].self, forKey: .bookmarks)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(profiles, forKey: .profiles)
        try container.encode(spaces, forKey: .spaces)
        try container.encode(folders, forKey: .folders)
        try container.encode(favorite, forKey: .favorite)
        try container.encode(pinnedLaunchers, forKey: .pinnedLaunchers)
        try container.encode(regularTabs, forKey: .regularTabs)
        try container.encode(bookmarks, forKey: .bookmarks)
    }

    var nonEmptyCategories: Set<SumiImportCategory> {
        var categories: Set<SumiImportCategory> = []
        if profiles.isEmpty == false { categories.insert(.profiles) }
        if spaces.isEmpty == false { categories.insert(.spaces) }
        if spaces.contains(where: { $0.themeDataBase64 != nil || $0.color != nil }) { categories.insert(.themes) }
        if bookmarks.isEmpty == false { categories.insert(.bookmarks) }
        if favorite.isEmpty == false { categories.insert(.favorite) }
        if pinnedLaunchers.isEmpty == false { categories.insert(.pinnedLaunchers) }
        if folders.isEmpty == false { categories.insert(.folders) }
        if regularTabs.isEmpty == false { categories.insert(.regularTabs) }
        return categories
    }
}

struct SumiPortableProfile: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var index: Int
    /// The source browser's own profile directory name (Chromium's `Profile 1`,
    /// a Firefox profile folder). Bulk extractors join history, cookies, and
    /// favicons to the right profile on this key; it is absent for sources that
    /// have no on-disk profile directory.
    var sourceDirectoryKey: String? = nil
}

struct SumiPortableSpace: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var icon: String
    var index: Int
    var profileId: String?
    var themeDataBase64: String?
    var color: SumiPortableRGBColor?
    /// Full source gradient (up to `WorkspaceGradientTheme.maximumColorCount` used);
    /// `color` stays populated with the primary stop for format compatibility.
    var colors: [SumiPortableRGBColor]? = nil
    var themeOpacity: Double? = nil
}

struct SumiPortableFolder: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var icon: String
    var colorHex: String
    var spaceId: String
    var parentFolderId: String?
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
    var titleIsCustom: Bool? = nil
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
    static let zenBackup = UTType(filenameExtension: "zenbackup") ?? .data
}

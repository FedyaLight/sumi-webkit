import Combine
import CryptoKit
import Foundation
#if DEBUG
import Darwin
#endif

enum AdblockFilterListCategory: String, Codable, CaseIterable, Sendable {
    case baseAds
    case nativeCosmeticCompatibleAds
    case annoyances
    case regional
    case privacyOverlap
}

enum AdblockFilterListProfileKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case currentDefault
    case lightNative
    case balancedNative
    case highBlockingNative
    case referenceAdGuardNative

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let profileKind = Self(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown Adblock native profile kind: \(rawValue)"
            )
        }
        self = profileKind
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum AdblockNativeProfileExposure: String, Codable, Sendable {
    case productionDefault
    case developerOnly
}

struct AdblockFilterListProfile: Codable, Equatable, Identifiable, Sendable {
    let id: AdblockFilterListProfileKind
    let displayName: String
    let listIdentifiers: [String]
    let isExperimental: Bool
    let isRecommended: Bool
    let exposure: AdblockNativeProfileExposure
    let appendsRecommendedRegionalList: Bool
    let notes: String

    var isDeveloperOnly: Bool {
        exposure == .developerOnly
    }
}

enum AdblockNativeCompilerKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case adblockRust
    case adGuardSafariExperimental

    var id: String { rawValue }
}

enum AdblockNativeCompilerIntegrationStatus: String, Codable, Sendable {
    case production
    case externalHarnessOnly
}

struct AdblockNativeCompilerDescriptor: Codable, Equatable, Identifiable, Sendable {
    let id: AdblockNativeCompilerKind
    let displayName: String
    let integrationStatus: AdblockNativeCompilerIntegrationStatus
    let isExperimental: Bool
    let notes: String
}

struct AdblockFilterListDescriptor: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let displayName: String
    let category: AdblockFilterListCategory
    let remoteURL: URL
    let homepageURL: URL?
    let defaultEnabled: Bool
    let localeTags: [String]
    let licenseNoticeHint: String
    let variantOfListId: String?
    let exclusionGroup: String?
    let shortDescription: String
    let mayContainCosmeticFilters: Bool
    let isAllowedInNativeOnlyMode: Bool
}

struct AdblockFilterListSelectionValidation: Equatable, Sendable {
    let requestedIdentifiers: [String]
    let resolvedIdentifiers: [String]
    let unknownIdentifiers: [String]
    let droppedConflictingIdentifiers: [String]
}

enum AdblockEffectiveListSelectionOrigin: String, Codable, CaseIterable, Sendable {
    case manualListToggle
    case currentDefault
    case lightNative
    case balancedNative
    case highBlockingNative
    case referenceAdGuardNative
    case recommendedRegional
    case other

    static func profile(_ kind: AdblockFilterListProfileKind) -> AdblockEffectiveListSelectionOrigin {
        switch kind {
        case .currentDefault:
            return .currentDefault
        case .lightNative:
            return .lightNative
        case .balancedNative:
            return .balancedNative
        case .highBlockingNative:
            return .highBlockingNative
        case .referenceAdGuardNative:
            return .referenceAdGuardNative
        }
    }
}

struct AdblockEffectiveSelectedListDiagnostics: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let displayName: String
    let category: AdblockFilterListCategory
    let origins: [AdblockEffectiveListSelectionOrigin]
}

struct AdblockEffectiveSelectionDiagnostics: Codable, Equatable, Sendable {
    let selectedNativeProfile: AdblockFilterListProfileKind
    let usesProfileDerivedSelection: Bool
    let manuallySelectedListIdentifiers: [String]
    let profileDerivedListIdentifiers: [String]
    let recommendedRegionalListIdentifiers: [String]
    let requestedIdentifiers: [String]
    let finalEffectiveListIdentifiers: [String]
    let unknownIdentifiers: [String]
    let droppedConflictingIdentifiers: [String]
    let selectedLists: [AdblockEffectiveSelectedListDiagnostics]

    func origins(forListIdentifier identifier: String) -> [AdblockEffectiveListSelectionOrigin] {
        selectedLists.first { $0.id == identifier }?.origins ?? []
    }

    var isCustomListSelection: Bool {
        !usesProfileDerivedSelection
    }

    var effectiveModeLabel: String {
        isCustomListSelection ? "Custom list selection" : "Selected profile"
    }
}

struct AdblockFilterListRegistry: Equatable, Sendable {
    let descriptors: [AdblockFilterListDescriptor]

    init(descriptors: [AdblockFilterListDescriptor] = Self.defaultDescriptors) {
        self.descriptors = descriptors
    }

    var defaultSelectionIdentifiers: [String] {
        descriptors
            .filter(\.defaultEnabled)
            .map(\.id)
            .sorted()
    }

    var nativeProfiles: [AdblockFilterListProfile] {
        [
            AdblockFilterListProfile(
                id: .currentDefault,
                displayName: "Sumi current default",
                listIdentifiers: defaultSelectionIdentifiers,
                isExperimental: false,
                isRecommended: false,
                exposure: .productionDefault,
                appendsRecommendedRegionalList: true,
                notes: "Conservative native profile used by Sumi today."
            ),
            AdblockFilterListProfile(
                id: .lightNative,
                displayName: "Light Native",
                listIdentifiers: ["easylist"],
                isExperimental: false,
                isRecommended: false,
                exposure: .developerOnly,
                appendsRecommendedRegionalList: true,
                notes: "Low-overlap native ads profile: one base ads list plus an optional locale-matched regional list."
            ),
            AdblockFilterListProfile(
                id: .balancedNative,
                displayName: "Balanced Native",
                listIdentifiers: [
                    "adguard-base",
                    "adguard-mobile-ads",
                ],
                isExperimental: true,
                isRecommended: false,
                exposure: .developerOnly,
                appendsRecommendedRegionalList: true,
                notes: "Candidate stronger native ads profile with no privacy-overlap lists and no JavaScript runtime; held for score measurement."
            ),
            AdblockFilterListProfile(
                id: .highBlockingNative,
                displayName: "High Blocking Native",
                listIdentifiers: [
                    "adguard-base",
                    "adguard-mobile-ads",
                    "adguard-annoyances",
                ],
                isExperimental: true,
                isRecommended: false,
                exposure: .developerOnly,
                appendsRecommendedRegionalList: true,
                notes: "Higher native coverage candidate with annoyance blocking and higher cap/false-positive pressure."
            ),
            AdblockFilterListProfile(
                id: .referenceAdGuardNative,
                displayName: "Reference AdGuard Native",
                listIdentifiers: [
                    "adguard-base",
                    "adguard-mobile-ads",
                    "adguard-tracking-protection",
                    "adguard-url-tracking",
                    "adguard-annoyances",
                ],
                isExperimental: true,
                isRecommended: false,
                exposure: .developerOnly,
                appendsRecommendedRegionalList: false,
                notes: "AdGuard-heavy reference profile for native compiler comparison only; not enabled by default."
            ),
        ]
    }

    var normalUserSelectableNativeProfiles: [AdblockFilterListProfile] {
        nativeProfiles.filter { !$0.isDeveloperOnly }
    }

    var comparisonProfiles: [AdblockFilterListProfile] {
        nativeProfiles
    }

    var nativeCompilerDescriptors: [AdblockNativeCompilerDescriptor] {
        [
            AdblockNativeCompilerDescriptor(
                id: .adblockRust,
                displayName: "adblock-rust",
                integrationStatus: .production,
                isExperimental: false,
                notes: "Current production WebKit-native compiler implementation."
            ),
            AdblockNativeCompilerDescriptor(
                id: .adGuardSafariExperimental,
                displayName: "AdGuard SafariConverterLib",
                integrationStatus: .externalHarnessOnly,
                isExperimental: true,
                notes: "Comparison-only today; not presented as an in-app compiler implementation."
            ),
        ]
    }

    func profile(for kind: AdblockFilterListProfileKind) -> AdblockFilterListProfile {
        nativeProfiles.first { $0.id == kind }
            ?? nativeProfiles.first { $0.id == .currentDefault }!
    }

    func selectedDescriptors(
        selection: SumiAdblockFilterListSelection,
        profileKind: AdblockFilterListProfileKind = .currentDefault,
        locale: Locale = .autoupdatingCurrent
    ) -> [AdblockFilterListDescriptor] {
        let ids = Set(
            validatedSelection(
                selection,
                profileKind: profileKind,
                locale: locale
            ).resolvedIdentifiers
        )
        return descriptors
            .filter { ids.contains($0.id) }
            .sorted { $0.id < $1.id }
    }

    func effectiveSelectionDiagnostics(
        selection: SumiAdblockFilterListSelection,
        profileKind: AdblockFilterListProfileKind = .currentDefault,
        locale: Locale = .autoupdatingCurrent
    ) -> AdblockEffectiveSelectionDiagnostics {
        let profile = profile(for: profileKind)
        let profileIdentifiers = profile.listIdentifiers
        let regionalIdentifiers = profile.appendsRecommendedRegionalList
            ? recommendedRegionalIdentifiers(for: locale)
            : []
        let validation = validatedSelection(
            selection,
            profileKind: profileKind,
            locale: locale
        )
        let descriptorById = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.id, $0) })
        let profileOrigin = AdblockEffectiveListSelectionOrigin.profile(profileKind)
        let manualIdentifiers = selection.usesDefaultSelection ? [] : selection.identifiers
        let selectedDiagnostics = validation.resolvedIdentifiers.compactMap { identifier -> AdblockEffectiveSelectedListDiagnostics? in
            guard let descriptor = descriptorById[identifier] else { return nil }
            var origins = [AdblockEffectiveListSelectionOrigin]()
            if selection.usesDefaultSelection {
                if profileIdentifiers.contains(identifier) {
                    origins.append(profileOrigin)
                }
                if regionalIdentifiers.contains(identifier) {
                    origins.append(.recommendedRegional)
                }
            } else if manualIdentifiers.contains(identifier) {
                origins.append(.manualListToggle)
            }
            if origins.isEmpty {
                origins.append(.other)
            }
            return AdblockEffectiveSelectedListDiagnostics(
                id: identifier,
                displayName: descriptor.displayName,
                category: descriptor.category,
                origins: origins
            )
        }

        return AdblockEffectiveSelectionDiagnostics(
            selectedNativeProfile: profileKind,
            usesProfileDerivedSelection: selection.usesDefaultSelection,
            manuallySelectedListIdentifiers: manualIdentifiers.sorted(),
            profileDerivedListIdentifiers: profileIdentifiers.sorted(),
            recommendedRegionalListIdentifiers: regionalIdentifiers.sorted(),
            requestedIdentifiers: validation.requestedIdentifiers,
            finalEffectiveListIdentifiers: validation.resolvedIdentifiers,
            unknownIdentifiers: validation.unknownIdentifiers,
            droppedConflictingIdentifiers: validation.droppedConflictingIdentifiers,
            selectedLists: selectedDiagnostics.sorted { $0.id < $1.id }
        )
    }

    func validatedSelection(
        _ selection: SumiAdblockFilterListSelection,
        profileKind: AdblockFilterListProfileKind = .currentDefault,
        locale: Locale = .autoupdatingCurrent
    ) -> AdblockFilterListSelectionValidation {
        let profile = profile(for: profileKind)
        let requested = selection.usesDefaultSelection
            ? profile.listIdentifiers
                + (profile.appendsRecommendedRegionalList ? recommendedRegionalIdentifiers(for: locale) : [])
            : selection.identifiers
        let descriptorById = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.id, $0) })
        let knownRequested = requested.filter { descriptorById[$0] != nil }
        let unknown = requested.filter { descriptorById[$0] == nil }.sorted()
        let knownSet = Set(knownRequested)
        let descriptorsByConflictGroup = Dictionary(grouping: descriptors) {
            $0.exclusionGroup ?? $0.id
        }
        var dropped = Set<String>()

        for groupDescriptors in descriptorsByConflictGroup.values {
            let selectedInGroup = groupDescriptors.filter { knownSet.contains($0.id) }
            guard selectedInGroup.count > 1 else { continue }
            let chosen = selectedInGroup
                .sorted { lhs, rhs in
                    if lhs.variantOfListId == nil && rhs.variantOfListId != nil { return true }
                    if lhs.variantOfListId != nil && rhs.variantOfListId == nil { return false }
                    if lhs.defaultEnabled != rhs.defaultEnabled { return lhs.defaultEnabled }
                    return lhs.id < rhs.id
                }
                .first?.id
            for descriptor in selectedInGroup where descriptor.id != chosen {
                dropped.insert(descriptor.id)
            }
        }

        let resolved = knownSet.subtracting(dropped).sorted()
        return AdblockFilterListSelectionValidation(
            requestedIdentifiers: requested,
            resolvedIdentifiers: resolved,
            unknownIdentifiers: unknown,
            droppedConflictingIdentifiers: dropped.sorted()
        )
    }

    func recommendedRegionalIdentifiers(for locale: Locale) -> [String] {
        let candidates = [
            locale.identifier.lowercased(),
            locale.language.languageCode?.identifier.lowercased(),
            locale.region?.identifier.lowercased(),
        ].compactMap { $0 }

        return descriptors
            .filter { descriptor in
                descriptor.category == .regional
                    && descriptor.localeTags.contains { tag in
                        candidates.contains(tag.lowercased())
                    }
            }
            .prefix(1)
            .map(\.id)
    }

    static let defaultDescriptors: [AdblockFilterListDescriptor] = {
        let easyListVariants = "easylist.base.variant"
        return [
        descriptor(
            id: "adguard-base",
            displayName: "AdGuard Base",
            category: .baseAds,
            remoteURL: URL(string: "https://filters.adtidy.org/extension/chromium/filters/2.txt")!,
            homepageURL: URL(string: "https://adguard.com/kb/general/ad-filtering/adguard-filters/")!,
            defaultEnabled: false,
            localeTags: ["en"],
            licenseNoticeHint: "upstream-managed",
            shortDescription: "Core AdGuard advertising filters used by high-coverage native reference profiles.",
            mayContainCosmeticFilters: true,
            isAllowedInNativeOnlyMode: true
        ),
        descriptor(
            id: "adguard-mobile-ads",
            displayName: "AdGuard Mobile Ads",
            category: .baseAds,
            remoteURL: URL(string: "https://filters.adtidy.org/extension/chromium/filters/11.txt")!,
            homepageURL: URL(string: "https://adguard.com/kb/general/ad-filtering/adguard-filters/")!,
            defaultEnabled: false,
            localeTags: [],
            licenseNoticeHint: "upstream-managed",
            shortDescription: "Mobile ad-network filters used by AdGuard-heavy native reference profiles; experimental on desktop WebKit.",
            mayContainCosmeticFilters: true,
            isAllowedInNativeOnlyMode: true
        ),
        descriptor(
            id: "adguard-tracking-protection",
            displayName: "AdGuard Tracking Protection",
            category: .privacyOverlap,
            remoteURL: URL(string: "https://filters.adtidy.org/extension/chromium/filters/3.txt")!,
            homepageURL: URL(string: "https://adguard.com/kb/general/ad-filtering/adguard-filters/")!,
            defaultEnabled: false,
            localeTags: [],
            licenseNoticeHint: "upstream-managed",
            shortDescription: "AdGuard privacy filters reserved for native compiler comparison while Tracking Protection remains separate.",
            mayContainCosmeticFilters: true,
            isAllowedInNativeOnlyMode: true
        ),
        descriptor(
            id: "adguard-url-tracking",
            displayName: "AdGuard URL Tracking",
            category: .privacyOverlap,
            remoteURL: URL(string: "https://filters.adtidy.org/windows/filters/17.txt")!,
            homepageURL: URL(string: "https://adguard.com/kb/general/ad-filtering/adguard-filters/")!,
            defaultEnabled: false,
            localeTags: [],
            licenseNoticeHint: "upstream-managed",
            shortDescription: "URL tracking filter modeled for native compiler comparison; not enabled by default.",
            mayContainCosmeticFilters: true,
            isAllowedInNativeOnlyMode: true
        ),
        descriptor(
            id: "easylist",
            displayName: "EasyList",
            category: .baseAds,
            remoteURL: URL(string: "https://easylist.to/easylist/easylist.txt")!,
            homepageURL: URL(string: "https://easylist.to/"),
            defaultEnabled: true,
            localeTags: ["en"],
            licenseNoticeHint: "upstream-managed",
            exclusionGroup: easyListVariants,
            shortDescription: "Primary international ad blocking list.",
            mayContainCosmeticFilters: true,
            isAllowedInNativeOnlyMode: true
        ),
        descriptor(
            id: "easylist-without-element-hiding",
            displayName: "EasyList without element hiding",
            category: .nativeCosmeticCompatibleAds,
            remoteURL: URL(string: "https://easylist-downloads.adblockplus.org/easylist_noelemhide.txt")!,
            homepageURL: URL(string: "https://easylist.to/pages/other-supplementary-filter-lists-and-easylist-variants.html")!,
            defaultEnabled: false,
            localeTags: ["en"],
            licenseNoticeHint: "upstream-managed",
            variantOfListId: "easylist",
            exclusionGroup: easyListVariants,
            shortDescription: "EasyList variant with element hiding removed.",
            mayContainCosmeticFilters: false,
            isAllowedInNativeOnlyMode: true
        ),
        descriptor(
            id: "easylist-cookie",
            displayName: "EasyList Cookie List",
            category: .annoyances,
            remoteURL: URL(string: "https://secure.fanboy.co.nz/fanboy-cookiemonster.txt")!,
            homepageURL: URL(string: "https://easylist.to/")!,
            localeTags: [],
            licenseNoticeHint: "upstream-managed",
            shortDescription: "Cookie banners and privacy notice filters.",
            mayContainCosmeticFilters: true,
            isAllowedInNativeOnlyMode: true
        ),
        descriptor(
            id: "fanboy-annoyances",
            displayName: "Fanboy's Annoyance List",
            category: .annoyances,
            remoteURL: URL(string: "https://secure.fanboy.co.nz/fanboy-annoyance.txt")!,
            homepageURL: URL(string: "https://easylist.to/")!,
            defaultEnabled: false,
            localeTags: [],
            licenseNoticeHint: "upstream-managed",
            shortDescription: "Social widgets, pop-ups, cookie notices, and other annoyances.",
            mayContainCosmeticFilters: true,
            isAllowedInNativeOnlyMode: true
        ),
        descriptor(
            id: "fanboy-social",
            displayName: "Fanboy's Social Blocking List",
            category: .annoyances,
            remoteURL: URL(string: "https://easylist.to/easylist/fanboy-social.txt")!,
            homepageURL: URL(string: "https://easylist.to/")!,
            localeTags: [],
            licenseNoticeHint: "upstream-managed",
            shortDescription: "Social widgets and embedded social content.",
            mayContainCosmeticFilters: true,
            isAllowedInNativeOnlyMode: true
        ),
        descriptor(
            id: "adguard-annoyances",
            displayName: "AdGuard Annoyances",
            category: .annoyances,
            remoteURL: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_14_Annoyances/filter.txt")!,
            homepageURL: URL(string: "https://adguard.com/kb/general/ad-filtering/adguard-filters/")!,
            localeTags: [],
            licenseNoticeHint: "upstream-managed",
            shortDescription: "Optional annoyance bundle; disabled by default.",
            mayContainCosmeticFilters: true,
            isAllowedInNativeOnlyMode: true
        ),
        descriptor(
            id: "adguard-cookie-notices",
            displayName: "AdGuard Cookie Notices",
            category: .annoyances,
            remoteURL: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_18_Annoyances_Cookies/filter.txt")!,
            homepageURL: URL(string: "https://adguard.com/kb/general/ad-filtering/adguard-filters/")!,
            localeTags: [],
            licenseNoticeHint: "upstream-managed",
            shortDescription: "Cookie notice placeholder list for native-compatible filtering.",
            mayContainCosmeticFilters: true,
            isAllowedInNativeOnlyMode: true
        ),
        descriptor(
            id: "abpindo",
            displayName: "ABPindo",
            category: .regional,
            remoteURL: URL(string: "https://raw.githubusercontent.com/ABPindo/indonesianadblockrules/master/subscriptions/abpindo.txt")!,
            homepageURL: URL(string: "https://easylist.to/pages/other-supplementary-filter-lists-and-easylist-variants.html")!,
            localeTags: ["id", "id_id"],
            shortDescription: "Indonesian language ad filters."
        ),
        descriptor(
            id: "abpvn",
            displayName: "ABPVN List",
            category: .regional,
            remoteURL: URL(string: "https://abpvn.com/filter/abpvn.txt")!,
            homepageURL: URL(string: "https://easylist.to/pages/other-supplementary-filter-lists-and-easylist-variants.html")!,
            localeTags: ["vi", "vi_vn"],
            shortDescription: "Vietnamese language ad filters."
        ),
        descriptor(
            id: "easylist-bulgarian",
            displayName: "Bulgarian List",
            category: .regional,
            remoteURL: URL(string: "https://stanev.org/abp/adblock_bg.txt")!,
            homepageURL: URL(string: "https://easylist.to/pages/other-supplementary-filter-lists-and-easylist-variants.html")!,
            localeTags: ["bg", "bg_bg"],
            shortDescription: "Bulgarian language ad filters."
        ),
        descriptor(
            id: "dandelion-nordic",
            displayName: "Dandelion Sprout's Nordic Filters",
            category: .regional,
            remoteURL: URL(string: "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/NorwegianList.txt")!,
            homepageURL: URL(string: "https://easylist.to/pages/other-supplementary-filter-lists-and-easylist-variants.html")!,
            localeTags: ["no", "nb", "nn", "da", "is", "fo", "kl", "fi", "sv"],
            shortDescription: "Nordic language ad filters."
        ),
        descriptor(
            id: "easylist-china",
            displayName: "EasyList China",
            category: .regional,
            remoteURL: URL(string: "https://easylist-downloads.adblockplus.org/easylistchina.txt")!,
            homepageURL: URL(string: "https://easylist.to/pages/other-supplementary-filter-lists-and-easylist-variants.html")!,
            localeTags: ["zh", "zh_cn", "zh_tw", "zh_hk"],
            shortDescription: "Chinese language ad filters."
        ),
        descriptor(
            id: "easylist-czech-slovak",
            displayName: "EasyList Czech and Slovak",
            category: .regional,
            remoteURL: URL(string: "https://raw.githubusercontent.com/tomasko126/easylistczechandslovak/master/filters.txt")!,
            homepageURL: URL(string: "https://easylist.to/pages/other-supplementary-filter-lists-and-easylist-variants.html")!,
            localeTags: ["cs", "cs_cz", "sk", "sk_sk"],
            shortDescription: "Czech and Slovak language ad filters."
        ),
        descriptor(
            id: "easylist-dutch",
            displayName: "EasyList Dutch",
            category: .regional,
            remoteURL: URL(string: "https://easylist-downloads.adblockplus.org/easylistdutch.txt")!,
            homepageURL: URL(string: "https://easylist.to/pages/other-supplementary-filter-lists-and-easylist-variants.html")!,
            localeTags: ["nl", "nl_nl", "nl_be"],
            shortDescription: "Dutch language ad filters."
        ),
        descriptor(
            id: "easylist-germany",
            displayName: "EasyList Germany",
            category: .regional,
            remoteURL: URL(string: "https://easylist.to/easylistgermany/easylistgermany.txt")!,
            homepageURL: URL(string: "https://easylist.to/pages/other-supplementary-filter-lists-and-easylist-variants.html")!,
            defaultEnabled: false,
            localeTags: ["de", "de_de", "de-at", "de-ch"],
            licenseNoticeHint: "upstream-managed",
            shortDescription: "German language ad filters.",
            mayContainCosmeticFilters: true,
            isAllowedInNativeOnlyMode: true
        ),
        descriptor(
            id: "easylist-hebrew",
            displayName: "EasyList Hebrew",
            category: .regional,
            remoteURL: URL(string: "https://raw.githubusercontent.com/easylist/EasyListHebrew/master/EasyListHebrew.txt")!,
            homepageURL: URL(string: "https://easylist.to/pages/other-supplementary-filter-lists-and-easylist-variants.html")!,
            localeTags: ["he", "he_il"],
            shortDescription: "Hebrew language ad filters."
        ),
        descriptor(
            id: "easylist-italy",
            displayName: "EasyList Italy",
            category: .regional,
            remoteURL: URL(string: "https://easylist-downloads.adblockplus.org/easylistitaly.txt")!,
            homepageURL: URL(string: "https://easylist.to/pages/other-supplementary-filter-lists-and-easylist-variants.html")!,
            localeTags: ["it", "it_it"],
            shortDescription: "Italian language ad filters."
        ),
        descriptor(
            id: "easylist-lithuania",
            displayName: "EasyList Lithuania",
            category: .regional,
            remoteURL: URL(string: "https://raw.githubusercontent.com/EasyList-Lithuania/easylist_lithuania/master/easylistlithuania.txt")!,
            homepageURL: URL(string: "https://easylist.to/pages/other-supplementary-filter-lists-and-easylist-variants.html")!,
            localeTags: ["lt", "lt_lt"],
            shortDescription: "Lithuanian language ad filters."
        ),
        descriptor(
            id: "liste-fr",
            displayName: "Liste FR",
            category: .regional,
            remoteURL: URL(string: "https://easylist-downloads.adblockplus.org/liste_fr.txt")!,
            homepageURL: URL(string: "https://easylist.to/pages/other-supplementary-filter-lists-and-easylist-variants.html")!,
            defaultEnabled: false,
            localeTags: ["fr", "fr_fr", "fr-ca", "fr-be", "fr-ch"],
            licenseNoticeHint: "upstream-managed",
            shortDescription: "French language ad filters.",
            mayContainCosmeticFilters: true,
            isAllowedInNativeOnlyMode: true
        ),
        descriptor(
            id: "ru-adlist",
            displayName: "RU AdList",
            category: .regional,
            remoteURL: URL(string: "https://easylist-downloads.adblockplus.org/advblock.txt")!,
            homepageURL: URL(string: "https://easylist.to/pages/other-supplementary-filter-lists-and-easylist-variants.html")!,
            defaultEnabled: false,
            localeTags: ["ru", "ru_ru", "uk", "uk_ua"],
            licenseNoticeHint: "upstream-managed",
            shortDescription: "Russian and Ukrainian language ad filters.",
            mayContainCosmeticFilters: true,
            isAllowedInNativeOnlyMode: true
        ),
        descriptor(
            id: "easylist-polish",
            displayName: "EasyList Polish",
            category: .regional,
            remoteURL: URL(string: "https://easylist-downloads.adblockplus.org/easylistpolish.txt")!,
            homepageURL: URL(string: "https://easylist.to/pages/other-supplementary-filter-lists-and-easylist-variants.html")!,
            defaultEnabled: false,
            localeTags: ["pl", "pl_pl"],
            licenseNoticeHint: "upstream-managed",
            shortDescription: "Polish language ad filters.",
            mayContainCosmeticFilters: true,
            isAllowedInNativeOnlyMode: true
        ),
        descriptor(
            id: "easylist-portuguese",
            displayName: "EasyList Portuguese",
            category: .regional,
            remoteURL: URL(string: "https://easylist-downloads.adblockplus.org/easylistportuguese.txt")!,
            homepageURL: URL(string: "https://easylist.to/pages/other-supplementary-filter-lists-and-easylist-variants.html")!,
            localeTags: ["pt", "pt_pt", "pt_br"],
            shortDescription: "Portuguese language ad filters."
        ),
        descriptor(
            id: "easylist-spanish",
            displayName: "EasyList Spanish",
            category: .regional,
            remoteURL: URL(string: "https://easylist-downloads.adblockplus.org/easylistspanish.txt")!,
            homepageURL: URL(string: "https://easylist.to/pages/other-supplementary-filter-lists-and-easylist-variants.html")!,
            localeTags: ["es", "es_es", "es_mx", "es_ar", "es_cl", "es_co"],
            shortDescription: "Spanish language ad filters."
        ),
        descriptor(
            id: "indianlist",
            displayName: "IndianList",
            category: .regional,
            remoteURL: URL(string: "https://easylist-downloads.adblockplus.org/indianlist.txt")!,
            homepageURL: URL(string: "https://easylist.to/pages/other-supplementary-filter-lists-and-easylist-variants.html")!,
            localeTags: ["hi", "bn", "gu", "pa", "as", "mr", "ml", "te", "kn", "or", "ne", "si"],
            shortDescription: "Indian subcontinent language ad filters."
        ),
        descriptor(
            id: "koreanlist",
            displayName: "KoreanList",
            category: .regional,
            remoteURL: URL(string: "https://easylist-downloads.adblockplus.org/koreanlist.txt")!,
            homepageURL: URL(string: "https://easylist.to/pages/other-supplementary-filter-lists-and-easylist-variants.html")!,
            localeTags: ["ko", "ko_kr"],
            shortDescription: "Korean language ad filters."
        ),
        descriptor(
            id: "latvian-list",
            displayName: "Latvian List",
            category: .regional,
            remoteURL: URL(string: "https://raw.githubusercontent.com/Latvian-List/adblock-latvian/master/lists/latvian-list.txt")!,
            homepageURL: URL(string: "https://easylist.to/pages/other-supplementary-filter-lists-and-easylist-variants.html")!,
            localeTags: ["lv", "lv_lv"],
            shortDescription: "Latvian language ad filters."
        ),
        descriptor(
            id: "liste-ar",
            displayName: "Liste AR",
            category: .regional,
            remoteURL: URL(string: "https://easylist-downloads.adblockplus.org/Liste_AR.txt")!,
            homepageURL: URL(string: "https://easylist.to/pages/other-supplementary-filter-lists-and-easylist-variants.html")!,
            localeTags: ["ar"],
            shortDescription: "Arabic language ad filters."
        ),
        descriptor(
            id: "adguard-social-media",
            displayName: "AdGuard Social Media",
            category: .annoyances,
            remoteURL: URL(string: "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_4_Social/filter.txt")!,
            homepageURL: URL(string: "https://adguard.com/kb/general/ad-filtering/adguard-filters/")!,
            localeTags: [],
            licenseNoticeHint: "upstream-managed",
            shortDescription: "Social buttons and widgets placeholder; disabled by default.",
            mayContainCosmeticFilters: true,
            isAllowedInNativeOnlyMode: true
        ),
        descriptor(
            id: "easyprivacy-future",
            displayName: "EasyPrivacy",
            category: .privacyOverlap,
            remoteURL: URL(string: "https://easylist.to/easylist/easyprivacy.txt")!,
            homepageURL: URL(string: "https://easylist.to/")!,
            localeTags: [],
            licenseNoticeHint: "upstream-managed",
            shortDescription: "Privacy-overlap list reserved while Tracking Protection remains separate.",
            mayContainCosmeticFilters: false,
            isAllowedInNativeOnlyMode: true
        ),
        ]
    }()

    private static func descriptor(
        id: String,
        displayName: String,
        category: AdblockFilterListCategory,
        remoteURL: URL,
        homepageURL: URL?,
        defaultEnabled: Bool = false,
        localeTags: [String],
        licenseNoticeHint: String = "upstream-managed",
        variantOfListId: String? = nil,
        exclusionGroup: String? = nil,
        shortDescription: String,
        mayContainCosmeticFilters: Bool = true,
        isAllowedInNativeOnlyMode: Bool = true
    ) -> AdblockFilterListDescriptor {
        AdblockFilterListDescriptor(
            id: id,
            displayName: displayName,
            category: category,
            remoteURL: remoteURL,
            homepageURL: homepageURL,
            defaultEnabled: defaultEnabled,
            localeTags: localeTags,
            licenseNoticeHint: licenseNoticeHint,
            variantOfListId: variantOfListId,
            exclusionGroup: exclusionGroup,
            shortDescription: shortDescription,
            mayContainCosmeticFilters: mayContainCosmeticFilters,
            isAllowedInNativeOnlyMode: isAllowedInNativeOnlyMode
        )
    }
}

struct SumiAdblockFilterListSelection: Codable, Equatable, Sendable {
    var identifiers: [String]

    static let defaultSelection = SumiAdblockFilterListSelection(identifiers: [])

    var usesDefaultSelection: Bool {
        identifiers.isEmpty
    }
}

struct AdblockFilterListHTTPMetadata: Codable, Equatable, Sendable {
    var eTag: String?
    var lastModified: String?
    var lastCheckedDate: Date?
    var lastSuccessfulDownloadDate: Date?
    var contentHash: String?
    var failureSummary: String?
    var failureStage: AdblockUpdateFailureStage?
    var lastHTTPStatus: Int?
}

enum AdblockUpdateFailureStage: String, Codable, CaseIterable, Sendable {
    case effectiveListSelectionFailed = "effective list selection failed"
    case missingSelectedListDescriptor = "missing selected list descriptor"
    case invalidListURL = "invalid list URL"
    case downloadRequestCreationFailed = "download request creation failed"
    case networkRequestFailed = "network request failed"
    case httpStatusFailure = "HTTP status failure"
    case redirectFailure = "redirect failure"
    case notModifiedWithoutRawCache = "304 returned but no previous raw list exists"
    case rawCacheReadFailed = "raw cache read failed"
    case rawStagingWriteFailed = "raw staging write failed"
    case rawFileEmpty = "raw file empty"
    case rawFileTooSmall = "raw file too small / suspicious"
    case rawFileAppearsHTML = "raw file appears to be HTML/error page"
    case contentHashFailed = "content hash failed"
    case compilerInputAssemblyFailed = "compiler input assembly failed"
    case nativeCompilationFailed = "native compilation failed"
    case shardPublishFailed = "shard publish failed"
    case manifestCommitFailed = "manifest commit failed"
}

struct AdblockFilterListUpdateStatus: Codable, Equatable, Identifiable, Sendable {
    let listIdentifier: String
    let displayName: String
    let category: AdblockFilterListCategory?
    let selectionOrigins: [AdblockEffectiveListSelectionOrigin]
    var finalURL: String?
    var lastCheckedDate: Date?
    var lastSuccessfulDownloadDate: Date?
    var httpStatus: Int?
    var eTagUsed: String?
    var eTagSaved: String?
    var lastModifiedUsed: String?
    var lastModifiedSaved: String?
    var notModifiedReused: Bool
    var rawFilePath: String?
    var rawFileExists: Bool
    var rawByteSize: Int?
    var contentHash: String?
    var failureStage: AdblockUpdateFailureStage?
    var failureReason: String?

    var id: String { listIdentifier }

    var isFailure: Bool {
        failureStage != nil || failureReason != nil
    }
}

struct AdblockRawListFileInfo: Equatable, Sendable {
    let path: String
    let exists: Bool
    let byteSize: Int?
}

struct AdblockRuleListGeneration: Codable, Equatable, Sendable {
    let id: String
    let createdDate: Date
}

enum AdblockRuleGenerationSource: String, Codable, CaseIterable, Sendable {
    case runtimeGenerated
    case embeddedBundle
    case futureRemoteBundle
}

struct AdblockCompiledGenerationManifest: Codable, Equatable, Sendable {
    struct SelectedFilterList: Codable, Equatable, Sendable {
        let id: String
        let displayName: String
        let contentHash: String
        let category: AdblockFilterListCategory?
        let inputByteCount: Int?
        let approximateRuleCount: Int?

        init(
            id: String,
            displayName: String,
            contentHash: String,
            category: AdblockFilterListCategory? = nil,
            inputByteCount: Int? = nil,
            approximateRuleCount: Int? = nil
        ) {
            self.id = id
            self.displayName = displayName
            self.contentHash = contentHash
            self.category = category
            self.inputByteCount = inputByteCount
            self.approximateRuleCount = approximateRuleCount
        }
    }

    struct Group: Codable, Equatable, Sendable {
        let kind: AdblockCompiledRuleGroupKind
        let webKitIdentifier: String
        let contentHash: String
        let convertedRuleCount: Int
    }

    let schemaVersion: Int
    let activeGenerationId: String
    let createdDate: Date
    let selectedFilterLists: [SelectedFilterList]
    let webKitRuleListIdentifiers: [String]
    let networkShards: [NativeContentBlockingShardDescriptor]
    let nativeCSSShards: [NativeContentBlockingShardDescriptor]
    let enhancedRuntimeBundle: AdblockEnhancedRuntimeBundle?
    let nativeProfile: AdblockFilterListProfileKind?
    let nativeCompiler: NativeContentBlockingCompilerIdentity?
    let nativeCompilerSourceLists: [NativeContentBlockingSourceList]?
    let nativeCompilationSummary: NativeContentBlockingCompilationSummary?
    let compilerDiagnosticsSummary: String
    let lastSuccessfulUpdateDate: Date
    let previousGenerationId: String?
    let generationSource: AdblockRuleGenerationSource
    let nativeRuleBundleId: String?

    var allNativeShards: [NativeContentBlockingShardDescriptor] {
        networkShards + nativeCSSShards
    }

    var groupedOutputs: [Group] {
        allNativeShards.map {
            Group(
                kind: $0.kind,
                webKitIdentifier: $0.webKitIdentifier,
                contentHash: $0.contentHash,
                convertedRuleCount: $0.approximateRuleCount
            )
        }
    }

    init(
        schemaVersion: Int,
        activeGenerationId: String,
        createdDate: Date,
        selectedFilterLists: [SelectedFilterList],
        networkShards: [NativeContentBlockingShardDescriptor],
        nativeCSSShards: [NativeContentBlockingShardDescriptor],
        enhancedRuntimeBundle: AdblockEnhancedRuntimeBundle?,
        nativeProfile: AdblockFilterListProfileKind? = nil,
        nativeCompiler: NativeContentBlockingCompilerIdentity?,
        nativeCompilerSourceLists: [NativeContentBlockingSourceList]?,
        nativeCompilationSummary: NativeContentBlockingCompilationSummary? = nil,
        compilerDiagnosticsSummary: String,
        lastSuccessfulUpdateDate: Date,
        previousGenerationId: String?,
        generationSource: AdblockRuleGenerationSource = .runtimeGenerated,
        nativeRuleBundleId: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.activeGenerationId = activeGenerationId
        self.createdDate = createdDate
        self.selectedFilterLists = selectedFilterLists
        self.networkShards = networkShards
        self.nativeCSSShards = nativeCSSShards
        self.webKitRuleListIdentifiers = (networkShards + nativeCSSShards)
            .map(\.webKitIdentifier)
            .sorted()
        self.enhancedRuntimeBundle = enhancedRuntimeBundle
        self.nativeProfile = nativeProfile
        self.nativeCompiler = nativeCompiler
        self.nativeCompilerSourceLists = nativeCompilerSourceLists
        self.nativeCompilationSummary = nativeCompilationSummary
        self.compilerDiagnosticsSummary = compilerDiagnosticsSummary
        self.lastSuccessfulUpdateDate = lastSuccessfulUpdateDate
        self.previousGenerationId = previousGenerationId
        self.generationSource = generationSource
        self.nativeRuleBundleId = nativeRuleBundleId
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case activeGenerationId
        case createdDate
        case selectedFilterLists
        case webKitRuleListIdentifiers
        case groupedOutputs
        case networkShards
        case nativeCSSShards
        case enhancedRuntimeBundle
        case nativeProfile
        case nativeCompiler
        case nativeCompilerSourceLists
        case nativeCompilationSummary
        case compilerDiagnosticsSummary
        case lastSuccessfulUpdateDate
        case previousGenerationId
        case generationSource
        case nativeRuleBundleId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        activeGenerationId = try container.decode(String.self, forKey: .activeGenerationId)
        createdDate = try container.decode(Date.self, forKey: .createdDate)
        selectedFilterLists = try container.decode([SelectedFilterList].self, forKey: .selectedFilterLists)
        enhancedRuntimeBundle = try container.decodeIfPresent(
            AdblockEnhancedRuntimeBundle.self,
            forKey: .enhancedRuntimeBundle
        )
        nativeProfile = try container.decodeIfPresent(
            AdblockFilterListProfileKind.self,
            forKey: .nativeProfile
        )
        nativeCompiler = try container.decodeIfPresent(
            NativeContentBlockingCompilerIdentity.self,
            forKey: .nativeCompiler
        )
        nativeCompilerSourceLists = try container.decodeIfPresent(
            [NativeContentBlockingSourceList].self,
            forKey: .nativeCompilerSourceLists
        )
        nativeCompilationSummary = try container.decodeIfPresent(
            NativeContentBlockingCompilationSummary.self,
            forKey: .nativeCompilationSummary
        )
        compilerDiagnosticsSummary = try container.decode(
            String.self,
            forKey: .compilerDiagnosticsSummary
        )
        lastSuccessfulUpdateDate = try container.decode(
            Date.self,
            forKey: .lastSuccessfulUpdateDate
        )
        previousGenerationId = try container.decodeIfPresent(
            String.self,
            forKey: .previousGenerationId
        )
        generationSource = try container.decodeIfPresent(
            AdblockRuleGenerationSource.self,
            forKey: .generationSource
        ) ?? .runtimeGenerated
        nativeRuleBundleId = try container.decodeIfPresent(
            String.self,
            forKey: .nativeRuleBundleId
        )

        if let decodedNetworkShards = try container.decodeIfPresent(
            [NativeContentBlockingShardDescriptor].self,
            forKey: .networkShards
        ),
           let decodedNativeCSSShards = try container.decodeIfPresent(
            [NativeContentBlockingShardDescriptor].self,
            forKey: .nativeCSSShards
        ) {
            networkShards = decodedNetworkShards
            nativeCSSShards = decodedNativeCSSShards
        } else {
            let legacyGroups = try container.decodeIfPresent([Group].self, forKey: .groupedOutputs) ?? []
            let activeGenerationIdForMigration = activeGenerationId
            let selectedFilterListsForMigration = selectedFilterLists
            let nativeCompilerForMigration = nativeCompiler
            let nativeProfileForMigration = nativeProfile
            let migrated = legacyGroups.enumerated().map { index, group in
                Self.legacyShard(
                    from: group,
                    index: index,
                    generationId: activeGenerationIdForMigration,
                    selectedFilterLists: selectedFilterListsForMigration,
                    nativeCompiler: nativeCompilerForMigration,
                    nativeProfile: nativeProfileForMigration
                )
            }
            networkShards = migrated.filter { $0.kind == .network }
            nativeCSSShards = migrated.filter { $0.kind == .nativeCosmeticCSS }
        }

        webKitRuleListIdentifiers = try container.decodeIfPresent(
            [String].self,
            forKey: .webKitRuleListIdentifiers
        ) ?? (networkShards + nativeCSSShards).map(\.webKitIdentifier).sorted()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(activeGenerationId, forKey: .activeGenerationId)
        try container.encode(createdDate, forKey: .createdDate)
        try container.encode(selectedFilterLists, forKey: .selectedFilterLists)
        try container.encode(webKitRuleListIdentifiers, forKey: .webKitRuleListIdentifiers)
        try container.encode(groupedOutputs, forKey: .groupedOutputs)
        try container.encode(networkShards, forKey: .networkShards)
        try container.encode(nativeCSSShards, forKey: .nativeCSSShards)
        try container.encodeIfPresent(enhancedRuntimeBundle, forKey: .enhancedRuntimeBundle)
        try container.encodeIfPresent(nativeProfile, forKey: .nativeProfile)
        try container.encodeIfPresent(nativeCompiler, forKey: .nativeCompiler)
        try container.encodeIfPresent(nativeCompilerSourceLists, forKey: .nativeCompilerSourceLists)
        try container.encodeIfPresent(nativeCompilationSummary, forKey: .nativeCompilationSummary)
        try container.encode(compilerDiagnosticsSummary, forKey: .compilerDiagnosticsSummary)
        try container.encode(lastSuccessfulUpdateDate, forKey: .lastSuccessfulUpdateDate)
        try container.encodeIfPresent(previousGenerationId, forKey: .previousGenerationId)
        try container.encode(generationSource, forKey: .generationSource)
        try container.encodeIfPresent(nativeRuleBundleId, forKey: .nativeRuleBundleId)
    }

    private static func legacyShard(
        from group: Group,
        index: Int,
        generationId: String,
        selectedFilterLists: [SelectedFilterList],
        nativeCompiler: NativeContentBlockingCompilerIdentity?,
        nativeProfile: AdblockFilterListProfileKind?
    ) -> NativeContentBlockingShardDescriptor {
        NativeContentBlockingShardDescriptor(
            id: "legacy-\(group.kind.rawValue)-\(String(format: "%04d", index + 1))",
            generationId: generationId,
            kind: group.kind,
            sourceListIdentifiers: selectedFilterLists.map(\.id).sorted(),
            sourceCategories: Array(Set(selectedFilterLists.compactMap(\.category)))
                .sorted { $0.rawValue < $1.rawValue },
            webKitIdentifier: group.webKitIdentifier,
            contentHash: group.contentHash,
            approximateRuleCount: group.convertedRuleCount,
            jsonByteCount: 0,
            compilerIdentity: nativeCompiler,
            profileIdentity: nativeProfile,
            diagnosticsSummary: "legacySingleGroupRepresentation"
        )
    }
}

struct AdblockGenerationCleanupReport: Equatable, Sendable {
    var removedWebKitIdentifiers: [String] = []
    var removedFilePaths: [String] = []
    var diagnostics: [String] = []
}

struct AdblockGenerationRollbackReport: Equatable, Sendable {
    let rolledBack: Bool
    let activeGenerationId: String?
    let restoredGenerationId: String?
    let diagnostics: [String]
}

enum AdblockRebuildMemoryStage: String, Codable, CaseIterable, Sendable {
    case beforeRebuild
    case afterDownloadRawValidation
    case afterRustConversion
    case afterShardJSONGeneration
    case afterWKContentRuleListStoreCompile
    case afterManifestCommitProviderSwitch
    case afterCleanup
    case afterClearingTemporaryObjects
    case afterPageReloadAttachment
}

struct AdblockRebuildMemorySnapshot: Codable, Equatable, Sendable {
    let stage: AdblockRebuildMemoryStage
    let timestamp: Date
    let residentMemoryBytes: UInt64
}

struct AdblockRebuildMemoryDiagnostics: Codable, Equatable, Sendable {
    let snapshots: [AdblockRebuildMemorySnapshot]
    let peakResidentMemoryBytes: UInt64?
    let steadyStateResidentMemoryBytes: UInt64?
    let activeGenerationShardCount: Int
    let attachedShardCount: Int
    let totalNetworkRuleCount: Int
    let totalNativeCSSRuleCount: Int
    let selectedProfile: AdblockFilterListProfileKind?
    let effectiveListCount: Int
    let manualListCount: Int
    let oldGenerationRetained: Bool
    let budgetWarnings: [String]

    init(
        snapshots: [AdblockRebuildMemorySnapshot],
        activeGenerationShardCount: Int,
        attachedShardCount: Int,
        totalNetworkRuleCount: Int,
        totalNativeCSSRuleCount: Int,
        selectedProfile: AdblockFilterListProfileKind?,
        effectiveListCount: Int,
        manualListCount: Int,
        oldGenerationRetained: Bool,
        budgetWarnings: [String]
    ) {
        self.snapshots = snapshots
        peakResidentMemoryBytes = snapshots.map(\.residentMemoryBytes).max()
        steadyStateResidentMemoryBytes = snapshots.last { snapshot in
            snapshot.stage == .afterClearingTemporaryObjects
        }?.residentMemoryBytes ?? snapshots.last?.residentMemoryBytes
        self.activeGenerationShardCount = activeGenerationShardCount
        self.attachedShardCount = attachedShardCount
        self.totalNetworkRuleCount = totalNetworkRuleCount
        self.totalNativeCSSRuleCount = totalNativeCSSRuleCount
        self.selectedProfile = selectedProfile
        self.effectiveListCount = effectiveListCount
        self.manualListCount = manualListCount
        self.oldGenerationRetained = oldGenerationRetained
        self.budgetWarnings = budgetWarnings
    }
}

enum AdblockRebuildBudget {
    static let networkRuleWarningThreshold = 150_000
    static let nativeCSSRuleWarningThreshold = 75_000
    static let shardWarningThreshold = 20

    static func warnings(
        networkRuleCount: Int,
        nativeCSSRuleCount: Int,
        shardCount: Int,
        selectionDiagnostics: AdblockEffectiveSelectionDiagnostics?
    ) -> [String] {
        var warnings = [String]()
        if networkRuleCount > networkRuleWarningThreshold {
            warnings.append("Network rules exceed lightweight budget: \(networkRuleCount) > \(networkRuleWarningThreshold)")
        }
        if nativeCSSRuleCount > nativeCSSRuleWarningThreshold {
            warnings.append("Native CSS rules exceed lightweight budget: \(nativeCSSRuleCount) > \(nativeCSSRuleWarningThreshold)")
        }
        if shardCount > shardWarningThreshold {
            warnings.append("Shard count exceeds lightweight budget: \(shardCount) > \(shardWarningThreshold)")
        }
        if selectionDiagnostics?.isCustomListSelection == true {
            warnings.append("Effective mode is custom list selection; selected profile is not the compiled list budget.")
        }
        return warnings
    }
}

#if DEBUG
actor AdblockRebuildMemoryRecorder {
    private var snapshots = [AdblockRebuildMemorySnapshot]()
    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    func record(_ stage: AdblockRebuildMemoryStage) {
        guard let residentMemoryBytes = AdblockProcessMemorySampler.residentMemoryBytes() else { return }
        let snapshot = AdblockRebuildMemorySnapshot(
            stage: stage,
            timestamp: now(),
            residentMemoryBytes: residentMemoryBytes
        )
        snapshots.append(snapshot)
        RuntimeDiagnostics.emit("[Adblock] rebuild memory \(stage.rawValue): \(residentMemoryBytes) bytes")
    }

    func diagnostics(
        manifest: AdblockCompiledGenerationManifest?,
        selectionDiagnostics: AdblockEffectiveSelectionDiagnostics?,
        attachedShardCount: Int
    ) -> AdblockRebuildMemoryDiagnostics {
        let networkRuleCount = manifest?.networkShards.reduce(0) { $0 + $1.approximateRuleCount } ?? 0
        let nativeCSSRuleCount = manifest?.nativeCSSShards.reduce(0) { $0 + $1.approximateRuleCount } ?? 0
        let shardCount = manifest?.allNativeShards.count ?? 0
        return AdblockRebuildMemoryDiagnostics(
            snapshots: snapshots,
            activeGenerationShardCount: shardCount,
            attachedShardCount: attachedShardCount,
            totalNetworkRuleCount: networkRuleCount,
            totalNativeCSSRuleCount: nativeCSSRuleCount,
            selectedProfile: selectionDiagnostics?.selectedNativeProfile ?? manifest?.nativeProfile,
            effectiveListCount: selectionDiagnostics?.finalEffectiveListIdentifiers.count
                ?? manifest?.selectedFilterLists.count
                ?? 0,
            manualListCount: selectionDiagnostics?.manuallySelectedListIdentifiers.count ?? 0,
            oldGenerationRetained: manifest?.previousGenerationId != nil,
            budgetWarnings: AdblockRebuildBudget.warnings(
                networkRuleCount: networkRuleCount,
                nativeCSSRuleCount: nativeCSSRuleCount,
                shardCount: shardCount,
                selectionDiagnostics: selectionDiagnostics
            )
        )
    }
}

enum AdblockRebuildMemoryLifecycle {
    @TaskLocal static var recorder: AdblockRebuildMemoryRecorder?

    static func record(_ stage: AdblockRebuildMemoryStage) async {
        await recorder?.record(stage)
    }
}

enum AdblockProcessMemorySampler {
    static func residentMemoryBytes() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(TASK_VM_INFO),
                    $0,
                    &count
                )
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return UInt64(info.phys_footprint)
    }
}
#endif

struct AdblockUpdateDiagnostics: Error, LocalizedError, Equatable, Sendable {
    var summary: String
    var stage: AdblockUpdateFailureStage?
    var listFailures: [String: String] = [:]
    var listStatuses: [AdblockFilterListUpdateStatus] = []
    var selectionDiagnostics: AdblockEffectiveSelectionDiagnostics?
    var failedShardIdentifier: String?
    var httpStatusCode: Int?
    var responseURLString: String?
    var responseETag: String?
    var responseLastModified: String?
    var memoryDiagnostics: AdblockRebuildMemoryDiagnostics?
    var generationSource: AdblockRuleGenerationSource?

    var errorDescription: String? { summary }

    init(
        summary: String,
        stage: AdblockUpdateFailureStage? = nil,
        listFailures: [String: String] = [:],
        listStatuses: [AdblockFilterListUpdateStatus] = [],
        selectionDiagnostics: AdblockEffectiveSelectionDiagnostics? = nil,
        failedShardIdentifier: String? = nil,
        httpStatusCode: Int? = nil,
        responseURLString: String? = nil,
        responseETag: String? = nil,
        responseLastModified: String? = nil,
        memoryDiagnostics: AdblockRebuildMemoryDiagnostics? = nil,
        generationSource: AdblockRuleGenerationSource? = nil
    ) {
        self.summary = summary
        self.stage = stage
        self.listFailures = listFailures
        self.listStatuses = listStatuses
        self.selectionDiagnostics = selectionDiagnostics
        self.failedShardIdentifier = failedShardIdentifier
        self.httpStatusCode = httpStatusCode
        self.responseURLString = responseURLString
        self.responseETag = responseETag
        self.responseLastModified = responseLastModified
        self.memoryDiagnostics = memoryDiagnostics
        self.generationSource = generationSource
    }
}

enum AdblockDownloadOutcome: Equatable, Sendable {
    case downloaded(Data, HTTPURLResponse)
    case notModified(HTTPURLResponse)
}

protocol AdblockFilterListDownloading: Sendable {
    func download(
        descriptor: AdblockFilterListDescriptor,
        previousMetadata: AdblockFilterListHTTPMetadata?
    ) async throws -> AdblockDownloadOutcome
}

struct AdblockFilterListDownloader: AdblockFilterListDownloading {
    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private let fetch: Fetch

    init(
        fetch: @escaping Fetch = { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw AdblockUpdateDiagnostics(
                    summary: "Network request failed: invalid HTTP response",
                    stage: .networkRequestFailed
                )
            }
            return (data, response)
        }
    ) {
        self.fetch = fetch
    }

    func download(
        descriptor: AdblockFilterListDescriptor,
        previousMetadata: AdblockFilterListHTTPMetadata?
    ) async throws -> AdblockDownloadOutcome {
        guard Self.isSupportedRemoteListURL(descriptor.remoteURL) else {
            throw AdblockUpdateDiagnostics(
                summary: "Invalid list URL: \(descriptor.remoteURL.absoluteString)",
                stage: .invalidListURL,
                responseURLString: descriptor.remoteURL.absoluteString
            )
        }

        var request = URLRequest(url: descriptor.remoteURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        if let eTag = previousMetadata?.eTag, !eTag.isEmpty {
            request.setValue(eTag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified = previousMetadata?.lastModified, !lastModified.isEmpty {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await fetch(request)
        } catch let diagnostics as AdblockUpdateDiagnostics {
            throw diagnostics
        } catch {
            throw AdblockUpdateDiagnostics(
                summary: "Network request failed: \(error.localizedDescription)",
                stage: .networkRequestFailed,
                responseURLString: descriptor.remoteURL.absoluteString
            )
        }
        guard let finalURL = response.url,
              Self.isSupportedRemoteListURL(finalURL)
        else {
            throw AdblockUpdateDiagnostics(
                summary: "Redirect failure: final URL is not a supported http(s) filter URL",
                stage: .redirectFailure,
                httpStatusCode: response.statusCode,
                responseURLString: response.url?.absoluteString,
                responseETag: response.value(forHTTPHeaderField: "ETag"),
                responseLastModified: response.value(forHTTPHeaderField: "Last-Modified")
            )
        }
        if response.statusCode == 304 {
            return .notModified(response)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw AdblockUpdateDiagnostics(
                summary: "HTTP status failure: \(response.statusCode)",
                stage: .httpStatusFailure,
                httpStatusCode: response.statusCode,
                responseURLString: finalURL.absoluteString,
                responseETag: response.value(forHTTPHeaderField: "ETag"),
                responseLastModified: response.value(forHTTPHeaderField: "Last-Modified")
            )
        }
        return .downloaded(data, response)
    }

    private static func isSupportedRemoteListURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host?.isEmpty == false
        else { return false }
        return true
    }
}

actor AdblockUpdateManifestStore {
    private let fileManager: FileManager
    private let rootDirectory: URL
    private let manifestURL: URL
    private let metadataURL: URL

    init(
        fileManager: FileManager = .default,
        rootDirectory: URL? = nil
    ) {
        self.fileManager = fileManager
        self.rootDirectory = rootDirectory ?? Self.defaultRootDirectory()
        manifestURL = self.rootDirectory.appendingPathComponent("active-generation.json")
        metadataURL = self.rootDirectory.appendingPathComponent("filter-list-http-metadata.json")
    }

    nonisolated var storageRoot: URL {
        rootDirectory
    }

    func activeManifest() throws -> AdblockCompiledGenerationManifest? {
        guard fileManager.fileExists(atPath: manifestURL.path) else { return nil }
        let data = try Data(contentsOf: manifestURL)
        return try JSONDecoder().decode(AdblockCompiledGenerationManifest.self, from: data)
    }

    func archivedManifest(generationId: String) throws -> AdblockCompiledGenerationManifest? {
        let url = generationDirectory(for: generationId)
            .appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AdblockCompiledGenerationManifest.self, from: data)
    }

    func loadHTTPMetadata() throws -> [String: AdblockFilterListHTTPMetadata] {
        guard fileManager.fileExists(atPath: metadataURL.path) else { return [:] }
        let data = try Data(contentsOf: metadataURL)
        return try JSONDecoder().decode([String: AdblockFilterListHTTPMetadata].self, from: data)
    }

    func rawListData(forListIdentifier identifier: String) throws -> Data? {
        let url = rawListURL(forListIdentifier: identifier)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    func rawListFileInfo(forListIdentifier identifier: String) -> AdblockRawListFileInfo {
        let url = rawListURL(forListIdentifier: identifier)
        let exists = fileManager.fileExists(atPath: url.path)
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? NSNumber)?.intValue
        return AdblockRawListFileInfo(
            path: url.path,
            exists: exists,
            byteSize: size
        )
    }

    func compiledShardDefinitions(
        for manifest: AdblockCompiledGenerationManifest
    ) throws -> [SumiContentRuleListDefinition] {
        try manifest.allNativeShards
            .sorted {
                if $0.kind == $1.kind {
                    return $0.id < $1.id
                }
                return $0.kind.rawValue < $1.kind.rawValue
            }
            .map { shard in
                let url = generationDirectory(for: shard.generationId)
                    .appendingPathComponent("\(shard.id).json")
                guard fileManager.fileExists(atPath: url.path) else {
                    throw AdblockUpdateDiagnostics(
                        summary: "Missing compiled Adblock shard JSON: \(shard.id)",
                        failedShardIdentifier: shard.webKitIdentifier
                    )
                }
                let data = try Data(contentsOf: url)
                guard !data.isEmpty else {
                    throw AdblockUpdateDiagnostics(
                        summary: "Empty compiled Adblock shard JSON: \(shard.id)",
                        failedShardIdentifier: shard.webKitIdentifier
                    )
                }
                return SumiContentRuleListDefinition(
                    name: shard.webKitIdentifier,
                    encodedContentRuleList: String(decoding: data, as: UTF8.self),
                    storeIdentifierOverride: shard.webKitIdentifier,
                    contentHashOverride: shard.contentHash
                )
            }
    }

    func validateCompiledShardFiles(
        for manifest: AdblockCompiledGenerationManifest
    ) throws {
        for shard in manifest.allNativeShards {
            let url = generationDirectory(for: shard.generationId)
                .appendingPathComponent("\(shard.id).json")
            guard fileManager.fileExists(atPath: url.path) else {
                throw AdblockUpdateDiagnostics(
                    summary: "Missing compiled Adblock shard JSON: \(shard.id)",
                    failedShardIdentifier: shard.webKitIdentifier
                )
            }
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
            guard size > 0 else {
                throw AdblockUpdateDiagnostics(
                    summary: "Empty compiled Adblock shard JSON: \(shard.id)",
                    failedShardIdentifier: shard.webKitIdentifier
                )
            }
        }
    }

    func beginStaging() throws -> URL {
        let stagingRoot = rootDirectory.appendingPathComponent("Staging", isDirectory: true)
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        let stagingURL = stagingRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        return stagingURL
    }

    func writeRawList(_ data: Data, identifier: String, stagingDirectory: URL) throws -> URL {
        let url = stagingDirectory.appendingPathComponent("\(identifier).txt")
        try data.write(to: url, options: .atomic)
        return url
    }

    func writeCompiledShard(_ shard: NativeContentBlockingCompiledShard, stagingDirectory: URL) throws -> URL {
        let url = stagingDirectory.appendingPathComponent("\(shard.descriptor.id).json")
        try Data(shard.encodedContentRuleList.utf8).write(to: url, options: .atomic)
        return url
    }

    func commit(
        manifest: AdblockCompiledGenerationManifest,
        httpMetadata: [String: AdblockFilterListHTTPMetadata],
        stagedRawListURLs: [String: URL],
        stagedCompiledShardURLs: [String: URL] = [:]
    ) throws {
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let rawDirectory = rootDirectory.appendingPathComponent("RawLists", isDirectory: true)
        try fileManager.createDirectory(at: rawDirectory, withIntermediateDirectories: true)
        let generationDirectory = generationDirectory(for: manifest.activeGenerationId)
        try fileManager.createDirectory(at: generationDirectory, withIntermediateDirectories: true)

        for (identifier, stagedURL) in stagedRawListURLs {
            let destination = rawDirectory.appendingPathComponent("\(identifier).txt")
            try replaceItem(at: destination, withItemAt: stagedURL)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        for (shardId, stagedURL) in stagedCompiledShardURLs {
            let destination = generationDirectory.appendingPathComponent("\(shardId).json")
            try copyReplacingItem(at: destination, withItemAt: stagedURL)
        }
        try atomicWrite(encoder.encode(manifest), to: generationDirectory.appendingPathComponent("manifest.json"))
        try atomicWrite(encoder.encode(httpMetadata), to: metadataURL)
        try atomicWrite(encoder.encode(manifest), to: manifestURL)
    }

    func replaceActiveManifest(_ manifest: AdblockCompiledGenerationManifest) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try atomicWrite(encoder.encode(manifest), to: manifestURL)
    }

    func archivedGenerationIds() throws -> [String] {
        let generatedRoot = rootDirectory.appendingPathComponent("Generated", isDirectory: true)
        guard fileManager.fileExists(atPath: generatedRoot.path) else { return [] }
        let urls = try fileManager.contentsOfDirectory(
            at: generatedRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        return try urls.compactMap { url in
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { return nil }
            return url.lastPathComponent
        }
    }

    func generationDirectoryURL(generationId: String) -> URL {
        generationDirectory(for: generationId)
    }

    func rawListsDirectoryURL() -> URL {
        rootDirectory.appendingPathComponent("RawLists", isDirectory: true)
    }

    func stagingDirectoryURL() -> URL {
        rootDirectory.appendingPathComponent("Staging", isDirectory: true)
    }

    func removeStagingDirectory(_ url: URL) {
        try? fileManager.removeItem(at: url)
    }

    func rawListURL(forListIdentifier identifier: String) -> URL {
        rootDirectory
            .appendingPathComponent("RawLists", isDirectory: true)
            .appendingPathComponent("\(identifier).txt")
    }

    private func generationDirectory(for generationId: String) -> URL {
        rootDirectory
            .appendingPathComponent("Generated", isDirectory: true)
            .appendingPathComponent(generationId, isDirectory: true)
    }

    private func atomicWrite(_ data: Data, to url: URL) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        try data.write(to: tempURL, options: .atomic)
        try replaceItem(at: url, withItemAt: tempURL)
    }

    private func replaceItem(at destination: URL, withItemAt source: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: source)
        } else {
            try fileManager.moveItem(at: source, to: destination)
        }
    }

    private func copyReplacingItem(at destination: URL, withItemAt source: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }

    private static func defaultRootDirectory() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Sumi/Adblock", isDirectory: true)
    }
}

@MainActor
final class AdblockManifestRuleListProvider: SumiContentRuleListSetProviding {
    private var manifest: AdblockCompiledGenerationManifest?
    private var cosmeticMode: SumiAdblockCosmeticMode
    private var compiledDefinitionsByIdentifier: [String: SumiContentRuleListDefinition]
    private let compiledDefinitionLoader: (NativeContentBlockingShardDescriptor) throws -> SumiContentRuleListDefinition
    private let changesSubject = PassthroughSubject<Void, Never>()

    init(
        manifest: AdblockCompiledGenerationManifest?,
        cosmeticMode: SumiAdblockCosmeticMode,
        compiledDefinitions: [SumiContentRuleListDefinition] = [],
        compiledDefinitionLoader: @escaping (NativeContentBlockingShardDescriptor) throws -> SumiContentRuleListDefinition = {
            throw AdblockUpdateDiagnostics(
                summary: "Missing compiled Adblock shard definition: \($0.webKitIdentifier)",
                failedShardIdentifier: $0.webKitIdentifier
            )
        }
    ) {
        self.manifest = manifest
        self.cosmeticMode = cosmeticMode
        self.compiledDefinitionLoader = compiledDefinitionLoader
        compiledDefinitionsByIdentifier = Dictionary(
            uniqueKeysWithValues: compiledDefinitions.map {
                (($0.storeIdentifierOverride ?? $0.name), $0)
            }
        )
    }

    var changesPublisher: AnyPublisher<Void, Never> {
        changesSubject.eraseToAnyPublisher()
    }

    var hasProfileSpecificRuleLists: Bool {
        false
    }

    var activeManifest: AdblockCompiledGenerationManifest? {
        manifest
    }

    func updateManifest(
        _ manifest: AdblockCompiledGenerationManifest?,
        compiledDefinitions: [SumiContentRuleListDefinition] = []
    ) {
        let definitionsByIdentifier = Dictionary(
            uniqueKeysWithValues: compiledDefinitions.map {
                (($0.storeIdentifierOverride ?? $0.name), $0)
            }
        )
        guard self.manifest != manifest || compiledDefinitionsByIdentifier != definitionsByIdentifier else { return }
        self.manifest = manifest
        compiledDefinitionsByIdentifier = definitionsByIdentifier
        changesSubject.send(())
    }

    func updateCosmeticMode(_ cosmeticMode: SumiAdblockCosmeticMode) {
        guard self.cosmeticMode != cosmeticMode else { return }
        self.cosmeticMode = cosmeticMode
        changesSubject.send(())
    }

    func ruleListSet(profileId: UUID?) throws -> SumiTrackingRuleListSet {
        guard let manifest else { return SumiTrackingRuleListSet() }
        let allowedKinds = Self.attachedGroupKinds(for: cosmeticMode)
        let definitions = try manifest.allNativeShards
            .filter { allowedKinds.contains($0.kind) }
            .map { shard in
                if let definition = compiledDefinitionsByIdentifier[shard.webKitIdentifier] {
                    return definition
                }
                return try compiledDefinitionLoader(shard)
            }
        return SumiTrackingRuleListSet(trackerDataSet: definitions)
    }

    static func attachedGroupKinds(
        for cosmeticMode: SumiAdblockCosmeticMode
    ) -> Set<AdblockCompiledRuleGroupKind> {
        switch cosmeticMode {
        case .off:
            return [.network]
        case .nativeCSS, .enhancedRuntime:
            return [.network, .nativeCosmeticCSS]
        }
    }

    static func diskBackedDefinitionLoader(
        storageRoot: URL,
        fileManager: FileManager = .default
    ) -> (NativeContentBlockingShardDescriptor) throws -> SumiContentRuleListDefinition {
        { shard in
            let url = storageRoot
                .appendingPathComponent("Generated", isDirectory: true)
                .appendingPathComponent(shard.generationId, isDirectory: true)
                .appendingPathComponent("\(shard.id).json")
            guard fileManager.fileExists(atPath: url.path) else {
                throw AdblockUpdateDiagnostics(
                    summary: "Missing compiled Adblock shard JSON: \(shard.id)",
                    failedShardIdentifier: shard.webKitIdentifier
                )
            }
            let data = try Data(contentsOf: url)
            guard !data.isEmpty else {
                throw AdblockUpdateDiagnostics(
                    summary: "Empty compiled Adblock shard JSON: \(shard.id)",
                    failedShardIdentifier: shard.webKitIdentifier
                )
            }
            return SumiContentRuleListDefinition(
                name: shard.webKitIdentifier,
                encodedContentRuleList: String(decoding: data, as: UTF8.self),
                storeIdentifierOverride: shard.webKitIdentifier,
                contentHashOverride: shard.contentHash
            )
        }
    }
}

struct PreparedAdblockRuleListPublication {
    let manifest: AdblockCompiledGenerationManifest
    let definitions: [SumiContentRuleListDefinition]
    let preparedContentBlockingUpdate: SumiPreparedContentBlockingUpdate
}

@MainActor
protocol AdblockRuleListPublishing: AnyObject, Sendable {
    func preparePublication(
        manifest: AdblockCompiledGenerationManifest,
        definitions: [SumiContentRuleListDefinition]
    ) async throws -> PreparedAdblockRuleListPublication

    func commitPublication(_ publication: PreparedAdblockRuleListPublication)
}

extension AdblockRuleListPublishing {
    func publish(
        manifest: AdblockCompiledGenerationManifest,
        definitions: [SumiContentRuleListDefinition]
    ) async throws {
        let publication = try await preparePublication(
            manifest: manifest,
            definitions: definitions
        )
        commitPublication(publication)
    }
}

@MainActor
final class AdblockRuleListPublisher: AdblockRuleListPublishing {
    private let ruleListProvider: AdblockManifestRuleListProvider
    private let contentBlockingService: SumiContentBlockingService

    init(
        ruleListProvider: AdblockManifestRuleListProvider,
        contentBlockingService: SumiContentBlockingService
    ) {
        self.ruleListProvider = ruleListProvider
        self.contentBlockingService = contentBlockingService
    }

    func publish(
        manifest: AdblockCompiledGenerationManifest,
        definitions: [SumiContentRuleListDefinition]
    ) async throws {
        let publication = try await preparePublication(
            manifest: manifest,
            definitions: definitions
        )
        commitPublication(publication)
    }

    func preparePublication(
        manifest: AdblockCompiledGenerationManifest,
        definitions: [SumiContentRuleListDefinition]
    ) async throws -> PreparedAdblockRuleListPublication {
        let prepared = try await contentBlockingService.prepareRuleListUpdate(
            ruleLists: definitions,
            retainEncodedRuleListsInPreparedPolicy: false
        )
        return PreparedAdblockRuleListPublication(
            manifest: manifest,
            definitions: definitions.map { $0.metadataOnly() },
            preparedContentBlockingUpdate: prepared
        )
    }

    func commitPublication(_ publication: PreparedAdblockRuleListPublication) {
        ruleListProvider.updateManifest(publication.manifest)
        contentBlockingService.commitPreparedContentBlockingUpdate(
            publication.preparedContentBlockingUpdate
        )
    }
}

actor AdblockGenerationGarbageCollector {
    private let manifestStore: AdblockUpdateManifestStore
    private let contentRuleListStore: any SumiContentRuleListCompiling
    private let fileManager: FileManager

    init(
        manifestStore: AdblockUpdateManifestStore,
        contentRuleListStore: any SumiContentRuleListCompiling,
        fileManager: FileManager = .default
    ) {
        self.manifestStore = manifestStore
        self.contentRuleListStore = contentRuleListStore
        self.fileManager = fileManager
    }

    func cleanupAfterSuccessfulUpdate() async -> AdblockGenerationCleanupReport {
        var report = AdblockGenerationCleanupReport()
        do {
            guard let activeManifest = try await manifestStore.activeManifest() else { return report }
            let previousManifest: AdblockCompiledGenerationManifest?
            if let previousGenerationId = activeManifest.previousGenerationId {
                previousManifest = try await manifestStore.archivedManifest(generationId: previousGenerationId)
            } else {
                previousManifest = nil
            }
            let preservedGenerationIds = Set(
                [activeManifest.activeGenerationId, activeManifest.previousGenerationId].compactMap { $0 }
            )
            let preservedIdentifiers = Self.preservedWebKitIdentifiers(
                activeManifest: activeManifest,
                previousManifest: previousManifest
            )
            let preservedIdentifierPrefixes = Set(
                [activeManifest.activeGenerationId, activeManifest.previousGenerationId]
                    .compactMap { $0 }
                    .flatMap(Self.webKitIdentifierPrefixes(forGenerationId:))
            )

            let identifiers = await contentRuleListStore.availableContentRuleListIdentifiers()
            for identifier in identifiers
                where AdblockUpdateCoordinator.isAdblockGeneratedWebKitIdentifier(identifier)
                    && !preservedIdentifiers.contains(identifier)
                    && !preservedIdentifierPrefixes.contains(where: identifier.hasPrefix) {
                do {
                    try await contentRuleListStore.removeContentRuleList(forIdentifier: identifier)
                    report.removedWebKitIdentifiers.append(identifier)
                } catch {
                    report.diagnostics.append("Failed to remove WebKit rule list \(identifier): \(error.localizedDescription)")
                }
            }

            report.removedFilePaths += await removeObsoleteGeneratedDirectories(
                preserving: preservedGenerationIds,
                diagnostics: &report.diagnostics
            )
            report.removedFilePaths += await removeObsoleteRawLists(
                preservingListIds: Self.preservedRawListIds(
                    activeManifest: activeManifest,
                    previousManifest: previousManifest
                ),
                diagnostics: &report.diagnostics
            )
            report.removedFilePaths += await removeInterruptedStagingDirectories(
                diagnostics: &report.diagnostics
            )
        } catch {
            report.diagnostics.append("Cleanup failed before deletion: \(error.localizedDescription)")
        }
        report.removedWebKitIdentifiers.sort()
        report.removedFilePaths.sort()
        return report
    }

    private func removeObsoleteGeneratedDirectories(
        preserving generationIds: Set<String>,
        diagnostics: inout [String]
    ) async -> [String] {
        do {
            let generationIdsOnDisk = try await manifestStore.archivedGenerationIds()
            var removed = [String]()
            for generationId in generationIdsOnDisk where !generationIds.contains(generationId) {
                let url = await manifestStore.generationDirectoryURL(generationId: generationId)
                if removeItemSafely(at: url, diagnostics: &diagnostics) {
                    removed.append(url.path)
                }
            }
            return removed
        } catch {
            diagnostics.append("Failed to enumerate generated generations: \(error.localizedDescription)")
            return []
        }
    }

    private func removeObsoleteRawLists(
        preservingListIds listIds: Set<String>,
        diagnostics: inout [String]
    ) async -> [String] {
        let rawDirectory = await manifestStore.rawListsDirectoryURL()
        guard fileManager.fileExists(atPath: rawDirectory.path) else { return [] }
        do {
            let urls = try fileManager.contentsOfDirectory(
                at: rawDirectory,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            )
            var removed = [String]()
            for url in urls where url.pathExtension == "txt" {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true || values.isSymbolicLink == true else { continue }
                let id = url.deletingPathExtension().lastPathComponent
                guard !listIds.contains(id) else { continue }
                if removeItemSafely(at: url, diagnostics: &diagnostics) {
                    removed.append(url.path)
                }
            }
            return removed
        } catch {
            diagnostics.append("Failed to enumerate raw lists: \(error.localizedDescription)")
            return []
        }
    }

    private func removeInterruptedStagingDirectories(
        diagnostics: inout [String]
    ) async -> [String] {
        let stagingRoot = await manifestStore.stagingDirectoryURL()
        guard fileManager.fileExists(atPath: stagingRoot.path) else { return [] }
        do {
            let urls = try fileManager.contentsOfDirectory(
                at: stagingRoot,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )
            var removed = [String]()
            for url in urls {
                if removeItemSafely(at: url, diagnostics: &diagnostics) {
                    removed.append(url.path)
                }
            }
            return removed
        } catch {
            diagnostics.append("Failed to enumerate staging directories: \(error.localizedDescription)")
            return []
        }
    }

    private func removeItemSafely(at url: URL, diagnostics: inout [String]) -> Bool {
        guard isInsideAdblockRoot(url) else {
            diagnostics.append("Refused to delete outside Adblock root: \(url.path)")
            return false
        }
        do {
            try fileManager.removeItem(at: url)
            return true
        } catch CocoaError.fileNoSuchFile {
            return true
        } catch {
            diagnostics.append("Failed to remove \(url.path): \(error.localizedDescription)")
            return false
        }
    }

    private func isInsideAdblockRoot(_ url: URL) -> Bool {
        let root = manifestStore.storageRoot.standardizedFileURL.path
        let candidate = url.standardizedFileURL.path
        return candidate == root || candidate.hasPrefix(root + "/")
    }

    private static func preservedWebKitIdentifiers(
        activeManifest: AdblockCompiledGenerationManifest,
        previousManifest: AdblockCompiledGenerationManifest?
    ) -> Set<String> {
        var identifiers = Set(activeManifest.webKitRuleListIdentifiers)
        if let previousManifest {
            identifiers.formUnion(previousManifest.webKitRuleListIdentifiers)
        }
        return identifiers
    }

    private static func webKitIdentifierPrefixes(forGenerationId generationId: String) -> [String] {
        guard let hash = generationId.split(separator: "-").last.map(String.init),
              !hash.isEmpty
        else {
            return [
                "sumi.adblock.network.\(generationId).",
                "sumi.adblock.nativeCSS.\(generationId).",
            ]
        }
        return [
            "sumi.adblock.network.\(generationId).",
            "sumi.adblock.nativeCSS.\(generationId).",
            "sumi.adblock.network.\(hash)",
            "sumi.adblock.nativeCSS.\(hash)",
        ]
    }

    private static func preservedRawListIds(
        activeManifest: AdblockCompiledGenerationManifest,
        previousManifest: AdblockCompiledGenerationManifest?
    ) -> Set<String> {
        var ids = Set(activeManifest.selectedFilterLists.map(\.id))
        if let previousManifest {
            ids.formUnion(previousManifest.selectedFilterLists.map(\.id))
        }
        return ids
    }
}

actor AdblockUpdateCoordinator {
    private let registry: AdblockFilterListRegistry
    private let selection: @Sendable () async -> SumiAdblockFilterListSelection
    private let nativeProfileSelection: @Sendable () async -> AdblockFilterListProfileKind
    private let isAdblockEnabled: @Sendable () async -> Bool
    private let downloader: any AdblockFilterListDownloading
    private let manifestStore: AdblockUpdateManifestStore
    private let nativeCompiler: any NativeContentBlockingCompiler
    private let enhancedCompiler: (any EnhancedCompatibilityCompiler)?
    private let publisher: any AdblockRuleListPublishing
    private let contentRuleListStore: (any SumiContentRuleListCompiling)?
    private let garbageCollector: AdblockGenerationGarbageCollector?
    private let now: @Sendable () -> Date
    private(set) var latestCleanupReport: AdblockGenerationCleanupReport?
    private(set) var latestDiagnostics: AdblockUpdateDiagnostics?

    init(
        registry: AdblockFilterListRegistry,
        selection: @escaping @Sendable () async -> SumiAdblockFilterListSelection,
        nativeProfileSelection: @escaping @Sendable () async -> AdblockFilterListProfileKind = {
            .currentDefault
        },
        isAdblockEnabled: @escaping @Sendable () async -> Bool,
        downloader: any AdblockFilterListDownloading,
        manifestStore: AdblockUpdateManifestStore,
        nativeCompiler: any NativeContentBlockingCompiler,
        enhancedCompiler: (any EnhancedCompatibilityCompiler)? = nil,
        publisher: any AdblockRuleListPublishing,
        contentRuleListStore: (any SumiContentRuleListCompiling)? = nil,
        garbageCollector: AdblockGenerationGarbageCollector? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.registry = registry
        self.selection = selection
        self.nativeProfileSelection = nativeProfileSelection
        self.isAdblockEnabled = isAdblockEnabled
        self.downloader = downloader
        self.manifestStore = manifestStore
        self.nativeCompiler = nativeCompiler
        self.enhancedCompiler = enhancedCompiler
        self.publisher = publisher
        self.contentRuleListStore = contentRuleListStore
        self.garbageCollector = garbageCollector
        self.now = now
    }

    static func production(
        registry: AdblockFilterListRegistry,
        selection: @escaping @Sendable () async -> SumiAdblockFilterListSelection,
        nativeProfileSelection: @escaping @Sendable () async -> AdblockFilterListProfileKind,
        isAdblockEnabled: @escaping @Sendable () async -> Bool,
        manifestStore: AdblockUpdateManifestStore,
        nativeCompiler: any NativeContentBlockingCompiler,
        enhancedCompiler: (any EnhancedCompatibilityCompiler)?,
        publisher: any AdblockRuleListPublishing,
        contentRuleListStore: (any SumiContentRuleListCompiling)?,
        garbageCollector: AdblockGenerationGarbageCollector?
    ) -> AdblockUpdateCoordinator {
        AdblockUpdateCoordinator(
            registry: registry,
            selection: selection,
            nativeProfileSelection: nativeProfileSelection,
            isAdblockEnabled: isAdblockEnabled,
            downloader: AdblockFilterListDownloader(),
            manifestStore: manifestStore,
            nativeCompiler: nativeCompiler,
            enhancedCompiler: enhancedCompiler,
            publisher: publisher,
            contentRuleListStore: contentRuleListStore,
            garbageCollector: garbageCollector
        )
    }

    func latestDiagnosticsSnapshot() -> AdblockUpdateDiagnostics? {
        latestDiagnostics
    }

    func prepareEmbeddedBundlePublication(
        manifest: AdblockCompiledGenerationManifest,
        definitions: [SumiContentRuleListDefinition]
    ) async throws -> PreparedAdblockRuleListPublication {
        try await publisher.preparePublication(
            manifest: manifest,
            definitions: definitions
        )
    }

    func commitEmbeddedBundlePublication(
        _ publication: PreparedAdblockRuleListPublication
    ) async {
        await publisher.commitPublication(publication)
        latestDiagnostics = AdblockUpdateDiagnostics(
            summary: "Embedded Adblock bundle installed",
            generationSource: .embeddedBundle
        )
    }

    func updateIfEnabled(reason: String) async throws -> AdblockCompiledGenerationManifest? {
        guard await isAdblockEnabled() else { return nil }
#if DEBUG
        let memoryRecorder = AdblockRebuildMemoryRecorder(now: now)
        await memoryRecorder.record(.beforeRebuild)
#endif

        let selection = await selection()
        let nativeProfile = await nativeProfileSelection()
        let selectionDiagnostics = registry.effectiveSelectionDiagnostics(
            selection: selection,
            profileKind: nativeProfile
        )
        if !selectionDiagnostics.unknownIdentifiers.isEmpty {
            let statuses = selectionDiagnostics.unknownIdentifiers.map {
                AdblockFilterListUpdateStatus(
                    listIdentifier: $0,
                    displayName: "Missing descriptor",
                    category: nil,
                    selectionOrigins: selection.usesDefaultSelection ? [.other] : [.manualListToggle],
                    finalURL: nil,
                    lastCheckedDate: now(),
                    lastSuccessfulDownloadDate: nil,
                    httpStatus: nil,
                    eTagUsed: nil,
                    eTagSaved: nil,
                    lastModifiedUsed: nil,
                    lastModifiedSaved: nil,
                    notModifiedReused: false,
                    rawFilePath: nil,
                    rawFileExists: false,
                    rawByteSize: nil,
                    contentHash: nil,
                    failureStage: .missingSelectedListDescriptor,
                    failureReason: "Missing selected list descriptor: \($0)"
                )
            }
            let diagnostics = AdblockUpdateDiagnostics(
                summary: "missing selected list descriptor: \(selectionDiagnostics.unknownIdentifiers.joined(separator: ","))",
                stage: .missingSelectedListDescriptor,
                listFailures: Dictionary(uniqueKeysWithValues: statuses.map { ($0.listIdentifier, $0.failureReason ?? "") }),
                listStatuses: statuses,
                selectionDiagnostics: selectionDiagnostics
            )
            latestDiagnostics = diagnostics
            throw diagnostics
        }

        let descriptors = registry.selectedDescriptors(
            selection: selection,
            profileKind: nativeProfile
        )
        guard !descriptors.isEmpty else {
            let diagnostics = AdblockUpdateDiagnostics(
                summary: "effective list selection failed: no selected Adblock filter lists",
                stage: .effectiveListSelectionFailed,
                selectionDiagnostics: selectionDiagnostics
            )
            latestDiagnostics = diagnostics
            throw diagnostics
        }

        let previousManifest = try await manifestStore.activeManifest()
        let previousMetadata = try await manifestStore.loadHTTPMetadata()
        let stagingDirectory = try await manifestStore.beginStaging()
        defer {
            Task { await manifestStore.removeStagingDirectory(stagingDirectory) }
        }

        var updatedMetadata = previousMetadata
        var stagedRawURLs = [String: URL]()
        var filterTexts = [String]()
        var selectedLists = [AdblockCompiledGenerationManifest.SelectedFilterList]()
        var failures = [String: String]()
        var statusesByIdentifier = [String: AdblockFilterListUpdateStatus]()

        for descriptor in descriptors {
            let rawInfo = await manifestStore.rawListFileInfo(forListIdentifier: descriptor.id)
            let metadata = previousMetadata[descriptor.id]
            statusesByIdentifier[descriptor.id] = AdblockFilterListUpdateStatus(
                listIdentifier: descriptor.id,
                displayName: descriptor.displayName,
                category: descriptor.category,
                selectionOrigins: selectionDiagnostics.origins(forListIdentifier: descriptor.id),
                finalURL: descriptor.remoteURL.absoluteString,
                lastCheckedDate: metadata?.lastCheckedDate,
                lastSuccessfulDownloadDate: metadata?.lastSuccessfulDownloadDate,
                httpStatus: metadata?.lastHTTPStatus,
                eTagUsed: metadata?.eTag,
                eTagSaved: metadata?.eTag,
                lastModifiedUsed: metadata?.lastModified,
                lastModifiedSaved: metadata?.lastModified,
                notModifiedReused: false,
                rawFilePath: rawInfo.path,
                rawFileExists: rawInfo.exists,
                rawByteSize: rawInfo.byteSize,
                contentHash: metadata?.contentHash,
                failureStage: metadata?.failureStage,
                failureReason: metadata?.failureSummary
            )
        }
        latestDiagnostics = AdblockUpdateDiagnostics(
            summary: "Adblock update started: \(reason)",
            listStatuses: Self.sortedStatuses(statusesByIdentifier),
            selectionDiagnostics: selectionDiagnostics
        )

        for descriptor in descriptors {
            var status = statusesByIdentifier[descriptor.id]!
            do {
                let prepared = try await prepareFilterList(
                    descriptor: descriptor,
                    previousMetadata: previousMetadata[descriptor.id],
                    stagingDirectory: stagingDirectory,
                    baseStatus: status
                )
                status = prepared.status
                statusesByIdentifier[descriptor.id] = status
                updatedMetadata[descriptor.id] = prepared.metadata
                if let stagedRawURL = prepared.stagedRawURL {
                    stagedRawURLs[descriptor.id] = stagedRawURL
                }
                filterTexts.append(prepared.filterText)
                selectedLists.append(
                    AdblockCompiledGenerationManifest.SelectedFilterList(
                        id: descriptor.id,
                        displayName: descriptor.displayName,
                        contentHash: prepared.contentHash,
                        category: descriptor.category,
                        inputByteCount: prepared.byteCount,
                        approximateRuleCount: Self.approximateRuleCount(in: prepared.data)
                    )
                )
                latestDiagnostics = AdblockUpdateDiagnostics(
                    summary: "Adblock update in progress: \(descriptor.id) prepared",
                    listStatuses: Self.sortedStatuses(statusesByIdentifier),
                    selectionDiagnostics: selectionDiagnostics
                )
            } catch let error as AdblockFilterListPreparationError {
                status = error.status
                statusesByIdentifier[descriptor.id] = status
                updatedMetadata[descriptor.id] = error.metadata
                failures[descriptor.id] = status.failureReason ?? error.diagnostics.summary
            } catch {
                var metadata = previousMetadata[descriptor.id] ?? AdblockFilterListHTTPMetadata()
                let stage = (error as? AdblockUpdateDiagnostics)?.stage ?? .networkRequestFailed
                metadata.lastCheckedDate = now()
                metadata.failureStage = stage
                metadata.failureSummary = error.localizedDescription
                status.lastCheckedDate = metadata.lastCheckedDate
                status.failureStage = stage
                status.failureReason = error.localizedDescription
                statusesByIdentifier[descriptor.id] = status
                failures[descriptor.id] = error.localizedDescription
                updatedMetadata[descriptor.id] = metadata
            }
        }

        if !failures.isEmpty {
            let currentStatuses = await currentRawFileStatuses(statusesByIdentifier)
            let failedStatuses = currentStatuses.filter(\.isFailure)
            let firstStage = failedStatuses.first?.failureStage ?? .effectiveListSelectionFailed
            let summary: String
            if failedStatuses.count == 1, let failed = failedStatuses.first {
                summary = "\(firstStage.rawValue): \(failed.listIdentifier): \(failed.failureReason ?? "failed")"
            } else {
                summary = "Adblock update failed before compilation: \(firstStage.rawValue)"
            }
            let diagnostics = AdblockUpdateDiagnostics(
                summary: summary,
                stage: firstStage,
                listFailures: failures,
                listStatuses: currentStatuses,
                selectionDiagnostics: selectionDiagnostics
            )
            latestDiagnostics = diagnostics
            throw diagnostics
        }

#if DEBUG
        await memoryRecorder.record(.afterDownloadRawValidation)
#endif
        guard await isAdblockEnabled() else { return nil }

        let seed = [
            "profile:\(nativeProfile.rawValue)",
            "compiler:\(nativeCompiler.identity.name):\(nativeCompiler.identity.version)",
            selectedLists.map { "\($0.id):\($0.contentHash)" }.joined(separator: "|"),
        ].joined(separator: "|")
        let generationHash = Self.shortHash(seed)
        let generation = AdblockRuleListGeneration(
            id: "\(Self.timestampString(now()))-\(generationHash)",
            createdDate: now()
        )
        let sourceIdentifier = "sumi.adblock.\(generationHash)"

        let sourceLists = selectedLists.map {
            NativeContentBlockingSourceList(
                id: $0.id,
                displayName: $0.displayName,
                contentHash: $0.contentHash,
                category: $0.category,
                inputByteCount: $0.inputByteCount,
                approximateRuleCount: $0.approximateRuleCount
            )
        }
        let nativeInputByteCount = filterTexts.reduce(0) { $0 + $1.utf8.count }
        var manifest: AdblockCompiledGenerationManifest!
        var definitions = [SumiContentRuleListDefinition]()
        var stagedCompiledShardURLs = [String: URL]()
        do {
            let compilationOutput: NativeAndEnhancedCompatibilityCompilationOutput = try await {
                let nativeInput = AdblockCompilationInput(
                    sourceIdentifier: sourceIdentifier,
                    generationId: generation.id,
                    nativeProfile: nativeProfile,
                    filterTexts: filterTexts,
                    selectedOutputGroups: [.network, .nativeCosmeticCSS],
                    sourceLists: sourceLists
                )
#if DEBUG
                return try await AdblockRebuildMemoryLifecycle.$recorder.withValue(memoryRecorder) {
                    try await compileNativeAndEnhancedOutputs(nativeInput)
                }
#else
                return try await compileNativeAndEnhancedOutputs(nativeInput)
#endif
            }()
            filterTexts.removeAll(keepingCapacity: false)

            guard await isAdblockEnabled() else { return nil }

            let nativeOutput = compilationOutput.nativeOutput
            let enhancedOutput = compilationOutput.enhancedOutput
            var compiledDefinitions = [SumiContentRuleListDefinition]()
            var compiledShardURLs = [String: URL]()
            for shard in nativeOutput.shards.sorted(by: {
                if $0.kind == $1.kind {
                    return $0.descriptor.id < $1.descriptor.id
                }
                return $0.kind.rawValue < $1.kind.rawValue
            }) {
                compiledShardURLs[shard.descriptor.id] = try await manifestStore.writeCompiledShard(
                    shard,
                    stagingDirectory: stagingDirectory
                )
                compiledDefinitions.append(shard.definition)
            }

            manifest = AdblockCompiledGenerationManifest(
                schemaVersion: 5,
                activeGenerationId: generation.id,
                createdDate: generation.createdDate,
                selectedFilterLists: selectedLists.sorted { $0.id < $1.id },
                networkShards: nativeOutput.networkShards.map(\.descriptor),
                nativeCSSShards: nativeOutput.nativeCosmeticCSSShards.map(\.descriptor),
                enhancedRuntimeBundle: enhancedOutput?.enhancedRuntimeBundle.isAvailable == true
                    ? enhancedOutput?.enhancedRuntimeBundle
                    : nil,
                nativeProfile: nativeProfile,
                nativeCompiler: nativeOutput.compilerIdentity,
                nativeCompilerSourceLists: nativeOutput.sourceLists,
                nativeCompilationSummary: NativeContentBlockingCompilationSummary(
                    inputRuleCount: nativeOutput.inputRuleCount,
                    inputByteCount: nativeInputByteCount,
                    convertedNetworkRuleCount: nativeOutput.convertedNetworkRuleCount,
                    convertedNativeCosmeticRuleCount: nativeOutput.convertedNativeCosmeticRuleCount,
                    unsupportedOrIgnoredRuleCount: nativeOutput.unsupportedOrIgnoredRuleCount,
                    networkJSONByteCount: nativeOutput.networkJSONByteCount,
                    nativeCosmeticJSONByteCount: nativeOutput.nativeCosmeticJSONByteCount,
                    totalJSONByteCount: nativeOutput.totalJSONByteCount,
                    ruleCap: nativeOutput.diagnostics.ruleCap
                ),
                compilerDiagnosticsSummary: Self.diagnosticsSummary(
                    nativeDiagnostics: nativeOutput.diagnostics,
                    nativeOutput: nativeOutput,
                    enhancedOutput: enhancedOutput
                ),
                lastSuccessfulUpdateDate: now(),
                previousGenerationId: previousManifest?.activeGenerationId
            )
            definitions = compiledDefinitions
            stagedCompiledShardURLs = compiledShardURLs
        } catch {
            let currentStatuses = await currentRawFileStatuses(statusesByIdentifier)
            let diagnostics = AdblockUpdateDiagnostics(
                summary: "Adblock native compilation failed: \(error.localizedDescription)",
                stage: .nativeCompilationFailed,
                listStatuses: currentStatuses,
                selectionDiagnostics: selectionDiagnostics
            )
            latestDiagnostics = diagnostics
            throw diagnostics
        }

        let preparedPublication: PreparedAdblockRuleListPublication
        do {
            preparedPublication = try await publisher.preparePublication(
                manifest: manifest,
                definitions: definitions
            )
        } catch let error as SumiContentBlockingCompilationError {
            let currentStatuses = await currentRawFileStatuses(statusesByIdentifier)
            let diagnostics = AdblockUpdateDiagnostics(
                summary: "Adblock shard publish failed: \(error.localizedDescription)",
                stage: .shardPublishFailed,
                listStatuses: currentStatuses,
                selectionDiagnostics: selectionDiagnostics,
                failedShardIdentifier: error.identifier
            )
            latestDiagnostics = diagnostics
            throw diagnostics
        }
#if DEBUG
        await memoryRecorder.record(.afterWKContentRuleListStoreCompile)
#endif
        definitions.removeAll(keepingCapacity: false)
        do {
            try await manifestStore.commit(
                manifest: manifest,
                httpMetadata: updatedMetadata,
                stagedRawListURLs: stagedRawURLs,
                stagedCompiledShardURLs: stagedCompiledShardURLs
            )
        } catch {
            let currentStatuses = await currentRawFileStatuses(statusesByIdentifier)
            let diagnostics = AdblockUpdateDiagnostics(
                summary: "Adblock manifest commit failed: \(error.localizedDescription)",
                stage: .manifestCommitFailed,
                listStatuses: currentStatuses,
                selectionDiagnostics: selectionDiagnostics
            )
            latestDiagnostics = diagnostics
            throw diagnostics
        }
        await publisher.commitPublication(preparedPublication)
#if DEBUG
        await memoryRecorder.record(.afterManifestCommitProviderSwitch)
#endif
        if let garbageCollector {
            latestCleanupReport = await garbageCollector.cleanupAfterSuccessfulUpdate()
        }
        let committedStatuses = await currentRawFileStatuses(statusesByIdentifier)
#if DEBUG
        await memoryRecorder.record(.afterCleanup)
        stagedRawURLs.removeAll(keepingCapacity: false)
        updatedMetadata.removeAll(keepingCapacity: false)
        selectedLists.removeAll(keepingCapacity: false)
        statusesByIdentifier.removeAll(keepingCapacity: false)
        await memoryRecorder.record(.afterClearingTemporaryObjects)
        let memoryDiagnostics = await memoryRecorder.diagnostics(
            manifest: manifest,
            selectionDiagnostics: selectionDiagnostics,
            attachedShardCount: manifest.allNativeShards.count
        )
        let finalMemoryDiagnostics: AdblockRebuildMemoryDiagnostics? = memoryDiagnostics
#else
        let finalMemoryDiagnostics: AdblockRebuildMemoryDiagnostics? = nil
#endif
        latestDiagnostics = AdblockUpdateDiagnostics(
            summary: "Adblock update completed",
            listStatuses: committedStatuses,
            selectionDiagnostics: selectionDiagnostics,
            memoryDiagnostics: finalMemoryDiagnostics,
            generationSource: .runtimeGenerated
        )
        return manifest
    }

    private struct PreparedFilterList: Sendable {
        let data: Data
        let filterText: String
        let contentHash: String
        let byteCount: Int
        let metadata: AdblockFilterListHTTPMetadata
        let status: AdblockFilterListUpdateStatus
        let stagedRawURL: URL?
    }

    private struct AdblockFilterListPreparationError: Error, Sendable {
        let diagnostics: AdblockUpdateDiagnostics
        let metadata: AdblockFilterListHTTPMetadata
        let status: AdblockFilterListUpdateStatus
    }

    private func compileNativeAndEnhancedOutputs(
        _ input: AdblockCompilationInput
    ) async throws -> NativeAndEnhancedCompatibilityCompilationOutput {
        if let enhancedCompiler,
           let combinedCompiler = nativeCompiler as? any NativeAndEnhancedCompatibilityCompiler,
           Self.isSameCompilerObject(combinedCompiler, enhancedCompiler) {
            return try await combinedCompiler.compileNativeAndEnhancedCompatibility(input)
        }

        let nativeOutput = try await nativeCompiler.compileNativeContentBlocking(input)
        let enhancedOutput = try await enhancedCompiler?.compileEnhancedCompatibility(input)
        return NativeAndEnhancedCompatibilityCompilationOutput(
            nativeOutput: nativeOutput,
            enhancedOutput: enhancedOutput
        )
    }

    private static func isSameCompilerObject(
        _ lhs: any NativeAndEnhancedCompatibilityCompiler,
        _ rhs: any EnhancedCompatibilityCompiler
    ) -> Bool {
        ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
    }

    private func prepareFilterList(
        descriptor: AdblockFilterListDescriptor,
        previousMetadata: AdblockFilterListHTTPMetadata?,
        stagingDirectory: URL,
        baseStatus: AdblockFilterListUpdateStatus
    ) async throws -> PreparedFilterList {
        var status = baseStatus
        var metadata = previousMetadata ?? AdblockFilterListHTTPMetadata()
        let checkDate = now()
        metadata.lastCheckedDate = checkDate
        status.lastCheckedDate = checkDate
        status.eTagUsed = previousMetadata?.eTag
        status.lastModifiedUsed = previousMetadata?.lastModified
        status.failureStage = nil
        status.failureReason = nil

        guard Self.isSupportedRemoteListURL(descriptor.remoteURL) else {
            throw preparationError(
                summary: "Invalid list URL: \(descriptor.remoteURL.absoluteString)",
                stage: .invalidListURL,
                metadata: metadata,
                status: status
            )
        }

        let result: AdblockDownloadOutcome
        do {
            result = try await downloader.download(
                descriptor: descriptor,
                previousMetadata: previousMetadata
            )
        } catch let diagnostics as AdblockUpdateDiagnostics {
            throw preparationError(
                diagnostics: diagnostics,
                metadata: metadata,
                status: status
            )
        } catch {
            throw preparationError(
                summary: "Network request failed: \(error.localizedDescription)",
                stage: .networkRequestFailed,
                metadata: metadata,
                status: status
            )
        }

        switch result {
        case .downloaded(let data, let response):
            return try await prepareDownloadedData(
                data,
                response: response,
                descriptor: descriptor,
                metadata: metadata,
                status: status,
                stagingDirectory: stagingDirectory
            )
        case .notModified(let response):
            status.httpStatus = response.statusCode
            status.finalURL = response.url?.absoluteString ?? descriptor.remoteURL.absoluteString
            status.eTagSaved = response.value(forHTTPHeaderField: "ETag") ?? previousMetadata?.eTag
            status.lastModifiedSaved = response.value(forHTTPHeaderField: "Last-Modified") ?? previousMetadata?.lastModified
            metadata.lastHTTPStatus = response.statusCode

            let cachedData: Data?
            do {
                cachedData = try await manifestStore.rawListData(forListIdentifier: descriptor.id)
            } catch {
                throw preparationError(
                    summary: "raw cache read failed: \(error.localizedDescription)",
                    stage: .rawCacheReadFailed,
                    metadata: metadata,
                    status: status
                )
            }

            if let cachedData {
                do {
                    try Self.validateRawListData(cachedData, descriptor: descriptor)
                    let filterText = try Self.compilerInputText(for: cachedData, descriptor: descriptor)
                    let hash = cachedData.sumiAdblockSHA256Digest
                    let rawInfo = await manifestStore.rawListFileInfo(forListIdentifier: descriptor.id)
                    metadata.contentHash = hash
                    metadata.failureSummary = nil
                    metadata.failureStage = nil
                    status.notModifiedReused = true
                    status.rawFilePath = rawInfo.path
                    status.rawFileExists = rawInfo.exists
                    status.rawByteSize = cachedData.count
                    status.contentHash = hash
                    status.lastSuccessfulDownloadDate = metadata.lastSuccessfulDownloadDate
                    status.failureStage = nil
                    status.failureReason = nil
                    return PreparedFilterList(
                        data: cachedData,
                        filterText: filterText,
                        contentHash: hash,
                        byteCount: cachedData.count,
                        metadata: metadata,
                        status: status,
                        stagedRawURL: nil
                    )
                } catch let diagnostics as AdblockUpdateDiagnostics
                    where diagnostics.stage == .rawFileEmpty || diagnostics.stage == .rawFileTooSmall || diagnostics.stage == .rawFileAppearsHTML {
                    return try await retryUnconditionalDownload(
                        descriptor: descriptor,
                        stagingDirectory: stagingDirectory,
                        metadata: metadata,
                        status: status,
                        cacheMissStage: diagnostics.stage ?? .rawFileEmpty,
                        cacheMissSummary: diagnostics.summary
                    )
                } catch let diagnostics as AdblockUpdateDiagnostics {
                    throw preparationError(
                        diagnostics: diagnostics,
                        metadata: metadata,
                        status: status
                    )
                }
            }

            return try await retryUnconditionalDownload(
                descriptor: descriptor,
                stagingDirectory: stagingDirectory,
                metadata: metadata,
                status: status,
                cacheMissStage: .notModifiedWithoutRawCache,
                cacheMissSummary: "304 returned but no previous raw list exists"
            )
        }
    }

    private func retryUnconditionalDownload(
        descriptor: AdblockFilterListDescriptor,
        stagingDirectory: URL,
        metadata: AdblockFilterListHTTPMetadata,
        status: AdblockFilterListUpdateStatus,
        cacheMissStage: AdblockUpdateFailureStage,
        cacheMissSummary: String
    ) async throws -> PreparedFilterList {
        var retryStatus = status
        retryStatus.notModifiedReused = false
        retryStatus.failureStage = nil
        retryStatus.failureReason = nil

        let retryResult: AdblockDownloadOutcome
        do {
            retryResult = try await downloader.download(
                descriptor: descriptor,
                previousMetadata: nil
            )
        } catch let diagnostics as AdblockUpdateDiagnostics {
            throw preparationError(
                diagnostics: diagnostics,
                metadata: metadata,
                status: retryStatus
            )
        } catch {
            throw preparationError(
                summary: "Network request failed after \(cacheMissStage.rawValue): \(error.localizedDescription)",
                stage: .networkRequestFailed,
                metadata: metadata,
                status: retryStatus
            )
        }

        switch retryResult {
        case .downloaded(let data, let response):
            return try await prepareDownloadedData(
                data,
                response: response,
                descriptor: descriptor,
                metadata: metadata,
                status: retryStatus,
                stagingDirectory: stagingDirectory
            )
        case .notModified:
            throw preparationError(
                summary: cacheMissSummary,
                stage: cacheMissStage,
                metadata: metadata,
                status: retryStatus
            )
        }
    }

    private func prepareDownloadedData(
        _ data: Data,
        response: HTTPURLResponse,
        descriptor: AdblockFilterListDescriptor,
        metadata: AdblockFilterListHTTPMetadata,
        status: AdblockFilterListUpdateStatus,
        stagingDirectory: URL
    ) async throws -> PreparedFilterList {
        var updatedMetadata = metadata
        var updatedStatus = status
        updatedStatus.httpStatus = response.statusCode
        updatedStatus.finalURL = response.url?.absoluteString ?? descriptor.remoteURL.absoluteString
        updatedStatus.eTagSaved = response.value(forHTTPHeaderField: "ETag")
        updatedStatus.lastModifiedSaved = response.value(forHTTPHeaderField: "Last-Modified")
        updatedStatus.notModifiedReused = false
        updatedMetadata.lastHTTPStatus = response.statusCode

        do {
            try Self.validateRawListData(data, descriptor: descriptor)
        } catch let diagnostics as AdblockUpdateDiagnostics {
            throw preparationError(
                diagnostics: diagnostics,
                metadata: updatedMetadata,
                status: updatedStatus
            )
        }

        let filterText: String
        do {
            filterText = try Self.compilerInputText(for: data, descriptor: descriptor)
        } catch let diagnostics as AdblockUpdateDiagnostics {
            throw preparationError(
                diagnostics: diagnostics,
                metadata: updatedMetadata,
                status: updatedStatus
            )
        }

        let stagedURL: URL
        do {
            stagedURL = try await manifestStore.writeRawList(
                data,
                identifier: descriptor.id,
                stagingDirectory: stagingDirectory
            )
        } catch {
            throw preparationError(
                summary: "raw staging write failed: \(error.localizedDescription)",
                stage: .rawStagingWriteFailed,
                metadata: updatedMetadata,
                status: updatedStatus
            )
        }

        let hash = data.sumiAdblockSHA256Digest
        updatedMetadata.eTag = response.value(forHTTPHeaderField: "ETag")
        updatedMetadata.lastModified = response.value(forHTTPHeaderField: "Last-Modified")
        updatedMetadata.lastSuccessfulDownloadDate = now()
        updatedMetadata.contentHash = hash
        updatedMetadata.failureSummary = nil
        updatedMetadata.failureStage = nil

        updatedStatus.lastSuccessfulDownloadDate = updatedMetadata.lastSuccessfulDownloadDate
        updatedStatus.rawFilePath = stagedURL.path
        updatedStatus.rawFileExists = true
        updatedStatus.rawByteSize = data.count
        updatedStatus.contentHash = hash
        updatedStatus.failureStage = nil
        updatedStatus.failureReason = nil

        return PreparedFilterList(
            data: data,
            filterText: filterText,
            contentHash: hash,
            byteCount: data.count,
            metadata: updatedMetadata,
            status: updatedStatus,
            stagedRawURL: stagedURL
        )
    }

    private func preparationError(
        summary: String,
        stage: AdblockUpdateFailureStage,
        metadata: AdblockFilterListHTTPMetadata,
        status: AdblockFilterListUpdateStatus
    ) -> AdblockFilterListPreparationError {
        preparationError(
            diagnostics: AdblockUpdateDiagnostics(summary: summary, stage: stage),
            metadata: metadata,
            status: status
        )
    }

    private func preparationError(
        diagnostics: AdblockUpdateDiagnostics,
        metadata: AdblockFilterListHTTPMetadata,
        status: AdblockFilterListUpdateStatus
    ) -> AdblockFilterListPreparationError {
        var failedMetadata = metadata
        var failedStatus = status
        let stage = diagnostics.stage ?? .networkRequestFailed
        failedMetadata.failureStage = stage
        failedMetadata.failureSummary = diagnostics.summary
        failedMetadata.lastHTTPStatus = diagnostics.httpStatusCode ?? failedMetadata.lastHTTPStatus
        failedStatus.failureStage = stage
        failedStatus.failureReason = diagnostics.summary
        failedStatus.httpStatus = diagnostics.httpStatusCode ?? failedStatus.httpStatus
        failedStatus.finalURL = diagnostics.responseURLString ?? failedStatus.finalURL
        failedStatus.eTagSaved = diagnostics.responseETag ?? failedStatus.eTagSaved
        failedStatus.lastModifiedSaved = diagnostics.responseLastModified ?? failedStatus.lastModifiedSaved
        return AdblockFilterListPreparationError(
            diagnostics: diagnostics,
            metadata: failedMetadata,
            status: failedStatus
        )
    }

    private static func sortedStatuses(
        _ statusesByIdentifier: [String: AdblockFilterListUpdateStatus]
    ) -> [AdblockFilterListUpdateStatus] {
        statusesByIdentifier.values.sorted { $0.listIdentifier < $1.listIdentifier }
    }

    private func currentRawFileStatuses(
        _ statusesByIdentifier: [String: AdblockFilterListUpdateStatus]
    ) async -> [AdblockFilterListUpdateStatus] {
        var statuses = [AdblockFilterListUpdateStatus]()
        statuses.reserveCapacity(statusesByIdentifier.count)
        for status in statusesByIdentifier.values {
            var refreshedStatus = status
            let rawInfo = await manifestStore.rawListFileInfo(forListIdentifier: status.listIdentifier)
            refreshedStatus.rawFilePath = rawInfo.path
            refreshedStatus.rawFileExists = rawInfo.exists
            refreshedStatus.rawByteSize = rawInfo.byteSize
            statuses.append(refreshedStatus)
        }
        return statuses.sorted { $0.listIdentifier < $1.listIdentifier }
    }

    private static func isSupportedRemoteListURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host?.isEmpty == false
        else { return false }
        return true
    }

    private static func compilerInputText(
        for data: Data,
        descriptor: AdblockFilterListDescriptor
    ) throws -> String {
        guard let text = String(data: data, encoding: .utf8) else {
            throw AdblockUpdateDiagnostics(
                summary: "compiler input assembly failed: \(descriptor.id) is not valid UTF-8",
                stage: .compilerInputAssemblyFailed
            )
        }
        return text
    }

    private static func validateRawListData(
        _ data: Data,
        descriptor: AdblockFilterListDescriptor
    ) throws {
        guard !data.isEmpty else {
            throw AdblockUpdateDiagnostics(
                summary: "raw file empty: \(descriptor.id)",
                stage: .rawFileEmpty
            )
        }

        let preview = String(decoding: data.prefix(4096), as: UTF8.self)
        let trimmedPreview = preview.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercasedPreview = trimmedPreview.lowercased()
        if lowercasedPreview.hasPrefix("<!doctype html")
            || lowercasedPreview.hasPrefix("<html")
            || (lowercasedPreview.contains("<body") && lowercasedPreview.contains("</html"))
            || (lowercasedPreview.contains("<title") && lowercasedPreview.contains("</title")) {
            throw AdblockUpdateDiagnostics(
                summary: "raw file appears to be HTML/error page: \(descriptor.id)",
                stage: .rawFileAppearsHTML
            )
        }

        guard data.count >= 4 else {
            throw AdblockUpdateDiagnostics(
                summary: "raw file too small / suspicious: \(descriptor.id) has \(data.count) bytes",
                stage: .rawFileTooSmall
            )
        }

        if data.count < 16 && !looksLikeFilterList(preview) {
            throw AdblockUpdateDiagnostics(
                summary: "raw file too small / suspicious: \(descriptor.id) does not look like a filter list",
                stage: .rawFileTooSmall
            )
        }
    }

    private static func looksLikeFilterList(_ text: String) -> Bool {
        text.components(separatedBy: .newlines)
            .prefix(64)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains { line in
                guard !line.isEmpty else { return false }
                return line.hasPrefix("!")
                    || line.hasPrefix("[Adblock")
                    || line.hasPrefix("||")
                    || line.hasPrefix("@@")
                    || line.hasPrefix("##")
                    || line.contains("##")
                    || line.contains("#@#")
                    || line.contains("$")
                    || line.hasPrefix("0.0.0.0 ")
                    || line.hasPrefix("127.0.0.1 ")
            }
    }

    func rollbackIfActiveGenerationFailsSmokeCheck() async -> AdblockGenerationRollbackReport {
        do {
            guard let activeManifest = try await manifestStore.activeManifest() else {
                return AdblockGenerationRollbackReport(
                    rolledBack: false,
                    activeGenerationId: nil,
                    restoredGenerationId: nil,
                    diagnostics: ["No active Adblock manifest"]
                )
            }
            let activeMissingIdentifiers = await missingIdentifiers(in: activeManifest)
            guard !activeMissingIdentifiers.isEmpty else {
                return AdblockGenerationRollbackReport(
                    rolledBack: false,
                    activeGenerationId: activeManifest.activeGenerationId,
                    restoredGenerationId: nil,
                    diagnostics: []
                )
            }
            guard let previousGenerationId = activeManifest.previousGenerationId,
                  let previousManifest = try await manifestStore.archivedManifest(generationId: previousGenerationId)
            else {
                return AdblockGenerationRollbackReport(
                    rolledBack: false,
                    activeGenerationId: activeManifest.activeGenerationId,
                    restoredGenerationId: nil,
                    diagnostics: ["Active generation smoke lookup failed; no previous generation is available"]
                )
            }
            let previousMissing = await missingIdentifiers(in: previousManifest)
            guard previousMissing.isEmpty else {
                return AdblockGenerationRollbackReport(
                    rolledBack: false,
                    activeGenerationId: activeManifest.activeGenerationId,
                    restoredGenerationId: nil,
                    diagnostics: ["Active and previous Adblock generations failed smoke lookup"]
                )
            }
            try await manifestStore.replaceActiveManifest(previousManifest)
            let previousDefinitions = try await manifestStore.compiledShardDefinitions(for: previousManifest)
            try await publisher.publish(
                manifest: previousManifest,
                definitions: previousDefinitions
            )
            return AdblockGenerationRollbackReport(
                rolledBack: true,
                activeGenerationId: activeManifest.activeGenerationId,
                restoredGenerationId: previousManifest.activeGenerationId,
                diagnostics: ["Rolled back after missing identifiers: \(activeMissingIdentifiers.joined(separator: ","))"]
            )
        } catch {
            return AdblockGenerationRollbackReport(
                rolledBack: false,
                activeGenerationId: nil,
                restoredGenerationId: nil,
                diagnostics: ["Rollback smoke check failed: \(error.localizedDescription)"]
            )
        }
    }

    private func missingIdentifiers(in manifest: AdblockCompiledGenerationManifest) async -> [String] {
        guard let contentRuleListStore else { return [] }
        var missing = [String]()
        for identifier in manifest.webKitRuleListIdentifiers {
            if await contentRuleListStore.canLookUpContentRuleList(forIdentifier: identifier) == false {
                missing.append(identifier)
            }
        }
        return missing
    }

    static func webKitIdentifier(
        kind: AdblockCompiledRuleGroupKind,
        generationHash: String
    ) -> String {
        switch kind {
        case .network:
            return "sumi.adblock.network.\(generationHash)"
        case .nativeCosmeticCSS:
            return "sumi.adblock.nativeCSS.\(generationHash)"
        }
    }

    static func isAdblockGeneratedWebKitIdentifier(_ identifier: String) -> Bool {
        identifier.hasPrefix("sumi.adblock.")
    }

    private static func diagnosticsSummary(
        nativeDiagnostics diagnostics: AdblockCompilationDiagnostics,
        nativeOutput: NativeContentBlockingCompilationOutput,
        enhancedOutput: EnhancedCompatibilityCompilationOutput?
    ) -> String {
        [
            "nativeCSSConverted=\(diagnostics.nativeCosmeticRuleCount)",
            "unsupportedCosmetic=\(diagnostics.unsupportedCosmeticRuleCount)",
            "scriptletOrProceduralIgnored=\(diagnostics.ignoredScriptletOrProceduralRuleCount)",
            "unsafeNativeCSSRootSelectorsFiltered=\(diagnostics.filteredUnsafeNativeCosmeticSelectors.count)",
            "nativeCSSEmpty=\(diagnostics.isNativeCosmeticGroupEmpty)",
            "unsupported=\(diagnostics.unsupportedRules.count)",
            "ignored=\(diagnostics.ignoredRules.count)",
            "ruleCapHit=\(diagnostics.ruleCap.wasHit)",
            "discarded=\(diagnostics.ruleCap.discardedRuleCount)",
            "networkShards=\(nativeOutput.networkShards.count)",
            "nativeCSSShards=\(nativeOutput.nativeCosmeticCSSShards.count)",
            "largestShardBytes=\(nativeOutput.shards.map(\.descriptor.jsonByteCount).max() ?? 0)",
            "enhancedResources=\(enhancedOutput?.enhancedRuntimeBundle.resources.count ?? 0)",
            "enhancedUnsupported=\(enhancedOutput?.enhancedRuntimeBundle.unsupportedDiagnostics.count ?? 0)",
        ].joined(separator: "; ")
    }

    private static func approximateRuleCount(in data: Data) -> Int {
        String(decoding: data, as: UTF8.self)
            .components(separatedBy: .newlines)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("!") && !$0.hasPrefix("[") }
            .count
    }

    private static func timestampString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
    }

    private static func shortHash(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}

private extension Data {
    var sumiAdblockSHA256Digest: String {
        SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }
}

import Combine
import CryptoKit
import Foundation

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
    case oraLikeNative

    var id: String { rawValue }
}

struct AdblockFilterListProfile: Codable, Equatable, Identifiable, Sendable {
    let id: AdblockFilterListProfileKind
    let displayName: String
    let listIdentifiers: [String]
    let isExperimental: Bool
    let isRecommended: Bool
    let appendsRecommendedRegionalList: Bool
    let notes: String
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
                appendsRecommendedRegionalList: true,
                notes: "Conservative native profile used by Sumi today."
            ),
            AdblockFilterListProfile(
                id: .lightNative,
                displayName: "Light Native",
                listIdentifiers: ["easylist"],
                isExperimental: false,
                isRecommended: false,
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
                isRecommended: true,
                appendsRecommendedRegionalList: true,
                notes: "Candidate stronger native ads profile with no privacy-overlap lists and no JavaScript runtime."
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
                appendsRecommendedRegionalList: true,
                notes: "Higher native coverage candidate with annoyance blocking and higher cap/false-positive pressure."
            ),
            AdblockFilterListProfile(
                id: .oraLikeNative,
                displayName: "Ora-like Experimental",
                listIdentifiers: [
                    "adguard-base",
                    "adguard-mobile-ads",
                    "adguard-tracking-protection",
                    "adguard-url-tracking",
                    "adguard-annoyances",
                ],
                isExperimental: true,
                isRecommended: false,
                appendsRecommendedRegionalList: false,
                notes: "Modeled from Ora's default/recommended AdGuard native lists for comparison only; not enabled by default."
            ),
        ]
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
            shortDescription: "Core AdGuard advertising filters; modeled for Ora-like native comparison.",
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
            shortDescription: "Mobile ad-network filters included in Ora's default profile; experimental on desktop WebKit.",
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
}

struct AdblockRuleListGeneration: Codable, Equatable, Sendable {
    let id: String
    let createdDate: Date
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
        previousGenerationId: String?
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

struct AdblockUpdateDiagnostics: Error, LocalizedError, Equatable, Sendable {
    var summary: String
    var listFailures: [String: String] = [:]
    var failedShardIdentifier: String?

    var errorDescription: String? { summary }
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
                throw AdblockUpdateDiagnostics(summary: "Invalid HTTP response")
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
        var request = URLRequest(url: descriptor.remoteURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        if let eTag = previousMetadata?.eTag, !eTag.isEmpty {
            request.setValue(eTag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified = previousMetadata?.lastModified, !lastModified.isEmpty {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }

        let (data, response) = try await fetch(request)
        if response.statusCode == 304 {
            return .notModified(response)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw AdblockUpdateDiagnostics(summary: "HTTP \(response.statusCode)")
        }
        guard !data.isEmpty else {
            throw AdblockUpdateDiagnostics(summary: "Downloaded list is empty")
        }
        return .downloaded(data, response)
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

    private func rawListURL(forListIdentifier identifier: String) -> URL {
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
    private let changesSubject = PassthroughSubject<Void, Never>()

    init(
        manifest: AdblockCompiledGenerationManifest?,
        cosmeticMode: SumiAdblockCosmeticMode
    ) {
        self.manifest = manifest
        self.cosmeticMode = cosmeticMode
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

    func updateManifest(_ manifest: AdblockCompiledGenerationManifest?) {
        guard self.manifest != manifest else { return }
        self.manifest = manifest
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
        let definitions = manifest.allNativeShards
            .filter { allowedKinds.contains($0.kind) }
            .map { shard in
                SumiContentRuleListDefinition(
                    name: shard.webKitIdentifier,
                    encodedContentRuleList: "[]",
                    storeIdentifierOverride: shard.webKitIdentifier
                )
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
}

@MainActor
protocol AdblockRuleListPublishing: AnyObject, Sendable {
    func publish(
        manifest: AdblockCompiledGenerationManifest,
        definitions: [SumiContentRuleListDefinition]
    ) async throws
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
        let prepared = try await contentBlockingService.prepareRuleListUpdate(ruleLists: definitions)
        ruleListProvider.updateManifest(manifest)
        contentBlockingService.commitPreparedContentBlockingUpdate(prepared)
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

    func updateIfEnabled(reason: String) async throws -> AdblockCompiledGenerationManifest? {
        guard await isAdblockEnabled() else { return nil }

        let selection = await selection()
        let nativeProfile = await nativeProfileSelection()
        let descriptors = registry.selectedDescriptors(
            selection: selection,
            profileKind: nativeProfile
        )
        guard !descriptors.isEmpty else {
            throw AdblockUpdateDiagnostics(summary: "No selected Adblock filter lists")
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

        for descriptor in descriptors {
            do {
                let result = try await downloader.download(
                    descriptor: descriptor,
                    previousMetadata: previousMetadata[descriptor.id]
                )
                let listData: Data
                var metadata = previousMetadata[descriptor.id] ?? AdblockFilterListHTTPMetadata()
                metadata.lastCheckedDate = now()
                metadata.failureSummary = nil

                switch result {
                case .downloaded(let data, let response):
                    listData = data
                    metadata.eTag = response.value(forHTTPHeaderField: "ETag")
                    metadata.lastModified = response.value(forHTTPHeaderField: "Last-Modified")
                    metadata.lastSuccessfulDownloadDate = now()
                    metadata.contentHash = data.sumiAdblockSHA256Digest
                    let stagedURL = try await manifestStore.writeRawList(
                        data,
                        identifier: descriptor.id,
                        stagingDirectory: stagingDirectory
                    )
                    stagedRawURLs[descriptor.id] = stagedURL
                case .notModified:
                    guard let previous = try await manifestStore.rawListData(forListIdentifier: descriptor.id) else {
                        throw AdblockUpdateDiagnostics(summary: "304 without previous raw list")
                    }
                    listData = previous
                    metadata.contentHash = previous.sumiAdblockSHA256Digest
                }

                updatedMetadata[descriptor.id] = metadata
                filterTexts.append(String(decoding: listData, as: UTF8.self))
                selectedLists.append(
                    AdblockCompiledGenerationManifest.SelectedFilterList(
                        id: descriptor.id,
                        displayName: descriptor.displayName,
                        contentHash: listData.sumiAdblockSHA256Digest,
                        category: descriptor.category,
                        inputByteCount: listData.count,
                        approximateRuleCount: Self.approximateRuleCount(in: listData)
                    )
                )
            } catch {
                failures[descriptor.id] = error.localizedDescription
                var metadata = previousMetadata[descriptor.id] ?? AdblockFilterListHTTPMetadata()
                metadata.lastCheckedDate = now()
                metadata.failureSummary = error.localizedDescription
                updatedMetadata[descriptor.id] = metadata
            }
        }

        if !failures.isEmpty {
            throw AdblockUpdateDiagnostics(
                summary: "Adblock update failed before compilation",
                listFailures: failures
            )
        }

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

        let nativeInput = AdblockCompilationInput(
            sourceIdentifier: sourceIdentifier,
            generationId: generation.id,
            nativeProfile: nativeProfile,
            filterTexts: filterTexts,
            selectedOutputGroups: [.network, .nativeCosmeticCSS],
            sourceLists: selectedLists.map {
                NativeContentBlockingSourceList(
                    id: $0.id,
                    displayName: $0.displayName,
                    contentHash: $0.contentHash,
                    category: $0.category,
                    inputByteCount: $0.inputByteCount,
                    approximateRuleCount: $0.approximateRuleCount
                )
            }
        )
        let nativeOutput: NativeContentBlockingCompilationOutput
        do {
            nativeOutput = try await nativeCompiler.compileNativeContentBlocking(nativeInput)
        } catch {
            throw AdblockUpdateDiagnostics(summary: "Adblock native compilation failed: \(error.localizedDescription)")
        }

        guard await isAdblockEnabled() else { return nil }

        let enhancedOutput = try await enhancedCompiler?.compileEnhancedCompatibility(nativeInput)

        guard await isAdblockEnabled() else { return nil }

        var definitions = [SumiContentRuleListDefinition]()
        var stagedCompiledShardURLs = [String: URL]()
        for shard in nativeOutput.shards.sorted(by: {
            if $0.kind == $1.kind {
                return $0.descriptor.id < $1.descriptor.id
            }
            return $0.kind.rawValue < $1.kind.rawValue
        }) {
            stagedCompiledShardURLs[shard.descriptor.id] = try await manifestStore.writeCompiledShard(
                shard,
                stagingDirectory: stagingDirectory
            )
            definitions.append(shard.definition)
        }

        let manifest = AdblockCompiledGenerationManifest(
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
                inputByteCount: filterTexts.reduce(0) { $0 + $1.utf8.count },
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

        do {
            try await publisher.publish(manifest: manifest, definitions: definitions)
        } catch let error as SumiContentBlockingCompilationError {
            throw AdblockUpdateDiagnostics(
                summary: "Adblock shard publish failed: \(error.localizedDescription)",
                failedShardIdentifier: error.identifier
            )
        }
        try await manifestStore.commit(
            manifest: manifest,
            httpMetadata: updatedMetadata,
            stagedRawListURLs: stagedRawURLs,
            stagedCompiledShardURLs: stagedCompiledShardURLs
        )
        if let garbageCollector {
            latestCleanupReport = await garbageCollector.cleanupAfterSuccessfulUpdate()
        }
        return manifest
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
            try await publisher.publish(
                manifest: previousManifest,
                definitions: Self.definitions(from: previousManifest)
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

    private static func definitions(
        from manifest: AdblockCompiledGenerationManifest
    ) -> [SumiContentRuleListDefinition] {
        manifest.allNativeShards.map { shard in
            SumiContentRuleListDefinition(
                name: shard.webKitIdentifier,
                encodedContentRuleList: "[]",
                storeIdentifierOverride: shard.webKitIdentifier
            )
        }
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

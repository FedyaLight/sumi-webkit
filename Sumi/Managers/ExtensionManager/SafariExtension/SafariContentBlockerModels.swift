//
//  SafariContentBlockerModels.swift
//  Sumi
//

import Foundation
import SwiftData

enum SafariExtensionBundleKind: String, Codable, CaseIterable, Sendable {
    case webExtension
    case contentBlocker
    case legacySafariAppExtension
    case unsupported

    var title: String {
        switch self {
        case .webExtension:
            return "Safari Web Extension"
        case .contentBlocker:
            return "Content Blocker"
        case .legacySafariAppExtension:
            return "Legacy Safari Extension"
        case .unsupported:
            return "Unsupported Extension"
        }
    }
}

enum SafariExtensionRuntimeStatus: String, Codable, CaseIterable, Sendable {
    case webExtensionImportable
    case contentBlockerImportable
    case unsupportedLegacySafariAppExtension
    case unsupportedExtensionPoint
    case unreadable

    var title: String {
        switch self {
        case .webExtensionImportable:
            return "Ready to enable"
        case .contentBlockerImportable:
            return "Ready to inspect rules"
        case .unsupportedLegacySafariAppExtension:
            return "Unsupported in Sumi"
        case .unsupportedExtensionPoint:
            return "Unsupported extension point"
        case .unreadable:
            return "Bundle is not readable"
        }
    }
}

enum SafariContentBlockerCompileStatus: String, Codable, CaseIterable, Sendable {
    case unknown
    case available
    case rulesUnavailable
    case compileFailed

    var title: String {
        switch self {
        case .unknown:
            return "Not validated"
        case .available:
            return "Rules compiled"
        case .rulesUnavailable:
            return "Static rules unavailable"
        case .compileFailed:
            return "Compile failed"
        }
    }
}

enum SumiSafariContentBlockerSiteOverride: String, Codable, CaseIterable, Sendable {
    case inherit
    case disabled
}

struct SumiSafariContentBlockerAttachmentState: Equatable, Sendable {
    let siteHost: String?
    let isEnabledForSite: Bool
    let enabledContentBlockerIds: [String]
    let enabledContentBlockerRuleIdentities: [String]

    init(
        siteHost: String?,
        isEnabledForSite: Bool,
        enabledContentBlockerIds: [String]
    ) {
        self.init(
            siteHost: siteHost,
            isEnabledForSite: isEnabledForSite,
            enabledContentBlockerIds: enabledContentBlockerIds,
            enabledContentBlockerRuleIdentities: enabledContentBlockerIds
        )
    }

    init(
        siteHost: String?,
        isEnabledForSite: Bool,
        enabledContentBlockerIds: [String],
        enabledContentBlockerRuleIdentities: [String]
    ) {
        self.siteHost = siteHost
        self.isEnabledForSite = isEnabledForSite
        self.enabledContentBlockerIds = enabledContentBlockerIds
        self.enabledContentBlockerRuleIdentities = enabledContentBlockerRuleIdentities
    }

    var isEnabled: Bool {
        isEnabledForSite && !enabledContentBlockerIds.isEmpty
    }

    var effectiveWebViewRuleIdentities: [String] {
        guard isEnabledForSite else { return [] }
        let identities = enabledContentBlockerRuleIdentities.isEmpty
            ? enabledContentBlockerIds
            : enabledContentBlockerRuleIdentities
        return identities.sorted()
    }

    func hasSameEffectiveWebViewAttachment(
        as other: SumiSafariContentBlockerAttachmentState
    ) -> Bool {
        effectiveWebViewRuleIdentities == other.effectiveWebViewRuleIdentities
    }

    static func disabled(siteHost: String?) -> SumiSafariContentBlockerAttachmentState {
        SumiSafariContentBlockerAttachmentState(
            siteHost: siteHost,
            isEnabledForSite: false,
            enabledContentBlockerIds: []
        )
    }
}

struct SumiSafariContentBlockerReloadRequirement: Equatable, Sendable {
    let siteHost: String?
    let desiredAttachmentState: SumiSafariContentBlockerAttachmentState
}

struct SumiSafariContentBlockerSiteState: Equatable, Sendable {
    let siteHost: String?
    let isGloballyAvailable: Bool
    let isEnabledForSite: Bool
    let enabledContentBlockerCount: Int

    var isInteractive: Bool {
        siteHost != nil && isGloballyAvailable
    }
}

struct InstalledSafariContentBlockerRecord: Identifiable, Equatable, Sendable {
    let id: String
    let extensionBundleIdentifier: String
    let displayName: String
    let version: String?
    let containingAppName: String
    let containingAppBundleIdentifier: String?
    let appexPath: String
    let containingAppPath: String
    let resourceFingerprint: String
    let isEnabled: Bool
    let installDate: Date
    let lastUpdateDate: Date
    let compileStatus: SafariContentBlockerCompileStatus
    let lastError: String?
    let ruleListCount: Int
    let ignoredEmptyRuleListCount: Int

    init(
        id: String,
        extensionBundleIdentifier: String,
        displayName: String,
        version: String?,
        containingAppName: String,
        containingAppBundleIdentifier: String?,
        appexPath: String,
        containingAppPath: String,
        resourceFingerprint: String,
        isEnabled: Bool,
        installDate: Date,
        lastUpdateDate: Date,
        compileStatus: SafariContentBlockerCompileStatus,
        lastError: String?,
        ruleListCount: Int,
        ignoredEmptyRuleListCount: Int
    ) {
        self.id = id
        self.extensionBundleIdentifier = extensionBundleIdentifier
        self.displayName = displayName
        self.version = version
        self.containingAppName = containingAppName
        self.containingAppBundleIdentifier = containingAppBundleIdentifier
        self.appexPath = appexPath
        self.containingAppPath = containingAppPath
        self.resourceFingerprint = resourceFingerprint
        self.isEnabled = isEnabled
        self.installDate = installDate
        self.lastUpdateDate = lastUpdateDate
        self.compileStatus = compileStatus
        self.lastError = lastError
        self.ruleListCount = ruleListCount
        self.ignoredEmptyRuleListCount = ignoredEmptyRuleListCount
    }

    init(entity: SafariContentBlockerEntity) {
        self.id = entity.id
        self.extensionBundleIdentifier = entity.extensionBundleIdentifier
        self.displayName = entity.displayName
        self.version = entity.version
        self.containingAppName = entity.containingAppName
        self.containingAppBundleIdentifier = entity.containingAppBundleIdentifier
        self.appexPath = entity.appexPath
        self.containingAppPath = entity.containingAppPath
        self.resourceFingerprint = entity.resourceFingerprint
        self.isEnabled = entity.isEnabled
        self.installDate = entity.installDate
        self.lastUpdateDate = entity.lastUpdateDate
        self.compileStatus = SafariContentBlockerCompileStatus(
            rawValue: entity.compileStatusRawValue
        ) ?? .unknown
        self.lastError = entity.lastError
        self.ruleListCount = entity.ruleListCount
        self.ignoredEmptyRuleListCount = entity.ignoredEmptyRuleListCount
    }
}

@Model
final class SafariContentBlockerEntity {
    @Attribute(.unique) var id: String
    var extensionBundleIdentifier: String
    var displayName: String
    var version: String?
    var containingAppName: String
    var containingAppBundleIdentifier: String?
    var appexPath: String
    var containingAppPath: String
    var resourceFingerprint: String
    var isEnabled: Bool
    var installDate: Date
    var lastUpdateDate: Date
    var compileStatusRawValue: String
    var lastError: String?
    var ruleListCount: Int
    var ignoredEmptyRuleListCount: Int

    init(
        id: String,
        extensionBundleIdentifier: String,
        displayName: String,
        version: String?,
        containingAppName: String,
        containingAppBundleIdentifier: String?,
        appexPath: String,
        containingAppPath: String,
        resourceFingerprint: String,
        isEnabled: Bool,
        installDate: Date = Date(),
        lastUpdateDate: Date = Date(),
        compileStatus: SafariContentBlockerCompileStatus,
        lastError: String?,
        ruleListCount: Int,
        ignoredEmptyRuleListCount: Int
    ) {
        self.id = id
        self.extensionBundleIdentifier = extensionBundleIdentifier
        self.displayName = displayName
        self.version = version
        self.containingAppName = containingAppName
        self.containingAppBundleIdentifier = containingAppBundleIdentifier
        self.appexPath = appexPath
        self.containingAppPath = containingAppPath
        self.resourceFingerprint = resourceFingerprint
        self.isEnabled = isEnabled
        self.installDate = installDate
        self.lastUpdateDate = lastUpdateDate
        self.compileStatusRawValue = compileStatus.rawValue
        self.lastError = lastError
        self.ruleListCount = ruleListCount
        self.ignoredEmptyRuleListCount = ignoredEmptyRuleListCount
    }

    var compileStatus: SafariContentBlockerCompileStatus {
        get {
            SafariContentBlockerCompileStatus(rawValue: compileStatusRawValue) ?? .unknown
        }
        set {
            compileStatusRawValue = newValue.rawValue
        }
    }
}

import Foundation

@MainActor
struct SumiCurrentSitePermissionRowsBuilder {
    @MainActor
    struct RowIndex {
        private let recordsByIdentity: [String: SumiPermissionStoreRecord]
        private let oneTimeRecordsByIdentity: [String: SumiPermissionStoreRecord]
        private let recentEventCountsByPermissionIdentity: [String: Int]
        private let siteActivityByPermissionIdentity: [String: SumiPermissionSiteActivityRecord]
        private let externalSchemeAttemptCountsByScheme: [String: Int]

        let blockedPopupAttemptCount: Int
        let externalSchemes: Set<String>

        init(
            context: SumiCurrentSitePermissionsViewModel.Context,
            storedRecords: [SumiPermissionStoreRecord],
            transientRecords: [SumiPermissionStoreRecord],
            blockedPopupStore: SumiBlockedPopupStore,
            externalSchemeSessionStore: SumiExternalSchemeSessionStore,
            indicatorEventStore: SumiPermissionIndicatorEventStore,
            siteActivityStore: SumiPermissionSiteActivityStore
        ) {
            var recordsByIdentity: [String: SumiPermissionStoreRecord] = [:]
            var oneTimeRecordsByIdentity: [String: SumiPermissionStoreRecord] = [:]
            var recentEventCountsByPermissionIdentity: [String: Int] = [:]
            var siteActivityByPermissionIdentity: [String: SumiPermissionSiteActivityRecord] = [:]
            var externalSchemeAttemptCountsByScheme: [String: Int] = [:]
            var externalSchemes = Set<String>()

            for record in storedRecords where record.decision.persistence != .oneTime {
                let lookupIdentity = Self.lookupIdentity(for: record.key)
                if recordsByIdentity[lookupIdentity] == nil {
                    recordsByIdentity[lookupIdentity] = record
                }

                guard Self.isCurrentSite(record.key, context: context),
                      case .externalScheme(let scheme) = record.key.permissionType
                else { continue }
                externalSchemes.insert(SumiPermissionType.normalizedExternalScheme(scheme))
            }

            for record in transientRecords
                where record.key.transientPageId == context.pageId
                    && record.decision.persistence == .oneTime
                    && record.decision.state == .allow
            {
                let lookupIdentity = Self.lookupIdentity(for: record.key)
                if oneTimeRecordsByIdentity[lookupIdentity] == nil {
                    oneTimeRecordsByIdentity[lookupIdentity] = record
                }
            }

            let siteActivityRecords = siteActivityStore.records(
                forSiteOf: context.origin,
                profilePartitionId: context.profilePartitionId,
                isEphemeralProfile: context.isEphemeralProfile
            )
            for activity in siteActivityRecords {
                let permissionIdentity = activity.permissionType.identity
                if siteActivityByPermissionIdentity[permissionIdentity] == nil {
                    siteActivityByPermissionIdentity[permissionIdentity] = activity
                }
                if case .externalScheme(let scheme) = activity.permissionType {
                    externalSchemes.insert(SumiPermissionType.normalizedExternalScheme(scheme))
                }
            }

            let pageId = context.pageId
            if let pageId {
                var seenIds = Set<String>()
                for record in indicatorEventStore.recordsSnapshot(forPageId: pageId)
                    where seenIds.insert(record.id).inserted
                {
                    for permissionType in record.permissionTypes {
                        recentEventCountsByPermissionIdentity[permissionType.identity, default: 0] += record.attemptCount
                    }
                }

                for record in externalSchemeSessionStore.records(forPageId: pageId) {
                    let scheme = SumiPermissionType.normalizedExternalScheme(record.scheme)
                    externalSchemeAttemptCountsByScheme[scheme, default: 0] += record.attemptCount
                    guard record.requestingOrigin.identity == context.origin.identity,
                          record.topOrigin.identity == context.origin.identity
                    else { continue }
                    externalSchemes.insert(scheme)
                }
            }

            blockedPopupAttemptCount = pageId.map {
                blockedPopupStore.records(forPageId: $0)
                    .reduce(0) { $0 + $1.attemptCount }
            } ?? 0
            self.recordsByIdentity = recordsByIdentity
            self.oneTimeRecordsByIdentity = oneTimeRecordsByIdentity
            self.recentEventCountsByPermissionIdentity = recentEventCountsByPermissionIdentity
            self.siteActivityByPermissionIdentity = siteActivityByPermissionIdentity
            self.externalSchemeAttemptCountsByScheme = externalSchemeAttemptCountsByScheme
            self.externalSchemes = externalSchemes
        }

        func record(for key: SumiPermissionKey) -> SumiPermissionStoreRecord? {
            recordsByIdentity[Self.lookupIdentity(for: key)]
        }

        func hasResolvedDecision(for key: SumiPermissionKey) -> Bool {
            guard let state = record(for: key)?.decision.state else { return false }
            return state == .allow || state == .deny
        }

        func activeOneTimeRecord(for key: SumiPermissionKey) -> SumiPermissionStoreRecord? {
            oneTimeRecordsByIdentity[Self.lookupIdentity(for: key)]
        }

        func recentEventCount(for permissionType: SumiPermissionType) -> Int {
            recentEventCountsByPermissionIdentity[permissionType.identity] ?? 0
        }

        func siteActivity(for permissionType: SumiPermissionType) -> SumiPermissionSiteActivityRecord? {
            siteActivityByPermissionIdentity[permissionType.identity]
        }

        func externalSchemeAttemptCount(for scheme: String) -> Int {
            externalSchemeAttemptCountsByScheme[SumiPermissionType.normalizedExternalScheme(scheme)] ?? 0
        }

        private static func lookupIdentity(for key: SumiPermissionKey) -> String {
            [
                key.persistentIdentity,
                key.isEphemeralProfile ? "ephemeral" : "persistent",
            ].joined(separator: "|")
        }

        private static func isCurrentSite(
            _ key: SumiPermissionKey,
            context: SumiCurrentSitePermissionsViewModel.Context
        ) -> Bool {
            key.profilePartitionId == context.profilePartitionId
                && key.isEphemeralProfile == context.isEphemeralProfile
                && key.requestingOrigin.identity == context.origin.identity
                && key.topOrigin.identity == context.origin.identity
        }
    }

    static func makeRows(
        context: SumiCurrentSitePermissionsViewModel.Context,
        profile: Profile?,
        reloadRequired: Bool,
        autoplayInUse: Bool,
        runtimeState: SumiRuntimePermissionState?,
        systemSnapshots: [SumiSystemPermissionKind: SumiSystemPermissionSnapshot],
        rowIndex: RowIndex,
        autoplayStore: any SumiCurrentSiteAutoplayPolicyManaging
    ) -> [SumiCurrentSitePermissionRow] {
        var result: [SumiCurrentSitePermissionRow] = []

        appendSitePermissionRowIfRelevant(
            .camera,
            to: &result,
            context: context,
            systemSnapshot: systemSnapshots[.camera],
            runtimeStatus: runtimeStatus(for: runtimeState?.camera),
            rowIndex: rowIndex
        )
        appendSitePermissionRowIfRelevant(
            .microphone,
            to: &result,
            context: context,
            systemSnapshot: systemSnapshots[.microphone],
            runtimeStatus: runtimeStatus(for: runtimeState?.microphone),
            rowIndex: rowIndex
        )
        appendSitePermissionRowIfRelevant(
            .screenCapture,
            to: &result,
            context: context,
            systemSnapshot: systemSnapshots[.screenCapture],
            runtimeStatus: runtimeStatus(for: runtimeState?.screenCapture),
            rowIndex: rowIndex
        )
        appendSitePermissionRowIfRelevant(
            .geolocation,
            to: &result,
            context: context,
            systemSnapshot: systemSnapshots[.geolocation],
            runtimeStatus: runtimeStatus(for: runtimeState?.geolocation),
            rowIndex: rowIndex
        )
        appendSitePermissionRowIfRelevant(
            .notifications,
            to: &result,
            context: context,
            systemSnapshot: systemSnapshots[.notifications],
            runtimeStatus: nil,
            rowIndex: rowIndex
        )
        appendPopupsRowIfRelevant(to: &result, context: context, rowIndex: rowIndex)
        result.append(contentsOf: externalAppRows(context: context, rowIndex: rowIndex))
        appendAutoplayRowIfRelevant(
            to: &result,
            context: context,
            profile: profile,
            reloadRequired: reloadRequired,
            autoplayInUse: autoplayInUse,
            rowIndex: rowIndex,
            autoplayStore: autoplayStore
        )
        appendSitePermissionRowIfRelevant(
            .storageAccess,
            to: &result,
            context: context,
            systemSnapshot: nil,
            runtimeStatus: nil,
            rowIndex: rowIndex,
            titleOverride: SumiCurrentSitePermissionsStrings.storageAccessTitle
        )
        appendFilePickerRowIfRelevant(to: &result, context: context, rowIndex: rowIndex)

        return result
    }

    static func systemKind(
        for row: SumiCurrentSitePermissionRow
    ) -> SumiSystemPermissionKind? {
        switch row.kind {
        case .sitePermission(.camera):
            return .camera
        case .sitePermission(.microphone):
            return .microphone
        case .sitePermission(.geolocation):
            return .geolocation
        case .sitePermission(.notifications):
            return .notifications
        case .sitePermission(.screenCapture):
            return .screenCapture
        default:
            return nil
        }
    }

    private static func appendSitePermissionRowIfRelevant(
        _ permissionType: SumiPermissionType,
        to result: inout [SumiCurrentSitePermissionRow],
        context: SumiCurrentSitePermissionsViewModel.Context,
        systemSnapshot: SumiSystemPermissionSnapshot?,
        runtimeStatus: String?,
        rowIndex: RowIndex,
        titleOverride: String? = nil,
        subtitleOverride: String? = nil
    ) {
        let recentCount = rowIndex.recentEventCount(for: permissionType)
        let siteActivity = rowIndex.siteActivity(for: permissionType)
        guard shouldShowSitePermissionRow(
            permissionType,
            context: context,
            systemSnapshot: systemSnapshot,
            runtimeStatus: runtimeStatus,
            recentEventCount: recentCount,
            siteActivity: siteActivity,
            rowIndex: rowIndex
        ) else { return }

        result.append(
            sitePermissionRow(
                permissionType: permissionType,
                context: context,
                systemSnapshot: systemSnapshot,
                runtimeStatus: runtimeStatus,
                recentEventCount: recentCount,
                siteActivity: siteActivity,
                rowIndex: rowIndex,
                titleOverride: titleOverride,
                subtitleOverride: subtitleOverride
            )
        )
    }

    private static func shouldShowSitePermissionRow(
        _ permissionType: SumiPermissionType,
        context: SumiCurrentSitePermissionsViewModel.Context,
        systemSnapshot: SumiSystemPermissionSnapshot?,
        runtimeStatus: String?,
        recentEventCount: Int,
        siteActivity: SumiPermissionSiteActivityRecord?,
        rowIndex: RowIndex
    ) -> Bool {
        if recentEventCount > 0 || runtimeStatus != nil || siteActivity != nil {
            return true
        }

        let key = context.key(for: permissionType)
        if rowIndex.hasResolvedDecision(for: key) || rowIndex.activeOneTimeRecord(for: key) != nil {
            return true
        }

        return systemStatus(from: systemSnapshot).text != nil
    }

    private static func sitePermissionRow(
        permissionType: SumiPermissionType,
        context: SumiCurrentSitePermissionsViewModel.Context,
        systemSnapshot: SumiSystemPermissionSnapshot?,
        runtimeStatus: String?,
        recentEventCount: Int,
        siteActivity: SumiPermissionSiteActivityRecord?,
        rowIndex: RowIndex,
        titleOverride: String? = nil,
        subtitleOverride: String? = nil
    ) -> SumiCurrentSitePermissionRow {
        let descriptor = SumiPermissionIconCatalog.icon(for: permissionType)
        let key = context.key(for: permissionType)
        let option = option(for: rowIndex.record(for: key), defaultOption: .ask)
        let oneTimeRecord = rowIndex.activeOneTimeRecord(for: key)
        let system = systemStatus(from: systemSnapshot)
        let disabledReason = context.origin.supportsSensitiveWebPermission(permissionType)
            ? nil
            : "Requires a secure connection"
        let isEditable = disabledReason == nil
        let subtitle = subtitleOverride
            ?? subtitle(
                option: option,
                recentEventCount: recentEventCount,
                isEphemeralProfile: context.isEphemeralProfile,
                hasActiveOneTimeGrant: oneTimeRecord != nil,
                siteActivity: siteActivity
            )

        return SumiCurrentSitePermissionRow(
            id: permissionType.identity,
            kind: .sitePermission(permissionType),
            title: titleOverride ?? permissionType.displayLabel,
            subtitle: subtitle,
            iconName: descriptor.chromeIconName,
            fallbackSystemName: descriptor.fallbackSystemName,
            currentOption: option,
            availableOptions: [.ask, .allow, .block],
            isEditable: isEditable,
            disabledReason: disabledReason,
            systemStatus: system.text,
            showsSystemSettingsAction: system.showsSettings,
            runtimeStatus: runtimeStatus,
            recentEventCount: recentEventCount,
            accessibilityLabel: "\(permissionType.displayLabel), \(option.title), \(context.displayDomain)"
        )
    }

    private static func popupsRow(
        context: SumiCurrentSitePermissionsViewModel.Context,
        rowIndex: RowIndex
    ) -> SumiCurrentSitePermissionRow {
        let descriptor = SumiPermissionIconCatalog.icon(for: .popups)
        let key = context.key(for: .popups)
        let option = option(for: rowIndex.record(for: key), defaultOption: .default)
        let count = rowIndex.blockedPopupAttemptCount

        return SumiCurrentSitePermissionRow(
            id: "popups",
            kind: .popups,
            title: "Pop-ups and redirects",
            subtitle: count > 0
                ? "\(count) blocked popup\(count == 1 ? "" : "s")"
                : popupSubtitle(for: option, isEphemeralProfile: context.isEphemeralProfile),
            iconName: descriptor.chromeIconName,
            fallbackSystemName: descriptor.fallbackSystemName,
            currentOption: option,
            availableOptions: [.default, .allow, .block],
            isEditable: true,
            recentEventCount: count,
            accessibilityLabel: "Pop-ups and redirects, \(option.title), \(context.displayDomain)"
        )
    }

    private static func appendPopupsRowIfRelevant(
        to result: inout [SumiCurrentSitePermissionRow],
        context: SumiCurrentSitePermissionsViewModel.Context,
        rowIndex: RowIndex
    ) {
        let key = context.key(for: .popups)
        let option = option(for: rowIndex.record(for: key), defaultOption: .default)
        let count = rowIndex.blockedPopupAttemptCount
        let siteActivity = rowIndex.siteActivity(for: .popups)
        guard count > 0 || option == .allow || option == .block || siteActivity != nil else { return }
        result.append(popupsRow(context: context, rowIndex: rowIndex))
    }

    private static func externalAppRows(
        context: SumiCurrentSitePermissionsViewModel.Context,
        rowIndex: RowIndex
    ) -> [SumiCurrentSitePermissionRow] {
        let descriptor = SumiPermissionIconCatalog.icon(for: .externalScheme(""))
        var rows: [SumiCurrentSitePermissionRow] = []

        for scheme in rowIndex.externalSchemes.sorted() {
            let permissionType = SumiPermissionType.externalScheme(scheme)
            let key = context.key(for: permissionType)
            let option = option(for: rowIndex.record(for: key), defaultOption: .ask)
            let recentCount = rowIndex.externalSchemeAttemptCount(for: scheme)
            let siteActivity = rowIndex.siteActivity(for: permissionType)
            rows.append(
                SumiCurrentSitePermissionRow(
                    id: "external-scheme-\(scheme)",
                    kind: .externalScheme(scheme),
                    title: "\(scheme) links",
                    subtitle: recentCount > 0
                        ? "\(recentCount) recent attempt\(recentCount == 1 ? "" : "s")"
                        : subtitle(
                            option: option,
                            recentEventCount: 0,
                            isEphemeralProfile: context.isEphemeralProfile,
                            siteActivity: siteActivity
                        ),
                    iconName: descriptor.chromeIconName,
                    fallbackSystemName: descriptor.fallbackSystemName,
                    currentOption: option,
                    availableOptions: [.ask, .allow, .block],
                    isEditable: true,
                    recentEventCount: recentCount,
                    accessibilityLabel: "\(scheme) external app links, \(option.title), \(context.displayDomain)"
                )
            )
        }

        return rows
    }

    private static func autoplayRow(
        context: SumiCurrentSitePermissionsViewModel.Context,
        profile: Profile?,
        reloadRequired: Bool,
        autoplayStore: any SumiCurrentSiteAutoplayPolicyManaging
    ) -> SumiCurrentSitePermissionRow {
        let explicitPolicy = autoplayStore.explicitPolicy(
            for: context.mainFrameURL ?? context.visibleURL ?? context.committedURL,
            profile: profile
        )
        let policy = explicitPolicy ?? .default
        let option = option(for: policy)
        let descriptor = SumiPermissionIconCatalog.icon(
            for: .autoplay,
            visualStyle: reloadRequired ? .reloadRequired : .neutral
        )
        let subtitle: String
        if reloadRequired {
            subtitle = "Reload required"
        } else {
            subtitle = compactPolicySubtitle(for: option)
        }

        return SumiCurrentSitePermissionRow(
            id: "autoplay",
            kind: .autoplay,
            title: SumiPermissionType.autoplay.displayLabel,
            subtitle: subtitle,
            iconName: descriptor.chromeIconName,
            fallbackSystemName: descriptor.fallbackSystemName,
            currentOption: option,
            availableOptions: [.default, .allowAll, .blockAudible, .blockAll],
            isEditable: true,
            runtimeStatus: reloadRequired ? "Reload required" : nil,
            reloadRequired: reloadRequired,
            accessibilityLabel: "Autoplay, \(option.title), \(context.displayDomain)"
        )
    }

    private static func appendAutoplayRowIfRelevant(
        to result: inout [SumiCurrentSitePermissionRow],
        context: SumiCurrentSitePermissionsViewModel.Context,
        profile: Profile?,
        reloadRequired: Bool,
        autoplayInUse: Bool,
        rowIndex: RowIndex,
        autoplayStore: any SumiCurrentSiteAutoplayPolicyManaging
    ) {
        let explicitPolicy = autoplayStore.explicitPolicy(
            for: context.mainFrameURL ?? context.visibleURL ?? context.committedURL,
            profile: profile
        )
        let recentCount = rowIndex.recentEventCount(for: .autoplay)
        let siteActivity = rowIndex.siteActivity(for: .autoplay)
        guard explicitPolicy != nil || reloadRequired || autoplayInUse || recentCount > 0 || siteActivity != nil else { return }
        result.append(
            autoplayRow(
                context: context,
                profile: profile,
                reloadRequired: reloadRequired,
                autoplayStore: autoplayStore
            )
        )
    }

    private static func filePickerRow(
        context: SumiCurrentSitePermissionsViewModel.Context,
        rowIndex: RowIndex
    ) -> SumiCurrentSitePermissionRow {
        let descriptor = SumiPermissionIconCatalog.icon(for: .filePicker)
        let count = rowIndex.recentEventCount(for: .filePicker)
        let subtitle = count > 0
            ? "File chooser used this visit"
            : SumiCurrentSitePermissionsStrings.fileChooserAlwaysAsks
        return SumiCurrentSitePermissionRow(
            id: "file-picker",
            kind: .filePicker,
            title: SumiCurrentSitePermissionsStrings.fileChooserTitle,
            subtitle: subtitle,
            iconName: descriptor.chromeIconName,
            fallbackSystemName: descriptor.fallbackSystemName,
            currentOption: nil,
            availableOptions: [],
            isEditable: false,
            runtimeStatus: SumiCurrentSitePermissionsStrings.fileChooserExplanation,
            recentEventCount: count,
            accessibilityLabel: "File chooser, always asks, \(context.displayDomain)"
        )
    }

    private static func appendFilePickerRowIfRelevant(
        to result: inout [SumiCurrentSitePermissionRow],
        context: SumiCurrentSitePermissionsViewModel.Context,
        rowIndex: RowIndex
    ) {
        let count = rowIndex.recentEventCount(for: .filePicker)
        guard count > 0 else { return }
        result.append(filePickerRow(context: context, rowIndex: rowIndex))
    }

    private static func option(
        for record: SumiPermissionStoreRecord?,
        defaultOption: SumiCurrentSitePermissionOption
    ) -> SumiCurrentSitePermissionOption {
        guard let state = record?.decision.state else { return defaultOption }
        switch state {
        case .ask:
            return defaultOption
        case .allow:
            return .allow
        case .deny:
            return .block
        }
    }

    private static func option(for policy: SumiAutoplayPolicy) -> SumiCurrentSitePermissionOption {
        switch policy {
        case .default:
            return .default
        case .allowAll:
            return .allowAll
        case .blockAudible:
            return .blockAudible
        case .blockAll:
            return .blockAll
        }
    }

    private static func subtitle(
        option: SumiCurrentSitePermissionOption,
        recentEventCount _: Int,
        isEphemeralProfile _: Bool,
        hasActiveOneTimeGrant: Bool = false,
        siteActivity _: SumiPermissionSiteActivityRecord? = nil
    ) -> String {
        if hasActiveOneTimeGrant {
            return SumiCurrentSitePermissionsStrings.policyOn
        }
        return compactPolicySubtitle(for: option)
    }

    private static func popupSubtitle(
        for option: SumiCurrentSitePermissionOption,
        isEphemeralProfile _: Bool
    ) -> String {
        return compactPolicySubtitle(for: option)
    }

    private static func compactPolicySubtitle(
        for option: SumiCurrentSitePermissionOption
    ) -> String {
        switch option {
        case .allow, .allowAll:
            return SumiCurrentSitePermissionsStrings.policyOn
        case .block, .blockAudible, .blockAll:
            return SumiCurrentSitePermissionsStrings.policyOff
        case .ask, .default:
            return SumiCurrentSitePermissionsStrings.defaultOption
        }
    }

    private static func systemStatus(
        from snapshot: SumiSystemPermissionSnapshot?
    ) -> (text: String?, showsSettings: Bool) {
        guard let snapshot else { return (nil, false) }
        switch snapshot.state {
        case .authorized:
            return (nil, false)
        case .notDetermined:
            return ("macOS has not been asked yet", false)
        case .denied, .restricted, .systemDisabled:
            return (snapshot.reason, snapshot.shouldOpenSystemSettings)
        case .unavailable, .missingUsageDescription, .missingEntitlement:
            return (snapshot.reason, false)
        }
    }

    private static func runtimeStatus(
        for state: SumiMediaCaptureRuntimeState?
    ) -> String? {
        switch state {
        case .active:
            return "Active"
        case .muted:
            return "Muted"
        case .stopping:
            return "Stopping"
        case .revoking:
            return "Revoking"
        case .unavailable:
            return "Unavailable"
        default:
            return nil
        }
    }

    private static func runtimeStatus(
        for state: SumiGeolocationRuntimeState?
    ) -> String? {
        switch state {
        case .active:
            return "Active"
        case .paused:
            return "Paused"
        case .revoked:
            return "Revoked"
        case .unavailable:
            return "Unavailable"
        default:
            return nil
        }
    }
}

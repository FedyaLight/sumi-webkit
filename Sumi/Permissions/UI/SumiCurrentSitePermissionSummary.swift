import Foundation
import WebKit

struct SumiCurrentSitePermissionSummary: Equatable, Sendable {
    var subtitle: String
    var activityText: String?

    static let `default` = SumiCurrentSitePermissionSummary(
        subtitle: SumiCurrentSitePermissionsStrings.defaultSummary,
        activityText: nil
    )

    static func make(
        rows: [SumiCurrentSitePermissionRow],
        isEphemeralProfile: Bool
    ) -> SumiCurrentSitePermissionSummary {
        var items: [String] = []

        for row in rows {
            if let runtimeStatus = row.runtimeStatus,
               runtimeStatus.localizedCaseInsensitiveContains("active")
                || runtimeStatus.localizedCaseInsensitiveContains("muted")
                || runtimeStatus.localizedCaseInsensitiveContains("paused")
            {
                items.append("\(row.title.lowercased()) \(runtimeStatus.lowercased())")
            }
        }

        let blockedAttempts = rows
            .filter { row in
                row.kind == .popups || row.id.hasPrefix("external-scheme-")
            }
            .reduce(0) { $0 + $1.recentEventCount }
        if blockedAttempts > 0 {
            items.append("\(blockedAttempts) blocked attempt\(blockedAttempts == 1 ? "" : "s")")
        }

        if items.isEmpty {
            let explicitCount = rows.filter { row in
                switch row.currentOption {
                case .allow, .block, .allowAll, .blockAudible, .blockAll:
                    return true
                case .ask, .default, .none:
                    return false
                }
            }.count
            if explicitCount > 0 {
                items.append("\(explicitCount) custom setting\(explicitCount == 1 ? "" : "s")")
            }
        }

        if items.isEmpty, isEphemeralProfile {
            items.append(SumiCurrentSitePermissionsStrings.sessionOnly)
        }

        guard let first = items.first else {
            return .default
        }

        let compactItems = Array(items.prefix(2))
        let subtitle = compactItems
            .joined(separator: ", ")
            .capitalizingFirstLetter()
        return SumiCurrentSitePermissionSummary(
            subtitle: subtitle,
            activityText: compactItems.count > 1 ? subtitle : first.capitalizingFirstLetter()
        )
    }

    @MainActor
    static func topLevelSubtitle(
        tab: Tab?,
        profile: Profile?,
        runtimeController: (any SumiRuntimePermissionControlling)?,
        blockedPopupStore: SumiBlockedPopupStore,
        externalSchemeSessionStore: SumiExternalSchemeSessionStore,
        indicatorEventStore: SumiPermissionIndicatorEventStore
    ) -> String {
        guard let tab,
              let profile,
              SumiPermissionOrigin(url: tab.extensionRuntimeCommittedMainDocumentURL ?? tab.url).isWebOrigin
        else {
            return SumiCurrentSitePermissionsStrings.defaultSummary
        }

        let pageId = tab.currentPermissionPageId()
        var items: [String] = []
        if let webView = tab.existingWebView,
           let runtimeController {
            let runtime = runtimeController.currentRuntimeState(for: webView, pageId: pageId)
            appendRuntimeSummary(runtime, to: &items)
        }

        let popupCount = blockedPopupStore.records(forPageId: pageId)
            .reduce(0) { $0 + $1.attemptCount }
        let externalCount = externalSchemeSessionStore.records(forPageId: pageId)
            .filter { $0.result != .opened }
            .reduce(0) { $0 + $1.attemptCount }
        let indicatorCount = indicatorEventStore.recordsSnapshot(forPageId: pageId)
            .filter { $0.category == .blockedEvent || $0.category == .pendingRequest }
            .reduce(0) { $0 + $1.attemptCount }
        let blockedCount = popupCount + externalCount + indicatorCount
        if blockedCount > 0 {
            items.append("\(blockedCount) blocked attempt\(blockedCount == 1 ? "" : "s")")
        }

        if items.isEmpty, profile.isEphemeral {
            items.append(SumiCurrentSitePermissionsStrings.sessionOnly)
        }

        return items.first?.capitalizingFirstLetter() ?? SumiCurrentSitePermissionsStrings.defaultSummary
    }

    private static func appendRuntimeSummary(
        _ runtime: SumiRuntimePermissionState,
        to items: inout [String]
    ) {
        switch runtime.camera {
        case .active:
            items.append("camera active")
        case .muted:
            items.append("camera muted")
        default:
            break
        }

        switch runtime.microphone {
        case .active:
            items.append("microphone active")
        case .muted:
            items.append("microphone muted")
        default:
            break
        }

        switch runtime.geolocation {
        case .active:
            items.append("location active")
        case .paused:
            items.append("location paused")
        default:
            break
        }
    }
}

private extension String {
    func capitalizingFirstLetter() -> String {
        guard let first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}

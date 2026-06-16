import Foundation
import WebKit

struct SumiCurrentSitePermissionSummary: Equatable, Sendable {
    var activityText: String?

    static let `default` = SumiCurrentSitePermissionSummary(
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
            activityText: compactItems.count > 1 ? subtitle : first.capitalizingFirstLetter()
        )
    }

}

private extension String {
    func capitalizingFirstLetter() -> String {
        guard let first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}

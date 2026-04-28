import SwiftUI

struct SumiSiteSettingsRecentActivityView: View {
    let items: [SumiSiteSettingsRecentActivityItem]

    var body: some View {
        SettingsSection(title: SumiSiteSettingsStrings.recentActivity) {
            if items.isEmpty {
                SettingsEmptyState(
                    systemImage: "clock",
                    title: "No Recent Activity",
                    detail: SumiSiteSettingsStrings.recentActivityEmpty
                )
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(items) { item in
                        activityRow(item)
                        if item.id != items.last?.id {
                            SettingsDivider()
                        }
                    }
                }
            }
        }
    }

    private func activityRow(_ item: SumiSiteSettingsRecentActivityItem) -> some View {
        SettingsRow(
            title: item.title,
            subtitle: "\(item.subtitle)\n\(relativeDateString(for: item.timestamp))",
            systemImage: item.systemImage
        ) {
            EmptyView()
        }
        .accessibilityLabel("\(item.title), \(relativeDateString(for: item.timestamp))")
    }

    private func relativeDateString(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

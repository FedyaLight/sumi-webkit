@MainActor
enum SumiImportPreviewWarningBuilder {
    static func warnings(for data: SumiPortableData, source: String) -> [String] {
        var warnings: [String] = []
        let overflow = Dictionary(grouping: data.essentials, by: { $0.profileId ?? "" })
            .values
            .reduce(0) { $0 + max(0, $1.count - SumiImportApplier.maxEssentialsPerProfile) }
        if overflow > 0 {
            warnings.append("\(overflow) \(source) essentials exceed Sumi's 12-item profile limit and will become space-pinned launchers.")
        }
        return warnings
    }
}

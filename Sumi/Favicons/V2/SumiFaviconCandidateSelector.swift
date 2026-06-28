import Foundation

enum SumiFaviconCandidateSelector {
    static func orderedCandidates(
        _ candidates: [SumiFaviconCandidate],
        for context: SumiFaviconDisplayContext,
        backingScale: CGFloat,
        preferMaskable: Bool = false
    ) -> [SumiFaviconCandidate] {
        let targetPixels = max(1, Int((context.canonicalPointSize * max(1, backingScale)).rounded(.up)))
        return candidates.sorted { lhs, rhs in
            let lhsScore = score(lhs, targetPixels: targetPixels, preferMaskable: preferMaskable)
            let rhsScore = score(rhs, targetPixels: targetPixels, preferMaskable: preferMaskable)
            if lhsScore != rhsScore {
                return lhsScore < rhsScore
            }
            if lhs.iconURL.absoluteString != rhs.iconURL.absoluteString {
                return lhs.iconURL.absoluteString < rhs.iconURL.absoluteString
            }
            return lhs.discoveredAt < rhs.discoveredAt
        }
    }

    static func bestCandidate(
        _ candidates: [SumiFaviconCandidate],
        for context: SumiFaviconDisplayContext,
        backingScale: CGFloat,
        preferMaskable: Bool = false
    ) -> SumiFaviconCandidate? {
        orderedCandidates(
            candidates,
            for: context,
            backingScale: backingScale,
            preferMaskable: preferMaskable
        ).first
    }

    private static func score(
        _ candidate: SumiFaviconCandidate,
        targetPixels: Int,
        preferMaskable: Bool
    ) -> Int {
        sourceScore(candidate, targetPixels: targetPixels)
            + purposeScore(candidate, preferMaskable: preferMaskable)
            + typeScore(candidate)
            + sizeScore(candidate, targetPixels: targetPixels)
    }

    private static func sourceScore(_ candidate: SumiFaviconCandidate, targetPixels: Int) -> Int {
        let hasGoodDeclaredSize = candidate.declaredSizes.isEmpty
            || candidate.declaredSizes.contains { $0.longestSide >= targetPixels }
        var sourceRank = candidate.sourcePriority

        if !hasGoodDeclaredSize,
           candidate.sourceKind == .documentLink,
           candidate.declaredSizes.contains(where: { $0.longestSide <= 16 }) {
            sourceRank += 2
        }

        return sourceRank * 10_000
    }

    private static func purposeScore(
        _ candidate: SumiFaviconCandidate,
        preferMaskable: Bool
    ) -> Int {
        let purposes = Set(candidate.purposes)
        if preferMaskable, purposes.contains(.maskable) {
            return 0
        }
        if purposes.contains(.any) {
            return 0
        }
        if purposes.contains(.maskable) {
            return preferMaskable ? 0 : 600
        }
        if purposes.contains(.monochrome) {
            return 900
        }
        return 400
    }

    private static func typeScore(_ candidate: SumiFaviconCandidate) -> Int {
        let urlExtension = candidate.iconURL.pathExtension.lowercased()
        let type = candidate.declaredType?.lowercased()
        if type == "image/svg+xml" || urlExtension == "svg" {
            return 0
        }
        if type == "image/png" || urlExtension == "png" {
            return 40
        }
        if type == "image/webp" || urlExtension == "webp" {
            return 60
        }
        if type == "image/x-icon" || type == "image/vnd.microsoft.icon" || urlExtension == "ico" {
            return 90
        }
        if type == "image/jpeg" || type == "image/jpg" || urlExtension == "jpg" || urlExtension == "jpeg" {
            return 140
        }
        if type == "image/gif" || urlExtension == "gif" {
            return 160
        }
        return 120
    }

    private static func sizeScore(_ candidate: SumiFaviconCandidate, targetPixels: Int) -> Int {
        guard !candidate.declaredSizes.isEmpty else {
            return 260
        }

        let scores = candidate.declaredSizes.map { size in
            let longest = max(1, size.longestSide)
            if longest >= targetPixels {
                return min(1200, longest - targetPixels)
            }
            return 2_000 + (targetPixels - longest) * 40
        }

        return scores.min() ?? 260
    }
}

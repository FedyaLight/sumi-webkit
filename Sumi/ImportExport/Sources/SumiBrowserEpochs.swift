import Foundation

/// Every browser stores timestamps against a different origin and unit.
/// Converting once, at extraction time, keeps the staged payload free of
/// source-specific arithmetic.
enum SumiBrowserEpochs {
    /// Chromium counts microseconds since 1601-01-01 UTC (the Windows epoch),
    /// even on macOS.
    static let chromiumEpochOffsetSeconds: Double = 11_644_473_600

    static func chromium(microseconds: Int64) -> Date? {
        guard microseconds > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(microseconds) / 1_000_000 - chromiumEpochOffsetSeconds)
    }

    /// Firefox counts microseconds since the Unix epoch.
    static func firefox(microseconds: Int64) -> Date? {
        guard microseconds > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(microseconds) / 1_000_000)
    }

    /// Safari stores `CFAbsoluteTime`: seconds since 2001-01-01 UTC.
    static func safari(absoluteSeconds: Double) -> Date? {
        guard absoluteSeconds > 0 else { return nil }
        return Date(timeIntervalSinceReferenceDate: absoluteSeconds)
    }

    /// `moz_cookies.expiry` switched from seconds to milliseconds around
    /// Firefox 108, and both are still found in the wild. Values far beyond a
    /// plausible expiry in seconds are milliseconds.
    static func firefoxCookieExpiry(_ value: Int64) -> Date? {
        guard value > 0 else { return nil }
        let millisecondThreshold: Int64 = 100_000_000_000 // ~year 5138 in seconds
        let seconds = value > millisecondThreshold ? Double(value) / 1000 : Double(value)
        return Date(timeIntervalSince1970: seconds)
    }
}

//
//  DownloadFlyMotion.swift
//  Sumi
//

import SwiftUI

/// Wall-clock durations for one download flight and for the corner basket that
/// receives it while the downloads button is off screen.
enum DownloadFlyTiming {
    static let flightDuration: TimeInterval = 1.0

    /// How long the basket stays parked at rest, measured from the moment its
    /// entry settles rather than from the start of the flight.
    static let basketHoldDuration: TimeInterval = flightDuration + 0.2

    static let basketOvershootDuration: TimeInterval = 0.35
    static let basketSettleDuration: TimeInterval = 0.2
    static let basketSquashDuration: TimeInterval = 0.15
    static let basketRetractDuration: TimeInterval = 0.3

    static let basketEntryDuration: TimeInterval =
        basketOvershootDuration + basketSettleDuration

    /// Total time the basket occupies the corner, entry through retraction.
    static let basketLifetime: TimeInterval =
        basketEntryDuration
            + basketHoldDuration
            + basketSquashDuration
            + basketRetractDuration
}

/// Timing curves the flight is built from.
///
/// The flight clock runs linearly and every keyframe value is derived from it
/// here, so the curve is exactly what ships rather than whatever spline SwiftUI
/// would fit between sparse keyframes.
enum DownloadFlyCurve {
    /// Warps the linear flight clock before any keyframe value is read.
    static func flightProgress(atTime time: CGFloat) -> CGFloat {
        unitBezier(clamped(time), 0.37, 0, 0.63, 1)
    }

    static func easeInOutQuad(_ time: CGFloat) -> CGFloat {
        let time = clamped(time)
        return time < 0.5 ? 2 * time * time : -1 + (4 - 2 * time) * time
    }

    /// Solves a CSS-style `cubic-bezier(x1, y1, x2, y2)` for the given x.
    static func unitBezier(
        _ x: CGFloat,
        _ x1: CGFloat,
        _ y1: CGFloat,
        _ x2: CGFloat,
        _ y2: CGFloat
    ) -> CGFloat {
        let cx = 3 * x1
        let bx = 3 * (x2 - x1) - cx
        let ax = 1 - cx - bx
        let cy = 3 * y1
        let by = 3 * (y2 - y1) - cy
        let ay = 1 - cy - by

        func sampleX(_ t: CGFloat) -> CGFloat { ((ax * t + bx) * t + cx) * t }
        func sampleY(_ t: CGFloat) -> CGFloat { ((ay * t + by) * t + cy) * t }
        func sampleDerivativeX(_ t: CGFloat) -> CGFloat { (3 * ax * t + 2 * bx) * t + cx }

        let x = clamped(x)
        let epsilon: CGFloat = 1e-6

        var t = x
        for _ in 0..<8 {
            let error = sampleX(t) - x
            if abs(error) < epsilon { return sampleY(t) }
            let derivative = sampleDerivativeX(t)
            if abs(derivative) < epsilon { break }
            t -= error / derivative
        }

        var low: CGFloat = 0
        var high: CGFloat = 1
        t = x
        while low < high {
            let sampled = sampleX(t)
            if abs(sampled - x) < epsilon { return sampleY(t) }
            if x > sampled { low = t } else { high = t }
            let next = (high + low) / 2
            if abs(next - t) < epsilon { break }
            t = next
        }
        return sampleY(t)
    }

    private static func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }
}

/// One sampled instant of a flight.
struct DownloadFlyFrame: Equatable {
    let position: CGPoint
    let scale: CGFloat
    let opacity: CGFloat
}

/// The parabola a downloaded file's icon travels along, expressed in SwiftUI
/// canvas coordinates (origin top-left, y growing downwards).
struct DownloadFlyArc: Equatable {
    /// Arc height relative to the straight-line distance between the endpoints.
    static let heightRatio: CGFloat = 0.8
    static let maximumHeight: CGFloat = 1200
    /// Share of the free space on the chosen side the arc is allowed to use.
    static let availableSpaceRatio: CGFloat = 0.8

    static let launchScale: CGFloat = 0.5
    static let apexScale: CGFloat = 1.8
    static let landingScale: CGFloat = 0.45

    let start: CGPoint
    let end: CGPoint
    let height: CGFloat
    /// `+1` bows the arc towards the bottom of the canvas, `-1` towards the top.
    let direction: CGFloat

    init(start: CGPoint, end: CGPoint, canvasHeight: CGFloat) {
        self.start = start
        self.end = end

        let distance = hypot(end.x - start.x, end.y - start.y)
        let spaceAbove = min(start.y, end.y)
        let spaceBelow = max(canvasHeight - max(start.y, end.y), 0)
        let bowsDownwards = spaceBelow > spaceAbove
        let availableSpace = bowsDownwards ? spaceBelow : spaceAbove

        direction = bowsDownwards ? 1 : -1
        height = max(
            min(
                distance * Self.heightRatio,
                Self.maximumHeight,
                availableSpace * Self.availableSpaceRatio
            ),
            0
        )
    }

    func frame(atTime time: CGFloat) -> DownloadFlyFrame {
        let progress = DownloadFlyCurve.flightProgress(atTime: time)
        let eased = DownloadFlyCurve.easeInOutQuad(progress)
        let bow = 1 - pow(2 * eased - 1, 2)

        return DownloadFlyFrame(
            position: CGPoint(
                x: start.x + (end.x - start.x) * eased,
                y: start.y + (end.y - start.y) * eased + direction * height * bow
            ),
            scale: Self.scale(atProgress: progress),
            opacity: Self.opacity(atProgress: progress)
        )
    }

    /// Swells to `apexScale` at the top of the arc, then shrinks into the target.
    static func scale(atProgress progress: CGFloat) -> CGFloat {
        progress < 0.5
            ? launchScale + (progress / 0.5) * (apexScale - launchScale)
            : apexScale - ((progress - 0.5) / 0.5) * (apexScale - landingScale)
    }

    static func opacity(atProgress progress: CGFloat) -> CGFloat {
        let raw: CGFloat
        if progress < 0.3 {
            raw = 0.3 + (progress / 0.3) * 0.6
        } else if progress < 0.98 {
            raw = 0.9 + ((progress - 0.3) / 0.6) * 0.1
        } else {
            // Deliberate step down rather than a continuation of the ramp: the
            // glyph snaps out on contact so the landing reads as an arrival
            // instead of a slow dissolve.
            raw = 1 - (progress - 0.9) / 0.1
        }
        return min(max(raw, 0), 1)
    }
}

/// Where the corner basket sits during each stage of its appearance.
enum DownloadFlyBasketPhase: Equatable, CaseIterable {
    /// Off screen, past the window edge.
    case parked
    /// Slid in past its resting spot.
    case overshoot
    /// At rest, waiting to receive the flight.
    case settled
    /// Compressed just before retracting.
    case squashed
}

struct DownloadFlyBasketMetrics: Equatable {
    /// Distance from the resting spot, away from the window edge the basket
    /// belongs to. Negative values sit further inside the window.
    let outwardOffset: CGFloat
    let scale: CGFloat
    let opacity: CGFloat
}

/// Entry, rest and exit motion for the corner basket.
enum DownloadFlyBasketMotion {
    static func metrics(
        for phase: DownloadFlyBasketPhase,
        reducesMotion: Bool
    ) -> DownloadFlyBasketMetrics {
        let metrics = standardMetrics(for: phase)
        guard reducesMotion else { return metrics }
        return DownloadFlyBasketMetrics(
            outwardOffset: 0,
            scale: 1,
            opacity: metrics.opacity
        )
    }

    /// Signed horizontal offset for a phase, given which edge the basket hugs.
    static func offset(
        for phase: DownloadFlyBasketPhase,
        sidebarPosition: SidebarPosition,
        reducesMotion: Bool
    ) -> CGFloat {
        let outwardSign: CGFloat = sidebarPosition == .left ? -1 : 1
        return metrics(for: phase, reducesMotion: reducesMotion).outwardOffset * outwardSign
    }

    static func animation(
        enteringPhase phase: DownloadFlyBasketPhase,
        reducesMotion: Bool
    ) -> Animation? {
        guard !reducesMotion else {
            return .easeInOut(duration: DownloadFlyTiming.basketSettleDuration)
        }
        switch phase {
        case .parked:
            return .timingCurve(
                0.5,
                0,
                0.75,
                0,
                duration: DownloadFlyTiming.basketRetractDuration
            )
        case .overshoot:
            return .easeOut(duration: DownloadFlyTiming.basketOvershootDuration)
        case .settled:
            return .easeInOut(duration: DownloadFlyTiming.basketSettleDuration)
        case .squashed:
            return .easeIn(duration: DownloadFlyTiming.basketSquashDuration)
        }
    }

    private static func standardMetrics(
        for phase: DownloadFlyBasketPhase
    ) -> DownloadFlyBasketMetrics {
        switch phase {
        case .parked:
            return DownloadFlyBasketMetrics(outwardOffset: 74, scale: 0.8, opacity: 0)
        case .overshoot:
            return DownloadFlyBasketMetrics(outwardOffset: -10, scale: 1.1, opacity: 1)
        case .settled:
            return DownloadFlyBasketMetrics(outwardOffset: 0, scale: 1, opacity: 1)
        case .squashed:
            return DownloadFlyBasketMetrics(outwardOffset: 0, scale: 0.9, opacity: 1)
        }
    }
}

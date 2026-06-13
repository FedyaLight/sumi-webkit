//
//  SidebarTabFaviconView.swift
//  Sumi
//
//  Aligns template SF Symbol tab icons (new tab globe, settings/history symbols) with
//  `NavButtonStyle` / top bar navigation controls (`ChromeThemeTokens.primaryText`).
//

import SwiftUI

struct SidebarTabFaviconView: View {
    @ObservedObject var tab: Tab
    var size: CGFloat
    var cornerRadius: CGFloat = 6

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    private var tokens: ChromeThemeTokens {
        themeContext.tokens(settings: sumiSettings)
    }

    /// Fresh `Image(systemName:)` so SF Symbol rendering mode is not "baked in" from `Tab.favicon` storage.
    private var chromeSystemImageName: String {
        if tab.representsSumiSettingsSurface {
            return SumiSurface.settingsTabFaviconSystemImageName
        }
        if tab.representsSumiHistorySurface {
            return SumiSurface.historyTabFaviconSystemImageName
        }
        if tab.representsSumiBookmarksSurface {
            return SumiSurface.bookmarksTabFaviconSystemImageName
        }
        return "globe"
    }

    var body: some View {
        Group {
            if tab.usesChromeThemedTemplateFavicon {
                Image(systemName: chromeSystemImageName)
                    .font(.system(size: size * 0.78, weight: .medium))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(tokens.primaryText)
                    .frame(width: size, height: size)
            } else {
                tab.favicon
                    .frame(width: size, height: size)
            }
        }
    }
}

struct SidebarUnloadedRegularTabFaviconFrame<Icon: View>: View {
    let size: CGFloat
    let cornerRadius: CGFloat
    private let icon: () -> Icon

    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext

    init(
        size: CGFloat,
        cornerRadius: CGFloat,
        @ViewBuilder icon: @escaping () -> Icon
    ) {
        self.size = size
        self.cornerRadius = cornerRadius
        self.icon = icon
    }

    var body: some View {
        let lineWidth = outlineLineWidth
        let outlineSize = size + outlineGap * 2
        let outlineCornerRadius = cornerRadius + outlineGap
        icon()
            .saturation(0.0)
            .opacity(0.8)
            .frame(width: size, height: size)
            .overlay {
                ZStack {
                    SidebarUnloadedRegularTabFaviconOutlineSide(
                        side: .left,
                        cornerRadius: outlineCornerRadius,
                        inset: lineWidth / 2
                    )
                    .stroke(
                        outlineColor,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                    )

                    SidebarUnloadedRegularTabFaviconOutlineSide(
                        side: .right,
                        cornerRadius: outlineCornerRadius,
                        inset: lineWidth / 2
                    )
                    .stroke(
                        outlineColor,
                        style: StrokeStyle(
                            lineWidth: lineWidth,
                            lineCap: .round,
                            lineJoin: .round,
                            dash: [max(2.6, size * 0.16), max(2.0, size * 0.12)]
                        )
                    )
                }
                .frame(width: outlineSize, height: outlineSize)
                .allowsHitTesting(false)
            }
    }

    private var outlineGap: CGFloat {
        max(2, size * 0.13)
    }

    private var outlineLineWidth: CGFloat {
        max(1.35, size * 0.075)
    }

    private var outlineColor: Color {
        themeContext.tokens(settings: sumiSettings).secondaryText.opacity(0.72)
    }
}

private struct SidebarUnloadedRegularTabFaviconOutlineSide: Shape {
    enum Side {
        case left
        case right
    }

    let side: Side
    let cornerRadius: CGFloat
    let inset: CGFloat

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: inset, dy: inset)
        let radius = min(max(cornerRadius - inset, 0), rect.width / 2, rect.height / 2)
        var path = Path()

        switch side {
        case .left:
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.minY))
            path.addArc(
                center: CGPoint(x: rect.minX + radius, y: rect.minY + radius),
                radius: radius,
                startAngle: .degrees(-90),
                endAngle: .degrees(-180),
                clockwise: true
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
            path.addArc(
                center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius),
                radius: radius,
                startAngle: .degrees(180),
                endAngle: .degrees(90),
                clockwise: true
            )
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        case .right:
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addArc(
                center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
                radius: radius,
                startAngle: .degrees(-90),
                endAngle: .degrees(0),
                clockwise: false
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
            path.addArc(
                center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius),
                radius: radius,
                startAngle: .degrees(0),
                endAngle: .degrees(90),
                clockwise: false
            )
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        }

        return path
    }
}

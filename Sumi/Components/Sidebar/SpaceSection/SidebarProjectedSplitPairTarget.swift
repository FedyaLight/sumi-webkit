import SumiDomain
import SwiftUI

struct SidebarProjectedSplitPairGeometry: Equatable {
    let previewSide: SplitDropSide
    let companionSize: CGSize

    private var visualHorizontalInset: CGFloat {
        SplitGroupSidebarVisualLayout.outerRowInset
            + SplitGroupSidebarVisualLayout.horizontalInset
    }

    var companionOriginX: CGFloat {
        if previewSide == .left {
            return visualHorizontalInset
                + companionSize.width
                + SplitGroupSidebarVisualLayout.segmentSpacing
        }
        return visualHorizontalInset
    }

    var companionOriginY: CGFloat {
        SplitGroupSidebarVisualLayout.verticalInset
    }

    func showsTitle(_ title: String) -> Bool {
        SplitGroupSidebarVisualLayout.showsTitle(
            title: title,
            segmentWidth: companionSize.width,
            trailingPadding:
                SplitGroupSidebarVisualLayout.standardTrailingPadding
        )
    }
}

struct SidebarProjectedSplitPairTarget<Icon: View>: View {
    let target: SidebarSplitPairingTarget
    let title: String
    @ViewBuilder let icon: () -> Icon

    @Environment(\.sumiSettings) private var settings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.chromeThemeTokens) private var scopedChromeTokens

    @ViewBuilder
    var body: some View {
        if let companionRect {
            let geometry = SidebarProjectedSplitPairGeometry(
                previewSide: target.side,
                companionSize: companionRect.size
            )
            ZStack(alignment: .topLeading) {
                SplitGroupSegmentLabel(
                    title: title,
                    showsTitle: geometry.showsTitle(title),
                    trailingPadding:
                        SplitGroupSidebarVisualLayout.standardTrailingPadding,
                    textColor: tokens.primaryText
                ) {
                    icon()
                }
                .frame(
                    width: companionRect.width,
                    height: companionRect.height
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius:
                            SplitGroupSidebarVisualLayout.segmentCornerRadius,
                        style: .continuous
                    )
                )
                .offset(
                    x: geometry.companionOriginX,
                    y: geometry.companionOriginY
                )
            }
            .frame(
                maxWidth: .infinity,
                minHeight: SidebarRowLayout.rowHeight,
                maxHeight: SidebarRowLayout.rowHeight,
                alignment: .topLeading
            )
            .clipped()
        } else {
            EmptyView()
        }
    }

    private var companionRect: CGRect? {
        guard case .projectedPair(let rect) = target.presentation else {
            return nil
        }
        return rect
    }

    private var tokens: ChromeThemeTokens {
        scopedChromeTokens ?? themeContext.tokens(settings: settings)
    }
}

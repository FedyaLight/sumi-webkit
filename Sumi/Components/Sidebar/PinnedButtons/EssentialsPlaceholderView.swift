//
//  EssentialsPlaceholderView.swift
//  Sumi
//

import SwiftUI

/// Fixed metrics for the empty-Essentials placeholder.
///
/// The height is a constant rather than intrinsic on purpose: the drop-frame the
/// sidebar reports for the Essentials zone is sized from the layout model, not
/// from a measured frame (`sidebarEssentialsLayoutGeometry`). An intrinsic height
/// would need a geometry read-back and would let the hit region drift away from
/// what the user sees, so the copy is laid out inside a known box instead.
enum EssentialsPlaceholderMetrics {
    static let height: CGFloat = 100
    static let horizontalPadding: CGFloat = 14
    static let badgeSize: CGFloat = 22
    static let badgeGlyphSize: CGFloat = 11
    static let badgeSpacing: CGFloat = 8
    static let titleSpacing: CGFloat = 3
    static let dismissHitSize: CGFloat = 18
    static let dismissInset: CGFloat = 7
    static let strokeWidth: CGFloat = 1
    static let dashPattern: [CGFloat] = [3, 2]
    static let revealAnimationDuration: TimeInterval = 0.18
}

/// Empty-state affordance for the Essentials zone: without it the zone collapses
/// to an invisible strip and nothing tells the user that dragging a tab here is
/// how Essentials get added.
///
/// Every colour comes from `ChromeThemeTokens`, which is already resolved against
/// the space theme's lightness and already cross-fades on space switches — so the
/// placeholder follows the theme with no colour math of its own at render time.
/// Deliberately flat: one stroked shape, no material, blur, shadow, or
/// compositing group, since this sits directly on the sidebar's gradient.
struct EssentialsPlaceholderView: View {
    let tokens: ChromeThemeTokens
    let cornerRadius: CGFloat
    /// `nil` renders the decorative variant used by the drag-hover reveal and by
    /// space-transition snapshots, where there is nothing to dismiss.
    let onDismiss: (() -> Void)?

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                tokens.separator,
                style: StrokeStyle(
                    lineWidth: EssentialsPlaceholderMetrics.strokeWidth,
                    dash: EssentialsPlaceholderMetrics.dashPattern
                )
            )
            .frame(height: EssentialsPlaceholderMetrics.height)
            .overlay { copy }
            .overlay(alignment: .topTrailing) { dismissButton }
            .accessibilityElement(children: .contain)
    }

    private var copy: some View {
        VStack(spacing: 0) {
            badge

            Text("Drag to add Favorites")
                .font(SidebarThemeTokens.Typography.essentialsPlaceholderTitle)
                .foregroundStyle(tokens.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, EssentialsPlaceholderMetrics.badgeSpacing)

            Text("Favorites keep your most used sites and apps close")
                .font(SidebarThemeTokens.Typography.essentialsPlaceholderSubtitle)
                .foregroundStyle(tokens.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .padding(.top, EssentialsPlaceholderMetrics.titleSpacing)
        }
        .padding(.horizontal, EssentialsPlaceholderMetrics.horizontalPadding)
        .allowsHitTesting(false)
    }

    private var badge: some View {
        Circle()
            .fill(tokens.buttonPrimaryBackground)
            .frame(
                width: EssentialsPlaceholderMetrics.badgeSize,
                height: EssentialsPlaceholderMetrics.badgeSize
            )
            .overlay {
                Image(systemName: "star.fill")
                    .font(.system(size: EssentialsPlaceholderMetrics.badgeGlyphSize, weight: .semibold))
                    .foregroundStyle(tokens.buttonPrimaryText)
            }
    }

    @ViewBuilder
    private var dismissButton: some View {
        if let onDismiss {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(SidebarThemeTokens.Typography.essentialsPlaceholderDismiss)
                    .foregroundStyle(tokens.secondaryText)
                    .frame(
                        width: EssentialsPlaceholderMetrics.dismissHitSize,
                        height: EssentialsPlaceholderMetrics.dismissHitSize
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(EssentialsPlaceholderMetrics.dismissInset)
            .accessibilityLabel("Hide the Favorites hint")
        }
    }
}

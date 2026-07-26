//
//  SplitGroupRowPresentation.swift
//  Sumi
//

import AppKit
import SwiftUI

/// Canonical appearance shared by live, transition, and drag split rows.
///
/// Callers supply member content and interaction. This renderer owns the
/// geometry and material rules that must not drift between surfaces.
enum SplitGroupRowMaterial: Equatable {
    case settled(isSelected: Bool)
    case dragCarrier

    var drawsPillMaterial: Bool {
        switch self {
        case .settled(let isSelected):
            return isSelected
        case .dragCarrier:
            return true
        }
    }

    var drawsSeparators: Bool {
        switch self {
        case .settled(let isSelected):
            return !isSelected
        case .dragCarrier:
            return false
        }
    }
}

struct SplitGroupRowSegmentMetrics: Equatable {
    let rowSize: CGSize
    let width: CGFloat
    let leadingOffset: CGFloat

    func showsTitle(
        _ title: String,
        trailingPadding: CGFloat
    ) -> Bool {
        SplitGroupSidebarVisualLayout.showsTitle(
            title: title,
            segmentWidth: width,
            trailingPadding: trailingPadding
        )
    }
}

struct SplitGroupSegmentedRow<Slot: Identifiable, Segment: View>: View {
    let slots: [Slot]
    let material: SplitGroupRowMaterial
    let tokens: ChromeThemeTokens
    let departingIDs: Set<Slot.ID>
    @ViewBuilder let segment: (
        Int,
        Slot,
        SplitGroupRowSegmentMetrics
    ) -> Segment

    var body: some View {
        GeometryReader { geometry in
            let activeCount = max(
                slots.count { !departingIDs.contains($0.id) },
                1
            )
            let segmentWidth = SplitGroupSidebarVisualLayout.segmentWidth(
                rowWidth: geometry.size.width,
                segmentCount: activeCount
            )

            HStack(spacing: SplitGroupSidebarVisualLayout.segmentSpacing) {
                ForEach(
                    Array(slots.enumerated()),
                    id: \.element.id
                ) { index, slot in
                    let isSlotDeparting = departingIDs.contains(slot.id)
                    let metrics = SplitGroupRowSegmentMetrics(
                        rowSize: geometry.size,
                        width: segmentWidth,
                        leadingOffset:
                            SplitGroupSidebarVisualLayout.horizontalInset
                            + CGFloat(
                                slots[..<index].count {
                                    !departingIDs.contains($0.id)
                                }
                            ) * (
                                segmentWidth
                                + SplitGroupSidebarVisualLayout.segmentSpacing
                            )
                    )

                    segment(index, slot, metrics)
                        .frame(width: isSlotDeparting ? 0 : segmentWidth)
                        .background(
                            material.drawsPillMaterial
                                ? tokens.fieldBackground
                                : Color.clear
                        )
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius:
                                    SplitGroupSidebarVisualLayout.segmentCornerRadius,
                                style: .continuous
                            )
                        )
                        .clipped()
                        .overlay(alignment: .trailing) {
                            if material.drawsSeparators,
                               !isSlotDeparting,
                               slots[(index + 1)...].contains(
                                   where: {
                                       !departingIDs.contains($0.id)
                                   }
                               ) {
                                Rectangle()
                                    .fill(tokens.separator.opacity(0.7))
                                    .frame(width: 1, height: 16)
                                    .offset(
                                        x: (
                                            SplitGroupSidebarVisualLayout.segmentSpacing
                                            + 1
                                        ) / 2
                                    )
                            }
                        }
                }
            }
            .padding(
                .horizontal,
                SplitGroupSidebarVisualLayout.horizontalInset
            )
            .padding(.vertical, SplitGroupSidebarVisualLayout.verticalInset)
        }
    }
}

enum SplitGroupRowIcon {
    case image(Image)
    case system(String)
    case emoji(String)
}

struct SplitGroupRowIconView: View {
    let icon: SplitGroupRowIcon
    let foregroundColor: Color
    var desaturates = false

    var body: some View {
        ZStack {
            switch icon {
            case .image(let image):
                image
                    .resizable()
                    .scaledToFit()
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 4,
                            style: .continuous
                        )
                    )
            case .system(let systemName):
                Image(systemName: systemName)
                    .font(.system(size: 15, weight: .medium))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(foregroundColor)
            case .emoji(let emoji):
                Text(emoji)
                    .font(.system(size: 16))
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
            }
        }
        .frame(
            width: SplitGroupSidebarVisualLayout.iconWidth,
            height: SplitGroupSidebarVisualLayout.iconWidth
        )
        .saturation(desaturates ? 0 : 1)
        .opacity(desaturates ? 0.8 : 1)
    }
}

struct SplitGroupSegmentLabel<Icon: View>: View {
    let title: String
    var showsTitle = true
    let trailingPadding: CGFloat
    let textColor: Color
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        HStack(spacing: SplitGroupSidebarVisualLayout.iconTitleSpacing) {
            icon()
            if showsTitle {
                SumiTabTitleLabel(
                    title: title,
                    font: SidebarThemeTokens.Typography.rowTitle,
                    textColor: textColor
                )
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.leading, SplitGroupSidebarVisualLayout.labelLeadingInset)
        .padding(.trailing, trailingPadding)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}

enum SplitGroupSidebarVisualLayout {
    static let outerRowInset: CGFloat = 2
    static let horizontalInset: CGFloat = 3
    static let verticalInset: CGFloat = 4
    static let segmentSpacing: CGFloat = 3
    static let segmentCornerRadius: CGFloat = 9
    /// The outer row and pill insets plus this value equal the canonical
    /// sidebar-row leading edge.
    static let labelLeadingInset: CGFloat = 7
    static let customIconLeadingInset =
        SidebarRowLayout.leadingInset - outerRowInset
    static let iconWidth: CGFloat = SidebarRowLayout.faviconSize
    static let iconTitleSpacing: CGFloat = 6
    static let standardTrailingPadding: CGFloat = 7

    static func segmentWidth(
        rowWidth: CGFloat,
        segmentCount: Int
    ) -> CGFloat {
        let count = max(segmentCount, 1)
        return max(
            0,
            (
                rowWidth
                - horizontalInset * 2
                - CGFloat(count - 1) * segmentSpacing
            ) / CGFloat(count)
        )
    }

    static func trailingPadding(
        hasMemberAction: Bool,
        showsMemberAction: Bool,
        isLastVisibleItem: Bool,
        groupActionTrailingPadding: CGFloat
    ) -> CGFloat {
        if hasMemberAction, showsMemberAction {
            return SidebarRowLayout.trailingActionPadding
        }
        if isLastVisibleItem, groupActionTrailingPadding > 0 {
            return groupActionTrailingPadding
        }
        return standardTrailingPadding
    }

    static func showsTitle(
        title: String,
        segmentWidth: CGFloat,
        trailingPadding: CGFloat
    ) -> Bool {
        guard !title.isEmpty else { return false }
        return segmentWidth
            - labelLeadingInset
            - iconWidth
            - iconTitleSpacing
            - trailingPadding
            >= minimumMeaningfulTitleWidth(for: title)
    }

    private static func minimumMeaningfulTitleWidth(
        for title: String
    ) -> CGFloat {
        let firstGrapheme = String(title.prefix(1))
        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        return ceil(
            ((firstGrapheme + "…") as NSString).size(
                withAttributes: [.font: font]
            ).width
        )
    }
}

//
//  SidebarNewTabRowLabel.swift
//  Sumi
//

import SwiftUI

/// Leading content for the in-list "New Tab" row, shared by the live row and the
/// transition snapshot so their type and geometry can't drift. Mirrors the
/// regular tab row (`SpaceTab`): the "+" sits in the favicon column
/// (leadingInset + an 18pt slot) and "New Tab" starts where tab titles do — the
/// same x as folder titles. Type is `Typography.newTabRow`, which matches
/// `folderTitle` (Zen parity).
struct SidebarNewTabRowLabel: View {
    /// Zen parity: the new-tab label is dimmed relative to the other rows
    /// (`#tabs-newtab-button:not([in-urlbar="true"]) label { opacity: 0.7 }`).
    /// Zen's rule targets only the label element, so the "+" keeps full opacity,
    /// and there is no hover override.
    private static let labelOpacity: Double = 0.7

    let tokens: ChromeThemeTokens

    var body: some View {
        HStack(spacing: SidebarRowLayout.iconTrailingSpacing) {
            Image(systemName: "plus")
                .font(SidebarThemeTokens.Typography.newTabRow)
                .frame(
                    width: SidebarRowLayout.faviconSize,
                    height: SidebarRowLayout.faviconSize
                )
                .accessibilityHidden(true)
            Text("New Tab")
                .font(SidebarThemeTokens.Typography.newTabRow)
                .opacity(Self.labelOpacity)
            Spacer(minLength: 0)
        }
        .foregroundStyle(tokens.primaryText)
        .padding(.leading, SidebarRowLayout.leadingInset)
        .padding(.trailing, SidebarRowLayout.trailingInset)
    }
}

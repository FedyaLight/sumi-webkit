//
//  SpaceSidebarEmptySpacesView.swift
//  SumiSidebarChrome
//
//  First real chrome peel: empty-spaces placeholder for the sidebar page area.
//  Depends on tokens + SwiftUI only — no BrowserManager / TabManager.
//

import SumiChromeTokens
import SwiftUI

/// Empty-spaces placeholder for the sidebar page area.
public struct SpaceSidebarEmptySpacesView: View {
    private let onCreateSpace: () -> Void

    public init(onCreateSpace: @escaping () -> Void) {
        self.onCreateSpace = onCreateSpace
    }

    public var body: some View {
        VStack(spacing: ChromeLayoutTokens.sidebarEmptyStateStackSpacing) {
            Image(systemName: "plus.circle")
                .font(.system(size: ChromeLayoutTokens.sidebarEmptyStateIconPointSize))
                .foregroundColor(.secondary)
            VStack(spacing: ChromeLayoutTokens.sidebarEmptyStateTextSpacing) {
                Text("No Spaces")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Create a space to start browsing")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            Button(action: onCreateSpace) {
                Label("Create Space", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

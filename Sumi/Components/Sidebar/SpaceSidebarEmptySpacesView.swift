//
//  SpaceSidebarEmptySpacesView.swift
//  Sumi
//
//  Empty-spaces placeholder for the sidebar page area.
//

import SwiftUI

/// Empty-spaces placeholder for the sidebar page area.
struct SpaceSidebarEmptySpacesView: View {
    private let onCreateSpace: () -> Void

    init(onCreateSpace: @escaping () -> Void) {
        self.onCreateSpace = onCreateSpace
    }

    var body: some View {
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

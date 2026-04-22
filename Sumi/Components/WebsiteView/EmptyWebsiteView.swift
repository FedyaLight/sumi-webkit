//
//  EmptyWebsiteView.swift
//  Sumi
//
//  Created by Maciek Bagiński on 28/07/2025.
//

import SwiftUI

struct EmptyWebsiteView: View {
    private var cornerRadius: CGFloat {
        if #available(macOS 26.0, *) {
            return 12
        } else {
            return 6
        }
    }

    var body: some View {
        Color(nsColor: .windowBackgroundColor)
            .opacity(0.2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 0)
            .accessibilityHidden(true)
    }
}

//
//  EmptyWebsiteView.swift
//  Sumi
//
//

import SwiftUI

struct EmptyWebsiteView: View {
    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
    }
}

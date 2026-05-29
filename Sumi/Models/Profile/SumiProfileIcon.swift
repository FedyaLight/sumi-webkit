//
//  SumiProfileIcon.swift
//  Sumi
//
//  Profile icons are stored and rendered as emoji. They do not share the
//  generic SF Symbol validation path used by spaces and launchers.
//

import Foundation
import SwiftUI

enum SumiProfileIcon {
    static let defaultIcon = "🏠"
    static let incognitoIcon = "🕶️"

    static func storedValue(_ icon: String) -> String {
        icon.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct SumiProfileIconView: View {
    let icon: String
    var font: Font = .body

    var body: some View {
        Text(SumiProfileIcon.storedValue(icon))
            .font(font)
    }
}

struct SumiProfileMenuLabel: View {
    let name: String
    let icon: String

    var body: some View {
        Label {
            Text(name)
        } icon: {
            Text(SumiProfileIcon.storedValue(icon))
        }
    }
}

// atelier-core @aeastr

import SwiftUI

extension View {
    @ViewBuilder
    func conditionally<Content: View>(
        if condition: @autoclosure () -> Bool,
        @ViewBuilder apply modifier: (Self) -> Content
    ) -> some View {
        if condition() {
            modifier(self)
        } else {
            self
        }
    }
}

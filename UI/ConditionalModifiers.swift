// atelier-core @aeastr

import SwiftUI

/// A view extension that provides clean conditional modifier application based on OS availability.
public extension View {
    /// Conditionally applies a modifier only if the current OS version supports it.
    ///
    /// - Parameters:
    ///   - condition: A boolean expression that determines if the modifier should be applied.
    ///                Uses `@autoclosure` so you can pass expressions directly without wrapping in `{ }`.
    ///   - modifier: The modifier to apply when the condition is met
    /// - Returns: The view with the modifier applied conditionally
    ///
    /// The `@autoclosure` parameter allows clean syntax for boolean expressions. The expression
    /// is automatically wrapped in a closure and only evaluated when needed, providing lazy evaluation.
    ///
    /// Example:
    /// ```swift
    /// Text("Hello")
    ///     .conditionally(if: someCondition) { view in
    ///         view.padding(.large)
    ///     }
    /// ```
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

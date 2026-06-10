#if os(iOS)
import SwiftUI

public extension View {

    /// Presents a custom input view in place of the system keyboard while
    /// `isPresented` is `true`.
    ///
    /// The panel slides up with the standard keyboard animation and
    /// participates in keyboard avoidance. Any external dismissal — an
    /// interactive scroll dismissal, `endEditing`, another field taking
    /// focus — is reflected back into `isPresented`.
    ///
    /// ```swift
    /// @State private var isEditing = false
    ///
    /// Text(amount, format: .currency(code: "UAH"))
    ///     .inputView(isPresented: $isEditing) {
    ///         CalculatorPad(value: $amount)
    ///     }
    /// ```
    ///
    /// - Parameters:
    ///   - isPresented: Controls and reflects whether the panel is presented.
    ///   - content: The panel's SwiftUI content. It receives the full
    ///     environment of this view, keeps its state across show/hide
    ///     cycles, and the panel adopts its ideal height.
    func inputView<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        inputViewProxy(focus: .bool(isPresented), content: content)
    }

    /// Presents a custom input view while `selection` matches `value`.
    ///
    /// Assigning a different value moves input focus to that field without
    /// dismissing the panel; assigning `nil` dismisses it. Mirrors
    /// `focused(_:equals:)`:
    ///
    /// ```swift
    /// enum Field { case amount, tip }
    /// @State private var focus: Field?
    ///
    /// Text(amount)
    ///     .inputView($focus, equals: .amount) {
    ///         CalcPad(value: $amount) { focus = .tip }   // next →
    ///     }
    /// Text(tip)
    ///     .inputView($focus, equals: .tip) {
    ///         CalcPad(value: $tip) { focus = nil }       // done
    ///     }
    /// ```
    ///
    /// - Parameters:
    ///   - selection: The currently focused field, or `nil` for none.
    ///   - value: The value identifying this field.
    ///   - content: The panel's SwiftUI content (see `inputView(isPresented:content:)`).
    func inputView<Value: Hashable, Content: View>(
        _ selection: Binding<Value?>,
        equals value: Value,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        inputViewProxy(focus: .value(selection, equals: value), content: content)
    }
}
#endif

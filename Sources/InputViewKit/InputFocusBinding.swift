#if os(iOS)
import SwiftUI

/// Normalizes the two public focus APIs (`Bool` and value + `equals:`)
/// into one shape the UIKit layer can drive.
@MainActor
struct InputFocusBinding {

    /// Whether this field should currently present its input view.
    let isActive: () -> Bool

    /// Clears the binding — but only if it still points at this field.
    /// Guard rationale: when focus moves A→B, the system delivers A's
    /// `resignFirstResponder` *after* B has claimed the binding; A must
    /// not wipe the value B just wrote.
    let deactivate: () -> Void

    static func bool(_ binding: Binding<Bool>) -> InputFocusBinding {
        InputFocusBinding(
            isActive: { binding.wrappedValue },
            deactivate: {
                if binding.wrappedValue { binding.wrappedValue = false }
            }
        )
    }

    static func value<Value: Hashable>(
        _ binding: Binding<Value?>,
        equals value: Value
    ) -> InputFocusBinding {
        InputFocusBinding(
            isActive: { binding.wrappedValue == value },
            deactivate: {
                if binding.wrappedValue == value { binding.wrappedValue = nil }
            }
        )
    }
}
#endif

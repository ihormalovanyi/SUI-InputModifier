#if os(iOS)
import SwiftUI

extension View {
    /// Shared wiring for both public overloads: an invisible 0×0 proxy in
    /// the background carrying the input view, hidden from interaction,
    /// layout and accessibility.
    func inputViewProxy<Content: View>(
        focus: InputFocusBinding,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        background(
            ProxyInputRepresentable(focus: focus, content: content)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)   // belt-and-suspenders; the UIView also sets isUserInteractionEnabled = false
                .accessibilityHidden(true)
        )
    }
}
#endif

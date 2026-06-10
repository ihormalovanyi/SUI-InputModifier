#if os(iOS)
import SwiftUI

/// Root view hosted inside the input panel's `UIHostingController`.
///
/// Forwards the host view's complete `EnvironmentValues` (including
/// environment objects) into the separately-hosted panel, and reports the
/// content's ideal height so the `UIInputView` wrapper can self-size.
struct InputHostRoot<Content: View>: View {
    var environment: EnvironmentValues
    var content: Content
    var onHeightChange: (CGFloat) -> Void

    var body: some View {
        content
            .environment(\.self, environment)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                onHeightChange(height)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
#endif

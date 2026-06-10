#if os(iOS)
import UIKit

/// `UIInputView` wrapper that adopts its content's ideal height and
/// live-resizes while presented.
///
/// The recipe below is verified empirically (iOS 26.5, 2026-06-10 — see the
/// design spec). All four parts are required:
/// 1. `allowsSelfSizing = true`
/// 2. `translatesAutoresizingMaskIntoConstraints = false` — without this the
///    panel freezes at its presentation height forever
/// 3. height supplied via `intrinsicContentSize` (a pinned autolayout chain
///    alone collapses the panel to zero height)
/// 4. on change: `invalidateIntrinsicContentSize()` and the owner calls
///    `reloadInputViews()` on the responder
final class SelfSizingInputView: UIInputView {

    /// Called after the intrinsic size is invalidated; the owner responds by
    /// calling `reloadInputViews()` on the proxy responder.
    var onSizeShouldReload: (() -> Void)?

    private var idealContentHeight: CGFloat = 0

    init() {
        super.init(frame: .zero, inputViewStyle: .keyboard)
        allowsSelfSizing = true
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setIdealContentHeight(_ height: CGFloat) {
        let height = max(0, height)
        guard height != idealContentHeight else { return }
        idealContentHeight = height
        invalidateIntrinsicContentSize()
        // SAFETY: reloadInputViews() may re-enter layout. The same-value guard
        // above breaks the cycle: a reload cannot synchronously produce a new
        // distinct ideal height for unchanged content.
        onSizeShouldReload?()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric,
               height: idealContentHeight + safeAreaInsets.bottom)
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        invalidateIntrinsicContentSize()
        onSizeShouldReload?()
    }
}
#endif

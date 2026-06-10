#if os(iOS)
import UIKit

/// Invisible 0×0 responder that carries the custom input view.
///
/// A plain `UIView` (not a text field) on purpose: no autofill heuristics,
/// no iPad shortcut bar, nothing announced to accessibility. Any
/// `UIResponder` may provide an `inputView` — that is the whole mechanism.
final class ProxyInputView: UIView {

    /// The self-sizing wrapper presented in place of the keyboard.
    var hostedInputView: UIView?

    /// Fired when the system dismisses the panel from outside
    /// (interactive dismissal, `endEditing`, another responder taking over).
    /// Not fired for binding-driven dismissals.
    /// May be invoked synchronously from within UIKit view teardown
    /// (e.g. `removeFromSuperview`) — owners must clear desired focus and
    /// this callback in `dismantleUIView` before the view is removed.
    var onResignedExternally: (() -> Void)?

    private var desiredFirstResponder = false
    private var applyScheduled = false

    override var canBecomeFirstResponder: Bool { true }
    override var inputView: UIView? { hostedInputView }

    /// Stores the desired focus state and applies it asynchronously.
    /// Coalesced: a burst of SwiftUI updates produces one application.
    /// Window-aware: applied in `didMoveToWindow` if not attached yet.
    ///
    /// Deliberately schedules even when the value is unchanged: every
    /// SwiftUI update is an organic retry for a `becomeFirstResponder`
    /// that failed earlier (inactive scene, non-key window). Do not add
    /// a value-diff guard here — it would create a stuck state.
    func setDesiredFocus(_ focused: Bool) {
        desiredFirstResponder = focused
        scheduleApply()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        scheduleApply()
    }

    @discardableResult
    override func resignFirstResponder() -> Bool {
        let wasFirstResponder = isFirstResponder
        let resigned = super.resignFirstResponder()
        if resigned, wasFirstResponder, desiredFirstResponder {
            // The system resigned us while the binding still wants focus:
            // an external dismissal. Sync it back.
            desiredFirstResponder = false
            onResignedExternally?()
        }
        return resigned
    }

    private func scheduleApply() {
        guard !applyScheduled else { return }
        applyScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.applyScheduled = false
            self.applyDesiredFocus()
        }
    }

    private func applyDesiredFocus() {
        guard window != nil else { return }
        if desiredFirstResponder, !isFirstResponder {
            becomeFirstResponder()
        } else if !desiredFirstResponder, isFirstResponder {
            resignFirstResponder()
        }
    }
}
#endif

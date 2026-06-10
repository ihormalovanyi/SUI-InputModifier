# How It Works

Public API only — no private SwiftUI internals.

## The proxy responder

`inputView` is a `UIResponder` feature: any responder can provide a view to be shown in
place of the keyboard. InputViewKit places an invisible, zero-sized, non-interactive,
accessibility-hidden `UIView` in your view's background. When the binding asks for
presentation, that proxy becomes first responder and the system presents its `inputView`.

It is deliberately *not* a hidden text field: no autofill heuristics, no iPad shortcut
bar, nothing announced to VoiceOver.

## Hosting and sizing

Your panel content lives in a `UIHostingController` whose root view forwards the host's
complete `EnvironmentValues` — which is why `@EnvironmentObject` works inside the panel.
The controller's view is wrapped in a `UIInputView` with the `.keyboard` style, so the
content sits on the system keyboard material, inside the rounded chrome on iOS 26.

Sizing uses the controller's intrinsic-content-size mode plus an
`intrinsicContentSize`-driven wrapper. Height changes invalidate the wrapper's intrinsic
size and reload the input views, so the panel tracks the content's ideal height live.

## Focus synchronization

The proxy stores the *desired* focus state. Application is guarded (no redundant
become/resign), coalesced (one application per update burst), and window-aware (a focus
request made before the view is in a window is applied when it enters one). External
dismissals are detected in `resignFirstResponder` and written back to your binding —
unless the binding already moved to another field.

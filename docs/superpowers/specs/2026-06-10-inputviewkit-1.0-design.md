# InputViewKit 1.0 — Design

- **Date:** 2026-06-10
- **Status:** Approved
- **Repository:** `SUI-InputModifier` (unchanged) · **Module:** `InputViewKit` (renamed from `SUI_InputModifier`)
- **Release target:** tag `1.0.0` after implementation, docs, and example app are complete (tagging deferred by owner decision)

## 1. Context

SwiftUI has no equivalent of UIKit's `UIResponder.inputView` — the mechanism that lets the
system present an arbitrary view in place of the keyboard, with the standard keyboard
animation, keyboard avoidance, and interactive dismissal.

The current package (`0.1-a3`) proves the concept but has issues found in a full review:

- The introspection-based overload (`input(input:anchor:)`) creates a new unretained
  `UIHostingController` on every SwiftUI update, never calls `reloadInputViews()`, has a
  dead `anchor` parameter, and depends on private view hierarchy details.
- The proxy-based overload works but resets panel state on every focus toggle
  (`.id(focused.wrappedValue)` workaround), calls `becomeFirstResponder`/`resignFirstResponder`
  unconditionally on every update (focus stealing), and does not forward the SwiftUI
  environment (`@EnvironmentObject` crashes inside the panel).
- Packaging blocks adoption: non-semver tags, a `branch: "main"` dependency
  (SPM forbids unversioned transitive dependencies for versioned consumers),
  `swift-tools-version: 6.2` (excludes Xcode < 26), committed `xcuserdata`,
  a one-line placeholder README.

**Market position.** The "custom keyboard for a real `TextField`/`TextEditor`" niche is
served by [CustomKeyboardKit](https://github.com/paescebu/CustomKeyboardKit)
(`UITextDocumentProxy` access, submit handler, system feedback). The unserved niche — and
this package's unique value — is **"a custom input panel for *any* view"**: an amount label
that opens a calculator pad, a color field that opens a palette, a rating row that opens a
star picker. 1.0 owns that niche and does nothing else.

## 2. Goals

1. One thing done at Apple quality: `.inputView` for any SwiftUI view, built only on
   public API.
2. API shaped like SwiftUI itself (mirrors the `.focused(_:)` / `.focused(_:equals:)` pair).
3. Full SwiftUI environment propagation into the panel (including `@EnvironmentObject`).
4. Deterministic two-way focus synchronization with no flakiness.
5. DocC documentation, an example app, behavior tests, and CI good enough to trust at 1.0.

## 3. Non-goals (deliberately out of 1.0)

- **Introspection overload** (custom keyboard for native `TextField`) — dropped; docs point
  to CustomKeyboardKit for that use case. May return in 1.x as a separate opt-in product
  if user demand appears.
- **`anchor` parameter** — removed. Its only effect was an incidental interaction with
  UIKit's scroll-to-first-responder machinery; not a designed, testable behavior. A
  deliberate "what stays visible" API can be added in 1.x without a breaking change.
- **`inputAccessoryView` support** — trivially possible with this architecture; deferred to
  keep the 1.0 surface minimal.
- **Style/appearance knobs, custom animations** — the system controls presentation.

## 4. Decisions

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| 1 | 1.0 scope | Proxy pillar only, zero dependencies | Unique niche; only public API; everything shipped is testable |
| 2 | `anchor` | Remove | Incidental, untestable, dead in one overload; removal is free pre-1.0 |
| 3 | Focus API | `Binding<Bool>` + value/`equals:` pair | Apple precedent (`.focused`); enables multi-field forms and next/done |
| 4 | Module name | `InputViewKit` | Clean import; repo name unchanged (ecosystem-normal, cf. `swift-composable-architecture` → `ComposableArchitecture`) |
| 5 | Minimum iOS | 16 | `UIHostingController.sizingOptions = .intrinsicContentSize` makes panel self-sizing reliable without shims |
| 6 | Proxy responder | Plain `UIView` subclass (not `UITextField`) | No text-system side effects (autofill, iPad assistant bar, a11y "text field" announcements); models exactly what the package promises |
| 7 | Tools version | `swift-tools-version: 6.0`, Swift 6 language mode | Xcode 16+ reach; nothing in the code needs 6.2 |

## 5. Public API

The entire public surface — two modifiers:

```swift
import InputViewKit

public extension View {

    /// Presents a custom input view in place of the system keyboard
    /// while `isPresented` is `true`.
    func inputView<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View

    /// Presents a custom input view while `selection` matches `value`.
    /// Assigning a different value moves input focus to that field without
    /// dismissing the panel; assigning `nil` dismisses it.
    func inputView<Value: Hashable, Content: View>(
        _ selection: Binding<Value?>,
        equals value: Value,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View
}
```

Usage shape (also the example-app demo):

```swift
enum Field { case amount, tip }
@State private var focus: Field?

Text(amount, format: .currency(code: "UAH"))
    .inputView($focus, equals: .amount) {
        CalcPad(value: $amount) { focus = .tip }   // next →
    }

Text(tip, format: .percent)
    .inputView($focus, equals: .tip) {
        CalcPad(value: $tip) { focus = nil }        // done
    }
```

## 6. Behavioral contract

These are the documented guarantees (DocC "Guarantees" section):

1. **Presentation.** When the condition becomes true, the panel slides up with the standard
   keyboard animation. Keyboard avoidance, safe-area adjustment, and
   `scrollDismissesKeyboard` work automatically — to the system this *is* the keyboard.
2. **Two-way sync invariant.** Any external dismissal — interactive scroll dismissal,
   `endEditing`, another responder taking focus, scene backgrounding — is reflected back
   into the binding (`false` / `nil`). The binding never lies about the real responder state.
3. **Switching without dismissal.** Reassigning the `equals:` binding from one field to
   another transitions panels without hiding the keyboard window. This is what makes
   next/done navigation possible.
4. **Stable identity.** Panel content keeps its `@State` across show/hide cycles for the
   lifetime of the host view. No `.id()` resets; scroll position and tab selection inside
   the panel survive.
5. **Full environment.** The host view's complete SwiftUI environment is forwarded into the
   panel: `@EnvironmentObject`, `colorScheme`, `locale`, `dynamicTypeSize`, custom keys.
6. **Self-sizing.** Panel height is the SwiftUI ideal height of the content and tracks
   content changes; the bottom safe area (home indicator) is respected.
7. **Documented limits** (DocC "Limitations" article): with a hardware keyboard attached the
   panel does not appear (a UIKit `inputView` limit, not ours); multiple `.inputView`
   modifiers on the same view are unsupported; iPad floating-keyboard behavior is verified
   and documented as found.

## 7. Internal architecture

### Files — `Sources/InputViewKit/`

| File | Responsibility |
|------|----------------|
| `View+InputView.swift` | The two public modifiers + doc comments; thin layer only |
| `InputViewModifier.swift` | Internal `ViewModifier` — shared logic for both overloads |
| `InputFocusBinding.swift` | Normalizes Bool/equals into `isActive` / `activate()` / `deactivate()` |
| `ProxyInputRepresentable.swift` | `UIViewRepresentable` + `Coordinator` (owns the hosting controller) |
| `ProxyInputView.swift` | The `UIView` responder subclass with `inputView` override |
| `EnvironmentForwarding.swift` | Forwards `context.environment` via `.environment(\.self, _)` |

### Mechanics

- **Hosting.** One generic `UIHostingController<Root<Content>>` (no `AnyView`), created in
  `makeUIView`, owned by the `Coordinator`. `sizingOptions = .intrinsicContentSize` for
  self-sizing. `rootView` is updated on every `updateUIView`; SwiftUI diffs, identity is
  stable.
- **Focus engine.** The proxy stores the *desired* focus state. Application is guarded
  (`isFirstResponder` checks — no redundant become/resign), coalesced (a burst of updates
  produces one application), and window-aware (if the view is not yet in a window, the
  pending state is applied in `didMoveToWindow`). This fixes both the
  "keyboard didn't appear on first render" flakiness and the focus stealing present in 0.1.
- **Guarded deactivation.** `resignFirstResponder()` is overridden to sync the binding on
  any external dismissal — but for the `equals:` variant it clears the binding **only if
  the binding still points at this field**. Otherwise A→B switching would break: A's resign
  (which the system delivers after B becomes first responder) would wipe the focus value B
  just claimed. This is the subtlest invariant in the design and has a dedicated test.
- **Teardown.** `dismantleUIView` resigns first responder if active and syncs the binding —
  a view that disappears while presenting cleans up after itself.
- **Panel backdrop — verified empirically (iOS 26.5 simulator, 2026-06-10).** iOS 26
  hosts *any* custom input view inside the system keyboard chrome automatically: both a raw
  `UIView` and a `UIInputView(inputViewStyle: .keyboard)` are clipped to the rounded
  Liquid-Glass keyboard silhouette. A raw view supplies its own background inside that
  shape; `UIInputView(inputViewStyle: .keyboard)` additionally puts the system keyboard
  material behind the content. **Decision:** wrap the hosting view in
  `UIInputView(inputViewStyle: .keyboard)` with `allowsSelfSizing = true` and a clear
  hosting-view background — panel content sits on the system glass exactly like the real
  keyboard; an opaque panel background remains possible by making the content itself
  opaque. Remaining example-app checks: visual pass on a physical device and on iOS 16/17
  where the chrome is the classic square keyboard.
- **Self-sizing — verified empirically (iOS 26.5 simulator, 2026-06-10).** The working
  recipe for a panel that adopts content height *and* live-resizes while presented:
  a `UIInputView` subclass with `allowsSelfSizing = true`,
  `translatesAutoresizingMaskIntoConstraints = false`, height supplied via an
  `intrinsicContentSize` override, and on change `invalidateIntrinsicContentSize()` +
  `reloadInputViews()` on the responder (measured 300 pt → 460 pt live). Two approaches
  verified **not** to work: (a) pinning an autolayout content chain inside the input view —
  collapses to zero height, panel never appears; (b) intrinsic invalidation with
  `translatesAutoresizingMaskIntoConstraints` left `true` — panel stays at presentation
  height even after `reloadInputViews()`. The package wires
  `UIHostingController.sizingOptions = .intrinsicContentSize` invalidations to the wrapper's
  `invalidateIntrinsicContentSize()` + `reloadInputViews()` (the reload may be redundant in
  some paths; it is idempotent and kept).
- **Proxy invisibility.** 0×0 in the host's `.background`, `isUserInteractionEnabled = false`,
  `isAccessibilityElement = false`, plus `.accessibilityHidden(true)` on the SwiftUI side.

### Package manifest

```swift
// swift-tools-version: 6.0
let package = Package(
    name: "SUI-InputModifier",
    platforms: [.iOS(.v16)],
    products: [.library(name: "InputViewKit", targets: ["InputViewKit"])],
    targets: [
        .target(name: "InputViewKit"),
        .testTarget(name: "InputViewKitTests", dependencies: ["InputViewKit"])
    ]
)
```

Zero dependencies — the `UIViewFinder` dependency leaves with the introspection overload.

All source files are wrapped in `#if os(iOS)` so that multiplatform consumers
(an app with iOS + macOS destinations) can depend on the package without build failures
on non-iOS platforms — the `platforms:` declaration alone does not prevent SPM from
compiling the target there.

## 8. Testing strategy

Swift Testing on an iOS Simulator destination, with a `UIWindow` harness (host a SwiftUI
view hierarchy in a real key window, drive bindings, assert responder state).

| # | Test | Asserts |
|---|------|---------|
| 1 | Bool present/dismiss | `isFirstResponder` follows the binding both ways |
| 2 | External resign | System-side dismissal sets the binding to `false` |
| 3 | Equals switching A→B | B is first responder, binding == `.b`, A did not clear it |
| 4 | State survival | A panel-internal `@State` value survives hide/show |
| 5 | Environment forwarding | An `@EnvironmentObject` injected on the host is readable inside the panel |
| 6 | Pending focus | Binding set `true` before window attach → panel presents after attach |

CI: GitHub Actions — `xcodebuild test` on an iOS Simulator (latest available runtime),
plus a build of the example app. Workflow must stay green before tagging 1.0.

## 9. Example app — `Examples/InputViewKitDemo`

Xcode project (not a package target) demonstrating, screen per screen:

1. **Calculator amount field** — the hero use case; source of the README GIF.
2. **Multi-field form** — `equals:` focus, next/done buttons inside the panel.
3. **Environment demo** — theming via `@EnvironmentObject` + dark mode inside the panel.

Doubles as the manual QA bench for the verification items (backdrop, iPad floating
keyboard, height-change animation).

## 10. Documentation plan

- **DocC catalog** (`Sources/InputViewKit/InputViewKit.docc`): landing page; articles
  *Getting Started*, *Multi-Field Forms*, *How It Works* (honest architecture description),
  *Limitations*; doc comments with examples on both modifiers.
- **`.spi.yml`** — Swift Package Index documentation hosting for the `InputViewKit` product.
- **README** — hero GIF, badges, quick start, installation, link to hosted docs, a
  migration note (`input(focused:anchor:input:)` → `inputView(isPresented:content:)`), and
  an honest pointer to CustomKeyboardKit for the native-`TextField` use case.
- **CHANGELOG.md** — kept from 1.0 onward.

## 11. Repo hygiene

- Add `.gitignore` (`.build/`, `xcuserdata/`, `.DS_Store`, `.swiftpm/xcode/xcuserdata/`);
  `git rm --cached` the committed `xcuserdata` files.
- Replace the GitHub repo description (currently `[tmp description] …`) via `gh repo edit`.
- Remove the old API entirely (pre-1.0 clean break) — no deprecated shims.
- `Package.resolved` becomes unnecessary (zero deps) and is removed.

## 12. Workflow

Work happens in `~/ClaudeCode/SUI-InputModifier` on branch `redesign/1.0`; merge to `main`
after owner review. Tagging `1.0.0` is a separate, owner-triggered step after everything
above is done and verified.

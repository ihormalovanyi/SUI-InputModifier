# InputViewKit 1.0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild SUI-InputModifier as `InputViewKit` — an Apple-quality SwiftUI modifier that presents a custom input panel (in place of the system keyboard) for any view, with tests, DocC, an example app, and CI.

**Architecture:** A hidden 0×0 `UIView` responder proxy (`ProxyInputView`) sits in the host view's background; its `inputView` is a self-sizing `UIInputView(.keyboard)` wrapper hosting a `UIHostingController` whose root forwards the full SwiftUI environment. Focus is two-way synced through an `InputFocusBinding` abstraction that normalizes the `Bool` and `equals:` public APIs. Empirically verified recipes (iOS 26.5 probes, see spec) are baked in: self-sizing requires `allowsSelfSizing + TAMIC=false + intrinsicContentSize override + invalidate + reloadInputViews`.

**Tech Stack:** Swift 6 (tools 6.0), SwiftUI + UIKit bridge, Swift Testing (simulator), DocC, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-06-10-inputviewkit-1.0-design.md` (approved). One refinement vs spec wording: `InputFocusBinding` exposes only `isActive`/`deactivate` — activation always flows binding→UIKit, so `activate()` is YAGNI.

**Working dir:** `~/ClaudeCode/SUI-InputModifier`, branch `redesign/1.0`.

**Shared commands** (referenced by tasks as BUILD / TEST / DOCC / DEMO):

```bash
# BUILD
xcodebuild build -scheme SUI-InputModifier -destination 'generic/platform=iOS Simulator' -quiet
# TEST
xcodebuild test -scheme SUI-InputModifier -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet
# DOCC
xcodebuild docbuild -scheme SUI-InputModifier -destination 'generic/platform=iOS Simulator' -quiet
# DEMO
xcodebuild build -project Examples/InputViewKitDemo/InputViewKitDemo.xcodeproj -scheme InputViewKitDemo -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO -quiet
```

---

### Task 1: Repo hygiene baseline

**Files:**
- Create: `.gitignore`
- Delete (untrack): `.swiftpm/xcode/package.xcworkspace/xcuserdata/`, `.swiftpm/xcode/xcuserdata/`, `Package.resolved`

- [ ] **Step 1: Create `.gitignore`**

```gitignore
.DS_Store
.build/
DerivedData/
xcuserdata/
*.xcuserstate
.swiftpm/xcode/package.xcworkspace/xcuserdata/
.swiftpm/xcode/xcuserdata/
```

- [ ] **Step 2: Untrack user state and stale lockfile**

```bash
git rm -r --cached .swiftpm/xcode/package.xcworkspace/xcuserdata .swiftpm/xcode/xcuserdata
git rm --cached Package.resolved
rm -f Package.resolved
```

Expected: paths removed from index; `git status` shows deletions + new `.gitignore`.

- [ ] **Step 3: Commit**

```bash
git add .gitignore
git commit -m "chore: add .gitignore, untrack xcuserdata and Package.resolved"
```

---

### Task 2: New manifest + `InputFocusBinding` (TDD)

Replaces the old package skeleton. The old source tree and the UIViewFinder dependency are deleted here — the build is green again by the end of this task.

**Files:**
- Modify: `Package.swift` (full rewrite)
- Delete: `Sources/SUI-InputModifier/SUI_InputModifier.swift` (entire old target dir)
- Create: `Sources/InputViewKit/InputFocusBinding.swift`
- Create: `Tests/InputViewKitTests/InputFocusBindingTests.swift`

- [ ] **Step 1: Rewrite `Package.swift`**

```swift
// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SUI-InputModifier",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "InputViewKit", targets: ["InputViewKit"])
    ],
    targets: [
        .target(name: "InputViewKit"),
        .testTarget(name: "InputViewKitTests", dependencies: ["InputViewKit"])
    ]
)
```

- [ ] **Step 2: Delete the old target**

```bash
git rm -r "Sources/SUI-InputModifier"
```

- [ ] **Step 3: Write the failing tests for `InputFocusBinding`**

`Tests/InputViewKitTests/InputFocusBindingTests.swift`:

```swift
import SwiftUI
import Testing
@testable import InputViewKit

@MainActor
struct InputFocusBindingTests {

    enum Field: Hashable { case a, b }

    @Test func boolBindingReflectsAndClears() {
        var value = true
        let binding = Binding(get: { value }, set: { value = $0 })
        let focus = InputFocusBinding.bool(binding)

        #expect(focus.isActive())
        focus.deactivate()
        #expect(value == false)
        #expect(!focus.isActive())
    }

    @Test func boolDeactivateIsIdempotent() {
        var value = false
        var writes = 0
        let binding = Binding(get: { value }, set: { value = $0; writes += 1 })
        let focus = InputFocusBinding.bool(binding)

        focus.deactivate()
        #expect(writes == 0, "must not write false over false")
    }

    @Test func valueBindingMatchesOnlyItsValue() {
        var selection: Field? = .a
        let binding = Binding(get: { selection }, set: { selection = $0 })
        let focusA = InputFocusBinding.value(binding, equals: Field.a)
        let focusB = InputFocusBinding.value(binding, equals: Field.b)

        #expect(focusA.isActive())
        #expect(!focusB.isActive())
    }

    @Test func valueDeactivateOnlyClearsOwnValue() {
        // The A→B switching guard — the subtlest invariant in the design.
        var selection: Field? = .a
        let binding = Binding(get: { selection }, set: { selection = $0 })
        let focusA = InputFocusBinding.value(binding, equals: Field.a)

        selection = .b              // B already claimed focus
        focusA.deactivate()         // A's late resign must NOT clear it
        #expect(selection == .b)

        selection = .a
        focusA.deactivate()         // but A clears itself when it owns focus
        #expect(selection == nil)
    }
}
```

- [ ] **Step 4: Run tests to verify they fail to compile**

Run: TEST
Expected: FAIL — `InputFocusBinding` not found (target has no sources yet).

- [ ] **Step 5: Implement `InputFocusBinding`**

`Sources/InputViewKit/InputFocusBinding.swift`:

```swift
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
```

- [ ] **Step 6: Run tests to verify they pass**

Run: TEST
Expected: PASS — 4 tests green.

- [ ] **Step 7: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "feat!: replace package skeleton with InputViewKit target

BREAKING CHANGE: module renamed to InputViewKit, old input(focused:)/
input(input:) API removed, UIViewFinder dependency dropped, iOS 16 floor,
tools 6.0. Adds InputFocusBinding with the A->B switching guard."
```

---

### Task 3: `InputHostRoot` — environment forwarding + height reporting

**Files:**
- Create: `Sources/InputViewKit/EnvironmentForwarding.swift`

- [ ] **Step 1: Implement `InputHostRoot`**

`Sources/InputViewKit/EnvironmentForwarding.swift`:

```swift
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
```

Notes for the implementer:
- `.environment(\.self, environment)` uses the identity `WritableKeyPath` to replace the
  hosted tree's environment wholesale. If the compiler rejects `\.self` here, the
  equivalent fallback is `.transformEnvironment(\.self) { $0 = environment }`.
- `.fixedSize(vertical: true)` makes the reported height the *ideal* height, independent
  of the wrapper's current bounds (avoids the chicken-and-egg between panel height and
  measured height). Documented consequence: scrollable panels must set an explicit
  `.frame(height:)` — covered in the Limitations article (Task 10).
- `.onGeometryChange` is back-deployed to iOS 16.

- [ ] **Step 2: Build**

Run: BUILD
Expected: succeeds, no warnings.

- [ ] **Step 3: Commit**

```bash
git add Sources/InputViewKit/EnvironmentForwarding.swift
git commit -m "feat: add InputHostRoot with full environment forwarding and height reporting"
```

---

### Task 4: `SelfSizingInputView` — the verified self-sizing wrapper

**Files:**
- Create: `Sources/InputViewKit/SelfSizingInputView.swift`

- [ ] **Step 1: Implement**

`Sources/InputViewKit/SelfSizingInputView.swift`:

```swift
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
        guard height != idealContentHeight else { return }
        idealContentHeight = height
        invalidateIntrinsicContentSize()
        onSizeShouldReload?()
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric,
               height: idealContentHeight + safeAreaInsets.bottom)
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        invalidateIntrinsicContentSize()
    }
}
#endif
```

- [ ] **Step 2: Build**

Run: BUILD
Expected: succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/InputViewKit/SelfSizingInputView.swift
git commit -m "feat: add SelfSizingInputView with verified live-resize recipe"
```

---

### Task 5: `ProxyInputView` — focus engine (TDD)

The proxy is a plain `UIView` responder — pure UIKit, so its focus engine is unit-testable without SwiftUI.

**Files:**
- Create: `Sources/InputViewKit/ProxyInputView.swift`
- Create: `Tests/InputViewKitTests/ProxyInputViewTests.swift`

- [ ] **Step 1: Write the failing tests**

`Tests/InputViewKitTests/ProxyInputViewTests.swift`:

```swift
import UIKit
import Testing
@testable import InputViewKit

@MainActor
struct ProxyInputViewTests {

    /// Pumps the main queue so the proxy's coalesced async focus apply runs.
    func settle() async {
        try? await Task.sleep(for: .milliseconds(300))
    }

    func makeWindow() -> UIWindow {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        return window
    }

    @Test func becomesAndResignsWithDesiredFocus() async {
        let window = makeWindow()
        let proxy = ProxyInputView()
        window.rootViewController!.view.addSubview(proxy)

        proxy.setDesiredFocus(true)
        await settle()
        #expect(proxy.isFirstResponder)

        proxy.setDesiredFocus(false)
        await settle()
        #expect(!proxy.isFirstResponder)
    }

    @Test func pendingFocusAppliesOnWindowAttach() async {
        let window = makeWindow()
        let proxy = ProxyInputView()
        proxy.setDesiredFocus(true)        // not in a window yet
        await settle()
        #expect(!proxy.isFirstResponder)

        window.rootViewController!.view.addSubview(proxy)
        await settle()
        #expect(proxy.isFirstResponder, "didMoveToWindow must apply pending focus")
    }

    @Test func externalResignFiresCallbackOnce() async {
        let window = makeWindow()
        let proxy = ProxyInputView()
        window.rootViewController!.view.addSubview(proxy)

        var externalResigns = 0
        proxy.onResignedExternally = { externalResigns += 1 }

        proxy.setDesiredFocus(true)
        await settle()
        #expect(proxy.isFirstResponder)

        window.endEditing(true)            // system-side dismissal
        await settle()
        #expect(!proxy.isFirstResponder)
        #expect(externalResigns == 1)
    }

    @Test func bindingDrivenResignDoesNotFireCallback() async {
        let window = makeWindow()
        let proxy = ProxyInputView()
        window.rootViewController!.view.addSubview(proxy)

        var externalResigns = 0
        proxy.onResignedExternally = { externalResigns += 1 }

        proxy.setDesiredFocus(true)
        await settle()
        proxy.setDesiredFocus(false)       // our own dismissal
        await settle()
        #expect(!proxy.isFirstResponder)
        #expect(externalResigns == 0, "no echo when the binding initiated the resign")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail to compile**

Run: TEST
Expected: FAIL — `ProxyInputView` not found.

- [ ] **Step 3: Implement `ProxyInputView`**

`Sources/InputViewKit/ProxyInputView.swift`:

```swift
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
    var onResignedExternally: (() -> Void)?

    private var desiredFirstResponder = false
    private var applyScheduled = false

    override var canBecomeFirstResponder: Bool { true }
    override var inputView: UIView? { hostedInputView }

    /// Stores the desired focus state and applies it asynchronously.
    /// Coalesced: a burst of SwiftUI updates produces one application.
    /// Window-aware: applied in `didMoveToWindow` if not attached yet.
    func setDesiredFocus(_ focused: Bool) {
        desiredFirstResponder = focused
        scheduleApply()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        scheduleApply()
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned, desiredFirstResponder {
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: TEST
Expected: PASS — 8 tests green (4 from Task 2 + 4 new).

- [ ] **Step 5: Commit**

```bash
git add Sources/InputViewKit/ProxyInputView.swift Tests/InputViewKitTests/ProxyInputViewTests.swift
git commit -m "feat: add ProxyInputView focus engine (guarded, coalesced, window-aware)"
```

---

### Task 6: `ProxyInputRepresentable` — the SwiftUI↔UIKit bridge

**Files:**
- Create: `Sources/InputViewKit/ProxyInputRepresentable.swift`

- [ ] **Step 1: Implement**

`Sources/InputViewKit/ProxyInputRepresentable.swift`:

```swift
#if os(iOS)
import SwiftUI
import UIKit

/// Bridges the proxy responder into SwiftUI and owns the hosting pipeline:
/// proxy → SelfSizingInputView wrapper → UIHostingController<InputHostRoot>.
struct ProxyInputRepresentable<Content: View>: UIViewRepresentable {

    let focus: InputFocusBinding
    let content: () -> Content

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ProxyInputView {
        let coordinator = context.coordinator
        let proxy = ProxyInputView()
        proxy.isUserInteractionEnabled = false
        proxy.isAccessibilityElement = false

        let wrapper = SelfSizingInputView()
        let host = UIHostingController(rootView: makeRoot(context: context, coordinator: coordinator))
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.sizingOptions = .intrinsicContentSize

        wrapper.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: wrapper.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor)
        ])
        wrapper.onSizeShouldReload = { [weak proxy] in
            proxy?.reloadInputViews()
        }

        coordinator.hostingController = host
        coordinator.wrapper = wrapper
        coordinator.focus = focus

        proxy.hostedInputView = wrapper
        proxy.onResignedExternally = { [weak coordinator] in
            coordinator?.focus?.deactivate()
        }
        return proxy
    }

    func updateUIView(_ proxy: ProxyInputView, context: Context) {
        let coordinator = context.coordinator
        coordinator.focus = focus
        coordinator.hostingController?.rootView = makeRoot(context: context, coordinator: coordinator)
        proxy.setDesiredFocus(focus.isActive())
    }

    static func dismantleUIView(_ proxy: ProxyInputView, coordinator: Coordinator) {
        proxy.onResignedExternally = nil
        if proxy.isFirstResponder {
            _ = proxy.resignFirstResponder()
        }
    }

    private func makeRoot(context: Context, coordinator: Coordinator) -> InputHostRoot<Content> {
        InputHostRoot(
            environment: context.environment,
            content: content(),
            onHeightChange: { [weak coordinator] height in
                coordinator?.wrapper?.setIdealContentHeight(height)
            }
        )
    }

    @MainActor
    final class Coordinator {
        var hostingController: UIHostingController<InputHostRoot<Content>>?
        var wrapper: SelfSizingInputView?
        var focus: InputFocusBinding?
    }
}
#endif
```

Ownership notes (why there are no retain cycles): the proxy strongly holds the wrapper and
the `onResignedExternally` closure captures the coordinator weakly; the wrapper's reload
closure captures the proxy weakly; the coordinator holds the hosting controller and wrapper
strongly and is itself owned by SwiftUI.

- [ ] **Step 2: Build**

Run: BUILD
Expected: succeeds, no warnings.

- [ ] **Step 3: Commit**

```bash
git add Sources/InputViewKit/ProxyInputRepresentable.swift
git commit -m "feat: add ProxyInputRepresentable bridging proxy, wrapper and hosting"
```

---

### Task 7: Public API + presentation integration tests (TDD)

**Files:**
- Create: `Sources/InputViewKit/View+InputView.swift`
- Create: `Sources/InputViewKit/InputViewModifier.swift`
- Create: `Tests/InputViewKitTests/Support/IntegrationHarness.swift`
- Create: `Tests/InputViewKitTests/PresentationTests.swift`

- [ ] **Step 1: Write the test harness**

`Tests/InputViewKitTests/Support/IntegrationHarness.swift`:

```swift
import SwiftUI
import UIKit
@testable import InputViewKit

/// Hosts a SwiftUI hierarchy in a real key window so responder state,
/// keyboard plumbing and the async focus engine behave as in an app.
@MainActor
final class IntegrationHarness {
    let window: UIWindow

    init<V: View>(@ViewBuilder content: () -> V) {
        window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIHostingController(rootView: content())
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
    }

    /// First `ProxyInputView` found in the window, depth-first.
    func proxies() -> [ProxyInputView] {
        func collect(_ view: UIView) -> [ProxyInputView] {
            var found: [ProxyInputView] = []
            if let proxy = view as? ProxyInputView { found.append(proxy) }
            for subview in view.subviews { found.append(contentsOf: collect(subview)) }
            return found
        }
        return collect(window)
    }

    func proxy() -> ProxyInputView? { proxies().first }
}

/// Pumps the main queue long enough for coalesced focus applies,
/// keyboard transitions and SwiftUI re-renders to settle.
@MainActor
func settle(_ milliseconds: Int = 500) async {
    try? await Task.sleep(for: .milliseconds(milliseconds))
}
```

- [ ] **Step 2: Write the failing presentation tests**

`Tests/InputViewKitTests/PresentationTests.swift`:

```swift
import SwiftUI
import Testing
@testable import InputViewKit

@MainActor
final class PresentationModel: ObservableObject {
    @Published var isPresented = false
}

@MainActor
struct PresentationTests {

    private struct Host: View {
        @ObservedObject var model: PresentationModel
        var body: some View {
            Text("amount")
                .inputView(isPresented: $model.isPresented) {
                    Color.red.frame(height: 220)
                }
        }
    }

    @Test func presentsAndDismissesWithBinding() async throws {
        let model = PresentationModel()
        let harness = IntegrationHarness { Host(model: model) }
        await settle()
        let proxy = try #require(harness.proxy())
        #expect(!proxy.isFirstResponder)

        model.isPresented = true
        await settle()
        #expect(proxy.isFirstResponder)

        model.isPresented = false
        await settle()
        #expect(!proxy.isFirstResponder)
    }

    @Test func externalDismissalSyncsBindingToFalse() async throws {
        let model = PresentationModel()
        let harness = IntegrationHarness { Host(model: model) }
        model.isPresented = true
        await settle()
        let proxy = try #require(harness.proxy())
        #expect(proxy.isFirstResponder)

        harness.window.endEditing(true)
        await settle()
        #expect(!proxy.isFirstResponder)
        #expect(model.isPresented == false, "binding must never lie about responder state")
    }

    @Test func focusRequestedBeforeWindowAttachPresentsAfterAttach() async throws {
        let model = PresentationModel()
        model.isPresented = true            // requested before any window exists
        let harness = IntegrationHarness { Host(model: model) }
        await settle()
        let proxy = try #require(harness.proxy())
        #expect(proxy.isFirstResponder)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail to compile**

Run: TEST
Expected: FAIL — `.inputView(isPresented:content:)` not found.

- [ ] **Step 4: Implement the internal modifier helper**

`Sources/InputViewKit/InputViewModifier.swift`:

```swift
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
                .accessibilityHidden(true)
        )
    }
}
#endif
```

- [ ] **Step 5: Implement the public API**

`Sources/InputViewKit/View+InputView.swift`:

```swift
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
```

- [ ] **Step 6: Run tests to verify they pass**

Run: TEST
Expected: PASS — 11 tests green.

- [ ] **Step 7: Commit**

```bash
git add Sources/InputViewKit/View+InputView.swift Sources/InputViewKit/InputViewModifier.swift Tests/InputViewKitTests
git commit -m "feat: add public inputView(isPresented:) and inputView(_:equals:) API"
```

---

### Task 8: Behavior contract tests — switching, state survival, environment (TDD)

**Files:**
- Create: `Tests/InputViewKitTests/ContractTests.swift`

- [ ] **Step 1: Write the failing tests**

`Tests/InputViewKitTests/ContractTests.swift`:

```swift
import SwiftUI
import Testing
@testable import InputViewKit

@MainActor
final class ContractModel: ObservableObject {
    enum Field: Hashable { case a, b }
    @Published var field: Field?
    @Published var isPresented = false
}

/// Reference box for observing panel-internal effects from tests.
@MainActor
final class Recorder {
    var stateValues: [Int] = []
    var environmentReads: [String] = []
}

@MainActor
final class ThemeObject: ObservableObject {
    @Published var name = "aurora"
}

@MainActor
struct ContractTests {

    // MARK: Switching (equals)

    private struct TwoFieldHost: View {
        @ObservedObject var model: ContractModel
        var body: some View {
            VStack {
                Text("a").inputView($model.field, equals: .a) { Color.red.frame(height: 200) }
                Text("b").inputView($model.field, equals: .b) { Color.blue.frame(height: 200) }
            }
        }
    }

    @Test func switchingFieldsKeepsBindingAndMovesFocus() async throws {
        let model = ContractModel()
        let harness = IntegrationHarness { TwoFieldHost(model: model) }
        await settle()
        let proxies = harness.proxies()
        #expect(proxies.count == 2)

        model.field = .a
        await settle()
        let first = try #require(proxies.first(where: { $0.isFirstResponder }))

        model.field = .b
        await settle(800)
        #expect(model.field == .b, "A's late resign must not clear B's claim")
        let second = try #require(proxies.first(where: { $0.isFirstResponder }))
        #expect(first !== second, "focus must have moved to the other proxy")

        model.field = nil
        await settle()
        #expect(harness.proxies().allSatisfy { !$0.isFirstResponder })
    }

    // MARK: State survival across show/hide

    private struct StatefulPanel: View {
        let recorder: Recorder
        @State private var counter = 0
        var body: some View {
            Color.green
                .frame(height: 120)
                .onAppear {
                    counter += 1
                    recorder.stateValues.append(counter)
                }
        }
    }

    private struct SurvivalHost: View {
        @ObservedObject var model: ContractModel
        let recorder: Recorder
        var body: some View {
            Text("host").inputView(isPresented: $model.isPresented) {
                StatefulPanel(recorder: recorder)
            }
        }
    }

    @Test func panelStateSurvivesShowHideCycle() async throws {
        let model = ContractModel()
        let recorder = Recorder()
        _ = IntegrationHarness { SurvivalHost(model: model, recorder: recorder) }

        model.isPresented = true
        await settle(800)
        model.isPresented = false
        await settle(800)
        model.isPresented = true
        await settle(800)

        // @State persisted across the hide: the counter kept its value,
        // so the second onAppear records 2 (a reset identity would record 1 again).
        #expect(recorder.stateValues.contains(2),
                "panel @State must survive show/hide, got \(recorder.stateValues)")
        #expect(!recorder.stateValues.dropFirst().contains(1),
                "identity reset detected: counter restarted from zero")
    }

    // MARK: Environment forwarding

    private struct EnvPanel: View {
        @EnvironmentObject var theme: ThemeObject
        @Environment(\.locale) var locale
        let recorder: Recorder
        var body: some View {
            Color.clear
                .frame(height: 80)
                .onAppear {
                    recorder.environmentReads.append(theme.name)
                    recorder.environmentReads.append(locale.identifier)
                }
        }
    }

    private struct EnvHost: View {
        @ObservedObject var model: ContractModel
        let recorder: Recorder
        var body: some View {
            Text("host")
                .inputView(isPresented: $model.isPresented) {
                    EnvPanel(recorder: recorder)
                }
                .environmentObject(ThemeObject())
                .environment(\.locale, Locale(identifier: "uk_UA"))
        }
    }

    @Test func panelReceivesHostEnvironmentIncludingObjects() async throws {
        let model = ContractModel()
        let recorder = Recorder()
        _ = IntegrationHarness { EnvHost(model: model, recorder: recorder) }

        model.isPresented = true
        await settle(800)

        // In 0.1 this crashed (no EnvironmentObject in the hosted tree).
        #expect(recorder.environmentReads.contains("aurora"))
        #expect(recorder.environmentReads.contains("uk_UA"))
    }
}
```

- [ ] **Step 2: Run tests**

Run: TEST
Expected: PASS if Tasks 3–7 are correct. If `switchingFieldsKeepsBindingAndMovesFocus`
is flaky on the A→B handoff, the cause is UIKit delivering A's resign before B's become —
verify `InputFocusBinding.deactivate`'s guard is intact and increase the settle to 1000 ms
before changing any production code.

- [ ] **Step 3: Commit**

```bash
git add Tests/InputViewKitTests/ContractTests.swift
git commit -m "test: lock behavior contract — switching, state survival, environment"
```

---

### Task 9: Multiplatform-resolve sanity

The `#if os(iOS)` guards are already on every source file (Tasks 2–7). Verify the package
is inert-but-buildable when a multiplatform consumer compiles it for macOS.

- [ ] **Step 1: Build for macOS**

```bash
swift build 2>&1 | tail -3
```

Expected: `Build complete!` — every file compiles to an empty module on macOS.
If it fails, a file is missing its `#if os(iOS)` guard — add it there.

- [ ] **Step 2: Commit (only if fixes were needed)**

```bash
git add Sources
git commit -m "fix: guard remaining sources with #if os(iOS)"
```

---

### Task 10: DocC catalog

**Files:**
- Create: `Sources/InputViewKit/InputViewKit.docc/InputViewKit.md`
- Create: `Sources/InputViewKit/InputViewKit.docc/GettingStarted.md`
- Create: `Sources/InputViewKit/InputViewKit.docc/MultiFieldForms.md`
- Create: `Sources/InputViewKit/InputViewKit.docc/HowItWorks.md`
- Create: `Sources/InputViewKit/InputViewKit.docc/Limitations.md`

- [ ] **Step 1: Landing page**

`Sources/InputViewKit/InputViewKit.docc/InputViewKit.md`:

```markdown
# ``InputViewKit``

Present a custom input panel — in place of the system keyboard — for any SwiftUI view.

## Overview

UIKit lets any responder provide an `inputView`: tap the field and the system slides your
view up instead of the keyboard, with the keyboard's animation, avoidance and dismissal.
SwiftUI has no such API. InputViewKit adds it as a single modifier:

```swift
import InputViewKit

@State private var isEditing = false

Text(amount, format: .currency(code: "UAH"))
    .inputView(isPresented: $isEditing) {
        CalculatorPad(value: $amount)
    }
```

The panel works for *any* view — a label, a row, an avatar — not just text fields. It
receives the full SwiftUI environment of its host (including environment objects), keeps
its state across show/hide cycles, and adopts its content's ideal height, including live
height changes while presented.

On iOS 26 the system automatically hosts the panel in the rounded Liquid Glass keyboard
chrome; with the default configuration your content sits on the system keyboard material
exactly like the built-in keyboard.

## Guarantees

1. Presentation uses the standard keyboard animation; keyboard avoidance, safe areas and
   `scrollDismissesKeyboard` work automatically.
2. The binding never lies: any external dismissal is reflected back as `false` / `nil`.
3. Reassigning an `equals:` binding moves focus between fields without dismissing the panel.
4. Panel content keeps its `@State` for the lifetime of the host view.
5. The host's complete environment is forwarded into the panel.
6. The panel self-sizes to its content's ideal height, live.

## Topics

### Essentials

- <doc:GettingStarted>
- ``SwiftUICore/View/inputView(isPresented:content:)``
- ``SwiftUICore/View/inputView(_:equals:content:)``

### Guides

- <doc:MultiFieldForms>
- <doc:HowItWorks>
- <doc:Limitations>
```

Note for the implementer: if the symbol links above fail to resolve in `docbuild`
(extension-symbol module prefixes vary), replace the two symbol entries with plain
backtick code spans and keep the articles — do not fight the resolver.

- [ ] **Step 2: Getting Started article**

`Sources/InputViewKit/InputViewKit.docc/GettingStarted.md`:

```markdown
# Getting Started

Attach a custom input panel to a view in three steps.

## Add the package

```swift
.package(url: "https://github.com/ihormalovanyi/SUI-InputModifier", from: "1.0.0")
```

Add the `InputViewKit` product to your target, then `import InputViewKit`.

## Present a panel

```swift
struct AmountRow: View {
    @State private var amount: Decimal = 0
    @State private var isEditing = false

    var body: some View {
        Text(amount, format: .currency(code: "UAH"))
            .inputView(isPresented: $isEditing) {
                CalculatorPad(value: $amount)
            }
            .onTapGesture { isEditing = true }
    }
}
```

Setting `isEditing` to `true` presents the panel with the system keyboard animation.
The user dismissing it — scroll-to-dismiss, tapping another field — sets it back to
`false` automatically.

## Build the panel itself

The panel is plain SwiftUI. Mutate the host's state directly:

```swift
struct CalculatorPad: View {
    @Binding var value: Decimal

    var body: some View {
        Grid {
            // digit and operator buttons writing into $value
        }
        .padding()
    }
}
```

Give the panel a natural ideal height (padding, fixed rows). For scrollable content set
an explicit `.frame(height:)` — see <doc:Limitations>.
```

- [ ] **Step 3: Multi-field forms article**

`Sources/InputViewKit/InputViewKit.docc/MultiFieldForms.md`:

```markdown
# Multi-Field Forms

Move focus between fields without dismissing the panel.

## One binding, many fields

Mirror `focused(_:equals:)`: one optional state value identifies the focused field.

```swift
enum Field: Hashable { case amount, tip }

struct CheckoutForm: View {
    @State private var amount: Decimal = 0
    @State private var tip: Decimal = 0
    @State private var focus: Field?

    var body: some View {
        Form {
            Text(amount, format: .currency(code: "UAH"))
                .inputView($focus, equals: .amount) {
                    CalcPad(value: $amount, onNext: { focus = .tip })
                }
                .onTapGesture { focus = .amount }

            Text(tip, format: .percent)
                .inputView($focus, equals: .tip) {
                    CalcPad(value: $tip, onNext: { focus = nil })
                }
                .onTapGesture { focus = .tip }
        }
    }
}
```

## Next and Done

Because the panel is your SwiftUI view, "Next" is just `focus = .tip` and "Done" is
`focus = nil`. The keyboard window stays up during the transition; only the panel
content changes.

## The switching guarantee

When focus moves from A to B, UIKit delivers A's resignation *after* B becomes first
responder. InputViewKit guards this internally: A's late resignation never clears the
focus value B just claimed.
```

- [ ] **Step 4: How It Works article**

`Sources/InputViewKit/InputViewKit.docc/HowItWorks.md`:

```markdown
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
```

- [ ] **Step 5: Limitations article**

`Sources/InputViewKit/InputViewKit.docc/Limitations.md`:

```markdown
# Limitations

Honest edges of the `inputView` mechanism.

## Hardware keyboards

When a hardware keyboard is attached and the software keyboard is suppressed, the system
does not present input views. This is a UIKit platform behavior, not an InputViewKit
policy. Provide an alternative input path if your app must work with hardware keyboards.

## Scrollable panels

The panel adopts its content's *ideal* height. A `ScrollView`'s ideal height is its full
content height, so an unbounded scrollable panel would try to be as tall as its content.
Give scrollable panels an explicit height:

```swift
.inputView(isPresented: $isPicking) {
    ScrollView { palette }
        .frame(height: 320)
}
```

## One panel per view

Attach one `inputView` modifier per view. Multiple modifiers on the same view create
multiple competing proxies; behavior is unspecified.

## iPad floating keyboard

With the floating keyboard active, custom input views follow the system's hosting
decisions. Verify your panel layout on iPad; treat very wide fixed layouts with care.
```

- [ ] **Step 6: Build docs**

Run: DOCC
Expected: succeeds. If symbol-link resolution errors appear for the two
`SwiftUICore/View/...` entries, apply the fallback from Step 1's note and re-run.

- [ ] **Step 7: Commit**

```bash
git add Sources/InputViewKit/InputViewKit.docc
git commit -m "docs: add DocC catalog — landing, getting started, forms, internals, limits"
```

---

### Task 11: Example app — `Examples/InputViewKitDemo`

Xcode 16+ project format (objectVersion 77, filesystem-synchronized groups) so the pbxproj
stays tiny and files added later appear automatically.

**Files:**
- Create: `Examples/InputViewKitDemo/InputViewKitDemo.xcodeproj/project.pbxproj`
- Create: `Examples/InputViewKitDemo/InputViewKitDemo.xcodeproj/xcshareddata/xcschemes/InputViewKitDemo.xcscheme`
- Create: `Examples/InputViewKitDemo/InputViewKitDemo/DemoApp.swift`
- Create: `Examples/InputViewKitDemo/InputViewKitDemo/CalculatorScreen.swift`
- Create: `Examples/InputViewKitDemo/InputViewKitDemo/FormScreen.swift`
- Create: `Examples/InputViewKitDemo/InputViewKitDemo/ThemeScreen.swift`

- [ ] **Step 1: Write `project.pbxproj`**

`Examples/InputViewKitDemo/InputViewKitDemo.xcodeproj/project.pbxproj`:

```text
// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 77;
	objects = {

/* Begin PBXFileSystemSynchronizedRootGroup section */
		DE0000000000000000000001 /* InputViewKitDemo */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			path = InputViewKitDemo;
			sourceTree = "<group>";
		};
/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFileReference section */
		DE0000000000000000000002 /* InputViewKitDemo.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = InputViewKitDemo.app; sourceTree = BUILT_PRODUCTS_DIR; };
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		DE0000000000000000000003 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				DE0000000000000000000010 /* InputViewKit in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXBuildFile section */
		DE0000000000000000000010 /* InputViewKit in Frameworks */ = {isa = PBXBuildFile; productRef = DE0000000000000000000011 /* InputViewKit */; };
/* End PBXBuildFile section */

/* Begin PBXGroup section */
		DE0000000000000000000004 = {
			isa = PBXGroup;
			children = (
				DE0000000000000000000001 /* InputViewKitDemo */,
				DE0000000000000000000005 /* Products */,
			);
			sourceTree = "<group>";
		};
		DE0000000000000000000005 /* Products */ = {
			isa = PBXGroup;
			children = (
				DE0000000000000000000002 /* InputViewKitDemo.app */,
			);
			name = Products;
			sourceTree = "<group>";
		};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		DE0000000000000000000006 /* InputViewKitDemo */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = DE0000000000000000000007 /* Build configuration list for PBXNativeTarget "InputViewKitDemo" */;
			buildPhases = (
				DE0000000000000000000008 /* Sources */,
				DE0000000000000000000003 /* Frameworks */,
				DE0000000000000000000009 /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
				DE0000000000000000000001 /* InputViewKitDemo */,
			);
			name = InputViewKitDemo;
			packageProductDependencies = (
				DE0000000000000000000011 /* InputViewKit */,
			);
			productName = InputViewKitDemo;
			productReference = DE0000000000000000000002 /* InputViewKitDemo.app */;
			productType = "com.apple.product-type.application";
		};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		DE000000000000000000000A /* Project object */ = {
			isa = PBXProject;
			attributes = {
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1600;
				LastUpgradeCheck = 1600;
			};
			buildConfigurationList = DE000000000000000000000B /* Build configuration list for PBXProject "InputViewKitDemo" */;
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = DE0000000000000000000004;
			minimizedProjectReferenceProxies = 1;
			packageReferences = (
				DE0000000000000000000012 /* XCLocalSwiftPackageReference "../.." */,
			);
			preferredProjectObjectVersion = 77;
			productRefGroup = DE0000000000000000000005 /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				DE0000000000000000000006 /* InputViewKitDemo */,
			);
		};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		DE0000000000000000000009 /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		DE0000000000000000000008 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
		DE000000000000000000000C /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				SDKROOT = iphoneos;
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
				SWIFT_VERSION = 6.0;
			};
			name = Debug;
		};
		DE000000000000000000000D /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				SDKROOT = iphoneos;
				SWIFT_VERSION = 6.0;
			};
			name = Release;
		};
		DE000000000000000000000E /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
				INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
				INFOPLIST_KEY_UILaunchScreen_Generation = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 16.0;
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = dev.malovanyi.InputViewKitDemo;
				PRODUCT_NAME = "$(TARGET_NAME)";
				TARGETED_DEVICE_FAMILY = "1,2";
			};
			name = Debug;
		};
		DE000000000000000000000F /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
				INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
				INFOPLIST_KEY_UILaunchScreen_Generation = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 16.0;
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = dev.malovanyi.InputViewKitDemo;
				PRODUCT_NAME = "$(TARGET_NAME)";
				TARGETED_DEVICE_FAMILY = "1,2";
			};
			name = Release;
		};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		DE000000000000000000000B /* Build configuration list for PBXProject "InputViewKitDemo" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				DE000000000000000000000C /* Debug */,
				DE000000000000000000000D /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		DE0000000000000000000007 /* Build configuration list for PBXNativeTarget "InputViewKitDemo" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				DE000000000000000000000E /* Debug */,
				DE000000000000000000000F /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
/* End XCConfigurationList section */

/* Begin XCLocalSwiftPackageReference section */
		DE0000000000000000000012 /* XCLocalSwiftPackageReference "../.." */ = {
			isa = XCLocalSwiftPackageReference;
			relativePath = ../..;
		};
/* End XCLocalSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
		DE0000000000000000000011 /* InputViewKit */ = {
			isa = XCSwiftPackageProductDependency;
			productName = InputViewKit;
		};
/* End XCSwiftPackageProductDependency section */
	};
	rootObject = DE000000000000000000000A /* Project object */;
}
```

- [ ] **Step 2: Write the shared scheme**

`Examples/InputViewKitDemo/InputViewKitDemo.xcodeproj/xcshareddata/xcschemes/InputViewKitDemo.xcscheme`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1600" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "DE0000000000000000000006"
               BuildableName = "InputViewKitDemo.app"
               BlueprintName = "InputViewKitDemo"
               ReferencedContainer = "container:InputViewKitDemo.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "DE0000000000000000000006"
            BuildableName = "InputViewKitDemo.app"
            BlueprintName = "InputViewKitDemo"
            ReferencedContainer = "container:InputViewKitDemo.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
```

- [ ] **Step 3: App entry + tabs**

`Examples/InputViewKitDemo/InputViewKitDemo/DemoApp.swift`:

```swift
import SwiftUI

@main
struct DemoApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                CalculatorScreen()
                    .tabItem { Label("Calculator", systemImage: "plus.forwardslash.minus") }
                FormScreen()
                    .tabItem { Label("Form", systemImage: "list.bullet.rectangle") }
                ThemeScreen()
                    .tabItem { Label("Theme", systemImage: "paintpalette") }
            }
        }
    }
}
```

- [ ] **Step 4: Calculator screen (hero demo + README GIF source)**

`Examples/InputViewKitDemo/InputViewKitDemo/CalculatorScreen.swift`:

```swift
import SwiftUI
import InputViewKit

struct CalculatorScreen: View {
    @State private var amount: Decimal = 0
    @State private var isEditing = false

    var body: some View {
        NavigationStack {
            List {
                Section("Amount") {
                    Text(amount, format: .currency(code: "UAH"))
                        .font(.title2.monospacedDigit())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .inputView(isPresented: $isEditing) {
                            CalculatorPad(amount: $amount) { isEditing = false }
                        }
                        .onTapGesture { isEditing = true }
                }
                Section {
                    Text("Tap the amount. A calculator pad slides up in place of the keyboard — for a plain Text, not a TextField.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("InputViewKit")
        }
    }
}

struct CalculatorPad: View {
    @Binding var amount: Decimal
    var onDone: () -> Void

    private let keys: [[String]] = [
        ["7", "8", "9"],
        ["4", "5", "6"],
        ["1", "2", "3"],
        ["C", "0", "⌫"]
    ]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(keys, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { key in
                        Button { tap(key) } label: {
                            Text(key)
                                .font(.title2.weight(.medium))
                                .frame(maxWidth: .infinity, minHeight: 52)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            Button { onDone() } label: {
                Text("Done").frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
    }

    private func tap(_ key: String) {
        switch key {
        case "C":
            amount = 0
        case "⌫":
            let digits = String(describing: amount).filter(\.isNumber).dropLast()
            amount = Decimal(string: String(digits)) ?? 0
        default:
            let digits = String(describing: amount).filter(\.isNumber) + key
            amount = Decimal(string: digits) ?? amount
        }
    }
}
```

- [ ] **Step 5: Form screen (equals + next/done)**

`Examples/InputViewKitDemo/InputViewKitDemo/FormScreen.swift`:

```swift
import SwiftUI
import InputViewKit

struct FormScreen: View {
    enum Field: Hashable { case price, tip }

    @State private var price: Decimal = 0
    @State private var tip: Decimal = 0
    @State private var focus: Field?

    var body: some View {
        NavigationStack {
            Form {
                row("Price", value: price)
                    .inputView($focus, equals: .price) {
                        CalculatorPad(amount: $price) { focus = .tip }
                    }
                    .onTapGesture { focus = .price }

                row("Tip", value: tip)
                    .inputView($focus, equals: .tip) {
                        CalculatorPad(amount: $tip) { focus = nil }
                    }
                    .onTapGesture { focus = .tip }

                Section {
                    Text("Done on the first pad jumps to the second field — the panel never dismisses in between.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Multi-field")
        }
    }

    private func row(_ title: String, value: Decimal) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value, format: .currency(code: "UAH"))
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}
```

- [ ] **Step 6: Theme screen (environment forwarding)**

`Examples/InputViewKitDemo/InputViewKitDemo/ThemeScreen.swift`:

```swift
import SwiftUI
import InputViewKit

@MainActor
final class ThemeStore: ObservableObject {
    @Published var accent: Color = .indigo
}

struct ThemeScreen: View {
    @StateObject private var theme = ThemeStore()
    @State private var mood = "—"
    @State private var isPicking = false

    var body: some View {
        NavigationStack {
            List {
                Section("Environment demo") {
                    HStack {
                        Text("Mood")
                        Spacer()
                        Text(mood).foregroundStyle(theme.accent)
                    }
                    .contentShape(Rectangle())
                    .inputView(isPresented: $isPicking) {
                        MoodPad(selection: $mood)
                    }
                    .onTapGesture { isPicking = true }

                    Picker("Accent", selection: $theme.accent) {
                        Text("Indigo").tag(Color.indigo)
                        Text("Orange").tag(Color.orange)
                        Text("Teal").tag(Color.teal)
                    }
                }
                Section {
                    Text("The pad reads ThemeStore via @EnvironmentObject — the host's environment is forwarded into the panel.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Theme")
        }
        .environmentObject(theme)
    }
}

struct MoodPad: View {
    @EnvironmentObject var theme: ThemeStore
    @Binding var selection: String

    private let moods = ["😀", "😎", "🤔", "😴", "🔥", "❄️", "🎯", "🌊"]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
            ForEach(moods, id: \.self) { mood in
                Button { selection = mood } label: {
                    Text(mood)
                        .font(.largeTitle)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(theme.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(16)
    }
}
```

- [ ] **Step 7: Build the demo**

Run: DEMO
Expected: `BUILD SUCCEEDED`. If the pbxproj fails to parse, compare section-by-section
against the listing in Step 1 — every UUID must appear exactly where shown.

- [ ] **Step 8: Manual verification on the booted simulator**

```bash
xcrun simctl list devices booted
# Install + launch (path from xcodebuild -showBuildSettings if needed):
xcodebuild -project Examples/InputViewKitDemo/InputViewKitDemo.xcodeproj -scheme InputViewKitDemo \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/ivk-demo build CODE_SIGNING_ALLOWED=NO -quiet
xcrun simctl install booted /tmp/ivk-demo/Build/Products/Debug-iphonesimulator/InputViewKitDemo.app
xcrun simctl launch booted dev.malovanyi.InputViewKitDemo
xcrun simctl io booted screenshot /tmp/ivk-demo-shot.png
```

Verify on screenshots / interactively: panel presents on tap with Liquid Glass chrome;
next/done moves between fields without dismissal; MoodPad uses the picked accent color.

- [ ] **Step 9: Commit**

```bash
git add Examples
git commit -m "feat: add InputViewKitDemo example app (calculator, multi-field, theme)"
```

---

### Task 12: README, CHANGELOG, SPI manifest, repo description

**Files:**
- Modify: `README.md` (full rewrite)
- Create: `CHANGELOG.md`
- Create: `.spi.yml`

- [ ] **Step 1: Rewrite `README.md`**

```markdown
# InputViewKit

Present a custom input panel — in place of the system keyboard — for **any** SwiftUI view.

```swift
import InputViewKit

@State private var isEditing = false

Text(amount, format: .currency(code: "UAH"))
    .inputView(isPresented: $isEditing) {
        CalculatorPad(value: $amount)
    }
```

Tap the amount → your calculator pad slides up with the system keyboard animation,
keyboard avoidance and scroll-to-dismiss. The view doesn't have to be a text field:
labels, rows, avatars — anything can take input.

> **Demo:** see `Examples/InputViewKitDemo` (calculator, multi-field form with
> next/done, environment theming).

## Features

- **Any view, not just text fields.** The unserved half of UIKit's `inputView` brought
  to SwiftUI — public API only, no private view-hierarchy introspection.
- **SwiftUI-shaped focus.** `inputView(isPresented:)` and `inputView(_:equals:)` mirror
  `focused(_:)` / `focused(_:equals:)`. Moving focus between fields keeps the panel up —
  next/done navigation is one assignment.
- **The binding never lies.** Swipe-to-dismiss, `endEditing`, another field taking over —
  every external dismissal syncs back to your state.
- **Full environment forwarding.** `@EnvironmentObject`, `colorScheme`, `locale`, custom
  keys — all available inside the panel.
- **Self-sizing, live.** The panel adopts your content's ideal height and resizes while
  presented. On iOS 26 it sits in the system's rounded Liquid Glass keyboard chrome
  automatically.
- **State survives.** Panel `@State` persists across show/hide cycles.

## Installation

```swift
.package(url: "https://github.com/ihormalovanyi/SUI-InputModifier", from: "1.0.0")
```

Requirements: iOS 16+, Swift 6 toolchain (Xcode 16+).

## Multi-field forms

```swift
enum Field { case amount, tip }
@State private var focus: Field?

Text(amount)
    .inputView($focus, equals: .amount) {
        CalcPad(value: $amount) { focus = .tip }   // next →
    }
Text(tip)
    .inputView($focus, equals: .tip) {
        CalcPad(value: $tip) { focus = nil }        // done
    }
```

## Documentation

Full DocC documentation — guarantees, how it works, limitations — is hosted on the
[Swift Package Index](https://swiftpackageindex.com/ihormalovanyi/SUI-InputModifier/documentation/inputviewkit).

## Looking for custom keyboards on a real `TextField`?

That's a different (and well-served) niche: editing real text with cursor and selection
through a custom key layout. Use
[CustomKeyboardKit](https://github.com/paescebu/CustomKeyboardKit) for that.
InputViewKit is for everything that *isn't* a text field.

## Migrating from 0.1

`input(focused:anchor:input:)` → `inputView(isPresented:content:)` (the `anchor`
parameter is gone). The introspection-based `input(input:anchor:)` overload was removed —
see the section above. Module name changed: `import InputViewKit`.

## License

MIT — see [LICENSE](LICENSE).
```

- [ ] **Step 2: Create `CHANGELOG.md`**

```markdown
# Changelog

## Unreleased (1.0.0)

### Added
- `inputView(isPresented:content:)` — custom input panel for any SwiftUI view.
- `inputView(_:equals:content:)` — multi-field focus with panel-preserving switching.
- Full environment forwarding into the panel (including `@EnvironmentObject`).
- Live self-sizing to the content's ideal height.
- DocC catalog, example app, behavior test suite, CI.

### Changed
- **Breaking:** module renamed `SUI_InputModifier` → `InputViewKit`.
- **Breaking:** minimum iOS raised to 16; tools version lowered to 6.0 (Xcode 16+).

### Removed
- **Breaking:** `anchor` parameter (incidental, untestable behavior).
- **Breaking:** introspection overload `input(input:anchor:)` and the UIViewFinder
  dependency — the package now has zero dependencies.
```

- [ ] **Step 3: Create `.spi.yml`**

```yaml
version: 1
builder:
  configs:
    - documentation_targets: [InputViewKit]
      platform: ios
```

- [ ] **Step 4: Fix the GitHub repo description**

```bash
gh repo edit ihormalovanyi/SUI-InputModifier \
  --description "InputViewKit — custom input panels (in place of the keyboard) for any SwiftUI view. iOS 16+, zero dependencies."
```

Expected: command succeeds; `gh repo view --json description` shows the new text
(no `[tmp description]`).

- [ ] **Step 5: Commit**

```bash
git add README.md CHANGELOG.md .spi.yml
git commit -m "docs: rewrite README, add CHANGELOG and Swift Package Index manifest"
```

---

### Task 13: CI workflow

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: Write the workflow**

```yaml
name: CI

on:
  push:
    branches: [main, "redesign/**"]
  pull_request:

jobs:
  test:
    name: Build & test (iOS Simulator)
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4
      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode.app
      - name: Resolve a simulator
        id: sim
        run: |
          DEVICE=$(xcrun simctl list devices available | grep -E '^\s+iPhone' | head -1 | sed -E 's/^ +([^(]+) \(.*/\1/' | xargs)
          echo "device=$DEVICE" >> "$GITHUB_OUTPUT"
          echo "Using simulator: $DEVICE"
      - name: Test package
        run: |
          xcodebuild test \
            -scheme SUI-InputModifier \
            -destination "platform=iOS Simulator,name=${{ steps.sim.outputs.device }}" \
            -quiet
      - name: Build example app
        run: |
          xcodebuild build \
            -project Examples/InputViewKitDemo/InputViewKitDemo.xcodeproj \
            -scheme InputViewKitDemo \
            -destination 'generic/platform=iOS Simulator' \
            CODE_SIGNING_ALLOWED=NO \
            -quiet
      - name: Build documentation
        run: |
          xcodebuild docbuild \
            -scheme SUI-InputModifier \
            -destination 'generic/platform=iOS Simulator' \
            -quiet
```

- [ ] **Step 2: Commit and push the branch**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add build, test, demo and docs workflow"
git push -u origin redesign/1.0
```

- [ ] **Step 3: Watch the run**

```bash
gh run watch --repo ihormalovanyi/SUI-InputModifier --exit-status || gh run view --log-failed
```

Expected: green. If the runner image `macos-26` is unavailable, fall back to the newest
available macOS image and re-push; if no iPhone simulator matches, the `Resolve a
simulator` step's output shows what is available — adjust only that step.

---

### Task 14: Final verification sweep

- [ ] **Step 1: Full local gate**

Run: TEST, then DOCC, then DEMO, then `swift build` (macOS inert build).
Expected: all green.

- [ ] **Step 2: Contract walk-through against the spec**

Check each guarantee from spec §6 has a passing test or a demo screen:

| Guarantee | Covered by |
|---|---|
| 1. Presentation/avoidance | `presentsAndDismissesWithBinding` + demo |
| 2. Two-way sync | `externalDismissalSyncsBindingToFalse`, `externalResignFiresCallbackOnce` |
| 3. Switching without dismissal | `switchingFieldsKeepsBindingAndMovesFocus` + Form demo |
| 4. Stable identity | `panelStateSurvivesShowHideCycle` |
| 5. Full environment | `panelReceivesHostEnvironmentIncludingObjects` + Theme demo |
| 6. Self-sizing | `SelfSizingInputView` recipe (probe-verified) + demo visual |
| 7. Limitations documented | `Limitations.md` |

- [ ] **Step 3: Repo hygiene check**

```bash
git ls-files | grep -E 'xcuserdata|xcuserstate' && echo "FAIL: user state tracked" || echo "OK"
gh repo view ihormalovanyi/SUI-InputModifier --json description -q .description
```

Expected: `OK`; description without `[tmp description]`.

- [ ] **Step 4: Done — hand back for owner review**

Open a PR from `redesign/1.0` to `main` (do not merge; owner reviews first):

```bash
gh pr create --repo ihormalovanyi/SUI-InputModifier \
  --base main --head redesign/1.0 \
  --title "InputViewKit 1.0" \
  --body "$(cat <<'EOF'
Rebuild per the approved design spec (docs/superpowers/specs/2026-06-10-inputviewkit-1.0-design.md):

- `InputViewKit` module: `.inputView(isPresented:)` + `.inputView(_:equals:)` for any view
- Plain-UIView proxy responder, full environment forwarding, verified live self-sizing
- 11 behavior tests, DocC catalog, example app (3 screens), CI
- Zero dependencies, iOS 16+, tools 6.0, repo hygiene fixes

Tagging 1.0.0 is a separate owner-triggered step after this merges.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Self-review (performed at planning time)

**Spec coverage:** §4 decisions → Tasks 2, 7 (API), 2 (manifest/tools/iOS 16), 5 (plain
UIView proxy); §5 API → Task 7; §6 contract → Tasks 7, 8, 14 (matrix); §7 architecture →
Tasks 3–6 (one file per unit, names match spec table; `InputFocusBinding` drops the
unused `activate()` — noted in header); §8 tests → Tasks 2, 5, 7, 8 + CI Task 13; §9
example app → Task 11; §10 docs → Tasks 10, 12; §11 hygiene → Tasks 1, 12; §12
workflow → Tasks 13, 14. No uncovered spec sections.

**Known risks flagged inline:** DocC symbol-link resolution (Task 10 fallback),
`\.self` environment keypath (Task 3 fallback), pbxproj parse (Task 11 Step 7), CI
runner image / simulator name (Task 13 Step 3). Each has a concrete fallback in place.

**Type consistency check:** `InputFocusBinding.bool/.value(_:equals:)` (Tasks 2, 7),
`setDesiredFocus`, `onResignedExternally`, `hostedInputView` (Tasks 5, 6),
`setIdealContentHeight`, `onSizeShouldReload` (Tasks 4, 6), `InputHostRoot(environment:content:onHeightChange:)`
(Tasks 3, 6), harness `proxies()/proxy()/settle` (Tasks 7, 8) — all call sites match
definitions.

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
labels, rows, avatars — anything can take input. On iOS 26 the panel automatically
sits in the rounded Liquid Glass keyboard chrome, on the system keyboard material.

> **Demo:** open `Examples/InputViewKitDemo` (Xcode 16+) — calculator, multi-field
> form with next/done, and environment theming.

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
  presented.
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

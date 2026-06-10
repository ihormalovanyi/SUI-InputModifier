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

### Guides

- <doc:MultiFieldForms>
- <doc:HowItWorks>
- <doc:Limitations>

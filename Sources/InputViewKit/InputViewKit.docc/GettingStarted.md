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

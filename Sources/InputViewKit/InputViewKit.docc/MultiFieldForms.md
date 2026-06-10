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

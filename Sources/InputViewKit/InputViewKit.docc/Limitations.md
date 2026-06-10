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

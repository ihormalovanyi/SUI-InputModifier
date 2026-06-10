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

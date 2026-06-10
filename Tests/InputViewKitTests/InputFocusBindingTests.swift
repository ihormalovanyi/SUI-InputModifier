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
        var writes = 0
        let binding = Binding(get: { selection }, set: { selection = $0; writes += 1 })
        let focusA = InputFocusBinding.value(binding, equals: Field.a)

        selection = .b              // B already claimed focus
        focusA.deactivate()         // A's late resign must NOT clear it
        #expect(selection == .b)
        #expect(writes == 0, "guard must not write at all when the value moved on")

        selection = nil             // already deactivated
        focusA.deactivate()
        #expect(writes == 0, "deactivate over nil must be a no-op write-wise")

        selection = .a
        focusA.deactivate()         // but A clears itself when it owns focus
        #expect(selection == nil)
        #expect(writes == 1)
    }
}

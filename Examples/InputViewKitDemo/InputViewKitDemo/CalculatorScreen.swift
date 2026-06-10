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
                        .accessibilityAddTraits(.isButton)
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

    /// Per-session digit buffer — also demonstrates that panel @State
    /// survives show/hide cycles. Integer-only by design; for fractional
    /// input use a locale-aware formatter, never String(describing: Decimal).
    @State private var digits = ""

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
                        .accessibilityLabel(key == "⌫" ? "Delete" : key == "C" ? "Clear" : key)
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
            digits = ""
        case "⌫":
            if !digits.isEmpty { digits.removeLast() }
        default:
            digits += key
        }
        amount = Decimal(string: digits.isEmpty ? "0" : digits) ?? 0
    }
}

#Preview {
    CalculatorScreen()
}

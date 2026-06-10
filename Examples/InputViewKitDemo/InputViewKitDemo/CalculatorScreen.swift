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

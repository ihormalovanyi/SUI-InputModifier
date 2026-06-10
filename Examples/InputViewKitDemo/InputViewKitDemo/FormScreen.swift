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
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    FormScreen()
}

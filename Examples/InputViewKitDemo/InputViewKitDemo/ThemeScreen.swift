import SwiftUI
import InputViewKit

@MainActor
final class ThemeStore: ObservableObject {
    @Published var accent: Color = .indigo
}

struct ThemeScreen: View {
    @StateObject private var theme = ThemeStore()
    @State private var mood = "—"
    @State private var isPicking = false

    var body: some View {
        NavigationStack {
            List {
                Section("Environment demo") {
                    HStack {
                        Text("Mood")
                        Spacer()
                        Text(mood).foregroundStyle(theme.accent)
                    }
                    .contentShape(Rectangle())
                    .accessibilityAddTraits(.isButton)
                    .inputView(isPresented: $isPicking) {
                        MoodPad(selection: $mood)
                    }
                    .onTapGesture { isPicking = true }

                    Picker("Accent", selection: $theme.accent) {
                        Text("Indigo").tag(Color.indigo)
                        Text("Orange").tag(Color.orange)
                        Text("Teal").tag(Color.teal)
                    }
                }
                Section {
                    Text("The pad reads ThemeStore via @EnvironmentObject — the host's environment is forwarded into the panel.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Theme")
        }
        .environmentObject(theme)
    }
}

#Preview {
    ThemeScreen()
}

struct MoodPad: View {
    @EnvironmentObject var theme: ThemeStore
    @Binding var selection: String

    private let moods = ["😀", "😎", "🤔", "😴", "🔥", "❄️", "🎯", "🌊"]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
            ForEach(moods, id: \.self) { mood in
                Button { selection = mood } label: {
                    Text(mood)
                        .font(.largeTitle)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(theme.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(16)
    }
}

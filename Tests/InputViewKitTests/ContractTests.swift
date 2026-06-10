import SwiftUI
import Testing
@testable import InputViewKit

@MainActor
final class ContractModel: ObservableObject {
    enum Field: Hashable { case a, b }
    @Published var field: Field?
    @Published var isPresented = false
}

/// Reference box for observing panel-internal effects from tests.
@MainActor
final class Recorder {
    var stateValues: [Int] = []
    var environmentReads: [String] = []
}

@MainActor
final class ThemeObject: ObservableObject {
    @Published var name = "aurora"
}

@Suite(.serialized)
@MainActor
struct ContractTests {

    // MARK: Switching (equals)

    private struct TwoFieldHost: View {
        @ObservedObject var model: ContractModel
        var body: some View {
            VStack {
                Text("a").inputView($model.field, equals: .a) { Color.red.frame(height: 200) }
                Text("b").inputView($model.field, equals: .b) { Color.blue.frame(height: 200) }
            }
        }
    }

    @Test func switchingFieldsKeepsBindingAndMovesFocus() async throws {
        let model = ContractModel()
        let harness = IntegrationHarness { TwoFieldHost(model: model) }
        await settle()
        let proxies = harness.proxies()
        #expect(proxies.count == 2)

        model.field = .a
        await settle()
        let first = try #require(proxies.first(where: { $0.isFirstResponder }))

        model.field = .b
        await settle(800)
        #expect(model.field == .b, "A's late resign must not clear B's claim")
        let second = try #require(proxies.first(where: { $0.isFirstResponder }))
        #expect(first !== second, "focus must have moved to the other proxy")

        model.field = nil
        await settle()
        #expect(harness.proxies().allSatisfy { !$0.isFirstResponder })
    }

    // MARK: State survival across show/hide

    private struct StatefulPanel: View {
        let recorder: Recorder
        @State private var counter = 0
        var body: some View {
            Color.green
                .frame(height: 120)
                .onAppear {
                    counter += 1
                    recorder.stateValues.append(counter)
                }
        }
    }

    private struct SurvivalHost: View {
        @ObservedObject var model: ContractModel
        let recorder: Recorder
        var body: some View {
            Text("host").inputView(isPresented: $model.isPresented) {
                StatefulPanel(recorder: recorder)
            }
        }
    }

    @Test func panelStateSurvivesShowHideCycle() async throws {
        let model = ContractModel()
        let recorder = Recorder()
        let harness = IntegrationHarness { SurvivalHost(model: model, recorder: recorder) }
        _ = harness

        model.isPresented = true
        await settle(800)
        model.isPresented = false
        await settle(800)
        model.isPresented = true
        await settle(800)

        // @State persisted across the hide: the counter kept its value,
        // so a second onAppear records 2 (a reset identity would record 1 again).
        #expect(recorder.stateValues.contains(2),
                "panel @State must survive show/hide, got \(recorder.stateValues)")
        #expect(!recorder.stateValues.dropFirst().contains(1),
                "identity reset detected: counter restarted from zero")
    }

    // MARK: Environment forwarding

    private struct EnvPanel: View {
        @EnvironmentObject var theme: ThemeObject
        @Environment(\.locale) var locale
        let recorder: Recorder
        var body: some View {
            Color.clear
                .frame(height: 80)
                .onAppear {
                    recorder.environmentReads.append(theme.name)
                    recorder.environmentReads.append(locale.identifier)
                }
                .onReceive(theme.$name.dropFirst()) { newName in
                    recorder.environmentReads.append(newName)
                }
        }
    }

    private struct EnvHost: View {
        @ObservedObject var model: ContractModel
        let recorder: Recorder
        let theme: ThemeObject
        var body: some View {
            Text("host")
                .inputView(isPresented: $model.isPresented) {
                    EnvPanel(recorder: recorder)
                }
                .environmentObject(theme)
                .environment(\.locale, Locale(identifier: "uk_UA"))
        }
    }

    @Test func panelReceivesHostEnvironmentIncludingObjects() async throws {
        let model = ContractModel()
        let recorder = Recorder()
        let theme = ThemeObject()
        let harness = IntegrationHarness { EnvHost(model: model, recorder: recorder, theme: theme) }
        _ = harness

        model.isPresented = true
        await settle(800)

        // In 0.1 this crashed (no EnvironmentObject in the hosted tree).
        #expect(recorder.environmentReads.contains("aurora"))
        #expect(recorder.environmentReads.contains("uk_UA"))

        // Mutation channel: ObservableObject changes re-render inside the
        // hosting controller WITHOUT a host updateUIView.
        theme.name = "nebula"
        await settle(800)
        #expect(recorder.environmentReads.contains("nebula"),
                "object mutation must re-render the hosted panel")
    }
}

import SwiftUI
import Testing
@testable import InputViewKit

@MainActor
final class PresentationModel: ObservableObject {
    @Published var isPresented = false
}

private enum ProbeField: Hashable { case amount }

@MainActor
private final class SelectionModel: ObservableObject {
    @Published var focus: ProbeField?
}

@Suite(.serialized)
@MainActor
struct PresentationTests {

    private struct Host: View {
        @ObservedObject var model: PresentationModel
        var body: some View {
            Text("amount")
                .inputView(isPresented: $model.isPresented) {
                    Color.red.frame(height: 220)
                }
        }
    }

    @Test func presentsAndDismissesWithBinding() async throws {
        let model = PresentationModel()
        let harness = IntegrationHarness { Host(model: model) }
        await settle()
        let proxy = try #require(harness.proxy())
        #expect(!proxy.isFirstResponder)

        model.isPresented = true
        await settle()
        #expect(proxy.isFirstResponder)

        model.isPresented = false
        await settle()
        #expect(!proxy.isFirstResponder)
    }

    @Test func externalDismissalSyncsBindingToFalse() async throws {
        let model = PresentationModel()
        let harness = IntegrationHarness { Host(model: model) }
        model.isPresented = true
        await settle()
        let proxy = try #require(harness.proxy())
        #expect(proxy.isFirstResponder)

        harness.window.endEditing(true)
        await settle()
        #expect(!proxy.isFirstResponder)
        #expect(model.isPresented == false, "binding must never lie about responder state")
    }

    @Test func focusRequestedBeforeWindowAttachPresentsAfterAttach() async throws {
        let model = PresentationModel()
        model.isPresented = true            // requested before any window exists
        let harness = IntegrationHarness { Host(model: model) }
        await settle()
        let proxy = try #require(harness.proxy())
        #expect(proxy.isFirstResponder)
    }

    private struct SelectionHost: View {
        @ObservedObject var model: SelectionModel
        var body: some View {
            Text("amount")
                .inputView($model.focus, equals: .amount) {
                    Color.blue.frame(height: 180)
                }
        }
    }

    @Test func externalDismissalSyncsValueBindingToNil() async throws {
        let model = SelectionModel()
        model.focus = .amount
        let harness = IntegrationHarness { SelectionHost(model: model) }
        await settle()
        let proxy = try #require(harness.proxy())
        #expect(proxy.isFirstResponder)

        harness.window.endEditing(true)
        await settle()
        #expect(!proxy.isFirstResponder)
        #expect(model.focus == nil, "value binding must be nil-ed on external dismissal")
    }
}

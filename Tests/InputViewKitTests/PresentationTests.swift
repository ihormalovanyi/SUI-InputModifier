import SwiftUI
import Testing
@testable import InputViewKit

@MainActor
final class PresentationModel: ObservableObject {
    @Published var isPresented = false
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
}

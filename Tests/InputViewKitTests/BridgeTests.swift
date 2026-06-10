import SwiftUI
import UIKit
import Testing
@testable import InputViewKit

private struct ProbeKey: EnvironmentKey {
    static let defaultValue = "default"
}

extension EnvironmentValues {
    fileprivate var probeValue: String {
        get { self[ProbeKey.self] }
        set { self[ProbeKey.self] = newValue }
    }
}

@MainActor
private final class BridgeRecorder {
    var heights: [CGFloat] = []
    var environmentReads: [String] = []
    var externalResigns = 0
}

private struct ProbeReader: View {
    let recorder: BridgeRecorder
    @Environment(\.probeValue) private var probeValue

    var body: some View {
        Color.red
            .frame(height: 133)
            .onAppear { recorder.environmentReads.append(probeValue) }
    }
}

@Suite(.serialized)
@MainActor
struct BridgeTests {

    func settle() async {
        try? await Task.sleep(for: .milliseconds(300))
    }

    func makeWindow() -> UIWindow {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        return window
    }

    @Test func dismantleClearsCallbackAndResignsSilently() async {
        let window = makeWindow()
        let proxy = ProxyInputView()
        window.rootViewController!.view.addSubview(proxy)

        let recorder = BridgeRecorder()
        proxy.onResignedExternally = { recorder.externalResigns += 1 }
        proxy.setDesiredFocus(true)
        await settle()
        #expect(proxy.isFirstResponder)

        ProxyInputRepresentable<EmptyView>.dismantleUIView(proxy, coordinator: .init())

        #expect(proxy.onResignedExternally == nil)
        #expect(!proxy.isFirstResponder)
        await settle()   // drain the pending coalesced apply
        #expect(!proxy.isFirstResponder, "pending apply must not re-focus after dismantle")
        #expect(recorder.externalResigns == 0, "teardown resign must be silent")
    }

    @Test func inputHostRootForwardsEnvironmentAndReportsHeight() async {
        let recorder = BridgeRecorder()

        var environment = EnvironmentValues()
        environment.probeValue = "forwarded"

        let root = InputHostRoot(
            environment: environment,
            content: ProbeReader(recorder: recorder),
            onHeightChange: { recorder.heights.append($0) }
        )

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIHostingController(rootView: root)
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        await settle()

        #expect(recorder.environmentReads == ["forwarded"],
                "custom environment key must reach the hosted tree")
        #expect(recorder.heights.contains(133),
                "ideal content height must be reported")
    }
}

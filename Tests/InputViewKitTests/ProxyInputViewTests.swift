import UIKit
import Testing
@testable import InputViewKit

@MainActor
struct ProxyInputViewTests {

    /// Pumps the main queue so the proxy's coalesced async focus apply runs.
    func settle() async {
        try? await Task.sleep(for: .milliseconds(300))
    }

    func makeWindow() -> UIWindow {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        return window
    }

    @Test func becomesAndResignsWithDesiredFocus() async {
        let window = makeWindow()
        let proxy = ProxyInputView()
        window.rootViewController!.view.addSubview(proxy)

        proxy.setDesiredFocus(true)
        await settle()
        #expect(proxy.isFirstResponder)

        proxy.setDesiredFocus(false)
        await settle()
        #expect(!proxy.isFirstResponder)
    }

    @Test func pendingFocusAppliesOnWindowAttach() async {
        let window = makeWindow()
        let proxy = ProxyInputView()
        proxy.setDesiredFocus(true)        // not in a window yet
        await settle()
        #expect(!proxy.isFirstResponder)

        window.rootViewController!.view.addSubview(proxy)
        await settle()
        #expect(proxy.isFirstResponder, "didMoveToWindow must apply pending focus")
    }

    @Test func externalResignFiresCallbackOnce() async {
        let window = makeWindow()
        let proxy = ProxyInputView()
        window.rootViewController!.view.addSubview(proxy)

        var externalResigns = 0
        proxy.onResignedExternally = { externalResigns += 1 }

        proxy.setDesiredFocus(true)
        await settle()
        #expect(proxy.isFirstResponder)

        window.endEditing(true)            // system-side dismissal
        await settle()
        #expect(!proxy.isFirstResponder)
        #expect(externalResigns == 1)
    }

    @Test func bindingDrivenResignDoesNotFireCallback() async {
        let window = makeWindow()
        let proxy = ProxyInputView()
        window.rootViewController!.view.addSubview(proxy)

        var externalResigns = 0
        proxy.onResignedExternally = { externalResigns += 1 }

        proxy.setDesiredFocus(true)
        await settle()
        proxy.setDesiredFocus(false)       // our own dismissal
        await settle()
        #expect(!proxy.isFirstResponder)
        #expect(externalResigns == 0, "no echo when the binding initiated the resign")
    }
}

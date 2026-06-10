import SwiftUI
import UIKit
@testable import InputViewKit

/// Hosts a SwiftUI hierarchy in a real key window so responder state,
/// keyboard plumbing and the async focus engine behave as in an app.
@MainActor
final class IntegrationHarness {
    let window: UIWindow

    init<V: View>(@ViewBuilder content: () -> V) {
        window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIHostingController(rootView: content())
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
    }

    deinit {
        let window = self.window
        MainActor.assumeIsolated {
            window.isHidden = true
            window.rootViewController = nil
        }
    }

    /// All `ProxyInputView`s found in the window, depth-first.
    func proxies() -> [ProxyInputView] {
        func collect(_ view: UIView) -> [ProxyInputView] {
            var found: [ProxyInputView] = []
            if let proxy = view as? ProxyInputView { found.append(proxy) }
            for subview in view.subviews { found.append(contentsOf: collect(subview)) }
            return found
        }
        return collect(window)
    }

    func proxy() -> ProxyInputView? { proxies().first }
}

/// Pumps the main queue long enough for coalesced focus applies,
/// keyboard transitions and SwiftUI re-renders to settle.
///
/// Call sites use 800 ms where a keyboard PRESENTATION is involved:
/// UIKit's keyboard animation (~250–350 ms) + hosting-controller
/// propagation headroom. Do not reduce without re-running the suite
/// repeatedly — these are real-window integration tests.
@MainActor
func settle(_ milliseconds: Int = 500) async {
    try? await Task.sleep(for: .milliseconds(milliseconds))
}

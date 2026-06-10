#if os(iOS)
import SwiftUI
import UIKit

/// Bridges the proxy responder into SwiftUI and owns the hosting pipeline:
/// proxy → SelfSizingInputView wrapper → UIHostingController<InputHostRoot>.
struct ProxyInputRepresentable<Content: View>: UIViewRepresentable {

    let focus: InputFocusBinding
    let content: () -> Content

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ProxyInputView {
        let coordinator = context.coordinator
        let proxy = ProxyInputView()
        proxy.isUserInteractionEnabled = false
        proxy.isAccessibilityElement = false

        let wrapper = SelfSizingInputView()
        let host = UIHostingController(rootView: makeRoot(context: context, coordinator: coordinator))
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.sizingOptions = .intrinsicContentSize

        wrapper.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: wrapper.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor)
        ])
        wrapper.onSizeShouldReload = { [weak proxy] in
            proxy?.reloadInputViews()
        }

        coordinator.hostingController = host
        coordinator.wrapper = wrapper
        coordinator.focus = focus

        proxy.hostedInputView = wrapper
        proxy.onResignedExternally = { [weak coordinator] in
            coordinator?.focus?.deactivate()
        }
        return proxy
    }

    func updateUIView(_ proxy: ProxyInputView, context: Context) {
        let coordinator = context.coordinator
        coordinator.focus = focus
        coordinator.hostingController?.rootView = makeRoot(context: context, coordinator: coordinator)
        proxy.setDesiredFocus(focus.isActive())
    }

    /// Teardown contract (see ProxyInputView.onResignedExternally docs):
    /// clear the callback and desired focus BEFORE the view leaves the
    /// hierarchy, so an in-flight coalesced apply cannot re-focus the proxy
    /// and the final resign takes the silent path — no binding write occurs
    /// from within a SwiftUI removal transaction.
    static func dismantleUIView(_ proxy: ProxyInputView, coordinator: Coordinator) {
        proxy.onResignedExternally = nil
        proxy.setDesiredFocus(false)
        if proxy.isFirstResponder {
            proxy.resignFirstResponder()
        }
    }

    private func makeRoot(context: Context, coordinator: Coordinator) -> InputHostRoot<Content> {
        InputHostRoot(
            environment: context.environment,
            content: content(),
            onHeightChange: { [weak coordinator] height in
                coordinator?.wrapper?.setIdealContentHeight(height)
            }
        )
    }

    @MainActor
    final class Coordinator {
        var hostingController: UIHostingController<InputHostRoot<Content>>?
        var wrapper: SelfSizingInputView?
        var focus: InputFocusBinding?
    }
}
#endif

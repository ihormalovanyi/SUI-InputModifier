import SwiftUI
import UIViewFinder

public extension View {
    
    @ViewBuilder func input<Input: View>(focused: Binding<Bool>, anchor: Alignment = .center, input: @escaping () -> Input) -> some View {
        background(alignment: anchor) {
            //TODO: workaround: AnyView is a semisolution keeping the input's identity
            _InputView(focused: focused) { .init(input().id(focused.wrappedValue)) }
                .frame(width: 0, height: 0)
                .opacity(0)
        }
    }
    
    @ViewBuilder func input<Input: View>(input: @escaping () -> Input, anchor: Alignment = .center) -> some View {
        
        findUIView((UITextInput & UIView).self) { view in
            let hostingController = UIHostingController(rootView: input())
            hostingController.view.backgroundColor = .clear
            hostingController.view.translatesAutoresizingMaskIntoConstraints = false
            if let view = view as? UITextField {
                view.inputView = hostingController.view
            } else if let view = view as? UITextView {
                view.inputView = hostingController.view
            }
        }
    }
 
}

private struct _InputView: UIViewRepresentable {
 
    @Binding var focused: Bool
    let content: () -> AnyView
    
    func makeUIView(context: Context) -> UITextField {
        let hostingController = UIHostingController(rootView: content())
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        context.coordinator.controller = hostingController
        context.coordinator.focused = $focused
        
        let textField = UITextField()
        textField.delegate = context.coordinator
        textField.inputView = hostingController.view
        textField.inputAccessoryView = UIView(frame: .zero)
        
        return textField
    }
    
    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.controller?.rootView = content()
        DispatchQueue.main.async {
            if focused {
                uiView.becomeFirstResponder()
            } else {
                uiView.resignFirstResponder()
            }
        }
    }
    
    func makeCoordinator() -> Coordinator { .init() }
    
    final class Coordinator: NSObject, UITextFieldDelegate {
        
        var controller: UIHostingController<AnyView>?
        var focused: Binding<Bool>?
        
        func textFieldDidEndEditing(_ textField: UITextField) {
            if focused?.wrappedValue == true {
                focused?.wrappedValue = false
            }
        }
    }
    
}

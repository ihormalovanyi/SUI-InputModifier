import SwiftUI

public extension View {
    
    @ViewBuilder func input<Input: View>(focused: Binding<Bool>, anchor: Alignment = .center, input: @escaping () -> Input) -> some View {
        background(alignment: anchor) {
            _InputView(focused: focused, content: input)
                .frame(width: 0, height: 0)
                .opacity(0)
        }
    }
    
    @ViewBuilder func input<Input: View>(input: @escaping () -> Input, anchor: Alignment = .center) -> some View {
        background(alignment: anchor) {
            _TextInputView(input: input)
                .frame(width: 0, height: 0)
                .opacity(0)
        }
    }
 
}

private struct _InputView<Content: View>: UIViewRepresentable {
 
    @Binding var focused: Bool
    let content: () -> Content
    
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
        
        var controller: UIHostingController<Content>?
        var focused: Binding<Bool>?
        
        func textFieldDidEndEditing(_ textField: UITextField) {
            if focused?.wrappedValue == true {
                focused?.wrappedValue = false
            }
        }
    }
    
}

private struct _TextInputView<Input: View>: UIViewRepresentable {
    
    let input: () -> Input
    
    func makeUIView(context: Context) -> UIView { .init() }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            if context.coordinator.textInput == nil {
                guard let parentView = uiView.superview?.superview else { return }
                let hostingController = UIHostingController(rootView: input())
                hostingController.view.backgroundColor = .clear
                hostingController.view.translatesAutoresizingMaskIntoConstraints = false
                
                if let textInput = findTargetTextField(from: parentView, relativeTo: uiView) {
                    if let textField = textInput as? UITextField {
                        textField.inputView = hostingController.view
                    } else if let textView = textInput as? UITextView {
                        textView.inputView = hostingController.view
                    }
                    
                    context.coordinator.controller = hostingController
                    context.coordinator.textInput = textInput
                }
            } else {
                context.coordinator.controller?.rootView = input()
            }
        }
    }
    
    private func findTargetTextField(from root: UIView, relativeTo sourceView: UIView) -> UITextInput? {
        let sourceFrame = sourceView.convert(sourceView.bounds, to: nil)
        
        typealias UITextInputView = UITextInput & UIView
        
        func findAllTextInputs(in view: UIView) -> [UITextInputView] {
            var results = [UITextInputView]()
            if let input = view as? UITextInputView {
                results.append(input)
            }
            for sub in view.subviews {
                results.append(contentsOf: findAllTextInputs(in: sub))
            }
            return results
        }
        
        let allInputs = findAllTextInputs(in: root)
        
        for input in allInputs {
            let frame = input.convert(input.bounds, to: nil)
            if frame.intersects(sourceFrame) {
                return input
            }
        }
        
        return nil
    }
    
    func makeCoordinator() -> Coordinator { .init() }
    final class Coordinator {
        
        weak var textInput: UITextInput?
        var controller: UIHostingController<Input>?
        
    }
    
}


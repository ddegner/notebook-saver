import SwiftUI
import Combine

// A view modifier that handles keyboard appearance and disappearance
struct KeyboardAwareModifier: ViewModifier {
    @Binding var keyboardHeight: CGFloat
    let includeDismissal: Bool
    
    init(keyboardHeight: Binding<CGFloat>, includeDismissal: Bool = true) {
        self._keyboardHeight = keyboardHeight
        self.includeDismissal = includeDismissal
    }
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                NotificationCenter.default.addObserver(
                    forName: UIResponder.keyboardWillShowNotification,
                    object: nil,
                    queue: .main
                ) { notification in
                    let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect ?? .zero
                    // Add a small buffer to ensure text field is fully visible
                    keyboardHeight = keyboardFrame.height + 20
                }
                
                NotificationCenter.default.addObserver(
                    forName: UIResponder.keyboardWillHideNotification,
                    object: nil,
                    queue: .main
                ) { _ in
                    keyboardHeight = 0
                }
            }
            .onDisappear {
                NotificationCenter.default.removeObserver(
                    self,
                    name: UIResponder.keyboardWillShowNotification,
                    object: nil
                )
                NotificationCenter.default.removeObserver(
                    self,
                    name: UIResponder.keyboardWillHideNotification,
                    object: nil
                )
            }
            .conditionalTapToDismiss(enabled: includeDismissal)
    }
}

// A simple modifier that only handles keyboard dismissal
struct KeyboardDismissalModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onTapGesture {
                dismissKeyboard()
            }
    }
    
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// Helper modifier for conditional tap-to-dismiss
struct ConditionalTapToDismissModifier: ViewModifier {
    let enabled: Bool
    
    func body(content: Content) -> some View {
        if enabled {
            content.modifier(KeyboardDismissalModifier())
        } else {
            content
        }
    }
}

// Extension to make the modifiers easier to use
extension View {
    func keyboardAware(keyboardHeight: Binding<CGFloat>, includeDismissal: Bool = true) -> some View {
        self.modifier(KeyboardAwareModifier(keyboardHeight: keyboardHeight, includeDismissal: includeDismissal))
    }
    
    func dismissKeyboardOnTap() -> some View {
        self.modifier(KeyboardDismissalModifier())
    }
    
    fileprivate func conditionalTapToDismiss(enabled: Bool) -> some View {
        self.modifier(ConditionalTapToDismissModifier(enabled: enabled))
    }
}
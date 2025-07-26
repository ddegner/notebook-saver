import SwiftUI
import Combine

// A view modifier that handles keyboard appearance and disappearance
struct KeyboardAwareModifier: ViewModifier {
    @Binding var keyboardHeight: CGFloat
    
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
    }
}

// Extension to make the modifier easier to use
extension View {
    func keyboardAware(keyboardHeight: Binding<CGFloat>) -> some View {
        self.modifier(KeyboardAwareModifier(keyboardHeight: keyboardHeight))
    }
}
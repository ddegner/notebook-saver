import SwiftUI

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

extension View {
    func dismissKeyboardOnTap() -> some View {
        self.modifier(KeyboardDismissalModifier())
    }
}

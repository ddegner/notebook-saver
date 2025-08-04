import SwiftUI

class AppStateManager: ObservableObject {
    @Published var showOnboarding = false
    @Published var shouldReloadAPIKey = false
    
    func presentOnboarding() {
        showOnboarding = true
    }
    
    func dismissOnboarding() {
        showOnboarding = false
    }
    
    func triggerAPIKeyReload() {
        shouldReloadAPIKey.toggle()
    }
}
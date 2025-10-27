import SwiftUI

class AppStateManager: ObservableObject {
    @Published var showOnboarding = false
    @Published var shouldReloadAPIKey = false
    @Published var imageToProcess: URL?
    @Published var isProcessingOpenedImage: Bool = false
    
    func presentOnboarding() {
        showOnboarding = true
    }
    
    func dismissOnboarding() {
        showOnboarding = false
    }
    
    func triggerAPIKeyReload() {
        shouldReloadAPIKey.toggle()
    }
    
    func processOpenedImage(url: URL) {
        imageToProcess = url
        isProcessingOpenedImage = true
    }
    
    func clearOpenedImage() {
        imageToProcess = nil
        isProcessingOpenedImage = false
    }
}
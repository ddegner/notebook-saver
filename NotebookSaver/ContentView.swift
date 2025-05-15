import SwiftUI

struct ContentView: View {
    @State private var isShowingSettings = false
    // Will likely need access to CameraManager, GeminiService etc.
    // Either via @StateObject, @EnvironmentObject, or passed in.

    var body: some View {
        // Use a ZStack to overlay buttons/indicators on the CameraView
        ZStack {
            // The CameraView should be the base layer
            // Placeholder until CameraView is implemented
            CameraView(isShowingSettings: $isShowingSettings)
                .edgesIgnoringSafeArea(.all)

        }
        // Present the SettingsView as a sheet
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
            // Optional: Add presentation detents if needed
            // .presentationDetents([.medium, .large])
        }
    }
}

#Preview {
    ContentView()
}

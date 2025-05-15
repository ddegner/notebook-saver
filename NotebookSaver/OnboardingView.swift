import SwiftUI

struct OnboardingView: View {
    @AppStorage("ocrEngine") private var ocrEngine: String = "vision" // Default to vision
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var apiKey = ""
    @State private var showSaveConfirmation = false
    @State private var apiKeyStatusMessage = ""
    @State private var showingApiKeyEntry = false // State to control API key section visibility
    @Binding var isOnboarding: Bool // This binding controls the sheet presentation

    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                // Feature Explanation & Choice Section
                ocrChoiceSection
                    .padding(.horizontal)
                    .padding(.top, 40)

                // Conditional API Key Entry Section
                if showingApiKeyEntry {
                    geminiApiKeySection
                        .padding()
                        .background(
                            // Use adaptive material background
                            .thinMaterial,
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                        .padding(.horizontal)
                        .transition(.opacity.combined(with: .scale)) // Add animation
                }

                Spacer() // Pushes content up
            }
            .padding(.vertical)
        }

        // Dismiss button (only shown before API key entry is visible)
        if !showingApiKeyEntry {
             Button("Decide Later (Use Apple Vision)") {
                  setDefaultAndDismiss()
             }
             .padding()
             .font(.caption)
             .foregroundColor(.secondary)
        }
    }

    // MARK: - View Components

    private var ocrChoiceSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Update title
            Text("Choose AI")
                .font(.largeTitle) // Make it more prominent
                .fontWeight(.bold)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, alignment: .center) // Center align

            // Apple Vision Option
            engineOption(
                title: "Apple Vision", // Simplified title
                description: "Processes images on device, faster but less accurate",
                action: selectAppleVision
            )

            Divider()

            // Gemini Option
            engineOption(
                title: "Google Gemini", // Simplified title
                description: "Uses Google's" +
                    " cloud AI for higher accuracy with handwriting, but requires a free API key.",
                action: {
                    withAnimation { // Animate the appearance
                         showingApiKeyEntry = true
                    }
                }
            )
        }
        .padding()
        // Use adaptive material background
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func engineOption(title: String, description: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
            Button("Choose \(title)") {
                action()
            }
            .buttonStyle(.bordered)
            .controlSize(.small) // Smaller button
        }
    }

    private var geminiApiKeySection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Enter Your Gemini API Key")
                .font(.title3)
                .fontWeight(.semibold)

            // API Key Input
            VStack(alignment: .leading, spacing: 8) {
                 Text("Your Gemini API Key:")
                     .font(.subheadline).bold()
                 SecureField("Paste your API key here", text: $apiKey)
                     .textContentType(.password)
                     .disableAutocorrection(true)
                     .padding(10)
                     .background(
                         // Use a simple background or another material
                         Color.gray.opacity(0.1), // Example: light gray
                         in: RoundedRectangle(cornerRadius: 8)
                     )
                     .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                     )

                // Status message
                if !apiKeyStatusMessage.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: showSaveConfirmation ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundColor(showSaveConfirmation ? .green : .red)

                        Text(apiKeyStatusMessage)
                            .font(.caption)
                            .foregroundColor(showSaveConfirmation ? .green : .red)
                    }
                }
            }

            // Instructions to get an API key (Summarized)
            VStack(alignment: .leading, spacing: 12) {
                Text("How to get your free API key:")
                    .font(.headline)

                instructionStep(number: "1", text: "Go to **Google AI Studio**")
                instructionStep(number: "2", text: "Sign in with your Google account")
                instructionStep(number: "3", text: "Click **Create API key**")
                instructionStep(number: "4", text: "Copy the generated key")
                instructionStep(number: "5", text: "Paste it in the field above")

                Link(destination: URL(string: "https://aistudio.google.com/apikey")!) {
                    HStack {
                        Text("Get your API key from Google AI Studio")
                        Image(systemName: "arrow.up.right.square")
                    }
                    .font(.caption)
                    .fontWeight(.medium)
                }
                .padding(.top, 4)
                 Text("*Keep your key secure like a password.*")
                     .font(.caption2)
                     .foregroundColor(.secondary)
                     .padding(.top, 2)
            }
            .padding(.top, 8)

            Button(action: saveAPIKeyAndFinish) {
                 Text("Save Key & Finish Setup")
                     .font(.headline)
                     .fontWeight(.semibold)
                     .frame(maxWidth: .infinity)
                     .padding()
                     .background(
                         RoundedRectangle(cornerRadius: 10)
                             .fill(apiKey.isEmpty ? Color.gray.opacity(0.3) : Color.accentColor)
                     )
                     .foregroundColor(apiKey.isEmpty ? .gray : .white)
             }
             .disabled(apiKey.isEmpty)
        }
    }

    // MARK: - Helper Views

    private func instructionStep(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor))

            Text(.init(text)) // Use Markdown initialiser for bold text
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
    }

    // MARK: - Actions

    private func selectAppleVision() {
        print("Apple Vision Selected")
        ocrEngine = "vision"
        hasCompletedOnboarding = true
        isOnboarding = false // Dismiss the sheet
    }

    private func saveAPIKeyAndFinish() {
        guard !apiKey.isEmpty else {
            apiKeyStatusMessage = "API Key cannot be empty"
            showSaveConfirmation = false
            return
        }

        // Attempt to save the key
        let success = KeychainService.saveAPIKey(apiKey)

        if success {
            print("Gemini API Key Saved")
            apiKeyStatusMessage = "API Key saved successfully!"
            showSaveConfirmation = true
            ocrEngine = "gemini" // Set engine to Gemini
            hasCompletedOnboarding = true

            // Dismiss after a short delay to show confirmation
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                isOnboarding = false
            }
        } else {
            apiKeyStatusMessage = "Failed to save API Key. Please try again."
            showSaveConfirmation = false
        }
    }

    // setDefaultAndDismiss remains the same
    private func setDefaultAndDismiss() {
         if !hasCompletedOnboarding { // Only set default if they haven't finished
             print("Onboarding dismissed/closed, defaulting to Apple Vision")
             ocrEngine = "vision"
             hasCompletedOnboarding = true
         }
         isOnboarding = false // Dismiss the sheet
     }
}

#Preview {
    OnboardingView(isOnboarding: .constant(true))
}

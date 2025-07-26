import SwiftUI
import Foundation

struct OnboardingView: View {
    @AppStorage("textExtractorService") private var textExtractorService: String = TextExtractorType.vision.rawValue // Default to vision (Local)
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var apiKey = ""
    @State private var showSaveConfirmation = false
    @State private var apiKeyStatusMessage = ""
    @Binding var isOnboarding: Bool // This binding controls the sheet presentation

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 32) {
                    // Welcome Header
                    welcomeHeader
                    
                    // API Key Setup Section
                    apiKeySetupSection
                        .padding(.horizontal)

                    // Setup Later Option
                    setupLaterSection
                        .padding(.horizontal)

                    Spacer(minLength: 30)
                }
                .padding(.vertical, 30)
            }
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.orange.opacity(0.1),
                        Color.orange.opacity(0.05)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: setupLaterWithAppleVision) {
                        Image(systemName: "xmark")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - View Components

    private var welcomeHeader: some View {
        VStack(spacing: 20) {
            Text("Connect to Gemini AI for best results")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "key.fill")
                    .foregroundColor(.orange)
                    .font(.title2)
                Text("Get Gemini API Key")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
            }
        }
    }
    
    private var stepOneView: some View {
        Link(destination: URL(string: "https://aistudio.google.com/apikey")!) {
            HStack {
                Text("1")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(Color.orange)
                    )
                
                Text("Open")
                    .font(.subheadline)
                
                Text("aistudio.google.com")
                    .font(.subheadline)
                    .foregroundColor(.blue)
                    .underline()
                
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var apiKeyInputView: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("4")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(Color.orange)
                )
            
            VStack(alignment: .leading, spacing: 8) {
                SecureField("Paste key here", text: $apiKey)
                    .textContentType(.password)
                    .disableAutocorrection(true)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.white.opacity(0.8))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(apiKey.isEmpty ? Color.gray.opacity(0.3) : Color.orange.opacity(0.5), lineWidth: 1)
                    )
                
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
        }
    }
    
    private var saveButtonView: some View {
        Button(action: saveAPIKeyAndFinish) {
            HStack {
                if showSaveConfirmation {
                    Image(systemName: "checkmark")
                }
                Text(showSaveConfirmation ? "Setup Complete! 🎉" : "Save")
            }
            .font(.headline)
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 20)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(apiKey.isEmpty ? Color.gray.opacity(0.3) : Color.black)
            )
            .foregroundColor(apiKey.isEmpty ? .gray : .white)
        }
        .disabled(apiKey.isEmpty)
    }

    private var apiKeySetupSection: some View {
        VStack(alignment: .leading, spacing: 28) {
            headerView
            
            VStack(alignment: .leading, spacing: 20) {
                stepOneView
                instructionStep(number: "2", text: "Click **\"Get API key\"** in the left menu")
                instructionStep(number: "3", text: "Click **\"Create API key in new project\"**")
                apiKeyInputView
            }
            
            saveButtonView
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.orange.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }

    private var setupLaterSection: some View {
        VStack(spacing: 16) {
            Button("Use Apple Vision") {
                setupLaterWithAppleVision()
            }
            .font(.headline)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 20)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray)
            )
            .overlay(
                HStack {
                    Image(systemName: "apple.logo")
                        .font(.title2)
                        .fontWeight(.medium)
                    Spacer()
                }
                .padding(.leading, 20)
                .foregroundColor(.white)
            )
        }
        .padding(.vertical, 20)
    }

    // MARK: - Helper Views

    private func instructionStep(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(Color.orange)
                )

            Text(.init(text)) // Use Markdown initialiser for bold text
                .font(.subheadline)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
    }

    // MARK: - Actions

    private func saveAPIKeyAndFinish() {
        guard !apiKey.isEmpty else {
            apiKeyStatusMessage = "API Key cannot be empty"
            showSaveConfirmation = false
            return
        }

        // Use the proper KeychainService
        let success = KeychainService.saveAPIKey(apiKey)

        if success {
            print("Gemini API Key Saved")
            apiKeyStatusMessage = "API Key saved successfully!"
            showSaveConfirmation = true
            textExtractorService = TextExtractorType.gemini.rawValue // Set to Cloud (Gemini)
            hasCompletedOnboarding = true

            // Dismiss after a short delay to show confirmation
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                isOnboarding = false
            }
        } else {
            apiKeyStatusMessage = "Failed to save API Key. Please try again."
            showSaveConfirmation = false
        }
    }
    
    private func setupLaterWithAppleVision() {
        print("Setup later selected, using Apple Vision")
        textExtractorService = TextExtractorType.vision.rawValue // Set to Local (Vision)
        hasCompletedOnboarding = true
        isOnboarding = false // Dismiss the sheet
    }
}

#Preview {
    OnboardingView(isOnboarding: .constant(true))
}

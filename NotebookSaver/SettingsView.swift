import SwiftUI
import Foundation // For NotificationCenter, keep if needed

// Enum for AI Model Identifiers
enum AIModelIdentifier: String, CaseIterable, Identifiable {
    case gemini2_5FlashPreview = "gemini-2.5-flash-preview-04-17"
    case gemini2_5ProPreview = "gemini-2.5-pro-preview"
    case gemini1_5Pro = "gemini-1.5-pro"
    case gemini1_5Flash = "gemini-1.5-flash"
    case gemini1_5Flash8B = "gemini-1.5-flash-8b"
    case custom = "Custom"

    var id: String { self.rawValue } // For Identifiable conformance if needed directly on rawValue

    var displayName: String { // Provides a default display name if not overridden
        switch self {
        case .gemini2_5FlashPreview: return "Gemini 2.5 Flash Preview"
        case .gemini2_5ProPreview: return "Gemini 2.5 Pro Preview"
        case .gemini1_5Pro: return "Gemini 1.5 Pro"
        case .gemini1_5Flash: return "Gemini 1.5 Flash"
        case .gemini1_5Flash8B: return "Gemini 1.5 Flash 8B"
        case .custom: return "Custom Model"
        }
    }
}

// Simple struct to hold display name and ID for picker
struct ModelOption: Identifiable, Hashable {
    let id: AIModelIdentifier // Use model ID or "Custom" as the identifier
    let displayName: String
    let description: String
    let speed: Int // 1-5 scale
    let quality: Int // 1-5 scale
}

// Enum for Target Application
enum TargetApplication: String, CaseIterable, Identifiable {
    case drafts = "Drafts"
    case other = "Notes" // "Notes" is used as the tag in the Picker for "Other"

    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .drafts: return "Drafts"
        case .other: return "Other" // Display name for UI
        }
    }
    }

    // Enum for Vision Recognition Level
    enum VisionRecognitionLevel: String, CaseIterable, Identifiable {
        case accurate = "accurate"
        case fast = "fast"

        var id: String { self.rawValue }

        var displayName: String {
            switch self {
            case .accurate: return "Accurate"
            case .fast: return "Fast"
            }
        }
    }

    // Enum for managing Settings Tabs
    enum SettingsTab: Int, CaseIterable, Identifiable {
    case general, ai, about

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .general: return "General"
        case .ai: return "AI"
        case .about: return "About"
        }
    }

    var iconName: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .ai: return "sparkles"
        case .about: return "info.circle"
        }
    }
}

// ViewModifier for common card styling
struct CardBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    var isSelected: Bool = false
    var isError: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(10) // Common padding, can be parameterized if needed
            .background(
                RoundedRectangle(cornerRadius: 8) // Common corner radius
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : (colorScheme == .dark ? Color(.systemGray5) : Color(.systemGray6)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isError ? Color.red : (isSelected ? Color.accentColor : Color.secondary.opacity(0.3)), lineWidth: 1)
            )
    }
}

// Extension to make the CardBackgroundModifier easier to use
extension View {
    func cardStyled(isSelected: Bool = false, isError: Bool = false) -> some View {
        self.modifier(CardBackgroundModifier(isSelected: isSelected, isError: isError))
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss // To close the sheet
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.presentationMode) var presentationMode

    // Tab selection state
    @State private var selectedTab: SettingsTab = .general

    // AppStorage keys - good practice to define them
    private enum StorageKeys {
        static let selectedModelId = "selectedModelId"
        static let customModelName = "customModelName"
        static let userPrompt = "userPrompt"
        static let apiEndpoint = "apiEndpointUrlString"
        static let draftsTag = "draftsTag"
        static let savePhotosToAlbum = "savePhotosToAlbum"
        static let targetApp = "targetApp"
        static let textExtractorService = "textExtractorService" // Add new key for the selected text extractor service
        // Vision specific keys
        static let visionRecognitionLevel = "visionRecognitionLevel"
        static let visionUsesLanguageCorrection = "visionUsesLanguageCorrection"
    }

    // === Persisted Settings ===
    @AppStorage(StorageKeys.selectedModelId) private var selectedModelId: AIModelIdentifier = .gemini2_5FlashPreview
    @AppStorage(StorageKeys.customModelName) private var customModelName: String = ""
    @AppStorage(StorageKeys.userPrompt) private var userPrompt: String = "Output the text from the image as text. Start immediately with the first word. Format for clarity, format blocks of text into paragraphs, and use markdown sparingly."
    @AppStorage(StorageKeys.apiEndpoint) private var apiEndpointUrlString: String = "https://generativelanguage.googleapis.com/v1beta/models/"
    @AppStorage(StorageKeys.draftsTag) private var draftsTag: String = "notebook"
    @AppStorage(StorageKeys.savePhotosToAlbum) private var savePhotosToAlbum: Bool = false
    @AppStorage(StorageKeys.targetApp) private var targetApp: TargetApplication = .drafts // Default to Drafts
    @AppStorage(StorageKeys.textExtractorService) private var selectedTextExtractor: TextExtractorType = .gemini // Default to Gemini
    // Vision specific settings
    @AppStorage(StorageKeys.visionRecognitionLevel) private var visionRecognitionLevel: VisionRecognitionLevel = .accurate // Default to accurate
    @AppStorage(StorageKeys.visionUsesLanguageCorrection) private var visionUsesLanguageCorrection: Bool = true // Default to true

    // === State for API Key (using Keychain) ===
    @State private var apiKey: String = ""
    @State private var apiKeyStatusMessage: String = ""
    @State private var showSaveConfirmation = false

    // State for expanded sections
    @State private var showAdvancedEndpoint = true

    // For custom prompt examples

    // State for connection test
    enum ConnectionStatus { case idle, testing, success, failure }
    @State private var connectionStatus: ConnectionStatus = .idle
    @State private var connectionStatusMessage: String = ""

    // === Available Model Options ===
    let availableModels: [ModelOption] = [
        // --- Preview --- (Experimental)
        ModelOption(
            id: .gemini2_5FlashPreview,
            displayName: "Gemini 2.5 Flash",
            description: "Next-gen model with improved capabilities (experimental)",
            speed: 4,
            quality: 5
        ),
        ModelOption(
            id: .gemini2_5ProPreview,
            displayName: "Gemini 2.5 Pro",
            description: "Next-gen Pro model, enhanced understanding (experimental)",
            speed: 2,
            quality: 5
        ),
        // --- Stable / Latest --- (Generally Recommended)
        ModelOption(
            id: .gemini1_5Pro,
            displayName: "Gemini 1.5 Pro",
            description: "Higher quality results with deeper understanding",
            speed: 3,
            quality: 5
        ),
        ModelOption(
            id: .gemini1_5Flash,
            displayName: "Gemini 1.5 Flash",
            description: "Balanced model for text extraction with good performance",
            speed: 5,
            quality: 3
        ),
        ModelOption(
            id: .gemini1_5Flash8B,
            displayName: "Gemini 1.5 Flash 8B",
            description: "Optimized for efficiency with excellent speed",
            speed: 4,
            quality: 4
        ),
        ModelOption(
            id: .custom,
            displayName: "Custom Model",
            description: "Use a specific model identifier",
            speed: 3,
            quality: 3
        )
    ]

    // Sample prompts
    let promptExamples = [
        "Output the text from the image below as plain text, starting immediately with the first word. Format for clarity, cohesive paragraphs and use markdown when helpful."
    ]

    @State private var showOnboarding = false
    // State variable to hold the randomly selected quote for the About tab
    @State private var aboutQuote: (quote: String, author: String)?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Custom tab selector
                HStack(spacing: 0) {
                    ForEach(SettingsTab.allCases) { tab in
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedTab = tab
                            }
                        }) {
                            VStack(spacing: 8) {
                                Image(systemName: tab.iconName)
                                    .font(.system(size: 20))

                                Text(tab.displayName)
                                    .font(.subheadline)

                                ZStack {
                                    Rectangle()
                                        .fill(Color.clear)
                                        .frame(height: 3)

                                    if selectedTab == tab {
                                        Rectangle()
                                            .fill(Color.accentColor)
                                            .frame(height: 3)
                                            .transition(.opacity)
                                    }
                                }
                            }
                            .foregroundColor(selectedTab == tab ? .accentColor : .gray)
                            .padding(.vertical, 12)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 8)
                .background(colorScheme == .dark ? Color.black : Color.white)

                // Tab content
                TabView(selection: $selectedTab) {
                    generalTabView.tag(SettingsTab.general)
                    aiTabView.tag(SettingsTab.ai)
                    aboutTabView.tag(SettingsTab.about)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.2), value: selectedTab)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        resetToDefaults()
                    }) {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
                }
            }
            .onAppear {
                loadAPIKey()
                if apiEndpointUrlString.isEmpty {
                    apiEndpointUrlString = "https://generativelanguage.googleapis.com/v1beta/models/"
                }
                // Select a random quote when the About tab appears
                aboutQuote = notebookQuotes.randomElement()
            }
        }
    }

    // MARK: - Tab Views

    // General tab with app settings
    var generalTabView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Combined General Settings Group
                GroupBox { // Remove the label here
                    VStack(alignment: .leading, spacing: 20) {
                        // === Start of original "Output Settings" content ===
                        // Target App Selection
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Send Text To", systemImage: "arrow.up.forward.app.fill")
                                .font(.headline)

                            Picker("Target App", selection: $targetApp) {
                                ForEach(TargetApplication.allCases) { appType in
                                    Text(appType.displayName).tag(appType)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(.top, 4)
                        }

                        // Drafts-specific settings (conditionally shown)
                        if targetApp == .drafts {
                            Divider()

                            // Drafts Tag Section
                            VStack(alignment: .leading, spacing: 12) {
                                Label("Drafts Tag", systemImage: "tag.fill")
                                    .font(.headline)

                                TextField("Enter tag (e.g., notebook)", text: $draftsTag)
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                                    .padding(10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                    )
                            }
                        } else {
                            // No description for Other setting
                        }
                        // === End of original "Output Settings" content ===

                        // Add a divider between the merged sections
                        Divider().padding(.vertical, 8)

                        // === Start of original "Image Settings" content ===
                        // Save Photos to Album Section
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Photo Storage", systemImage: "photo.on.rectangle")
                                .font(.headline)

                            Toggle("Save to 'notebook' album", isOn: $savePhotosToAlbum)
                                .padding(.top, 4)
                        }
                        // === End of original "Image Settings" content ===
                    }
                    .padding(.vertical, 8)
                }
                .padding(.horizontal)
                .onChange(of: targetApp) { _, newValue in
                    // Logic for when the target app changes
                    print("Target app changed to: \(newValue)")
                }

                // Remove the second GroupBox entirely
                /*
                GroupBox(label: Label("Image Settings", systemImage: "camera")) {
                    VStack(alignment: .leading, spacing: 20) {
                        // ... content moved above ...
                    }
                    .padding(.vertical, 8)
                }
                .padding(.horizontal)
                */

                Spacer(minLength: 40)
            }
            .padding(.vertical)
        }
    }

    // AI tab with model selection and API settings
    var aiTabView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 20) {
                        // Text Extraction Service Picker
                        Picker("Text Extraction Service", selection: $selectedTextExtractor) {
                            ForEach(TextExtractorType.allCases) { serviceType in
                                Text(serviceType.rawValue).tag(serviceType)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.top, 4)

                        if selectedTextExtractor == .gemini {
                            // Model selection
                            VStack(alignment: .leading, spacing: 12) {
                                Text("AI Model")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(availableModels) { model in
                                            modelCard(model: model)
                                        }
                                    }
                                }
                                if selectedModelId == .custom {
                                    TextField("Custom Model ID (e.g. gemini-custom-001)", text: $customModelName)
                                        .autocapitalization(.none)
                                        .disableAutocorrection(true)
                                        .cardStyled(isError: customModelName.isEmpty && selectedModelId == .custom)
                                    if customModelName.isEmpty {
                                        Text("Custom model name is required")
                                            .font(.caption)
                                            .foregroundColor(.red)
                                    }
                                }
                            }
                            // Prompt editor
                            VStack(alignment: .leading, spacing: 10) {
                                Text("AI Instruction Prompt")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                TextEditor(text: $userPrompt)
                                    .frame(minHeight: 80)
                                    .scrollContentBackground(.hidden)
                                    .cardStyled()
                            }
                            // API Key and Endpoint
                            VStack(alignment: .leading, spacing: 12) {
                                SecureField("Cloud API Key", text: $apiKey)
                                    .textContentType(.password)
                                    .cardStyled()
                                HStack(spacing: 8) {
                                    Button(action: { saveApiKey() }) {
                                        Text("Save Key")
                                            .fontWeight(.medium)
                                            .padding(.vertical, 8)
                                            .padding(.horizontal, 16)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(apiKey.isEmpty ? Color.gray.opacity(0.3) : Color.accentColor)
                                            )
                                            .foregroundColor(apiKey.isEmpty ? .gray : .white)
                                    }
                                    .disabled(apiKey.isEmpty)
                                    if !apiKeyStatusMessage.isEmpty {
                                        Text(apiKeyStatusMessage)
                                            .font(.caption)
                                            .foregroundColor(showSaveConfirmation ? .green : .red)
                                    }
                                    Spacer()
                                    Button(action: { showApiKeyOnboarding() }) {
                                        Image(systemName: "questionmark.circle")
                                    }
                                }
                                TextField("API Endpoint URL", text: $apiEndpointUrlString)
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                                    .cardStyled(isError: apiEndpointUrlString.isEmpty)
                                HStack {
                                    Button(action: { if connectionStatus != .testing { testConnection() } }) {
                                        HStack(spacing: 8) {
                                            if connectionStatus == .testing {
                                                ProgressView()
                                                    .scaleEffect(0.8)
                                                    .frame(width: 20, height: 20)
                                            } else {
                                                Image(systemName: "arrow.clockwise")
                                                    .frame(width: 20, height: 20)
                                            }
                                            Text(connectionStatus == .testing ? "Testing..." : "Test Connection")
                                        }
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(colorScheme == .dark ? Color(.systemGray5) : Color(.systemGray6))
                                    )
                                    .font(.subheadline)
                                    .foregroundColor(.accentColor)
                                    .disabled(connectionStatus == .testing)
                                    if connectionStatus != .idle && connectionStatus != .testing {
                                        HStack(spacing: 4) {
                                            Image(systemName: connectionStatus == .success ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                                .foregroundColor(connectionStatus == .success ? .green : .red)
                                            Text(connectionStatusMessage)
                                                .font(.caption)
                                                .foregroundColor(connectionStatus == .success ? .green : .red)
                                        }
                                        .padding(.leading, 8)
                                    }
                                }
                            }
                        } else if selectedTextExtractor == .vision {
                            // Vision-specific settings
                            VStack(alignment: .leading, spacing: 18) {
                                Text("Uses Apple's on-device Vision framework. Works offline, no API key needed.")
                                    .font(.caption)
                                    .foregroundColor(.gray)

                                Divider()

                                // Recognition Level Picker
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Recognition Level")
                                        .font(.headline)
                                    Text("Accurate is slower but better quality. Fast is quicker but may miss details.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Picker("Recognition Level", selection: $visionRecognitionLevel) {
                                        ForEach(VisionRecognitionLevel.allCases) { level in
                                            Text(level.displayName).tag(level)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                }

                                Divider()

                                // Language Correction Toggle
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Language Correction")
                                        .font(.headline)
                                    Toggle("Apply language rules to improve results", isOn: $visionUsesLanguageCorrection)
                                }
                            }
                            .padding(.top, 8) // Add some padding above the Vision settings
                        }
                    }
                    .padding(.vertical, 8)
                }
                .padding(.horizontal)
                Spacer(minLength: 40)
            }
            .padding(.vertical)
            .animation(.easeInOut, value: selectedTextExtractor)
        }
    }

    // About tab with app info
    var aboutTabView: some View {
        ScrollView {
            VStack(spacing: 30) {
                // App logo - Removed

                // App version
                Text("Cat Scribe v1.0.0")
                    .font(.headline)

                // App description
                Text("Capture notebook pages and convert them to digital notes using AI.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 20)

                // Display a random quote
                if let quote = aboutQuote {
                    VStack {
                        Text("\"\(quote.quote)\"")
                            .font(.callout)
                            .italic()
                            .multilineTextAlignment(.center)
                        Text("- \(quote.author)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.accentColor.opacity(0.05))
                    )
                    .padding(.horizontal)
                }

                // Help and support
                VStack(spacing: 16) {
                    Link(destination: URL(string: "https://example.com/help")!) {
                        Label("Help & Documentation", systemImage: "questionmark.circle")
                            .font(.subheadline)
                    }

                    Link(destination: URL(string: "https://example.com/privacy")!) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                            .font(.subheadline)
                    }

                    Link(destination: URL(string: "mailto:support@example.com")!) {
                        Label("Contact Support", systemImage: "envelope")
                            .font(.subheadline)
                    }
                }
                .padding(.top)

                Spacer(minLength: 40)
            }
            .padding()
        }
    }

    // MARK: - Helper Views

    // Model card view
    private func modelCard(model: ModelOption) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Model name with optional preview tag
            HStack(spacing: 6) {
                Text(model.displayName)
                    .font(.headline)

                // Remove the Preview tag display while keeping the property for future use
            }

            // Description
            Text(model.description)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(height: 32, alignment: .top)

            // Performance indicators - only show for non-custom models
            if model.id != .custom {
                HStack(spacing: 12) {
                    // Speed indicator
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.caption)
                            .foregroundColor(.yellow)

                        ratingBar(rating: model.speed, max: 5)
                    }

                    // Quality indicator
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundColor(.orange)

                        ratingBar(rating: model.quality, max: 5)
                    }
                }
            }

            // Add a spacer to maintain consistent card height when ratings are hidden
            if model.id == .custom {
                Spacer().frame(height: 20)
            }

            // Selection indicator
            HStack {
                Spacer()

                Image(systemName: selectedModelId == model.id ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(selectedModelId == model.id ? .accentColor : .secondary.opacity(0.5))
            }
        }
        .padding(12)
        .frame(width: 220, height: 160)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(selectedModelId == model.id ?
                      Color.accentColor.opacity(0.1) :
                      (colorScheme == .dark ? Color(.systemGray5) : Color(.systemGray6)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(selectedModelId == model.id ? Color.accentColor : Color.clear, lineWidth: 2)
                .padding(0.5) // Add slight inset to prevent clipping
        )
        .onTapGesture {
            withAnimation {
                selectedModelId = model.id
            }
        }
    }

    // Rating bar helper
    private func ratingBar(rating: Int, max: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(1...max, id: \.self) { index in
                Rectangle()
                    .fill(index <= rating ? Color.accentColor : Color.gray.opacity(0.3))
                    .frame(width: 8, height: 4)
                    .cornerRadius(2)
            }
        }
    }

    // MARK: - Helper Functions

    // Load API key from keychain
    private func loadAPIKey() {
        if let loadedKey = KeychainService.loadAPIKey() {
            apiKey = loadedKey
            apiKeyStatusMessage = "Key loaded from Keychain"
            showSaveConfirmation = true
        } else {
            apiKeyStatusMessage = "Enter your API Key"
            showSaveConfirmation = false
        }
    }

    // Save API key to keychain
    private func saveApiKey() {
        let success = KeychainService.saveAPIKey(apiKey)
        apiKeyStatusMessage = success ? "API Key Saved Successfully!" : "Failed to Save API Key."
        if success {
            withAnimation { showSaveConfirmation = true }
            // Optionally hide checkmark after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation { showSaveConfirmation = false }
            }
        } else {
            withAnimation { showSaveConfirmation = false }
        }
    }

    // Test connection (placeholder)
    private func testConnection() {
        connectionStatus = .testing
        connectionStatusMessage = "Connecting..."

        // --- Simulate API Call --- 
        // In a real app, you would make an actual network request here
        // using the apiEndpointUrlString and potentially the apiKey.
        let isValidEndpoint = URL(string: apiEndpointUrlString) != nil // Basic URL validation
        let simulateSuccess = isValidEndpoint && !apiKey.isEmpty // Simulate success if URL is valid and key exists

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { // Simulate network delay
            if simulateSuccess {
                // Simulate a successful connection
                connectionStatus = .success
                connectionStatusMessage = "Connection successful!"
            } else {
                // Simulate a failed connection
                connectionStatus = .failure
                connectionStatusMessage = apiKey.isEmpty ? "Connection failed: API Key missing." : "Connection failed: Invalid endpoint or key."
            }

            // Optional: Reset status after a few seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                if connectionStatus != .testing { // Don't reset if another test started
                   connectionStatus = .idle
                   connectionStatusMessage = ""
                }
            }
        }
    }

    // Reset settings to defaults
    private func resetToDefaults() {
        // Also reset the text extractor service
        selectedTextExtractor = .gemini

        selectedModelId = .gemini2_5FlashPreview
        customModelName = ""
        userPrompt = "Output the text from the image as text. Start immediately with the first word. Format for clarity, format blocks of text into paragraphs, and use markdown sparingly."
        apiEndpointUrlString = "https://generativelanguage.googleapis.com/v1beta/models/"
        draftsTag = "notebook"
        savePhotosToAlbum = false
        targetApp = .drafts
        // Reset Vision settings
        visionRecognitionLevel = .accurate
        visionUsesLanguageCorrection = true
        // Note: API key is not reset as it's sensitive information
    }

    private func showApiKeyOnboarding() {
        // Dismiss this view first
        presentationMode.wrappedValue.dismiss()

        // Use NotificationCenter to trigger the onboarding
        NotificationCenter.default.post(name: NSNotification.Name("ShowOnboarding"), object: nil)
    }

    // Helper to update API key status message
    private func updateApiKeyStatus() {
        if apiKey.isEmpty {
            apiKeyStatusMessage = "API Key not set."
        } else {
            // Basic check, could add more validation if needed
            apiKeyStatusMessage = "API Key loaded."
        }
    }
}

#Preview {
    SettingsView()
}

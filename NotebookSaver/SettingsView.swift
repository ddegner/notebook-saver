import SwiftUI
import Foundation // For NotificationCenter, keep if needed

// Enum for AI Model Identifiers
enum AIModelIdentifier: String, CaseIterable, Identifiable {
    case geminiFlash25Preview = "gemini-2.5-flash-preview-04-17"
    case geminiPro25Preview = "gemini-2.5-pro-preview"
    case geminiPro15 = "gemini-1.5-pro"
    case geminiFlash15 = "gemini-1.5-flash"
    case geminiFlash15B = "gemini-1.5-flash-8b"
    case custom = "Custom"

    var id: String { self.rawValue } // For Identifiable conformance if needed directly on rawValue

    var displayName: String { // Provides a default display name if not overridden
        switch self {
        case .geminiFlash25Preview: return "Gemini 2.5 Flash Preview"
        case .geminiPro25Preview: return "Gemini 2.5 Pro Preview"
        case .geminiPro15: return "Gemini 1.5 Pro"
        case .geminiFlash15: return "Gemini 1.5 Flash"
        case .geminiFlash15B: return "Gemini 1.5 Flash 8B"
        case .custom: return "Custom Model"
        }
    }
}

// Simple struct to hold display name and ID for picker
struct ModelOption: Identifiable, Hashable {
    let id: AIModelIdentifier // Use model ID or "Custom" as the identifier
    let displayName: String
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
}

// ViewModifier for common card styling
struct CardBackgroundModifier: ViewModifier {
    var isSelected: Bool = false
    var isError: Bool = false // Not used for model cards per spec, but kept for flexibility

    func body(content: Content) -> some View {
        content
            .padding(10) // Common padding, can be parameterized if needed
            .background(
                RoundedRectangle(cornerRadius: 8) // Common corner radius
                    .fill(isSelected ? Color.orangeTabbyLight.opacity(0.9) : Color.white.opacity(0.8))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isError ? Color.red : (isSelected ? Color.orangeTabbyAccent : Color.orangeTabbyDark.opacity(0.2)), lineWidth: isSelected ? 2 : 1)
            )
    }
}

// Extension to make the CardBackgroundModifier easier to use
extension View {
    func cardStyled(isSelected: Bool = false, isError: Bool = false) -> some View {
        self.modifier(CardBackgroundModifier(isSelected: isSelected, isError: isError))
    }
}

// Add the new Color extensions here
extension Color {
    static let orangeTabbyBackground = Color(red: 1.0, green: 0.65, blue: 0.2) // Vibrant orange background to match image
    static let orangeTabbyDark = Color(red: 0.9, green: 0.45, blue: 0.1) // Darker orange for selected segments
    static let orangeTabbyLight = Color(red: 1.0, green: 0.8, blue: 0.5) // Light peachy orange for input fields
    static let orangeTabbyAccent = Color(red: 0.8, green: 0.4, blue: 0.05) // Deep orange for accents
    static let orangeTabbyText = Color(red: 0.2, green: 0.1, blue: 0.05) // Very dark brown text for contrast
}

// Custom Segmented Picker View
struct CustomSegmentedPicker<Data, Content>: View where Data: RandomAccessCollection, Data.Element: Hashable, Content: View {
    @Binding var selection: Data.Element
    let items: Data
    let content: (Data.Element, Bool) -> Content // Closure to define the content for each segment

    var body: some View {
        HStack(spacing: 0) { // No spacing between buttons
            ForEach(items, id: \.self) { item in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selection = item
                    }
                }) {
                    content(item, selection == item)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(selection == item ? Color.orangeTabbyDark : Color.clear) // Corrected: Dark orange if selected
                        .foregroundColor(selection == item ? Color.white : Color.orangeTabbyText) // Corrected: White text if selected
                        .cornerRadius(8) // Apply corner radius to all segments for consistent shape within the container
                }
            }
        }
        .background(Color.orangeTabbyLight.opacity(0.6)) // Overall background of the control
        .cornerRadius(8) // Rounded corners for the entire control
        .padding(.vertical, 4) // Give a little vertical breathing room for the control itself
    }
}

struct SettingsView: View {
    // Tab selection state
    @State private var selectedTab: SettingsTab = .general

    // AppStorage keys - good practice to define them
    private enum StorageKeys {
        static let selectedModelId = "selectedModelId"
        static let customModelName = "customModelName"
        static let userPrompt = "userPrompt"
        static let apiEndpoint = "apiEndpointUrlString"
        static let draftsTag = "draftsTag"
        static let photoFolderName = "photoFolderName" // Changed from savePhotosToAlbum
        static let targetApp = "targetApp"
        static let textExtractorService = "textExtractorService" // Add new key for the selected text extractor service
        // Vision specific keys
        static let visionRecognitionLevel = "visionRecognitionLevel"
        static let visionUsesLanguageCorrection = "visionUsesLanguageCorrection"
    }

    // === Persisted Settings ===
    @AppStorage(StorageKeys.selectedModelId) private var selectedModelId: AIModelIdentifier = .geminiFlash25Preview
    @AppStorage(StorageKeys.customModelName) private var customModelName: String = ""
    @AppStorage(StorageKeys.userPrompt) private var userPrompt: String = """
        Output the text from the image as text. Start immediately with the first word. \
        Format for clarity, format blocks of text into paragraphs, and use markdown sparingly.
        """
    @AppStorage(StorageKeys.apiEndpoint) private var apiEndpointUrlString: String = "https://generativelanguage.googleapis.com/v1beta/models/"
    @AppStorage(StorageKeys.draftsTag) private var draftsTag: String = "notebook"
    @AppStorage(StorageKeys.photoFolderName) private var photoFolderName: String = "notebook" // Changed from savePhotosToAlbum
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

    // Focus state for text fields to enable tap-to-dismiss
    @FocusState private var isPromptFocused: Bool
    @FocusState private var isApiKeyFocused: Bool
    @FocusState private var isDraftsTagFocused: Bool
    @FocusState private var isPhotoFolderFocused: Bool
    @FocusState private var isCustomModelFocused: Bool
    @FocusState private var isApiEndpointFocused: Bool

    // === Available Model Options ===
    let availableModels: [ModelOption] = [
        // --- Preview --- (Experimental)
        ModelOption(
            id: .geminiFlash25Preview,
            displayName: "Gemini 2.5 Flash",
            speed: 4,
            quality: 5
        ),
        ModelOption(
            id: .geminiPro25Preview,
            displayName: "Gemini 2.5 Pro",
            speed: 2,
            quality: 5
        ),
        // --- Stable / Latest --- (Generally Recommended)
        ModelOption(
            id: .geminiPro15,
            displayName: "Gemini 1.5 Pro",
            speed: 3,
            quality: 5
        ),
        ModelOption(
            id: .geminiFlash15,
            displayName: "Gemini 1.5 Flash",
            speed: 5,
            quality: 3
        ),
        ModelOption(
            id: .geminiFlash15B,
            displayName: "Gemini 1.5 Flash 8B",
            speed: 4,
            quality: 4
        ),
        ModelOption(
            id: .custom,
            displayName: "Custom Model",
            speed: 3,
            quality: 3
        )
    ]

    // Sample prompts
    let promptExamples = [
        "Output the text from the image below as plain text, starting immediately with the first word. Format for clarity, cohesive paragraphs and use markdown when helpful."
    ]

    @State private var showOnboarding = false
    
    // Computed property for dynamic API key placeholder text
    private var apiKeyPlaceholderText: String {
        if apiKey.isEmpty {
            return "API Key Required"
        } else if showSaveConfirmation {
            return "API Key (Saved)"
        } else {
            return "API Key (Loaded)"
        }
    }
    
    // Computed property for dynamic API URL placeholder text
    private var apiUrlPlaceholderText: String {
        switch connectionStatus {
        case .idle:
            return apiEndpointUrlString.isEmpty ? "API Endpoint URL Required" : "API Endpoint URL"
        case .testing:
            return "Testing Connection..."
        case .success:
            return "API Endpoint URL (Connected)"
        case .failure:
            return "API Endpoint URL (Connection Failed)"
        }
    }
    
    // Computed property for API URL error state
    private var apiUrlHasError: Bool {
        return apiEndpointUrlString.isEmpty || connectionStatus == .failure
    }

    var body: some View {
        VStack(spacing: 0) {
            // Add padding at the top so tabs are visible when camera slides up
            Spacer()
                .frame(height: 50) // Reduced space for the camera's bottom portion
            
            // Custom tab selector
            HStack(spacing: 0) {
                ForEach(SettingsTab.allCases) { tab in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTab = tab
                        }
                    }) {
                        VStack(spacing: 8) {
                            Text(tab.displayName)
                                .font(.headline)

                            ZStack {
                                // Transparent placeholder for consistent height
                                Capsule().fill(Color.clear).frame(height: 5)

                                if selectedTab == tab {
                                    Capsule() // Use Capsule for rounded ends
                                        .fill(Color.orangeTabbyAccent)
                                        .frame(height: 5) // Make it thicker
                                        .transition(.opacity)
                                }
                            }
                        }
                        .foregroundColor(selectedTab == tab ? .orangeTabbyAccent : .orangeTabbyText.opacity(0.6))
                        .padding(.vertical, 12)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 8)
            .background(Color.orangeTabbyBackground) // Changed background to match main

            // Tab content - using conditional views instead of TabView for proper scrolling
            Group {
                switch selectedTab {
                case .general:
                    generalTabView
                case .ai:
                    aiTabView
                case .about:
                    aboutTabView
                }
            }
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: selectedTab)
        }
        .background(Color.orangeTabbyBackground)
        .preferredColorScheme(.light)
        .onAppear {
            loadAPIKey()
            if apiEndpointUrlString.isEmpty {
                apiEndpointUrlString = "https://generativelanguage.googleapis.com/v1beta/models/"
            }
        }
    }

    // MARK: - Tab Views

    // General tab with app settings
    var generalTabView: some View {
        ScrollView { // Added ScrollView for content that might exceed screen height
            VStack(alignment: .leading, spacing: 20) { // Main container for general settings
                // Target App Selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("Send Text To")
                        .font(.headline)
                        .foregroundColor(Color.orangeTabbyText)

                    CustomSegmentedPicker(selection: $targetApp, items: TargetApplication.allCases) { appType, isSelected in
                        Text(appType.displayName)
                            .font(isSelected ? .headline : .subheadline) // Example: different font weight for selected
                    }
                    // Removed old Picker and its modifiers
                }

                // Drafts-specific settings
                if targetApp == .drafts {
                    Divider().background(Color.orangeTabbyDark.opacity(0.3))

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Drafts Tag")
                            .font(.headline)
                            .foregroundColor(Color.orangeTabbyText)

                        TextField("Add tag to draft", text: $draftsTag)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .focused($isDraftsTagFocused)
                            .onSubmit { isDraftsTagFocused = false }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.orangeTabbyLight.opacity(0.7))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(isDraftsTagFocused ? Color.orangeTabbyAccent : Color.orangeTabbyDark.opacity(0.4), lineWidth: isDraftsTagFocused ? 2 : 1)
                                    )
                            )
                            .foregroundColor(Color.orangeTabbyText)
                            // Placeholder text color customization can be complex, may need ZStack approach
                    }
                }

                Divider().background(Color.orangeTabbyDark.opacity(0.3))

                // Photo Album Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Photo Album")
                        .font(.headline)
                        .foregroundColor(Color.orangeTabbyText)

                    TextField("Save photo to Photos App album", text: $photoFolderName)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .focused($isPhotoFolderFocused)
                        .onSubmit { isPhotoFolderFocused = false }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.orangeTabbyLight.opacity(0.7))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(isPhotoFolderFocused ? Color.orangeTabbyAccent : Color.orangeTabbyDark.opacity(0.4), lineWidth: isPhotoFolderFocused ? 2 : 1)
                                )
                        )
                        .foregroundColor(Color.orangeTabbyText)
                }
            }
            .padding() // Add padding around the content of the panel
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.orangeTabbyDark.opacity(0.6)) // Panel background
                    .overlay( // Panel border
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.orangeTabbyAccent.opacity(0.5), lineWidth: 1)
                    )
            )
            .padding() // Add padding around the panel itself
        }
        .onTapGesture {
            dismissAllKeyboards()
        }
    }

    // AI tab with model selection and API settings
    var aiTabView: some View {
        ScrollView { // Added ScrollView
            VStack(alignment: .leading, spacing: 24) {
                // AI Instruction Prompt
                VStack(alignment: .leading, spacing: 10) {
                    Text("AI Instruction Prompt")
                        .font(.headline)
                        .foregroundColor(Color.orangeTabbyText.opacity(0.7))
                    TextEditor(text: $userPrompt)
                        .frame(minHeight: 50, maxHeight: 80)
                        .scrollContentBackground(.hidden)
                        // .cardStyled() // cardStyled provides its own background, let the VStack handle the panel bg
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orangeTabbyLight.opacity(0.7)))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isPromptFocused ? Color.orangeTabbyAccent : Color.orangeTabbyDark.opacity(0.4), lineWidth: isPromptFocused ? 2: 1))
                        .focused($isPromptFocused)
                        .onSubmit { isPromptFocused = false }
                        .foregroundColor(Color.orangeTabbyText)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.orangeTabbyDark.opacity(0.6))
                        .stroke(Color.orangeTabbyAccent.opacity(0.5), lineWidth: 1)
                )

                // AI Settings
                VStack(alignment: .leading, spacing: 20) {
                    CustomSegmentedPicker(selection: $selectedTextExtractor, items: TextExtractorType.allCases) { serviceType, isSelected in
                        Text(serviceType.rawValue)
                             .font(isSelected ? .headline : .subheadline)
                    }
                    // Removed old Picker and its modifiers
                    
                    if selectedTextExtractor == .gemini {
                        geminiSettingsSection // This section has its own styling for model cards, API fields
                    } else if selectedTextExtractor == .vision {
                        visionSettingsSection
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.orangeTabbyDark.opacity(0.6))
                        .stroke(Color.orangeTabbyAccent.opacity(0.5), lineWidth: 1)
                )
                
                Spacer()
            }
            .padding() // Padding for the content within ScrollView
        }
        .animation(.easeInOut, value: selectedTextExtractor)
        .onTapGesture {
            dismissAllKeyboards()
        }
    }

    // About tab with app info
    var aboutTabView: some View {
        VStack(spacing: 30) {
            Text("Cat Scribe v1.0.0")
                .font(.headline)
                .foregroundColor(Color.orangeTabbyText)

            Text("Capture notebook pages and convert them to digital notes using AI.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(Color.orangeTabbyText.opacity(0.7))

            VStack(spacing: 16) {
                Link(destination: URL(string: "https://example.com/help")!) {
                    Label("Help & Documentation", systemImage: "questionmark.circle")
                        .font(.subheadline)
                        .foregroundColor(Color.orangeTabbyAccent)
                }

                Link(destination: URL(string: "https://example.com/privacy")!) {
                    Label("Privacy Policy", systemImage: "hand.raised")
                        .font(.subheadline)
                        .foregroundColor(Color.orangeTabbyAccent)
                }

                Link(destination: URL(string: "mailto:support@example.com")!) {
                    Label("Contact Support", systemImage: "envelope")
                        .font(.subheadline)
                        .foregroundColor(Color.orangeTabbyAccent)
                }
            }
            .padding(.top)

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical)
        .onTapGesture {
            dismissAllKeyboards()
        }
    }

    // MARK: - Section Views
    
    @ViewBuilder
    private var geminiSettingsSection: some View {
        // Model selection
        VStack(alignment: .leading, spacing: 12) {
            Text("AI Model")
                .font(.headline)
                .foregroundColor(Color.orangeTabbyText.opacity(0.7))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(availableModels) { model in
                        modelCard(model: model) // Uses updated modelCard, which uses CardBackgroundModifier
                    }
                }
            }
            if selectedModelId == .custom {
                TextField("Custom Model ID (e.g. gemini-custom-001)", text: $customModelName)
                    .disableAutocorrection(true)
                    .focused($isCustomModelFocused)
                    .onSubmit { isCustomModelFocused = false }
                    // .cardStyled(isError: customModelName.isEmpty && selectedModelId == .custom) // Apply explicit styling for consistency
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.orangeTabbyLight.opacity(0.7)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(isCustomModelFocused ? Color.orangeTabbyAccent : (customModelName.isEmpty && selectedModelId == .custom ? Color.red : Color.orangeTabbyDark.opacity(0.4)), lineWidth: isCustomModelFocused || (customModelName.isEmpty && selectedModelId == .custom) ? 2 : 1))
                    .foregroundColor(Color.orangeTabbyText)
                if customModelName.isEmpty && selectedModelId == .custom { // Ensure error text is visible
                    Text("Custom model name is required")
                        .font(.caption)
                        .foregroundColor(.red) // Error color remains red
                }
            }
        }
        
        Divider().background(Color.orangeTabbyDark.opacity(0.3))
        
        // API Key
        HStack(spacing: 12) {
            SecureField(apiKeyPlaceholderText, text: $apiKey)
                .textContentType(.password)
                // .cardStyled(isError: apiKey.isEmpty)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.orangeTabbyLight.opacity(0.7)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(isApiKeyFocused ? Color.orangeTabbyAccent : (apiKey.isEmpty ? Color.red : Color.orangeTabbyDark.opacity(0.4)), lineWidth: isApiKeyFocused || apiKey.isEmpty ? 2:1 ))
                .frame(minHeight: 36)
                .layoutPriority(1)
                .focused($isApiKeyFocused)
                .onSubmit { isApiKeyFocused = false }
                .onChange(of: isApiKeyFocused) { _, focused in // Corrected onChange usage
                    if (!focused) { saveApiKey() }
                }
                .foregroundColor(Color.orangeTabbyText)
            Button(action: { saveApiKey() }) {
                Image(systemName: "tray.and.arrow.down")
                    .imageScale(.large)
                    .foregroundColor((apiKey.isEmpty || !showSaveConfirmation) ? Color.orangeTabbyText.opacity(0.4) : Color.white)
            }
            .frame(width: 44, height: 46) // Adjusted height to match TextField + padding
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill((apiKey.isEmpty || !showSaveConfirmation) ? 
                         Color.orangeTabbyText.opacity(0.2) : Color.orangeTabbyDark)
            )
            .disabled(apiKey.isEmpty)
        }
        
        Divider().background(Color.orangeTabbyDark.opacity(0.3))
        
        // API Endpoint URL and Test Connection
        HStack(spacing: 12) {
            TextField(apiUrlPlaceholderText, text: $apiEndpointUrlString)
                .disableAutocorrection(true)
                .focused($isApiEndpointFocused)
                .onSubmit { isApiEndpointFocused = false }
                // .cardStyled(isError: apiUrlHasError)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.orangeTabbyLight.opacity(0.7)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(isApiEndpointFocused ? Color.orangeTabbyAccent : (apiUrlHasError ? Color.red : Color.orangeTabbyDark.opacity(0.4)), lineWidth: isApiEndpointFocused || apiUrlHasError ? 2:1 ))
                .frame(minHeight: 36)
                .layoutPriority(1)
                .foregroundColor(Color.orangeTabbyText)
            Button(action: { if connectionStatus != .testing { testConnection() } }) {
                Image(systemName: "network")
                    .imageScale(.large)
                    .foregroundColor((apiEndpointUrlString.isEmpty || connectionStatus == .testing) ? 
                                   Color.orangeTabbyText.opacity(0.4) : Color.white)
                    .rotationEffect(connectionStatus == .testing ? .degrees(90) : .degrees(0))
            }
            .frame(width: 44, height: 46) // Adjusted height
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill((apiEndpointUrlString.isEmpty || connectionStatus == .testing) ? 
                         Color.orangeTabbyText.opacity(0.2) : Color.orangeTabbyDark)
            )
            .disabled(apiEndpointUrlString.isEmpty || connectionStatus == .testing)
        }
    }
    
    @ViewBuilder
    private var visionSettingsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("""
                Uses Apple's on-device Vision framework. Works offline, no API key needed. \
                Optimized for accurate text recognition with language correction enabled.
                """)
                .font(.caption)
                .foregroundColor(Color.orangeTabbyText.opacity(0.7))
        }
        .padding(.top, 8)
        .onAppear {
            visionRecognitionLevel = .accurate
            visionUsesLanguageCorrection = true
        }
    }

    // MARK: - Helper Views

    // Model card view
    private func modelCard(model: ModelOption) -> some View {
        let isSelected = selectedModelId == model.id

        return VStack(alignment: .leading, spacing: 8) {
            // Model name
            Text(model.displayName)
                .font(.headline)
                .foregroundColor(isSelected ? Color.orangeTabbyText : Color.white)

            // Rating bars (only show for non-custom models)
            if model.id != .custom {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Speed")
                            .font(.caption)
                            .foregroundColor(isSelected ? Color.orangeTabbyAccent : Color.orangeTabbyLight.opacity(0.8))

                        ratingBar(rating: model.speed, max: 5,
                                  activeColor: isSelected ? Color.orangeTabbyAccent : Color.orangeTabbyLight.opacity(0.8),
                                  inactiveColor: isSelected ? Color.orangeTabbyText.opacity(0.3) : Color.white.opacity(0.3))
                    }

                    HStack {
                        Text("Quality")
                            .font(.caption)
                            .foregroundColor(isSelected ? Color.orangeTabbyAccent : Color.orangeTabbyLight.opacity(0.8))

                        ratingBar(rating: model.quality, max: 5,
                                  activeColor: isSelected ? Color.orangeTabbyAccent : Color.orangeTabbyLight.opacity(0.8),
                                  inactiveColor: isSelected ? Color.orangeTabbyText.opacity(0.3) : Color.white.opacity(0.3))
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 220, height: 90)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.orangeTabbyLight.opacity(0.9) : Color.orangeTabbyDark.opacity(0.8))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.orangeTabbyAccent : Color.orangeTabbyAccent.opacity(0.5), lineWidth: isSelected ? 2 : 1)
        )
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedModelId = model.id
            }
        }
    }

    // Rating bar helper
    private func ratingBar(rating: Int, max: Int, activeColor: Color, inactiveColor: Color) -> some View {
        HStack(spacing: 2) {
            ForEach(1...max, id: \.self) { index in
                Circle()
                    .fill(index <= rating ? activeColor : inactiveColor) // Use parameterized colors
                    .frame(width: 6, height: 6)
            }
        }
    }

    // MARK: - Helper Functions
    
    // Dismiss all keyboards
    private func dismissAllKeyboards() {
        isPromptFocused = false
        isApiKeyFocused = false
        isDraftsTagFocused = false
        isPhotoFolderFocused = false
        isCustomModelFocused = false
        isApiEndpointFocused = false
    }

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
                   // Update status indicator colors if needed based on new scheme, e.g., for idle/success messages
                }
            }
        }
    }

    // Reset settings to defaults
    private func resetToDefaults() {
        // Also reset the text extractor service
        selectedTextExtractor = .gemini

        selectedModelId = .geminiFlash25Preview
        customModelName = ""
        userPrompt = """
            Output the text from the image as text. Start immediately with the first word. \
            Format for clarity, format blocks of text into paragraphs, and use markdown sparingly.
            """
        apiEndpointUrlString = "https://generativelanguage.googleapis.com/v1beta/models/"
        draftsTag = "notebook"
        photoFolderName = "notebook" // Updated from savePhotosToAlbum
        targetApp = .drafts
        // Reset Vision settings
        visionRecognitionLevel = .accurate
        visionUsesLanguageCorrection = true
        // Note: API key is not reset as it's sensitive information
    }

    private func showApiKeyOnboarding() {
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

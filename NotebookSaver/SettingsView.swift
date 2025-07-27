import SwiftUI
import UIKit // For UIResponder keyboard notifications
import Foundation // For NotificationCenter, keep if needed

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
    case ai, general, about

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .ai: return "AI"
        case .general: return "General"
        case .about: return "About"
        }
    }

    var iconName: String {
        switch self {
        case .ai: return "brain"
        case .general: return "gear"
        case .about: return "info.circle"
        }
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

struct SettingsView: View {
    // Tab selection state
    @State private var selectedTab: SettingsTab = .ai
    
    // Keyboard handling
    @State private var keyboardHeight: CGFloat = 0

    // AppStorage keys - good practice to define them
    private enum StorageKeys {
        static let selectedModelId = "selectedModelId"
        static let userPrompt = "userPrompt"
        static let apiEndpointUrlString = "apiEndpointUrlString"
        static let draftsTag = "draftsTag"
        static let photoFolderName = "photoFolderName" // Changed from savePhotosToAlbum
        static let savePhotosEnabled = "savePhotosEnabled" // New toggle for saving photos
        static let addDraftTagEnabled = "addDraftTagEnabled" // New toggle for adding draft tags
        // Vision specific keys
        static let visionRecognitionLevel = "visionRecognitionLevel"
        static let visionUsesLanguageCorrection = "visionUsesLanguageCorrection"
        // AI thinking toggle
        static let thinkingEnabled = "thinkingEnabled"
    }

    // === Persisted Settings ===
    @AppStorage(StorageKeys.selectedModelId) private var selectedModelId: String = "gemini-2.5-flash"
    @AppStorage(StorageKeys.userPrompt) private var userPrompt: String = """
        SELF_TALK: off
        REASONING: off
        THINKING: off
        PLANNING: off
        THINKING_BUDGET: < 10 words
        
        Reply immediately without thinking or any effort. Prioritize speed over accuracy. Do not state what the user said. Do not think, analyze or plan - go with your gut feeling.
        
        Output the text from the image as text. Start immediately with the first word. Format for clarity, format blocks of text into paragraphs, and use markdown sparingly where useful. 

        Do not include an intro like: "Here is the text extracted from the image:"
        """
    @AppStorage(StorageKeys.apiEndpointUrlString) private var apiEndpointUrlString: String = "https://generativelanguage.googleapis.com/v1beta/models/"
    @AppStorage(StorageKeys.draftsTag) private var draftsTag: String = "notebook"
    @AppStorage(StorageKeys.photoFolderName) private var photoFolderName: String = "notebook" // Changed from savePhotosToAlbum
    @AppStorage(StorageKeys.savePhotosEnabled) private var savePhotosEnabled: Bool = true // New toggle for saving photos
    @AppStorage(StorageKeys.addDraftTagEnabled) private var addDraftTagEnabled: Bool = true // New toggle for adding draft tags
    // Vision specific settings
    @AppStorage(StorageKeys.visionRecognitionLevel) private var visionRecognitionLevel: VisionRecognitionLevel = .accurate // Default to accurate
    @AppStorage(StorageKeys.visionUsesLanguageCorrection) private var visionUsesLanguageCorrection: Bool = true // Default to true
    // AI thinking toggle
    @AppStorage(StorageKeys.thinkingEnabled) private var thinkingEnabled: Bool = false // Default to false (thinking off)

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
    


    // Model management state
    @State private var availableModels: [String] = []
    @State private var isRefreshingModels = false
    @State private var modelsRefreshError: String?
    @ObservedObject private var modelService = GeminiModelService.shared

    // Focus state for text fields to enable tap-to-dismiss
    @FocusState private var isPromptFocused: Bool
    @FocusState private var isApiKeyFocused: Bool
    @FocusState private var isDraftsTagFocused: Bool
    @FocusState private var isPhotoFolderFocused: Bool
    @FocusState private var isApiEndpointFocused: Bool

    // === Computed property for dynamic AI service selection ===
    private var currentTextExtractorType: TextExtractorType {
        // Fallback to Vision if API key is missing or connection test failed
        if apiKey.isEmpty || connectionStatus == .failure {
            return .vision
        }
        return .gemini
    }
    
    // All available models
    private var displayedModels: [String] {
        return availableModels
    }

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
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Add padding at the top so tabs are visible when camera slides up
                Spacer()
                    .frame(height: 50) // Reduced space for the camera's bottom portion
                
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
                .frame(maxHeight: .infinity) // Allow content to expand

                
                // Custom tab selector - moved to bottom with enhanced 3D styling
                HStack(spacing: 0) {
                    ForEach(Array(SettingsTab.allCases.enumerated()), id: \.element) { index, tab in
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedTab = tab
                            }
                        }) {
                            VStack(spacing: 6) {
                                // Icon with backlit effect for selected tab
                                Image(systemName: tab.iconName)
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundColor(selectedTab == tab ? Color(red: 1.0, green: 0.4, blue: 0.0) : Color.orangeTabbyText.opacity(0.6))
                                    .shadow(color: selectedTab == tab ? Color.yellow.opacity(0.7) : Color.clear, radius: selectedTab == tab ? 4 : 0)
                                    .shadow(color: selectedTab == tab ? Color.yellow.opacity(0.4) : Color.clear, radius: selectedTab == tab ? 8 : 0)
                                
                                Text(tab.displayName)
                                    .font(.caption2)
                                    .fontWeight(selectedTab == tab ? .semibold : .regular)
                                    .foregroundColor(selectedTab == tab ? Color(red: 1.0, green: 0.4, blue: 0.0) : Color.orangeTabbyText.opacity(0.6))
                                    .shadow(color: selectedTab == tab ? Color.yellow.opacity(0.6) : Color.clear, radius: selectedTab == tab ? 3 : 0)
                                    .shadow(color: selectedTab == tab ? Color.yellow.opacity(0.3) : Color.clear, radius: selectedTab == tab ? 6 : 0)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                            .scaleEffect(selectedTab == tab ? 1.05 : 1.0)
                            .animation(.easeInOut(duration: 0.2), value: selectedTab == tab)
                        }
                        .padding(.horizontal, 4)
                        
                        // Add vertical divider between tabs (but not after the last one)
                        if index < SettingsTab.allCases.count - 1 {
                            Rectangle()
                                .fill(Color.orangeTabbyDark.opacity(0.5))
                                .frame(width: 1, height: 40)
                                .padding(.vertical, 10)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 12)
                .padding(.bottom, 16) // Add extra space under the tabs
                .background(
                    Color.orangeTabbyBackground
                        .overlay(
                            Rectangle()
                                .fill(Color.orangeTabbyDark.opacity(0.1))
                                .frame(height: 1),
                            alignment: .top
                        )
                )
                .background(Color.orangeTabbyBackground) // Extend background to safe area
                .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: -2) // Shadow cast from tabs onto content above
            }
            .frame(width: geometry.size.width, height: geometry.size.height - 80) // Subtract 80 to account for top padding in ContentView
        }
        .background(Color.orangeTabbyBackground)
        .preferredColorScheme(.light)
        .onAppear {
            loadAPIKey()
            if apiEndpointUrlString.isEmpty {
                apiEndpointUrlString = "https://generativelanguage.googleapis.com/v1beta/models/"
            }
            setupKeyboardObservers()
            initializeModels()
            // Initialize prompt to match thinking toggle state on first launch
            initializePromptForThinkingState()
            

        }
        .onDisappear {
            removeKeyboardObservers()
        }
        .dismissKeyboardOnTap()
    }

    // MARK: - Keyboard Handling
    
    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                withAnimation(.easeInOut(duration: 0.3)) {
                    // Add a larger buffer to ensure text field is fully visible with extra space
                    self.keyboardHeight = keyboardFrame.height + 60
                }
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                self.keyboardHeight = 0
            }
        }
    }
    
    private func removeKeyboardObservers() {
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
    
    // MARK: - Tab Views

    // General tab with app settings
    var generalTabView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                // Add tag to draft toggle - horizontal layout
                HStack(spacing: 16) {
                    Text("Add Tag To Draft")
                        .font(.headline)
                        .foregroundColor(Color.orangeTabbyText.opacity(0.7))
                    
                    Spacer()
                    
                    Toggle("", isOn: $addDraftTagEnabled)
                        .labelsHidden()
                        .tint(Color.orangeTabbyAccent)
                }

                // Draft Tag - horizontal layout (only show if adding tags is enabled)
                if addDraftTagEnabled {
                    HStack(spacing: 16) {
                        Text("Draft Tag")
                            .font(.headline)
                            .foregroundColor(Color.orangeTabbyText.opacity(0.7))
                            .frame(width: 120, alignment: .leading)
                        
                        TextField("Tag name", text: $draftsTag)
                            .disableAutocorrection(true)
                            .focused($isDraftsTagFocused)
                            .onSubmit { isDraftsTagFocused = false }
                            .id("draftsTag")
                            .onChange(of: isDraftsTagFocused) { _, focused in
                                if focused {
                                    // Add a small delay to ensure keyboard is shown first
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            proxy.scrollTo("draftsTag", anchor: .top)
                                        }
                                    }
                                }
                            }
                            .frame(height: 46)
                            .padding(.horizontal, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.orangeTabbyLight.opacity(0.7))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(isDraftsTagFocused ? Color.orangeTabbyAccent : Color.orangeTabbyDark.opacity(0.4), lineWidth: isDraftsTagFocused ? 2 : 1)
                                    )
                            )
                            .foregroundColor(Color.orangeTabbyText)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Save Photo Toggle - horizontal layout
                HStack(spacing: 16) {
                    Text("Save Photo")
                        .font(.headline)
                        .foregroundColor(Color.orangeTabbyText.opacity(0.7))
                    
                    Spacer()
                    
                    Toggle("", isOn: $savePhotosEnabled)
                        .labelsHidden()
                        .tint(Color.orangeTabbyAccent)
                }

                // Photo Album - horizontal layout (only show if saving photos is enabled)
                if savePhotosEnabled {
                    HStack(spacing: 16) {
                        Text("Photo Album")
                            .font(.headline)
                            .foregroundColor(Color.orangeTabbyText.opacity(0.7))
                            .frame(width: 120, alignment: .leading)
                        
                        TextField("Album name", text: $photoFolderName)
                            .disableAutocorrection(true)
                            .focused($isPhotoFolderFocused)
                            .onSubmit { isPhotoFolderFocused = false }
                            .id("photoFolder")
                            .onChange(of: isPhotoFolderFocused) { _, focused in
                                if focused {
                                    // Add a small delay to ensure keyboard is shown first
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            proxy.scrollTo("photoFolder", anchor: .top)
                                        }
                                    }
                                }
                            }
                            .frame(height: 46)
                            .padding(.horizontal, 12)
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
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding()
            .padding(.bottom, keyboardHeight)
        }
        .animation(.easeInOut(duration: 0.3), value: addDraftTagEnabled)
        .animation(.easeInOut(duration: 0.3), value: savePhotosEnabled)
        }
    }

        // AI tab with model selection and API settings
    var aiTabView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                // AI Instruction Prompt - Always show for Gemini configuration
                VStack(alignment: .leading, spacing: 12) {
                    Text("Prompt")
                        .font(.headline)
                        .foregroundColor(Color.orangeTabbyText.opacity(0.7))
                    
                    TextEditor(text: $userPrompt)
                        .frame(minHeight: 100, maxHeight: 200)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.orangeTabbyLight.opacity(0.7))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(isPromptFocused ? Color.orangeTabbyAccent : Color.orangeTabbyDark.opacity(0.4), lineWidth: isPromptFocused ? 2 : 1)
                                )
                        )
                        .focused($isPromptFocused)
                        .onSubmit { isPromptFocused = false }
                        .id("promptEditor")
                        .onChange(of: isPromptFocused) { _, focused in
                            if focused {
                                // Add a small delay to ensure keyboard is shown first
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        proxy.scrollTo("promptEditor", anchor: .top)
                                    }
                                }
                            }
                        }
                        .foregroundColor(Color.orangeTabbyText)
                }

                geminiSettingsSection(proxy: proxy) // Always show Gemini settings (API key, model, endpoint)
                
                // AI Thinking Toggle - horizontal layout (moved to bottom)
                HStack(spacing: 16) {
                    Text("Thinking")
                        .font(.headline)
                        .foregroundColor(Color.orangeTabbyText.opacity(0.7))
                    
                    Spacer()
                    
                    Toggle("", isOn: $thinkingEnabled)
                        .labelsHidden()
                        .tint(Color.orangeTabbyAccent)
                        .onChange(of: thinkingEnabled) { _, enabled in
                            updatePromptForThinking(enabled: enabled)
                        }
                }
                
                // Conditional display for Vision if it's the active fallback
                if currentTextExtractorType == .vision {
                    HStack(spacing: 12) {
                        Image(systemName: "eye.circle.fill")
                            .font(.title2)
                            .foregroundColor(Color.orangeTabbyAccent)
                        
                        Text("Using Apple Vision for offline text recognition")
                            .font(.subheadline)
                            .foregroundColor(Color.orangeTabbyText)
                        
                        Spacer()
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.orangeTabbyLight.opacity(0.4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.orangeTabbyAccent.opacity(0.3), lineWidth: 1)
                            )
                    )
                    visionSettingsSection(proxy: proxy)
                }
                
                Spacer(minLength: 40)
            }
            .padding()
            .padding(.bottom, keyboardHeight)
        }
        .animation(.easeInOut(duration: 0.3), value: currentTextExtractorType) // Animate changes when Vision section appears/disappears
        .animation(.easeInOut(duration: 0.2), value: isViewInitialized) // Animate spacing changes
        }
        .onAppear {
            // Initialize prompt to match thinking toggle state on first launch
            initializePromptForThinkingState()
        }
        .id("aiTabView") // Add stable ID to prevent layout issues
    }

    // About tab with app info
    var aboutTabView: some View {
        ScrollView {
            VStack(spacing: 30) {
                // App Icon with 16:9 aspect ratio and rounded corners
                Group {
                    #if os(iOS)
                    if let image = UIImage(named: "AboutIcon") {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(maxHeight: 120)
                            .aspectRatio(16/9, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.orangeTabbyLight.opacity(0.8))
                                .aspectRatio(16/9, contentMode: .fit)
                                .frame(maxHeight: 120)
                            
                            Image(systemName: "doc.text.image")
                                .font(.system(size: 40, weight: .light))
                                .foregroundColor(Color.orangeTabbyAccent)
                        }
                    }
                    #else
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.orangeTabbyLight.opacity(0.8))
                            .aspectRatio(16/9, contentMode: .fit)
                            .frame(maxHeight: 120)
                        
                        Image(systemName: "doc.text.image")
                            .font(.system(size: 40, weight: .light))
                            .foregroundColor(Color.orangeTabbyAccent)
                    }
                    #endif
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.orangeTabbyAccent.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: Color.orangeTabbyDark.opacity(0.3), radius: 8, x: 0, y: 4)
                .padding(.top, 20)

                // App Title and Version
                VStack(spacing: 8) {
                    Text("Cat Scribe")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(Color.orangeTabbyText)
                    
                    Text("v1.0.0")
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(Color.orangeTabbyText.opacity(0.8))
                }

                // Description
                Text("Capture notebook pages and convert them to digital notes using AI.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(Color.orangeTabbyText.opacity(0.7))
                    .padding(.horizontal, 20)

                // Links Section
                VStack(spacing: 20) {
                    Link(destination: URL(string: "https://www.daviddegner.com/blog/cat-scribe/")!) {
                        HStack {
                            Image(systemName: "questionmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(Color.orangeTabbyAccent)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Help & Documentation")
                                    .font(.headline)
                                    .foregroundColor(Color.orangeTabbyText)
                                
                                Text("Get help and learn how to use the app")
                                    .font(.caption)
                                    .foregroundColor(Color.orangeTabbyText.opacity(0.6))
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(Color.orangeTabbyText.opacity(0.4))
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.orangeTabbyLight.opacity(0.3))
                        )
                    }

                    Link(destination: URL(string: "mailto:David@DavidDegner.com")!) {
                        HStack {
                            Image(systemName: "envelope.fill")
                                .font(.title2)
                                .foregroundColor(Color.orangeTabbyAccent)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Contact Support")
                                    .font(.headline)
                                    .foregroundColor(Color.orangeTabbyText)
                                
                                Text("Get help with any issues")
                                    .font(.caption)
                                    .foregroundColor(Color.orangeTabbyText.opacity(0.6))
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(Color.orangeTabbyText.opacity(0.4))
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.orangeTabbyLight.opacity(0.3))
                        )
                    }
                }
                .padding(.horizontal)

                Spacer(minLength: 40)
            }
            .padding(.horizontal)
            .padding(.vertical)
        }
    }

    // MARK: - Section Views
    
    @ViewBuilder
    private func geminiSettingsSection(proxy: ScrollViewProxy) -> some View {
        // Model selection
        VStack(alignment: .leading, spacing: 12) {
            Text("Model")
                .font(.headline)
                .foregroundColor(Color.orangeTabbyText.opacity(0.7))
            
            // Show error if models refresh failed
            if let error = modelsRefreshError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.red.opacity(0.1))
                    )
            }
            
            // Model picker with refresh button beside it
            HStack(spacing: 12) {
                // Replace ScrollView with Picker dropdown
                Picker("Select AI Model", selection: $selectedModelId) {
                    ForEach(displayedModels, id: \.self) { model in
                        Text(model)
                            .foregroundColor(Color.black)
                            .tag(model)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 46)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.orangeTabbyLight.opacity(0.7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.orangeTabbyDark.opacity(0.4), lineWidth: 1)
                        )
                )
                .tint(Color.black)
                
                // Refresh button beside the dropdown
                Button(action: refreshModels) {
                    HStack(spacing: 4) {
                        if isRefreshingModels {
                            ProgressView()
                                .scaleEffect(0.8)
                                .progressViewStyle(CircularProgressViewStyle(tint: Color.white))
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .medium))
                        }
                    }
                    .foregroundColor(isRefreshingModels || apiKey.isEmpty ? Color.orangeTabbyText.opacity(0.4) : Color.white)
                }
                .frame(width: 44, height: 46)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isRefreshingModels || apiKey.isEmpty ? 
                             Color.orangeTabbyText.opacity(0.2) : Color.orangeTabbyDark)
                )
                .disabled(isRefreshingModels || apiKey.isEmpty)
            }
            

        }
        
        // API Key
        VStack(alignment: .leading, spacing: 8) {
            Text("Key")
                .font(.headline)
                .foregroundColor(Color.orangeTabbyText.opacity(0.7))
            
            HStack(spacing: 12) {
                SecureField(apiKeyPlaceholderText, text: $apiKey)
                    .textContentType(.password)
                    // .cardStyled(isError: apiKey.isEmpty)
                    .frame(height: 46)
                    .padding(.horizontal, 12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.orangeTabbyLight.opacity(0.7)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(isApiKeyFocused ? Color.orangeTabbyAccent : (apiKey.isEmpty ? Color.red : Color.orangeTabbyDark.opacity(0.4)), lineWidth: isApiKeyFocused || apiKey.isEmpty ? 2:1 ))
                    .layoutPriority(1)
                    .focused($isApiKeyFocused)
                    .onSubmit { isApiKeyFocused = false }
                    .id("apiKey")
                    .onChange(of: isApiKeyFocused) { _, focused in
                        if focused {
                            // Add a small delay to ensure keyboard is shown first
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    proxy.scrollTo("apiKey", anchor: .top)
                                }
                            }
                        } else { 
                            saveApiKey() 
                        }
                    }
                    .foregroundColor(Color.orangeTabbyText)
                Button(action: { saveApiKey() }) {
                    Image(systemName: "square.and.arrow.down")
                        .imageScale(.large)
                        .foregroundColor((apiKey.isEmpty || !showSaveConfirmation) ? Color.orangeTabbyText.opacity(0.4) : Color.white)
                }
                .frame(width: 44, height: 46)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill((apiKey.isEmpty || !showSaveConfirmation) ? 
                             Color.orangeTabbyText.opacity(0.2) : Color.orangeTabbyDark)
                )
                .disabled(apiKey.isEmpty)
            }
            
            if !apiKeyStatusMessage.isEmpty {
                HStack {
                    Spacer()
                    Text(apiKeyStatusMessage)
                        .font(.caption)
                        .foregroundColor(apiKeyStatusMessage.contains("Saved") ? Color.black : .red)
                }
            }
        }
        
        // API Endpoint URL and Test Connection
        VStack(alignment: .leading, spacing: 8) {
            Text("AI Endpoint")
                .font(.headline)
                .foregroundColor(Color.orangeTabbyText.opacity(0.7))
            
            HStack(spacing: 12) {
                TextField(apiUrlPlaceholderText, text: $apiEndpointUrlString)
                    .disableAutocorrection(true)
                    .focused($isApiEndpointFocused)
                    .onSubmit { isApiEndpointFocused = false }
                    .id("apiEndpoint")
                    .onChange(of: isApiEndpointFocused) { _, focused in
                        if focused {
                            // Add a small delay to ensure keyboard is shown first
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    proxy.scrollTo("apiEndpoint", anchor: .top)
                                }
                            }
                        }
                    }
                    // .cardStyled(isError: apiUrlHasError)
                    .frame(height: 46)
                    .padding(.horizontal, 12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.orangeTabbyLight.opacity(0.7)))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(isApiEndpointFocused ? Color.orangeTabbyAccent : (apiUrlHasError ? Color.red : Color.orangeTabbyDark.opacity(0.4)), lineWidth: isApiEndpointFocused || apiUrlHasError ? 2:1 ))
                    .layoutPriority(1)
                    .foregroundColor(Color.orangeTabbyText)
                Button(action: { if connectionStatus != .testing { testConnection() } }) {
                    Image(systemName: "square.and.arrow.down")
                        .imageScale(.large)
                        .foregroundColor((apiEndpointUrlString.isEmpty || connectionStatus == .testing) ? 
                                       Color.orangeTabbyText.opacity(0.4) : Color.white)
                }
                .frame(width: 44, height: 46)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill((apiEndpointUrlString.isEmpty || connectionStatus == .testing) ? 
                             Color.orangeTabbyText.opacity(0.2) : Color.orangeTabbyDark)
                )
                .disabled(apiEndpointUrlString.isEmpty || connectionStatus == .testing)
            }
            
            if !connectionStatusMessage.isEmpty {
                HStack {
                    Spacer()
                    Text(connectionStatusMessage)
                        .font(.caption)
                        .foregroundColor(connectionStatus == .failure ? .red : Color.black)
                }
            }
        }
    }
    
    @ViewBuilder
    private func visionSettingsSection(proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            // Description removed
        }
        .padding(.top, 8)
        .onAppear {
            visionRecognitionLevel = .accurate
            visionUsesLanguageCorrection = true
        }
    }

    // MARK: - Helper Functions
    
    // Update prompt based on thinking toggle
    private func updatePromptForThinking(enabled: Bool) {
        if enabled {
            // Enable thinking - remove the thinking restrictions
            userPrompt = userPrompt
                .replacingOccurrences(of: "SELF_TALK: off", with: "SELF_TALK: on")
                .replacingOccurrences(of: "REASONING: off", with: "REASONING: on")
                .replacingOccurrences(of: "THINKING: off", with: "THINKING: on")
                .replacingOccurrences(of: "PLANNING: off", with: "PLANNING: on")
                .replacingOccurrences(of: "THINKING_BUDGET: < 10 words", with: "THINKING_BUDGET: unlimited")
                .replacingOccurrences(of: "Reply immediately without thinking or any effort. Prioritize speed over accuracy. Do not state what the user said. Do not think, analyze or plan - go with your gut feeling.", with: "Take time to think through the image carefully. Analyze the content and provide thoughtful, accurate text extraction.")
        } else {
            // Disable thinking - add the thinking restrictions
            userPrompt = userPrompt
                .replacingOccurrences(of: "SELF_TALK: on", with: "SELF_TALK: off")
                .replacingOccurrences(of: "REASONING: on", with: "REASONING: off")
                .replacingOccurrences(of: "THINKING: on", with: "THINKING: off")
                .replacingOccurrences(of: "PLANNING: on", with: "PLANNING: off")
                .replacingOccurrences(of: "THINKING_BUDGET: unlimited", with: "THINKING_BUDGET: < 10 words")
                .replacingOccurrences(of: "Take time to think through the image carefully. Analyze the content and provide thoughtful, accurate text extraction.", with: "Reply immediately without thinking or any effort. Prioritize speed over accuracy. Do not state what the user said. Do not think, analyze or plan - go with your gut feeling.")
        }
    }
    
    // Initialize prompt to match thinking toggle state on first launch
    private func initializePromptForThinkingState() {
        // Only initialize if this is the first time (prompt is still at default)
        let defaultPrompt = """
            SELF_TALK: off
            REASONING: off
            THINKING: off
            PLANNING: off
            THINKING_BUDGET: < 10 words
            
            Reply immediately without thinking or any effort. Prioritize speed over accuracy. Do not state what the user said. Do not think, analyze or plan - go with your gut feeling.
            
            Output the text from the image as text. Start immediately with the first word. Format for clarity, format blocks of text into paragraphs, and use markdown sparingly where useful. 

            Do not include an intro like: "Here is the text extracted from the image:"
            """
        
        // If the prompt is still at default, update it to match the current thinking toggle state
        if userPrompt == defaultPrompt {
            updatePromptForThinking(enabled: thinkingEnabled)
        }
    }



    // Load API key from keychain
    private func loadAPIKey() {
        if let loadedKey = KeychainService.loadAPIKey() {
            apiKey = loadedKey
            showSaveConfirmation = true
        } else {
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

        Task {
            let success = await GeminiService.warmUpConnection()
            DispatchQueue.main.async {
                if success {
                    connectionStatus = .success
                    connectionStatusMessage = "Connection successful!"
                } else {
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
    }

    // Reset settings to defaults
    private func resetToDefaults() {
        selectedModelId = "gemini-2.5-flash"
        userPrompt = """
            SELF_TALK: off
            REASONING: off
            THINKING: off
            PLANNING: off
            THINKING_BUDGET: < 10 words
            
            Reply immediately without thinking or any effort. Prioritize speed over accuracy. Do not state what the user said. Do not think, analyze or plan - go with your gut feeling.
            
            Output the text from the image as text. Start immediately with the first word. Format for clarity, format blocks of text into paragraphs, and use markdown sparingly where useful. 

            Do not include an intro like: "Here is the text extracted from the image:"
            """
        apiEndpointUrlString = "https://generativelanguage.googleapis.com/v1beta/models/"
        draftsTag = "notebook"
        photoFolderName = "notebook" // Updated from savePhotosToAlbum
        savePhotosEnabled = true
        addDraftTagEnabled = true
        // Reset Vision settings
        visionRecognitionLevel = .accurate
        visionUsesLanguageCorrection = true
        // Reset AI thinking setting
        thinkingEnabled = false
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
    
    // Function to initialize available models
    private func initializeModels() {
        // Load cached models
        loadInitialModels()
    }
    
    private func loadInitialModels() {
        let stringModels = modelService.loadCachedModelIds()
        availableModels = stringModels
    }
    
    // Function to refresh models from API
    private func refreshModels() {
        guard !apiKey.isEmpty else {
            modelsRefreshError = "API key is required to refresh models"
            return
        }
        
        isRefreshingModels = true
        modelsRefreshError = nil
        print("Refreshing models with API key: \(apiKey.prefix(10))...")
        
        Task {
            do {
                let stringModels = try await modelService.fetchAvailableModels()
                await MainActor.run {
                    self.availableModels = stringModels
                    self.isRefreshingModels = false
                    print("Successfully refreshed \(availableModels.count) models")
                }
            } catch APIError.authenticationError {
                await MainActor.run {
                    self.modelsRefreshError = "Authentication failed. Please check your API key in Settings."
                    self.isRefreshingModels = false
                    print("Authentication failed - invalid API key")
                }
            } catch APIError.missingApiKey {
                await MainActor.run {
                    self.modelsRefreshError = "API key is missing. Please add it in Settings."
                    self.isRefreshingModels = false
                    print("Missing API key")
                }
            } catch {
                await MainActor.run {
                    self.modelsRefreshError = error.localizedDescription
                    self.isRefreshingModels = false
                    print("Failed to refresh models: \(error)")
                }
            }
        }
    }

}

#Preview {
    SettingsView()
}


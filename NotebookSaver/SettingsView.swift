import SwiftUI
import os.log

// Logger for Settings-related actions
private let settingsLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "NotebookSaver", category: "Settings")

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
    @EnvironmentObject var appState: AppStateManager
    @EnvironmentObject var cameraManager: CameraManager
    @Environment(\.openURL) private var openURL
    // Tab selection state
    @State private var selectedTab: SettingsTab = .ai

    // === Persisted Settings (using centralized SettingsKey) ===
    @AppStorage(SettingsKey.selectedModelId) private var selectedModelId: String = "gemini-2.5-flash-lite"
    @AppStorage(SettingsKey.userPrompt) private var userPrompt: String = GeminiService.defaultPrompt
    @AppStorage(SettingsKey.apiEndpointUrlString) private var apiEndpointUrlString: String = "https://generativelanguage.googleapis.com/v1beta/models/"
    @AppStorage(SettingsKey.draftsTag) private var draftsTag: String = "notebook"
    @AppStorage(SettingsKey.photoFolderName) private var photoFolderName: String = "notebook"
    @AppStorage(SettingsKey.savePhotosEnabled) private var savePhotosEnabled: Bool = true
    @AppStorage(SettingsKey.addDraftTagEnabled) private var addDraftTagEnabled: Bool = true
    // Vision specific settings
    @AppStorage(SettingsKey.visionRecognitionLevel) private var visionRecognitionLevel: VisionRecognitionLevel = .accurate
    @AppStorage(SettingsKey.visionUsesLanguageCorrection) private var visionUsesLanguageCorrection: Bool = true
    // AI thinking toggle
    @AppStorage(SettingsKey.thinkingEnabled) private var thinkingEnabled: Bool = false
    @AppStorage(SettingsKey.geminiPhotoTokenBudget) private var geminiPhotoTokenBudget: GeminiPhotoTokenBudget = .high
    // Text extraction service selection (typed enum)
    @AppStorage(SettingsKey.textExtractorService) private var textExtractorService: TextExtractorType = .vision

    // === State for API Key (using Keychain) ===
    @State private var apiKey: String = ""
    @State private var apiKeyStatusMessage: String = ""
    @State private var showSaveConfirmation = false


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
    @State private var showResetConfirmation = false
    @State private var showingPerformanceLogs = false
    
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

    private func isGemini3Model(_ model: String) -> Bool {
        return model.lowercased().hasPrefix("gemini-3")
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Add padding at the top so content doesn't get cut off by camera
                Spacer()
                    .frame(height: 20) // Minimal space for the camera's bottom portion
                
                // Tab content with swiping motion using TabView
                TabView(selection: $selectedTab) {
                    aiTabView
                        .tag(SettingsTab.ai)
                    
                    generalTabView
                        .tag(SettingsTab.general)
                    
                    aboutTabView
                        .tag(SettingsTab.about)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: selectedTab)
                .frame(maxHeight: .infinity) // Allow content to expand

                
                // Custom tab selector - moved to bottom with enhanced 3D styling
                HStack(spacing: 0) {
                    // Ensure tabs are in the correct order: AI / General / About
                    ForEach([SettingsTab.ai, SettingsTab.general, SettingsTab.about], id: \.self) { tab in
                        let index = [SettingsTab.ai, SettingsTab.general, SettingsTab.about].firstIndex(of: tab) ?? 0
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                selectedTab = tab
                            }
                        }) {
                            VStack(spacing: 6) {
                                Image(systemName: tab.iconName)
                                    .font(.system(size: 22, weight: .medium))
                                
                                Text(tab.displayName)
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(selectedTab == tab ? Color.orangeTabbyAccent : Color.orangeTabbyText.opacity(0.6))
                        .padding(.horizontal, 4)
                        
                        // Add vertical divider between tabs (but not after the last one)
                        if index < 2 { // Since we have 3 tabs (AI, General, About)
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
        .task {
            loadAPIKey()
            if apiEndpointUrlString.isEmpty {
                apiEndpointUrlString = "https://generativelanguage.googleapis.com/v1beta/models/"
            }
            initializeModels()
            // Initialize prompt to match thinking toggle state on first launch
            initializePromptForThinkingState()
        }
        .onChange(of: appState.shouldReloadAPIKey) { _, _ in
            loadAPIKey()
        }
        .onDisappear {
            // Cancel any pending tasks to prevent memory leaks
            saveConfirmationTask?.cancel()
            connectionTestTask?.cancel()
        }
        .dismissKeyboardOnTap()
    }

    // MARK: - Keyboard Handling (Focus-based)
    
    // MARK: - Tab Views

    // General tab with app settings
    var generalTabView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Add top padding to prevent content from being cut off by camera
                    Spacer()
                        .frame(height: 20)
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
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .focused($isDraftsTagFocused)
                            .onSubmit { isDraftsTagFocused = false }
                            .id("draftsTag")
                            .onChange(of: isDraftsTagFocused) { _, focused in
                                if focused {
                                    // Add a small delay to ensure keyboard is shown first
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            proxy.scrollTo("draftsTag", anchor: .center)
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
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .focused($isPhotoFolderFocused)
                            .onSubmit { isPhotoFolderFocused = false }
                            .id("photoFolder")
                            .onChange(of: isPhotoFolderFocused) { _, focused in
                                if focused {
                                    // Add a small delay to ensure keyboard is shown first
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            proxy.scrollTo("photoFolder", anchor: .center)
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
        }
        .scrollDismissesKeyboard(.interactively)
        .animation(.easeInOut(duration: 0.3), value: addDraftTagEnabled)
        .animation(.easeInOut(duration: 0.3), value: savePhotosEnabled)
        }
    }

    // AI tab with model selection and API settings
    var aiTabView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Add top padding to prevent content from being cut off by camera
                    Spacer()
                        .frame(height: 20)
                    // Service Selection - using default segmented picker
                    Picker("Text Extraction Service", selection: $textExtractorService) {
                        ForEach(TextExtractorType.allCases) { service in
                            Text(service.displayName)
                                .tag(service)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .frame(height: 46)
                    .animation(.easeInOut(duration: 0.2), value: textExtractorService)
                    
                    // Show different content based on selected service
                    if textExtractorService == .gemini {
                        // Cloud (Gemini) settings
                        
                        // AI Instruction Prompt
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Prompt")
                                .font(.headline)
                                .foregroundColor(Color.orangeTabbyText.opacity(0.7))
                            
                            TextEditor(text: $userPrompt)
                                .frame(minHeight: 100, idealHeight: 150, maxHeight: 200)
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
                                                proxy.scrollTo("promptEditor", anchor: .center)
                                            }
                                        }
                                    }
                                }
                                .foregroundColor(Color.orangeTabbyText)
                                .layoutPriority(1)
                        }

                        geminiSettingsSection(proxy: proxy)
                        
                        // AI Thinking Toggle - horizontal layout
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
                        .padding(.top, 8) // Add consistent spacing to match General tab
                    } else {
                        // Local (Vision) explanation
                        localVisionExplanationSection
                    }
                    
                    // Vision settings section - show when Vision is selected
                    if textExtractorService == .vision {
                        visionSettingsSection(proxy: proxy)
                    }
                    
                    Spacer(minLength: 40)
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .animation(.easeInOut, value: textExtractorService) // Animate changes when Vision section appears/disappears
            .refreshable {
                // Only refresh if not already refreshing and API key is available
                guard !isRefreshingModels && !apiKey.isEmpty else { return }
                refreshModels()
                // Wait for the refresh to complete
                while isRefreshingModels {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                }
            }
        }
    }

    // About tab with app info
    var aboutTabView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Add top padding to prevent content from being cut off by camera
                Spacer()
                    .frame(height: 20)
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
                    
                    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
                    Text("v\(version)")
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(Color.orangeTabbyText.opacity(0.8))
                }

                // Description
                Text("Capture and digitize notebook pages.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(Color.orangeTabbyText.opacity(0.7))
                    .padding(.horizontal, 20)

                // Links Section
                VStack(spacing: 20) {
                    Button("Performance Logs") {
                        showingPerformanceLogs = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.orangeTabbyAccent)
                    
                    Button("How to get an API Key") {
                        showApiKeyOnboarding()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.orangeTabbyAccent)
                    
                    Button("Help & Documentation") {
                        if let url = URL(string: "https://www.daviddegner.com/blog/cat-scribe/") {
                            openURL(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.orangeTabbyAccent)

                    Button("Contact Support") {
                        if let url = URL(string: "mailto:David@DavidDegner.com") {
                            openURL(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.orangeTabbyAccent)
                }

                // Reset to Default Settings Button
                Button("Reset to Default Settings") {
                    showResetConfirmation = true
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .padding(.top, 30)
                .alert("Reset Settings", isPresented: $showResetConfirmation) {
                    Button("Cancel", role: .cancel) { }
                    Button("Reset", role: .destructive) {
                        resetToDefaults()
                    }
                } message: {
                    Text("This will reset all settings to their default values. This action cannot be undone.")
                }
                .sheet(isPresented: $showingPerformanceLogs) {
                    PerformanceLogView()
                }

                Spacer(minLength: 40)
            }
            .padding()
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
                    ForEach(availableModels, id: \.self) { model in
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
                    if isRefreshingModels {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .tint(Color.orangeTabbyAccent)
                .disabled(isRefreshingModels || apiKey.isEmpty)
                .accessibilityLabel("Refresh Models")
                .accessibilityHint("Fetches the latest list of available AI models from the API")
            }
        }

        if isGemini3Model(selectedModelId) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Photo Token Budget")
                    .font(.headline)
                    .foregroundColor(Color.orangeTabbyText.opacity(0.7))

                Picker("Photo Token Budget", selection: $geminiPhotoTokenBudget) {
                    ForEach(GeminiPhotoTokenBudget.allCases) { budget in
                        Text(budget.displayName)
                            .foregroundColor(Color.black)
                            .tag(budget)
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

                Text("Gemini 3 only. Higher budgets improve detail but can increase latency and cost.")
                    .font(.caption)
                    .foregroundColor(Color.orangeTabbyText.opacity(0.7))
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
                                    proxy.scrollTo("apiKey", anchor: .center)
                                }
                            }
                        } else { 
                            saveApiKey() 
                        }
                    }
                    .foregroundColor(Color.orangeTabbyText)
                Button(action: { saveApiKey() }) {
                    Image(systemName: "checkmark.circle.fill")
                }
                .buttonStyle(.bordered)
                .tint(Color.orangeTabbyAccent)
                .disabled(apiKey.isEmpty)
                .accessibilityLabel("Save API Key")
                .accessibilityHint("Saves the API key securely to the keychain")
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
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .keyboardType(.URL)
                    .focused($isApiEndpointFocused)
                    .onSubmit { 
                        isApiEndpointFocused = false
                        validateApiEndpointUrl()
                    }
                    .id("apiEndpoint")
                    .onChange(of: isApiEndpointFocused) { _, focused in
                        if focused {
                            // Add a small delay to ensure keyboard is shown first
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    proxy.scrollTo("apiEndpoint", anchor: .center)
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
                    Image(systemName: "network")
                }
                .buttonStyle(.bordered)
                .tint(Color.orangeTabbyAccent)
                .disabled(apiEndpointUrlString.isEmpty || connectionStatus == .testing)
                .accessibilityLabel("Test Connection")
                .accessibilityHint("Tests the connection to the API endpoint")
            }
            
            if !connectionStatusMessage.isEmpty {
                HStack {
                    Spacer()
                    Text(connectionStatusMessage)
                        .font(.caption)
                        .foregroundColor(connectionStatus == .failure ? .red : Color.black)
                    
                    if connectionStatus == .failure {
                        Button("Clear") {
                            clearConnectionStatus()
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                    }
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
        // Note: Removed .onAppear that was incorrectly resetting user settings
        // @AppStorage properties already persist correctly
    }
    
    @ViewBuilder
    private var localVisionExplanationSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "apple.logo")
                    .foregroundColor(Color.orangeTabbyAccent)
                    .font(.title2)
                Text("Apple Vision")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(Color.orangeTabbyText)
            }
            
            // Explanation content
            VStack(alignment: .leading, spacing: 16) {
                explanationItem(
                    icon: "exclamationmark.triangle.fill",
                    title: "Lower Quality",
                    description: "Basic text recognition with limited accuracy, especially poor with handwritten text. Best for printed text only."
                )
                
                explanationItem(
                    icon: "bolt.fill",
                    title: "Fast & Offline",
                    description: "Works instantly without internet connection. No API keys, accounts, or setup required."
                )
                
                explanationItem(
                    icon: "lock.shield.fill",
                    title: "Private & Secure",
                    description: "Text recognition happens entirely on your device. Your images never leave your phone."
                )
                

            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.orangeTabbyLight.opacity(0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.orangeTabbyAccent.opacity(0.3), lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private func explanationItem(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(Color.orangeTabbyAccent)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(Color.orangeTabbyText)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(Color.orangeTabbyText.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Helper Functions
    
    // Update prompt based on thinking toggle - now just ensures prompt is clean
    private func updatePromptForThinking(enabled: Bool) {
        let basePrompt = GeminiService.defaultPrompt
        
        // Only reset to base prompt if it contains thinking directives or is empty
        // This preserves user customizations while cleaning up old thinking directives
        if userPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || 
           userPrompt.contains("THINKING:") || userPrompt.contains("REASONING:") || userPrompt.contains("PLANNING:") {
            userPrompt = basePrompt
        }
        // If user has a custom prompt without thinking directives, preserve it
    }
    
    // Initialize prompt to match thinking toggle state on first launch
    private func initializePromptForThinkingState() {
        // If prompt is empty or contains old thinking directives, reset to clean base prompt
        if userPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || 
           userPrompt.contains("THINKING:") || userPrompt.contains("REASONING:") || userPrompt.contains("PLANNING:") {
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

    // Validate API endpoint URL format
    private func validateApiEndpointUrl() {
        guard !apiEndpointUrlString.isEmpty else { return }
        
        if URL(string: apiEndpointUrlString) == nil {
            connectionStatus = .failure
            connectionStatusMessage = "Invalid URL format"
        } else if connectionStatus == .failure && connectionStatusMessage == "Invalid URL format" {
            // Clear the error if URL is now valid
            connectionStatus = .idle
            connectionStatusMessage = ""
        }
    }
    
    // Save API key to keychain
    @State private var saveConfirmationTask: Task<Void, Never>?
    
    private func saveApiKey() {
        let success = KeychainService.saveAPIKey(apiKey)
        apiKeyStatusMessage = success ? "API Key Saved Successfully!" : "Failed to Save API Key."
        if success {
            withAnimation { showSaveConfirmation = true }
            
            // Cancel any existing confirmation task to prevent race conditions
            saveConfirmationTask?.cancel()
            
            // Optionally hide checkmark after a delay
            saveConfirmationTask = Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                if !Task.isCancelled {
                    await MainActor.run {
                        withAnimation { showSaveConfirmation = false }
                    }
                }
            }
        } else {
            withAnimation { showSaveConfirmation = false }
        }
    }

    // Test connection with better error handling
    @State private var connectionTestTask: Task<Void, Never>?
    
    private func testConnection() {
        // Cancel any existing connection test
        connectionTestTask?.cancel()
        
        connectionStatus = .testing
        connectionStatusMessage = "Connecting..."

        connectionTestTask = Task {
            let success = await GeminiService.warmUpConnection()
            
            if !Task.isCancelled {
                await MainActor.run {
                    if success {
                        connectionStatus = .success
                        connectionStatusMessage = "Connection successful!"
                    } else {
                        connectionStatus = .failure
                        connectionStatusMessage = apiKey.isEmpty ? "Connection failed: API Key missing." : "Connection failed: Invalid endpoint or key."
                    }

                    // Reset status after a few seconds, but only if not cancelled
                    Task {
                        try? await Task.sleep(nanoseconds: 4_000_000_000) // 4 seconds
                        if !Task.isCancelled && connectionStatus != .testing {
                            await MainActor.run {
                                connectionStatus = .idle
                                connectionStatusMessage = ""
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func clearConnectionStatus() {
        connectionTestTask?.cancel()
        connectionStatus = .idle
        connectionStatusMessage = ""
    }

    // Reset settings to defaults
    private func resetToDefaults() {
        selectedModelId = "gemini-2.5-flash-lite"
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
        // Reset Gemini 3 photo token budget setting
        geminiPhotoTokenBudget = .high
        // Reset text extractor service to default
        textExtractorService = .vision
        // Force reset prompt to the current default prompt
        userPrompt = GeminiService.defaultPrompt
        // Note: API key is not reset as it's sensitive information
    }

    private func showApiKeyOnboarding() {
        appState.presentOnboarding()
    }
    
    // Function to initialize available models
    private func initializeModels() {
        // Load cached models first
        loadInitialModels()
        
        // If this is the first launch and we have an API key, fetch models immediately
        if modelService.shouldFetchModels && !apiKey.isEmpty {
            refreshModels()
        }
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
        settingsLogger.info("Refreshing models list (API key present: \(apiKey.isEmpty ? "no" : "yes"))")
        
        Task {
            do {
                let stringModels = try await modelService.fetchAvailableModels()
                await MainActor.run {
                    self.availableModels = stringModels
                    self.isRefreshingModels = false
                    settingsLogger.info("Successfully refreshed models list: \(stringModels.count) models available")
                }
            } catch APIError.authenticationError {
                await MainActor.run {
                    self.modelsRefreshError = "Authentication failed. Please check your API key in Settings."
                    self.isRefreshingModels = false
                    settingsLogger.error("Models refresh failed: authentication error")
                }
            } catch APIError.missingApiKey {
                await MainActor.run {
                    self.modelsRefreshError = "API key is missing. Please add it in Settings."
                    self.isRefreshingModels = false
                    settingsLogger.error("Models refresh failed: missing API key")
                }
            } catch {
                await MainActor.run {
                    self.modelsRefreshError = error.localizedDescription
                    self.isRefreshingModels = false
                    settingsLogger.error("Models refresh failed: \(error.localizedDescription)")
                }
            }
        }
    }

}

#Preview {
    SettingsView()
        .environmentObject(AppStateManager())
        .environmentObject(CameraManager(setupOnInit: false))
}

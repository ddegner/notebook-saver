import SwiftUI
import AVFoundation // Needed for AVCaptureSession and sound effects
import UIKit // For UIKit components like UIImpactFeedbackGenerator, UIApplication, etc.

struct CameraView: View {
    @EnvironmentObject private var cameraManager: CameraManager
    @EnvironmentObject private var appState: AppStateManager
    @Binding var isShowingSettings: Bool
    
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false
    @State private var currentQuote: (quote: String, author: String)?



    var body: some View {
        GeometryReader { geometry in
            let safeAreaInsets = geometry.safeAreaInsets
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height
            let cameraHeight = screenWidth * (4.0/3.0)
            let statusBarHeight = max(safeAreaInsets.top + 10, 60)
            let bottomSafeArea = safeAreaInsets.bottom
            
            // Calculate available height for controls (everything below camera)
            let controlsHeight = screenHeight - statusBarHeight - cameraHeight

            VStack(spacing: 0) {
                StatusBarView(
                    cameraManager: cameraManager,
                    safeAreaInsets: safeAreaInsets
                )
                
                CameraPreviewArea(
                    cameraManager: cameraManager,
                    screenWidth: screenWidth,
                    cameraHeight: cameraHeight,
                    isLoading: isLoading,
                    currentQuote: currentQuote
                )
                
                ControlsArea(
                    isLoading: isLoading,
                    isShowingSettings: $isShowingSettings,
                    onCapturePressed: capturePhoto,
                    availableHeight: controlsHeight,
                    bottomSafeArea: bottomSafeArea
                )
            }
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 22,
                    bottomLeadingRadius: 40,
                    bottomTrailingRadius: 40,
                    topTrailingRadius: 22,
                    style: .continuous
                )
            )
            .ignoresSafeArea()
            .persistentSystemOverlays(.hidden)
        }
        .setupCameraView(
            cameraManager: cameraManager,
            appState: appState,
            errorMessage: $errorMessage,
            showErrorAlert: $showErrorAlert,
            processOpenedImage: processOpenedImage
        )
        .dismissKeyboardOnTap()
    }
}

// MARK: - Status Bar Component
struct StatusBarView: View {
    let cameraManager: CameraManager
    let safeAreaInsets: EdgeInsets
    
    var body: some View {
        Rectangle()
            .fill(Color.black)
            .frame(height: max(safeAreaInsets.top + 10, 60))
            .frame(maxWidth: .infinity)
            .edgesIgnoringSafeArea(.top)
    }
}

// MARK: - Camera Preview Component
struct CameraPreviewArea: View {
    let cameraManager: CameraManager
    let screenWidth: CGFloat
    let cameraHeight: CGFloat
    let isLoading: Bool
    let currentQuote: (quote: String, author: String)?
    
    var body: some View {
            ZStack {
            CameraPreview(
                session: cameraManager.session,
                isSessionReady: cameraManager.isSetupComplete && cameraManager.isAuthorized
            )
            .frame(width: screenWidth, height: cameraHeight)
            .clipped() // Ensure camera preview doesn't overflow
            .background(Color.black)
            .onDisappear {
                cameraManager.stopSession()
            }
            
            if isLoading {
                LoadingOverlay(currentQuote: currentQuote)
            }
        }
        .frame(width: screenWidth, height: cameraHeight)
        .background(Color.black)
    }
}

// MARK: - Loading Overlay Component
struct LoadingOverlay: View {
    let currentQuote: (quote: String, author: String)?
    
    var body: some View {
        ZStack {
            // Blurred camera preview overlay
            Color.black.opacity(0.5)
            Rectangle()
                .fill(.ultraThinMaterial)
            
            // Quote overlay
            VStack(spacing: 20) {
                if let quote = currentQuote {
                    VStack(spacing: 16) {
                        Text(quote.quote)
                            .font(.custom("Baskerville", size: 26))
                            .multilineTextAlignment(.center)
                            .foregroundColor(.white)
                            .padding(.horizontal, 30)
                            .frame(maxWidth: .infinity)

                        Text("— \(quote.author)")
                            .font(.custom("Baskerville", size: 20))
                            .italic()
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.top, 8)
                    }
                    .padding(.vertical, 30)
                    .padding(.horizontal, 20)
                } else {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                }
            }
            .padding(30)
        }
    }
}

// MARK: - Chevron pinned to CameraView
struct CameraChevron: View {
    @Binding var isShowingSettings: Bool

    var body: some View {
        Button {
            // Let the container’s implicit animation handle the slide
            isShowingSettings.toggle()
        } label: {
            Image(systemName: "chevron.up")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.gray)
                .frame(width: 44, height: 28)
                .rotationEffect(.degrees(isShowingSettings ? 180 : 0))
                .contentShape(Rectangle())
        }
        .accessibilityLabel(isShowingSettings ? "Hide Settings" : "Show Settings")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Controls Area Component
struct ControlsArea: View {
    let isLoading: Bool
    @Binding var isShowingSettings: Bool
    let onCapturePressed: () -> Void
    let availableHeight: CGFloat
    let bottomSafeArea: CGFloat
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Main controls
            VStack(spacing: 0) {
                Spacer()
                CaptureButtonView(isPressed: false, action: onCapturePressed)
                    .disabled(isLoading)
                Spacer()
            }

            // Chevron pinned to bottom
            CameraChevron(isShowingSettings: $isShowingSettings)
                .padding(.bottom, max(bottomSafeArea, 20))
        }
        .frame(height: availableHeight)
        .frame(maxWidth: .infinity)
        .background(Color.black.ignoresSafeArea(.all))
    }
}



// MARK: - View Setup Extension
extension View {
    func setupCameraView(
        cameraManager: CameraManager,
        appState: AppStateManager,
        errorMessage: Binding<String?>,
        showErrorAlert: Binding<Bool>,
        processOpenedImage: @escaping (URL) async -> Void
    ) -> some View {
        self
            .alert("Error", isPresented: showErrorAlert, presenting: errorMessage.wrappedValue) { _ in
                Button("OK", role: .cancel) { errorMessage.wrappedValue = nil }
            } message: { message in
                Text(message)
            }
            .preferredColorScheme(.dark)
            .statusBarHidden(true)
            .onChange(of: cameraManager.errorMessage) { _, newError in
                if let error = newError {
                    errorMessage.wrappedValue = error
                    showErrorAlert.wrappedValue = true
                }
            }
            .onChange(of: cameraManager.isAuthorized) { _, authorized in
                if authorized {
                    print("CameraView: isAuthorized changed to true, starting session.")
                    cameraManager.startSession()
                } else {
                    if cameraManager.permissionRequested {
                        print("CameraView: isAuthorized changed to false after permission check.")
                        errorMessage.wrappedValue = CameraManager.CameraError.authorizationDenied.localizedDescription
                        showErrorAlert.wrappedValue = true
                    }
                }
            }
            .onAppear {
                // If camera is already authorized when view appears, start session immediately
                if cameraManager.isAuthorized && !cameraManager.session.isRunning {
                    print("CameraView: Camera already authorized on appear, starting session.")
                    cameraManager.startSession()
                }
            }
            .onChange(of: appState.imageToProcess) { _, newURL in
                guard let url = newURL else { return }
                Task {
                    await processOpenedImage(url)
                }
            }
    }
}

// Inserted sound enum and helper function for playing system sounds
enum AppSound: UInt32 {
    case shutter = 1108
    case softClick = 1105
    case positionClick = 1104
}

@inline(__always)
func play(_ sound: AppSound) {
    AudioServicesPlaySystemSound(sound.rawValue)
}

// MARK: - CameraView Photo Capture Extension
extension CameraView {
    private func capturePhoto() {
        play(.shutter)
        
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred(intensity: 0.9)
        
        guard !isLoading else { return }
        
        isLoading = true
        currentQuote = notebookQuotes.randomElement()
        
        // Start performance logging session for the entire photo-to-note pipeline
        let sessionId = PerformanceLogger.shared.startSession()
        
        cameraManager.capturePhoto { result in
            Task {
                await handlePhotoCapture(result: result, sessionId: sessionId)
            }
        }
    }
    
    private func processOpenedImage(url: URL) async {
        print("📎 Processing opened URL: \(url)")
        print("📎 URL scheme: \(url.scheme ?? "none"), isFileURL: \(url.isFileURL)")
        
        // Check if this is just a deep link to open the app (not an actual file)
        if url.scheme == "notebooksaver" || !url.isFileURL {
            print("📎 URL is a deep link to open the app, not a file. Ignoring.")
            appState.clearOpenedImage()
            return
        }
        
        // Request access to security-scoped resource if needed
        // Note: Not all URLs require this (e.g., Photos app URLs), so we don't fail if it returns false
        let needsSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if needsSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        print("📎 Processing image file from URL: \(url.lastPathComponent)")
        print("📎 Security-scoped access: \(needsSecurityScope)")
        
        do {
            // Load image data from URL
            let imageData: Data
            do {
                imageData = try Data(contentsOf: url)
            } catch let error as NSError {
                // Handle specific file read errors
                if error.domain == NSCocoaErrorDomain {
                    switch error.code {
                    case NSFileReadNoPermissionError:
                        await handleError("Permission denied. Cannot read the selected image file.")
                    case NSFileReadNoSuchFileError:
                        await handleError("The selected image file no longer exists.")
                    case NSFileReadCorruptFileError:
                        await handleError("The selected image file is corrupted or unreadable.")
                    default:
                        await handleError("Failed to read image file: \(error.localizedDescription)")
                    }
                } else {
                    await handleError("Failed to read image file: \(error.localizedDescription)")
                }
                appState.clearOpenedImage()
                return
            }
            
            // Validate image data is not empty
            guard !imageData.isEmpty else {
                await handleError("The selected image file is empty.")
                appState.clearOpenedImage()
                return
            }
            
            // Validate it's a valid image format
            guard let validatedImage = UIImage(data: imageData) else {
                await handleError("Invalid image format. Please select a JPEG, PNG, or HEIC image.")
                appState.clearOpenedImage()
                return
            }
            
            // Additional validation: check image has valid dimensions
            guard validatedImage.size.width > 0 && validatedImage.size.height > 0 else {
                await handleError("Invalid image dimensions. The image appears to be corrupted.")
                appState.clearOpenedImage()
                return
            }
            
            print("Successfully loaded image from URL: \(url.lastPathComponent)")
            print("Image size: \(imageData.count) bytes, dimensions: \(validatedImage.size.width)x\(validatedImage.size.height)")
            
            // Show loading overlay with quotes
            await MainActor.run {
                isLoading = true
                currentQuote = notebookQuotes.randomElement()
            }
            
            // Start performance logging
            let sessionId = PerformanceLogger.shared.startSession()
            
            // Reuse existing pipeline
            await handlePhotoCapture(
                result: .success(imageData),
                sessionId: sessionId
            )
            
            // Clear state after successful processing
            appState.clearOpenedImage()
        }
    }
    
    private func handlePhotoCapture(result: Result<Data, CameraManager.CameraError>, sessionId: UUID) async {
        do {
            // Log photo capture completion (conflated with session start)
            let capturedImageData = try await PerformanceLogger.shared.measureOperation(
                "Photo Capture Pipeline",
                sessionId: sessionId
            ) {
                try result.get()
            }
            print("Photo captured successfully, size: \(capturedImageData.count) bytes")

            // 1. Process image once and cache it - eliminates redundant UIImage creations
            let processedImage = try await processImageOnce(from: capturedImageData, sessionId: sessionId)
            print("Image processed and cached, size: \(processedImage.size)")

            // 2. Run parallel processing using cached image - eliminates sequential blocking
            async let photoSaveTask = savePhotoIfNeeded(image: processedImage, sessionId: sessionId)
            async let textExtractionTask = extractTextFromProcessedImage(processedImage, sessionId: sessionId)
            
            // Wait for both operations to complete
            let (photoURL, extractedText) = try await (photoSaveTask, textExtractionTask)
            print("Parallel processing completed - Photo: \(photoURL?.absoluteString ?? "not saved"), Text: \(extractedText.prefix(50))...")

            // 3. Send to target app
            try await sendToTargetApp(text: extractedText, sessionId: sessionId)

            // 4. Complete the performance logging session
            PerformanceLogger.shared.endSession(sessionId)

            // 5. Single state update at the end - eliminates multiple MainActor calls
            await MainActor.run { 
                isLoading = false
                let notif = UINotificationFeedbackGenerator()
                notif.prepare()
                notif.notificationOccurred(.success)
                print("Processing pipeline completed successfully")
            }

        } catch let error as CameraManager.CameraError {
            PerformanceLogger.shared.cancelSession(sessionId)
            await handleError(error.localizedDescription)
        } catch let error as APIError {
            PerformanceLogger.shared.cancelSession(sessionId)
            await handleError("Gemini Error: \(error.localizedDescription)")
        } catch let error as VisionError {
            PerformanceLogger.shared.cancelSession(sessionId)
            await handleError("Vision Error: \(error.localizedDescription)")
        } catch let error as DraftsError {
            PerformanceLogger.shared.cancelSession(sessionId)
            await handleError(error.localizedDescription)
        } catch {
            PerformanceLogger.shared.cancelSession(sessionId)
            await handleError("An unexpected error occurred: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Optimized Image Processing
    
    private func processImageOnce(from data: Data, sessionId: UUID) async throws -> UIImage {
        return try await PerformanceLogger.shared.measureOperation(
            "Image Preprocessing",
            sessionId: sessionId
        ) {
            guard let imageToProcess = UIImage(data: data) else {
                throw CameraManager.CameraError.processingFailed("Could not create UIImage from captured data.")
            }

            // For now, return the original image without any processing
            // This could be enhanced with resizing/optimization if needed for the UI
            return imageToProcess
        }
    }
    
    private func extractTextFromProcessedImage(_ processedImage: UIImage, sessionId: UUID) async throws -> String {
        let defaults = UserDefaults.standard
        let selectedServiceRaw = defaults.string(forKey: "textExtractorService") ?? TextExtractorType.gemini.rawValue
        var selectedService = TextExtractorType(rawValue: selectedServiceRaw) ?? .gemini

        // Check if Gemini is properly configured, fallback to Vision if not
        if selectedService == .gemini {
            let apiKey = KeychainService.loadAPIKey()
            if apiKey?.isEmpty ?? true {
                print("Gemini selected but API key is missing, falling back to Vision")
                selectedService = .vision
            }
        }

        print("Selected Text Extractor: \(selectedService.rawValue)")

        let textExtractor: ImageTextExtractor
        switch selectedService {
        case .gemini:
            textExtractor = GeminiService()
            print("Using Gemini Service with processed image")
        case .vision:
            textExtractor = VisionService()
            print("Using Vision Service with processed image")
        }

        print("Calling \(selectedService.rawValue) Service with cached image...")
        let extractedText = try await textExtractor.extractText(from: processedImage, sessionId: sessionId)
        print("Successfully extracted text: \(extractedText.prefix(100))...")
        return extractedText
    }
    
    private func savePhotoIfNeeded(image: UIImage, sessionId: UUID) async throws -> URL? {
        let savePhotosEnabled = UserDefaults.standard.bool(forKey: "savePhotosEnabled")
        let photoFolder = UserDefaults.standard.string(forKey: "photoFolderName") ?? "notebook"
        let shouldSavePhoto = savePhotosEnabled && !photoFolder.isEmpty
        
        guard shouldSavePhoto else { return nil }
        
        return try await PerformanceLogger.shared.measureOperation(
            "Photo Saving",
            sessionId: sessionId
        ) {
            print("Saving photo to album: \(photoFolder)")
            guard let processedImageData = image.jpegData(compressionQuality: 0.9) else {
                throw CameraManager.CameraError.processingFailed("Could not encode processed image for saving.")
            }
            let localIdentifier = try await cameraManager.savePhotoToAlbum(imageData: processedImageData, albumName: photoFolder)
            let photoURL = cameraManager.generatePhotoURL(for: localIdentifier)
            print("Photo saved with URL: \(photoURL?.absoluteString ?? "none")")
            return photoURL
        }
    }
    
    private func sendToTargetApp(text: String, sessionId: UUID) async throws {
        try await PerformanceLogger.shared.measureVoidOperation(
            "Drafts App Integration",
            sessionId: sessionId
        ) {
            let draftsTag = UserDefaults.standard.string(forKey: "draftsTag") ?? "notebook"
            let addDraftTagEnabled = UserDefaults.standard.bool(forKey: "addDraftTagEnabled")
            print("Using draftsTag: \(draftsTag), addDraftTagEnabled: \(addDraftTagEnabled)")

            let finalText = text
            
            var tagsToSend = [String]()
            if addDraftTagEnabled && !draftsTag.isEmpty {
                tagsToSend.append(draftsTag)
            }

            let uniqueTags = Set(tagsToSend)
            let combinedTags = uniqueTags.joined(separator: ",")

            if isDraftsAppInstalled() {
                print("Drafts app is installed. Sending text to Drafts.")
                try await sendToDraftsApp(text: finalText, tags: combinedTags, sessionId: sessionId)
            } else {
                print("Drafts app is not installed. Presenting share sheet.")
                try await presentShareSheet(text: finalText, sessionId: sessionId)
            }
        }
    }
    
    private func isDraftsAppInstalled() -> Bool {
        guard let draftsURL = URL(string: "drafts://") else { return false }
        return UIApplication.shared.canOpenURL(draftsURL)
    }
    
    private func sendToDraftsApp(text: String, tags: String, sessionId: UUID) async throws {
        _ = try await DraftsHelper.createDraftAsync(with: text, tag: tags, sessionId: sessionId)
    }
    
    private func presentShareSheet(text: String, sessionId: UUID) async throws {
        try await PerformanceLogger.shared.measureVoidOperation(
            "Share Sheet Presentation",
            sessionId: sessionId
        ) {
            await MainActor.run {
                let activityItems: [Any] = [text]

                guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                      let rootViewController = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
                    print("Error: Could not find root view controller to present share sheet.")
                    self.errorMessage = "Could not initiate sharing."
                    self.showErrorAlert = true
                    return
                }

                let activityViewController = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)

                if let popoverController = activityViewController.popoverPresentationController {
                    popoverController.sourceView = rootViewController.view
                    popoverController.sourceRect = CGRect(x: rootViewController.view.bounds.midX,
                                                        y: rootViewController.view.bounds.midY,
                                                        width: 0, height: 0)
                    popoverController.permittedArrowDirections = []
                }

                rootViewController.present(activityViewController, animated: true, completion: nil)
            }
        }
    }
    
    private func handleError(_ message: String) async {
        await MainActor.run {
            self.errorMessage = message
            self.showErrorAlert = true
            self.isLoading = false
            let notif = UINotificationFeedbackGenerator()
            notif.prepare()
            notif.notificationOccurred(.error)
            play(.softClick)
        }
    }

}

// MARK: - Custom Capture Button Component
struct CaptureButtonView: View {
    let isPressed: Bool
    let action: () -> Void
    @State private var buttonPressed = false
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // Outer ring - always solid white
                Circle()
                    .stroke(Color.white, lineWidth: 2.5)
                    .frame(width: 100, height: 100)
                    .opacity(1) // Force full opacity
                
                // Inner circle - changes opacity when pressed
                Circle()
                    .fill(buttonPressed ? Color.white.opacity(0.3) : Color.white)
                    .frame(width: 86, height: 86)
                    .scaleEffect(buttonPressed ? 0.85 : 1.0)
                    .animation(.easeInOut(duration: 0.1), value: buttonPressed)
            }
            .compositingGroup() // Ensure opacity is applied separately to each layer
        }
        .buttonStyle(PlainButtonStyle()) // Prevent button styling from affecting opacity
        .simultaneousGesture(
            DragGesture(minimumDistance: 5)
                .onChanged { _ in
                    if !buttonPressed {
                        buttonPressed = true
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred(intensity: 0.8)
                    }
                }
                .onEnded { _ in
                    buttonPressed = false
                }
        )
    }
}

// MARK: - Preview
#Preview {
    struct PreviewWrapper: View {
        @State var showSettings = false
        @StateObject private var previewCameraManager = CameraManager(setupOnInit: true)
        @StateObject private var previewAppState = AppStateManager()
        
        var body: some View {
            CameraView(isShowingSettings: $showSettings)
                .environmentObject(previewCameraManager)
                .environmentObject(previewAppState)
        }
    }
    return PreviewWrapper()
}

// Intentionally removed unused legacy button styles to keep the codebase lean



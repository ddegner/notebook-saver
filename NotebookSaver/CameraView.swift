import SwiftUI
import AVFoundation // Needed for AVCaptureSession and sound effects
import UIKit // For UIKit components like UIImpactFeedbackGenerator, UIApplication, etc.

struct CameraView: View {
    @EnvironmentObject private var cameraManager: CameraManager
    @Binding var isShowingSettings: Bool
    
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false
    @State private var currentQuote: (quote: String, author: String)?

    private func isDraftsAppInstalled() -> Bool {
        guard let draftsURL = URL(string: "drafts://") else { return false }
        return UIApplication.shared.canOpenURL(draftsURL)
    }

    var body: some View {
        GeometryReader { geometry in
            let safeAreaInsets = geometry.safeAreaInsets
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height
            let cameraHeight = screenWidth * (4.0/3.0)
            let statusBarHeight = max(safeAreaInsets.top, 50)
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
            errorMessage: $errorMessage,
            showErrorAlert: $showErrorAlert
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
            .frame(height: max(safeAreaInsets.top, 50))
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
        Color.black.opacity(0.7)
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

                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white.opacity(0.6)))
                    .scaleEffect(0.8)
            } else {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
            }
        }
        .padding(30)
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
        VStack(spacing: 0) {
            // Top spacer - takes up space above capture button
            Spacer()
            
            // Capture Button - centered in the middle of available space
            CaptureButtonView(isPressed: false, action: onCapturePressed)
                .disabled(isLoading)
            
            // Bottom spacer - takes up space below capture button
            Spacer()
            
            // Settings Toggle at bottom with proper safe area handling
            SettingsToggleButton(isShowingSettings: $isShowingSettings)
                .padding(.bottom, max(bottomSafeArea, 20))
        }
        .frame(height: availableHeight)
        .frame(maxWidth: .infinity)
        .background(Color.black.ignoresSafeArea(.all))
    }
}

// MARK: - Settings Toggle Component
struct SettingsToggleButton: View {
    @Binding var isShowingSettings: Bool
    
    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.3)) {
                isShowingSettings.toggle()
            }
            
            // Faster haptic feedback and sound - reduced delay to match quicker animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                let impactGenerator = UIImpactFeedbackGenerator(style: .light)
                impactGenerator.impactOccurred(intensity: 0.7)
                
                // Play softer click sound when camera reaches its final position
                AudioServicesPlaySystemSound(1104) // Softer click sound
            }
        } label: {
            Image(systemName: "chevron.up")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.gray)
                .frame(width: 44, height: 28)
                .rotationEffect(.degrees(isShowingSettings ? 180 : 0))
        }
    }
}

// MARK: - View Setup Extension
extension View {
    func setupCameraView(
        cameraManager: CameraManager,
        errorMessage: Binding<String?>,
        showErrorAlert: Binding<Bool>
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
    }
}

// MARK: - CameraView Photo Capture Extension
extension CameraView {
    private func capturePhoto() {
        playShutterSound()
        
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred(intensity: 0.9)
        
        guard !isLoading else { return }
        
        isLoading = true
        currentQuote = notebookQuotes.randomElement()
        
        cameraManager.capturePhoto { result in
            Task {
                await handlePhotoCapture(result: result)
            }
        }
    }
    
    private func handlePhotoCapture(result: Result<Data, CameraManager.CameraError>) async {
        do {
            let capturedImageData = try result.get()
            print("Photo captured successfully, size: \(capturedImageData.count) bytes")

            // 1. Process image once and cache it - eliminates redundant UIImage creations
            let processedImage = try await processImageOnce(from: capturedImageData)
            print("Image processed and cached, size: \(processedImage.size)")

            // 2. Run parallel processing using cached image - eliminates sequential blocking
            async let photoSaveTask = savePhotoIfNeeded(image: processedImage)
            async let textExtractionTask = extractTextFromProcessedImage(processedImage)
            
            // Wait for both operations to complete
            let (photoURL, extractedText) = try await (photoSaveTask, textExtractionTask)
            print("Parallel processing completed - Photo: \(photoURL?.absoluteString ?? "not saved"), Text: \(extractedText.prefix(50))...")

            // 3. Send to target app
            try await sendToTargetApp(text: extractedText)

            // 4. Single state update at the end - eliminates multiple MainActor calls
            await MainActor.run { 
                isLoading = false 
                print("Processing pipeline completed successfully")
            }

        } catch let error as CameraManager.CameraError {
            await handleError(error.localizedDescription)
        } catch let error as APIError {
            await handleError("Cloud Error: \(error.localizedDescription)")
        } catch let error as VisionError {
            await handleError("Vision Error: \(error.localizedDescription)")
        } catch let error as DraftsError {
            await handleError(error.localizedDescription)
        } catch {
            await handleError("An unexpected error occurred: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Optimized Image Processing
    
    private func processImageOnce(from data: Data) async throws -> UIImage {
        guard let imageToProcess = UIImage(data: data) else {
            throw CameraManager.CameraError.processingFailed("Could not create UIImage from captured data.")
        }

        // For now, return the original image without any processing
        // This could be enhanced with resizing/optimization if needed for the UI
        return imageToProcess
    }
    
    private func extractTextFromProcessedImage(_ processedImage: UIImage) async throws -> String {
        let defaults = UserDefaults.standard
        let selectedServiceRaw = defaults.string(forKey: "textExtractorService") ?? TextExtractorType.cloud.rawValue
        var selectedService = TextExtractorType(rawValue: selectedServiceRaw) ?? .cloud

        // Check if Cloud is properly configured, fallback to Vision if not
        if selectedService == .cloud {
            let apiKey = KeychainService.loadAPIKey()
            if apiKey?.isEmpty ?? true {
                print("Cloud selected but API key is missing, falling back to Vision")
                selectedService = .vision
            }
        }

        print("Selected Text Extractor: \(selectedService.rawValue)")

        let textExtractor: ImageTextExtractor
        switch selectedService {
        case .cloud:
            textExtractor = GeminiService()
            print("Using Cloud Service with processed image")
        case .vision:
            textExtractor = VisionService()
            print("Using Vision Service with processed image")
        }

        print("Calling \(selectedService.rawValue) Service with cached image...")
        let extractedText = try await textExtractor.extractText(from: processedImage)
        print("Successfully extracted text: \(extractedText.prefix(100))...")
        return extractedText
    }
    
    private func savePhotoIfNeeded(image: UIImage) async throws -> URL? {
        let savePhotosEnabled = UserDefaults.standard.bool(forKey: "savePhotosEnabled")
        let photoFolder = UserDefaults.standard.string(forKey: "photoFolderName") ?? "notebook"
        let shouldSavePhoto = savePhotosEnabled && !photoFolder.isEmpty
        
        guard shouldSavePhoto else { return nil }
        
        do {
            print("Saving photo to album: \(photoFolder)")
            guard let processedImageData = image.jpegData(compressionQuality: 0.9) else {
                throw CameraManager.CameraError.processingFailed("Could not encode processed image for saving.")
            }
            let localIdentifier = try await cameraManager.savePhotoToAlbum(imageData: processedImageData, albumName: photoFolder)
            let photoURL = cameraManager.generatePhotoURL(for: localIdentifier)
            print("Photo saved with URL: \(photoURL?.absoluteString ?? "none")")
            return photoURL
        } catch {
            print("Warning: Failed to save photo: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func sendToTargetApp(text: String) async throws {
        let draftsTag = UserDefaults.standard.string(forKey: "draftsTag") ?? "notebook"
        let addDraftTagEnabled = UserDefaults.standard.bool(forKey: "addDraftTagEnabled")
        print("Using draftsTag: \(draftsTag), addDraftTagEnabled: \(addDraftTagEnabled)")

        // Include photo link in text if available and enabled in settings
        let finalText = text
        
        var tagsToSend = [String]()
        if addDraftTagEnabled && !draftsTag.isEmpty {
            tagsToSend.append(draftsTag)
        }

        let uniqueTags = Set(tagsToSend)
        let combinedTags = uniqueTags.joined(separator: ",")

        if isDraftsAppInstalled() {
            print("Drafts app is installed. Sending text to Drafts.")
            try await sendToDraftsApp(text: finalText, tags: combinedTags)
        } else {
            print("Drafts app is not installed. Presenting share sheet.")
            presentShareSheet(text: finalText)
            print("Share sheet presented (or attempted).")
        }
    }
    
    private func sendToDraftsApp(text: String, tags: String) async throws {
        print("Calling Drafts Helper with text: \(text.prefix(50))... and tags: \(tags)")
        let _ = try await DraftsHelper.createDraftAsync(with: text, tag: tags)
        print("Drafts Helper call succeeded.")
    }
    
    private func handleError(_ message: String) async {
        await MainActor.run {
            self.errorMessage = message
            self.showErrorAlert = true
            self.isLoading = false
            playSoftClickSound()
        }
    }

    @MainActor
    private func presentShareSheet(text: String) {
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

    private func playShutterSound() {
        AudioServicesPlaySystemSound(1108)
    }

    private func playSoftClickSound() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            AudioServicesPlaySystemSound(1105)
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

// Legacy safe area helpers removed in favor of SwiftUI-native geometry safe area insets

// MARK: - Preview
#Preview {
    struct PreviewWrapper: View {
        @State var showSettings = false
        @StateObject private var previewCameraManager = CameraManager(setupOnInit: true)
        
        var body: some View {
            CameraView(isShowingSettings: $showSettings)
                .environmentObject(previewCameraManager)
        }
    }
    return PreviewWrapper()
}

// Intentionally removed unused legacy button styles to keep the codebase lean

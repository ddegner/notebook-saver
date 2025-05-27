import SwiftUI
import AVFoundation // Needed for AVCaptureSession and sound effects
import UIKit // For UIKit components like UIImpactFeedbackGenerator, UIApplication, etc.

struct CameraView: View {
    @StateObject private var cameraManager = CameraManager(setupOnInit: false)
    @Binding var isShowingSettings: Bool
    
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false
    @State private var currentQuote: (quote: String, author: String)?
    
    @Environment(\.safeAreaInsets) private var safeAreaInsets

    var body: some View {
        GeometryReader { geometry in
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
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .path(in: CGRect(x: 0, y: 0, width: geometry.size.width, height: geometry.size.height)))
            .edgesIgnoringSafeArea(.all)
        }
        .setupCameraView(
            cameraManager: cameraManager,
            errorMessage: $errorMessage,
            showErrorAlert: $showErrorAlert
        )
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
            .onAppear {
                cameraManager.checkPermissionsAndSetup()
            }
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
            
            // Delay haptic feedback and sound to match when camera movement feels complete
            // The ContentView animation feels complete around 0.35 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
                impactGenerator.impactOccurred(intensity: 1.0)
                
                // Play deeper clunk sound when camera reaches its final position
                AudioServicesPlaySystemSound(1105)
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
                        errorMessage.wrappedValue = CameraError.authorizationDenied.localizedDescription
                        showErrorAlert.wrappedValue = true
                    }
                }
            }
            .task {
                try? await Task.sleep(nanoseconds: 100_000_000)
                await cameraManager.setupAsync()
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
    
    private func handlePhotoCapture(result: Result<Data, CameraError>) async {
        do {
            let capturedImageData = try result.get()
            print("Photo captured successfully, size: \(capturedImageData.count) bytes")

            let processedImage = try await processImage(from: capturedImageData)
            let photoURL = try await savePhotoIfNeeded(image: processedImage)
            let extractedText = try await extractTextFromImage(capturedImageData)
            try await sendToTargetApp(text: extractedText, photoURL: photoURL)

            await MainActor.run { isLoading = false }

        } catch let error as CameraError {
            await handleError(error.localizedDescription)
        } catch let error as APIError {
            await handleError("Gemini Error: \(error.localizedDescription)")
        } catch let error as VisionError {
            await handleError("Vision Error: \(error.localizedDescription)")
        } catch let error as DraftsError {
            await handleError(error.localizedDescription)
        } catch {
            await handleError("An unexpected error occurred: \(error.localizedDescription)")
        }
    }
    
    private func processImage(from data: Data) async throws -> UIImage {
        guard var imageToProcess = UIImage(data: data) else {
            throw CameraError.processingFailed("Could not create UIImage from captured data.")
        }

        let imageProcessor = ImageProcessor()
        do {
            print("CameraView: Attempting to detect and crop page using Vision framework.")
            imageToProcess = try await imageProcessor.detectAndCropPage(image: imageToProcess)
            print("CameraView: Page detection and cropping completed successfully.")
        } catch let pageError as PreprocessingError {
            print("CameraView: Page detection/cropping failed: \(pageError.localizedDescription). Proceeding with original image for now.")
        } catch {
            print("CameraView: An unexpected error occurred during page detection/cropping: \(error.localizedDescription). Proceeding with original image.")
        }
        
        return imageToProcess
    }
    
    private func savePhotoIfNeeded(image: UIImage) async throws -> URL? {
        let photoFolder = UserDefaults.standard.string(forKey: "photoFolderName") ?? "notebook"
        let shouldSavePhoto = !photoFolder.isEmpty
        
        guard shouldSavePhoto else { return nil }
        
        do {
            print("Saving photo to album...")
            guard let processedImageData = image.jpegData(compressionQuality: 0.9) else {
                throw CameraError.processingFailed("Could not encode processed image for saving.")
            }
            let localIdentifier = try await cameraManager.savePhotoToAlbum(imageData: processedImageData)
            let photoURL = cameraManager.generatePhotoURL(for: localIdentifier)
            print("Photo saved with URL: \(photoURL?.absoluteString ?? "none")")
            return photoURL
        } catch {
            print("Warning: Failed to save photo: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func extractTextFromImage(_ imageData: Data) async throws -> String {
        let defaults = UserDefaults.standard
        let selectedServiceRaw = defaults.string(forKey: "textExtractorService") ?? TextExtractorType.gemini.rawValue
        let selectedService = TextExtractorType(rawValue: selectedServiceRaw) ?? .gemini

        print("Selected Text Extractor: \(selectedService.rawValue)")

        let textExtractor: ImageTextExtractor
        switch selectedService {
        case .gemini:
            textExtractor = GeminiService()
            print("Using Gemini Service")
        case .vision:
            textExtractor = VisionService()
            print("Using Vision Service")
        }

        print("Calling \(selectedService.rawValue) Service...")
        let extractedText = try await textExtractor.extractText(from: imageData)
        print("Successfully extracted text: \(extractedText.prefix(100))...")
        return extractedText
    }
    
    private func sendToTargetApp(text: String, photoURL: URL?) async throws {
        let draftsTag = UserDefaults.standard.string(forKey: "draftsTag") ?? "notebook"
        print("Using draftsTag: \(draftsTag)")

        let targetApp = UserDefaults.standard.string(forKey: "targetApp") ?? "Drafts"
        print("Target app: \(targetApp)")

        let finalText = text
        var tagsToSend = [String]()
        if !draftsTag.isEmpty {
            tagsToSend.append(draftsTag)
        }

        let uniqueTags = Set(tagsToSend)
        let combinedTags = uniqueTags.joined(separator: ",")

        if targetApp == "Drafts" {
            print("Calling Drafts Helper with text: \(finalText.prefix(50))... and tags: \(combinedTags)")
            try await DraftsHelper.createDraft(with: finalText, tag: combinedTags)
            print("Drafts Helper call succeeded.")
        } else if targetApp == "Notes" {
            print("Preparing to share to Notes app...")
            shareToNotesApp(text: text, photoURL: photoURL)
            print("Share sheet presented (or attempted).")
        }
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
    private func shareToNotesApp(text: String, photoURL: URL?) {
        var activityItems: [Any] = [text]
        if let url = photoURL {
            activityItems.append(url)
        }

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

    private func appendDraftsTagIfNeeded(to text: String) -> String {
        let draftsTag = UserDefaults.standard.string(forKey: "draftsTag") ?? "notebook"
        if !draftsTag.isEmpty {
            return text + "\n\n#\(draftsTag)"
        }
        return text
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
            DragGesture(minimumDistance: 0)
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

// MARK: - Error Types and Extensions
enum CameraError: LocalizedError {
    case captureFailed(Error?)
    case authorizationDenied
    case setupFailed
    case invalidInput
    case invalidOutput
    case processingFailed(String)
    case photoLibraryAccessDenied
    case albumCreationFailed(Error)
    case photoSavingFailed(String)

    var errorDescription: String? {
        switch self {
        case .captureFailed(let underlyingError):
            return "Failed to capture photo." + (underlyingError != nil ? " (\(underlyingError!.localizedDescription))" : "")
        case .authorizationDenied:
            return "Camera access was denied. Please enable it in Settings."
        case .setupFailed:
            return "Could not set up the camera session."
        case .invalidInput:
             return "Could not add camera input device."
         case .invalidOutput:
             return "Could not add photo output."
        case .processingFailed(let message):
             return "Failed to process image: \(message)"
        case .photoLibraryAccessDenied:
             return "Photos access denied. Please enable it in Settings to save photos."
        case .albumCreationFailed(let error):
             return "Failed to create album: \(error.localizedDescription)"
        case .photoSavingFailed(let message):
             return "Failed to save photo: \(message)"
        }
    }
}

extension EnvironmentValues {
    var safeAreaInsets: EdgeInsets {
        self[SafeAreaInsetsKey.self]
    }
}

private struct SafeAreaInsetsKey: EnvironmentKey {
    static var defaultValue: EdgeInsets {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return .init()
        }
        guard let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }) else {
            return .init()
        }
        return keyWindow.safeAreaInsets.insets
    }
}

private extension UIEdgeInsets {
    var insets: EdgeInsets {
        EdgeInsets(top: top, leading: left, bottom: bottom, trailing: right)
    }
}

// MARK: - Preview
#Preview {
    struct PreviewWrapper: View {
        @State var showSettings = false
        var body: some View {
            CameraView(isShowingSettings: $showSettings)
        }
    }
    return PreviewWrapper()
}

// MARK: - Button Styles (Legacy - keeping for compatibility)
extension View {
    func pressEffect() -> some View {
        buttonStyle(PhysicalButtonStyle())
    }
    
    func iosCaptureButtonStyle() -> some View {
        buttonStyle(IOSCaptureButtonStyle())
    }
    
    func recessedButtonStyle() -> some View {
        buttonStyle(RecessedButtonStyle())
    }
}

struct PhysicalButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct IOSCaptureButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            Circle()
                .stroke(Color.white, lineWidth: 4)
                .frame(width: 90, height: 90)
            
            Circle()
                .fill(Color.white)
                .frame(width: 78, height: 78)
                .scaleEffect(configuration.isPressed ? 0.85 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
        }
        .onChange(of: configuration.isPressed) { _, newValue in
            if newValue {
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred(intensity: 0.8)
            }
        }
    }
}

struct RecessedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ButtonStyleBody(configuration: configuration)
    }

    private struct ButtonStyleBody: View {
        let configuration: ButtonStyle.Configuration
        @State private var wasPressed = false

        var body: some View {
            configuration.label
                .opacity(configuration.isPressed ? 0.7 : 1.0)
                .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
                .animation(.spring(response: 0.15, dampingFraction: 0.8), value: configuration.isPressed)
                .onChange(of: configuration.isPressed) { _, newValue in
                    if newValue && !wasPressed {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred(intensity: 0.5)
                    }
                    wasPressed = newValue
                }
        }
    }
}

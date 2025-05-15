import SwiftUI
import AVFoundation // Needed for AVCaptureSession and sound effects

struct CameraView: View {
    @StateObject private var cameraManager = CameraManager(setupOnInit: false) // Manages camera logic
    @Binding var isShowingSettings: Bool // To toggle the settings sheet

    // Replace loadingStatusMessage with a simple boolean
    @State private var isLoading: Bool = false // Tracks loading state
    @State private var errorMessage: String? // Holds error messages for display
    @State private var showErrorAlert = false // Controls alert presentation
    @State private var currentQuote: (quote: String, author: String)? // To store the selected quote

    // Screen metrics to calculate proportions
    @Environment(\.safeAreaInsets) private var safeAreaInsets

    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            // Calculate height based on 4:3 aspect ratio (portrait mode becomes 3:4)
            let cameraHeight = screenWidth * (4.0/3.0)

            VStack(spacing: 0) {
                // CAMERA PREVIEW AREA (top portion, directly under notch/dynamic island)
                ZStack {
                    // Camera preview with exact 4:3 aspect ratio
                    CameraPreview(
                        session: cameraManager.session,
                        isSessionReady: cameraManager.isSetupComplete && cameraManager.isAuthorized
                    )
                        .frame(width: screenWidth, height: cameraHeight)
                        .background(Color.black)
                        .overlay(
                                    // Add a subtle black gradient at the bottom of the preview
                                    // to create a smoother transition to the controls area
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.black.opacity(0),
                                    Color.black.opacity(0.3)
                                ]),
                                startPoint: .center,
                                endPoint: .bottom
                            )
                        )
                        .onAppear {
                            // Only trigger the check/setup on appear
                            cameraManager.checkPermissionsAndSetup()
                            // DO NOT start session here
                        }
                        .onDisappear {
                            cameraManager.stopSession()
                        }

                    // Loading overlay (only shows during loading)
                    if isLoading { // Show overlay if loading
                        Color.black.opacity(0.7)
                        VStack(spacing: 20) {
                            if let quote = currentQuote {
                                VStack(spacing: 16) {
                                    // Quote text
                                    Text(quote.quote)
                                        .font(.custom("Baskerville", size: 26))
                                        .italic()
                                        .multilineTextAlignment(.center)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 30)
                                        .frame(maxWidth: .infinity)

                                    // Author attribution
                                    Text("— \(quote.author)")
                                        .font(.custom("Baskerville", size: 20))
                                        .foregroundColor(.white.opacity(0.8))
                                        .padding(.top, 8)
                                }
                                .padding(.vertical, 30)

                                // Less prominent progress indicator
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white.opacity(0.6)))
                                    .scaleEffect(0.8)
                            } else {
                                // Fallback if no quote is available
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(1.5)
                            }
                        }
                        .padding(30)
                    }
                }

                // CONTROLS AREA (directly under camera preview)
                VStack(spacing: 0) {
                    // Control buttons row - directly under the camera preview
                    GeometryReader { geo in
                        ZStack {
                            // Flash button
                            if cameraManager.isFlashAvailable {
                                Button {
                                    cameraManager.cycleFlashMode()
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(
                                                LinearGradient(
                                                    gradient: Gradient(colors: [
                                                        Color.black.opacity(0.8),
                                                        Color.gray.opacity(0.3)
                                                    ]),
                                                    startPoint: .bottomTrailing,
                                                    endPoint: .topLeading
                                                )
                                            )
                                            .frame(width: 50, height: 50)
                                            .shadow(color: .black.opacity(0.5), radius: 1, x: 1, y: 1)
                                            .overlay(
                                                Circle()
                                                    .stroke(
                                                        LinearGradient(
                                                            gradient: Gradient(colors: [
                                                                Color.gray.opacity(0.7),
                                                                Color.black.opacity(0.7)
                                                            ]),
                                                            startPoint: .topLeading,
                                                            endPoint: .bottomTrailing
                                                        ),
                                                        lineWidth: 1
                                                    )
                                            )
                                        Image(systemName: flashIconName(for: cameraManager.flashMode))
                                            .font(.system(size: 20))
                                            .foregroundColor(cameraManager.flashMode == .off ? .gray : .yellow)
                                    }
                                    .recessedButtonStyle()
                                }
                                .position(x: geo.size.width * (1.0/6.0), y: geo.size.height / 2)
                            }
                            // Capture button (center)
                            Button {
                                capturePhoto()
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(Color.black.opacity(0.3))
                                        .frame(width: 151, height: 151)
                                        .blur(radius: 8)
                                        .offset(y: 4)
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                gradient: Gradient(colors: [
                                                    Color.black.opacity(0.8),
                                                    Color.gray.opacity(0.3)
                                                ]),
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 156, height: 156)
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                gradient: Gradient(colors: [
                                                    Color.black.opacity(0.9),
                                                    Color.gray.opacity(0.3)
                                                ]),
                                                startPoint: .bottomTrailing,
                                                endPoint: .topLeading
                                            )
                                        )
                                        .frame(width: 140, height: 140)
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                gradient: Gradient(colors: [
                                                    Color.gray.opacity(0.8),
                                                    Color.gray.opacity(0.5)
                                                ]),
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 130, height: 130)
                                        .overlay(
                                            Circle()
                                                .stroke(
                                                    LinearGradient(
                                                        gradient: Gradient(colors: [
                                                            Color.white.opacity(0.5),
                                                            Color.gray.opacity(0.1)
                                                        ]),
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    ),
                                                    lineWidth: 1
                                                )
                                        )
                                        .overlay(
                                            Circle()
                                                .fill(
                                                    LinearGradient(
                                                        gradient: Gradient(colors: [
                                                            Color.white.opacity(0.3),
                                                            Color.white.opacity(0.0)
                                                        ]),
                                                        startPoint: .topLeading,
                                                        endPoint: .center
                                                    )
                                                )
                                                .frame(width: 130, height: 130)
                                                .blendMode(.screen)
                                                .opacity(0.5)
                                        )
                                        .shadow(color: .black.opacity(0.5),
                                                radius: 3,
                                                x: 0,
                                                y: 2)
                                }
                            }
                            .recessedButtonStyle()
                            .disabled(isLoading)
                            .position(x: geo.size.width * 0.5, y: geo.size.height / 2)
                            // Settings button
                            Button {
                                isShowingSettings = true
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                gradient: Gradient(colors: [
                                                    Color.black.opacity(0.8),
                                                    Color.gray.opacity(0.3)
                                                ]),
                                                startPoint: .bottomTrailing,
                                                endPoint: .topLeading
                                            )
                                        )
                                        .frame(width: 50, height: 50)
                                        .shadow(color: .black.opacity(0.5), radius: 1, x: 1, y: 1)
                                        .overlay(
                                            Circle()
                                                .stroke(
                                                    LinearGradient(
                                                        gradient: Gradient(colors: [
                                                            Color.gray.opacity(0.7),
                                                            Color.black.opacity(0.7)
                                                        ]),
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    ),
                                                    lineWidth: 1
                                                )
                                        )
                                    Image(systemName: "gearshape")
                                        .font(.system(size: 20))
                                        .foregroundColor(.gray.opacity(0.9))
                                }
                            }
                            .recessedButtonStyle()
                            .position(x: geo.size.width * (5.0/6.0), y: geo.size.height / 2)
                        }
                        .frame(width: geo.size.width, height: 180, alignment: .center)
                    }
                    Spacer() // Push controls to top, leaving space for feedback
                }
                .frame(minHeight: 0, maxHeight: .infinity)
                .background(
                    Rectangle()
                        .fill(Color.black)
                        .edgesIgnoringSafeArea(.bottom)
                )
            }
            .edgesIgnoringSafeArea(.all)
        }
        .alert("Error", isPresented: $showErrorAlert, presenting: errorMessage) { _ in
            Button("OK", role: .cancel) { errorMessage = nil }
            // Optionally add a button to open settings if the error is permission related
        } message: { message in
            Text(message)
        }
        .preferredColorScheme(.dark)
        .onChange(of: cameraManager.errorMessage) { _, newError in
            if let error = newError {
                self.errorMessage = error
                self.showErrorAlert = true
                // It's often better to let CameraManager manage clearing its own error
                // cameraManager.errorMessage = nil // Remove this line if CameraManager handles it
            }
        }
        // Updated onChange for isAuthorized
        .onChange(of: cameraManager.isAuthorized) { _, authorized in
            if authorized {
                // Permission granted (or was already granted), start the session
                print("CameraView: isAuthorized changed to true, starting session.")
                cameraManager.startSession()
            } else {
                // Permission denied or revoked after initial check
                // Only show the error if the permission was actually requested/checked
                if cameraManager.permissionRequested {
                    print("CameraView: isAuthorized changed to false after permission check.")
                    self.errorMessage = CameraError.authorizationDenied.localizedDescription
                    self.showErrorAlert = true
                }
            }
        }
        // Initialize camera asynchronously after view appears
        .task {
            // Setup camera after UI is visible, with a slight delay to allow UI to render first
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms delay
            await cameraManager.setupAsync()
        }
    }

    // Helper function to determine flash icon
    private func flashIconName(for mode: AVCaptureDevice.FlashMode) -> String {
        switch mode {
        case .off: return "bolt.slash.fill"
        case .on: return "bolt.fill"
        case .auto: return "bolt.badge.a.fill"
        @unknown default: return "bolt.slash.fill"
        }
    }

    private func capturePhoto() {
        // Play camera shutter sound
        playShutterSound()

        // Use lighter haptic feedback when photo is captured
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred(intensity: 0.9)

        // Prevent double taps
        guard !isLoading else { return } // Check loading state

        // Set initial status message
        isLoading = true // Start loading

        // Select a random quote
        currentQuote = notebookQuotes.randomElement()

        cameraManager.capturePhoto { result in
            Task {
                var capturedImageData: Data?
                var photoURL: URL?

                // Declare the extractor variable conforming to the protocol
                let textExtractor: ImageTextExtractor

                do {
                    capturedImageData = try result.get()
                    print("Photo captured successfully, size: \(capturedImageData!.count) bytes")

                    // --- Select the Text Extraction Service ---
                    let defaults = UserDefaults.standard
                    let selectedServiceRaw = defaults.string(forKey: "textExtractorService") ?? TextExtractorType.gemini.rawValue
                    let selectedService = TextExtractorType(rawValue: selectedServiceRaw) ?? .gemini

                    print("Selected Text Extractor: \(selectedService.rawValue)")

                    switch selectedService {
                    case .gemini:
                        textExtractor = GeminiService()
                        print("Using Gemini Service")
                    case .vision:
                        textExtractor = VisionService()
                        print("Using Vision Service")
                    }
                    // --- End Service Selection ---

                    // --- Image Preprocessing ---
                    guard var imageToProcess = UIImage(data: capturedImageData!) else {
                        throw CameraError.processingFailed("Could not create UIImage from captured data.")
                    }

                    // 1. Detect and crop the page (NEW STEP)
                    // This is a placeholder call. Actual implementation would be in ImageProcessor.
                    let imageProcessor = ImageProcessor() // Assuming ImageProcessor is accessible
                    do {
                        print("CameraView: Attempting to detect and crop page.")
                        imageToProcess = try imageProcessor.detectAndCropPage(image: imageToProcess)
                        print("CameraView: Page detection and cropping step completed (or placeholder executed).")
                    } catch let pageError as PreprocessingError {
                        print("CameraView: Page detection/cropping failed: \(pageError.localizedDescription). Proceeding with original image for now.")
                        // Optionally, you could decide to throw the error and stop processing:
                        // throw pageError
                        // For now, we'll log and continue with the uncropped image.
                    } catch {
                        print("CameraView: An unexpected error occurred during page detection/cropping: \(error.localizedDescription). Proceeding with original image.")
                        // Optionally, throw and stop.
                    }

                    // 2. Resize and encode the image (EXISTING STEPS, now using potentially cropped image)
                    // Note: The current GeminiService and VisionService handle their own resizing and encoding.
                    // If you want to centralize this, you'd pass `imageToProcess` to them,
                    // and they would need to be adapted to accept a UIImage instead of Data,
                    // or you'd re-encode `imageToProcess` here before passing it.

                    // For demonstration, let's assume services take Data. We'd need to re-encode imageToProcess.
                    // This part depends on how GeminiService/VisionService are structured.
                    // If they take UIImage directly, you'd pass `imageToProcess`.
                    // If they expect Data, you might need to re-encode:
                    // guard let processedImageData = imageToProcess.jpegData(compressionQuality: 0.8) else { // Or .pngData()
                    //     throw CameraError.processingFailed("Could not re-encode processed UIImage.")
                    // }
                    // For now, we'll assume the services can handle a UIImage or will continue to use the original capturedImageData
                    // and the above was a conceptual step. The key is that `detectAndCropPage` was called.

                    // The services (Gemini, Vision) currently expect raw `Data` and do their own
                    // UIImage conversion and processing. To use the `imageToProcess` (potentially cropped),
                    // those services would need to be refactored to accept a UIImage, or we'd
                    // re-encode `imageToProcess` back to Data here.
                    //
                    // For this example, we will continue passing original `capturedImageData`
                    // to the services, as refactoring them is outside the scope of this specific request.
                    // The user will need to decide how to integrate the `imageToProcess` (cropped UIImage)
                    // into their `ImageTextExtractor` protocol and implementations.
                    // A simple way would be to add a method to ImageProcessor to convert UIImage back to Data.

                    // Check if photo saving is enabled
                    let shouldSavePhoto = UserDefaults.standard.bool(forKey: "savePhotosToAlbum")

                    // Save photo if enabled (keep status as "Processing photo...")
                    if shouldSavePhoto {
                        do {
                            print("Saving photo to album...")
                            let localIdentifier = try await cameraManager.savePhotoToAlbum(imageData: capturedImageData!)
                            photoURL = cameraManager.generatePhotoURL(for: localIdentifier)
                            print("Photo saved with URL: \(photoURL?.absoluteString ?? "none")")
                        } catch {
                            // Log error but continue with text extraction
                            print("Warning: Failed to save photo: \(error.localizedDescription)")
                            // Only show error if it's a permissions issue
                            if let cameraError = error as? CameraError {
                                if case .photoLibraryAccessDenied = cameraError {
                                    // Don't block extraction, but show alert later maybe? Or just log.
                                    // For now, just print. Error alert is handled below.
                                }
                            }
                        }
                    }

                    // Call the selected service via the protocol
                    print("Calling \(selectedService.rawValue) Service...")
                    // IMPORTANT: The `extractText` method in GeminiService/VisionService currently takes `Data`.
                    // If `imageToProcess` (our potentially cropped UIImage) is to be used,
                    // these services need to be refactored, or `imageToProcess` needs to be converted back to Data.
                    // For now, passing the original `capturedImageData`.
                    let extractedText = try await textExtractor.extractText(from: capturedImageData!)
                    print("Successfully extracted text: \(extractedText.prefix(100))...")

                    // Get the tag from settings before calling Drafts Helper
                    let draftsTag = UserDefaults.standard.string(forKey: "draftsTag") ?? "notebook" // Match key and default from SettingsView
                    print("Using draftsTag: \(draftsTag)")

                    // Get the target app setting
                    let targetApp = UserDefaults.standard.string(forKey: "targetApp") ?? "Drafts"
                    print("Target app: \(targetApp)")

                    // --- Prepare text and tags for the target app ---
                    let finalText = extractedText // Originally defined as var but never modified
                    var tagsToSend = [String]() // Use var as it is appended to
                    if !draftsTag.isEmpty { // Add the default tag if it's set (using the existing draftsTag variable)
                        tagsToSend.append(draftsTag)
                    }

                    // Combine tags into a single comma-separated string for DraftsHelper
                    // Use a Set to ensure uniqueness before joining
                    let uniqueTags = Set(tagsToSend)
                    let combinedTags = uniqueTags.joined(separator: ",")

                    // Call the appropriate helper based on the target app
                    if targetApp == "Drafts" {
                        print("Calling Drafts Helper with text: \(finalText.prefix(50))... and tags: \(combinedTags)")
                        try await DraftsHelper.createDraft(with: finalText, tag: combinedTags)
                        print("Drafts Helper call succeeded.")

                    } else if targetApp == "Notes" {
                        print("Preparing to share to Notes app...")
                        // Pass the original text *with* potential bracket tags for Notes compatibility, photo optional
                        shareToNotesApp(text: extractedText, photoURL: photoURL)
                        print("Share sheet presented (or attempted).")
                    }

                    // Reset state on success
                    await MainActor.run { isLoading = false }

                } catch let error as CameraError {
                    await MainActor.run {
                        self.errorMessage = error.localizedDescription
                        self.showErrorAlert = true
                        self.isLoading = false // Reset state on error
                        playSoftClickSound()
                    }
                } catch let error as APIError {
                     // Handle Gemini-specific errors
                     await MainActor.run {
                         self.errorMessage = "Gemini Error: \(error.localizedDescription)"
                         self.showErrorAlert = true
                         self.isLoading = false // Reset state on error
                         playSoftClickSound()
                     }
                 } catch let error as VisionError {
                     // Handle Vision-specific errors
                     await MainActor.run {
                         self.errorMessage = "Vision Error: \(error.localizedDescription)"
                         self.showErrorAlert = true
                         self.isLoading = false // Reset state on error
                         playSoftClickSound()
                     }
                 } catch let error as DraftsError {
                     await MainActor.run {
                         self.errorMessage = error.localizedDescription
                         self.showErrorAlert = true
                         self.isLoading = false // Reset state on error
                         playSoftClickSound()
                     }
                 } catch {
                     await MainActor.run {
                         self.errorMessage = "An unexpected error occurred: \(error.localizedDescription)"
                         self.showErrorAlert = true
                         self.isLoading = false // Reset state on error
                         playSoftClickSound()
                     }
                 }
            }
        }
    }

    // MARK: - Share Sheet Helper

    @MainActor
    private func shareToNotesApp(text: String, photoURL: URL?) {
        // Updated to include photoURL if available
        var activityItems: [Any] = [text]
        if let url = photoURL {
            activityItems.append(url)
        }

        // Find the current key window scene and its root view controller
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            print("Error: Could not find root view controller to present share sheet.")
            // Optionally show an error to the user here
            self.errorMessage = "Could not initiate sharing."
            self.showErrorAlert = true
            return
        }

        // Create the activity view controller
        let activityViewController = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)

        // Configure for iPad if necessary
        if let popoverController = activityViewController.popoverPresentationController {
            popoverController.sourceView = rootViewController.view
            popoverController.sourceRect = CGRect(x: rootViewController.view.bounds.midX,
                                                y: rootViewController.view.bounds.midY,
                                                width: 0, height: 0)
            popoverController.permittedArrowDirections = [] // No arrow
        }

        // Present the share sheet
        rootViewController.present(activityViewController, animated: true, completion: nil)
    }

    // Play camera shutter sound
    private func playShutterSound() {
        // Use a more subtle, modern sound
        AudioServicesPlaySystemSound(1108) // 1108 is the system sound ID for camera shutter
    }

    // Play soft click sound when operation completes
    private func playSoftClickSound() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            AudioServicesPlaySystemSound(1104) // Subtle click sound
        }
    }

    // Append the drafts tag if needed
    private func appendDraftsTagIfNeeded(to text: String) -> String {
        let draftsTag = UserDefaults.standard.string(forKey: "draftsTag") ?? "notebook"
        if !draftsTag.isEmpty {
            return text + "\n\n#\(draftsTag)"
        }
        return text
    }
}

// Custom Error Enum for Camera related issues
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

// Extension to access safe area insets in SwiftUI views
extension EnvironmentValues {
    var safeAreaInsets: EdgeInsets {
        self[SafeAreaInsetsKey.self]
    }
}

private struct SafeAreaInsetsKey: EnvironmentKey {
    static var defaultValue: EdgeInsets {
        // Get the first connected window scene
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            return .init()
        }
        // Get the key window from the scene
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

// Preview Provider
#Preview {
    struct PreviewWrapper: View {
        @State var showSettings = false
        var body: some View {
            CameraView(isShowingSettings: $showSettings)
        }
    }
    return PreviewWrapper()
}

// Button press effect modifier
extension View {
    func pressEffect() -> some View {
        buttonStyle(PhysicalButtonStyle())
    }
}

struct PhysicalButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// At the end of the file, add a new button style
extension View {
    func recessedButtonStyle() -> some View {
        buttonStyle(RecessedButtonStyle())
    }
}

struct RecessedButtonStyle: ButtonStyle {
    // ButtonStyle doesn't support @State, we'll use a different approach

    func makeBody(configuration: Configuration) -> some View {
        ButtonStyleBody(configuration: configuration)
    }

    // Use a separate view that can hold state
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
                        // Button was just pressed
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred(intensity: 0.5)
                    }
                    wasPressed = newValue
                }
        }
    }
}

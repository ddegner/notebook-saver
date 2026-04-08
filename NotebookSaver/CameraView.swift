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
    @State private var retryableImageData: Data?
    @State private var showRetryOption = false
    @State private var showApiKeyLink = false
    @State private var currentQuote: (quote: String, author: String)?
    @State private var modeLabelText: String = ""
    @State private var showModeLabel: Bool = false



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
                .overlay(alignment: .bottom) {
                    if showModeLabel {
                        ModeLabelView(text: modeLabelText)
                            .padding(.bottom, 12)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: showModeLabel)

                ControlsArea(
                    isLoading: isLoading,
                    isShowingSettings: $isShowingSettings,
                    onCapturePressed: capturePhoto,
                    availableHeight: controlsHeight,
                    bottomSafeArea: bottomSafeArea,
                    onModeChanged: { label in
                        modeLabelText = label
                        showModeLabel = true
                        Task {
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            withAnimation { showModeLabel = false }
                        }
                    }
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
            .persistentSystemOverlays(.visible)
        }
        .setupCameraView(
            cameraManager: cameraManager,
            appState: appState,
            errorMessage: $errorMessage,
            showErrorAlert: $showErrorAlert,
            retryableImageData: $retryableImageData,
            showRetryOption: $showRetryOption,
            processOpenedImage: processOpenedImage
        )
        .dismissKeyboardOnTap()
        .alert("Error", isPresented: $showErrorAlert, presenting: errorMessage) { _ in
            if showApiKeyLink {
                Button("Get API Key") {
                    if let url = URL(string: "https://aistudio.google.com/apikey") {
                        UIApplication.shared.open(url)
                    }
                }
            }
            if showRetryOption && retryableImageData != nil {
                Button("Retry") { retryFailedPhoto() }
                Button("Cancel", role: .cancel) {
                    errorMessage = nil
                    showApiKeyLink = false
                    clearRetryState()
                }
            } else {
                Button("OK", role: .cancel) {
                    errorMessage = nil
                    showRetryOption = false
                    showApiKeyLink = false
                }
            }
        } message: { message in
            Text(message)
        }
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
            CameraPreview(session: cameraManager.session, cameraManager: cameraManager)
            .frame(width: screenWidth, height: cameraHeight)
            .clipped() // Ensure camera preview doesn't overflow
            .background(Color.black)
            .onDisappear {
                cameraManager.stopSession()
            }
            
            if isLoading {
                LoadingOverlay(currentQuote: currentQuote)
                    .transition(.opacity)
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
            Haptic.softImpact()
            isShowingSettings.toggle()
        } label: {
            Image(systemName: "chevron.up")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.gray)
                .frame(width: 44, height: 44)
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
    var onModeChanged: ((String) -> Void)? = nil

    @AppStorage(SettingsKey.scanMode) private var scanModeRaw: String = ScanMode.fast.rawValue
    @AppStorage(SettingsKey.useCustomSettings) private var useCustomSettings: Bool = false
    @AppStorage(SettingsKey.textExtractorService) private var textExtractorService: TextExtractorType = .vision

    private var showScanModePicker: Bool {
        textExtractorService == .gemini && !useCustomSettings
    }

    var body: some View {
        VStack(spacing: 0) {
            // Picker pinned to top of controls area (only for Gemini preset mode)
            if showScanModePicker {
                ScanModePicker(scanModeRaw: $scanModeRaw, onModeChanged: onModeChanged)
                    .padding(.top, 10)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }

            // Capture button centered in remaining space
            Spacer()
            CaptureButtonView(action: onCapturePressed)
                .disabled(isLoading)
            Spacer()

            // Chevron pinned to bottom
            CameraChevron(isShowingSettings: $isShowingSettings)
                .padding(.bottom, max(bottomSafeArea, 20))
        }
        .animation(.easeInOut(duration: 0.25), value: showScanModePicker)
        .frame(height: availableHeight)
        .frame(maxWidth: .infinity)
        .background(Color(white: 0.08).ignoresSafeArea(.all))
    }
}

// MARK: - Mode Label View (Transient Glass Toast)
struct ModeLabelView: View {
    let text: String

    var body: some View {
        if #available(iOS 26.0, *) {
            Text(text)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .glassEffect(.regular.interactive(), in: .capsule)
        } else {
            Text(text)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
        }
    }
}

// MARK: - Scan Mode Picker (Custom Dark Pill)
struct ScanModePicker: View {
    @Binding var scanModeRaw: String
    var onModeChanged: ((String) -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ScanMode.allCases) { mode in
                Button {
                    scanModeRaw = mode.rawValue
                } label: {
                    Image(systemName: mode.iconName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 34, height: 28)
                        .background(
                            Capsule()
                                .fill(scanModeRaw == mode.rawValue ? Color.white.opacity(0.20) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.10))
                .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
        )
        .animation(.easeInOut(duration: 0.2), value: scanModeRaw)
        .onChange(of: scanModeRaw) { _, newValue in
            Haptic.lightImpact()
            if let mode = ScanMode(rawValue: newValue) {
                onModeChanged?(mode.displayName)
            }
        }
    }
}



// MARK: - View Setup Extension
extension View {
    func setupCameraView(
        cameraManager: CameraManager,
        appState: AppStateManager,
        errorMessage: Binding<String?>,
        showErrorAlert: Binding<Bool>,
        retryableImageData: Binding<Data?>,
        showRetryOption: Binding<Bool>,
        processOpenedImage: @escaping (URL) async -> Void
    ) -> some View {
        self
            .preferredColorScheme(.dark)
            .statusBarHidden(false)
            .onChange(of: cameraManager.errorMessage) { _, newError in
                if let error = newError {
                    retryableImageData.wrappedValue = nil
                    showRetryOption.wrappedValue = false
                    errorMessage.wrappedValue = error
                    if !appState.showOnboarding {
                        showErrorAlert.wrappedValue = true
                    }
                }
            }
            .onChange(of: cameraManager.isAuthorized) { _, authorized in
                if authorized {
                    #if DEBUG
                    print("CameraView: isAuthorized changed to true, starting session.")
                    #endif
                    Task {
                        await cameraManager.startSession()
                    }
                } else {
                    if cameraManager.permissionRequested {
                        #if DEBUG
                        print("CameraView: isAuthorized changed to false after permission check.")
                        #endif
                        retryableImageData.wrappedValue = nil
                        showRetryOption.wrappedValue = false
                        errorMessage.wrappedValue = CameraManager.CameraError.authorizationDenied.localizedDescription
                        if !appState.showOnboarding {
                            showErrorAlert.wrappedValue = true
                        }
                    }
                }
            }
            .onAppear {
                // If camera is already authorized when view appears, start session immediately
                if cameraManager.isAuthorized && !cameraManager.session.isRunning {
                    #if DEBUG
                    print("CameraView: Camera already authorized on appear, starting session.")
                    #endif
                    Task {
                        await cameraManager.startSession()
                    }
                }
                // Pre-establish TLS connection to Gemini while user frames their shot
                Task {
                    let _ = await GeminiService.warmUpConnection()
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
    @MainActor
    private func clearRetryState() {
        retryableImageData = nil
        showRetryOption = false
    }

    @MainActor
    private func retryFailedPhoto() {
        guard !isLoading, let retryData = retryableImageData else { return }

        errorMessage = nil
        showErrorAlert = false
        showRetryOption = false
        isLoading = true
        currentQuote = notebookQuotes.randomElement()

        let sessionId = PerformanceLogger.shared.startSession()
        Task {
            await handlePhotoCapture(
                result: .success(retryData),
                sessionId: sessionId,
                captureTimingToken: nil
            )
        }
    }

    private enum OpenedImageValidationError: Error {
        case invalidFormat
        case invalidDimensions
    }
    
    private func readImageData(from url: URL) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let data = try Data(contentsOf: url, options: [.mappedIfSafe])
                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func validateOpenedImageData(_ data: Data) async throws -> CGSize {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let image = UIImage(data: data) else {
                    continuation.resume(throwing: OpenedImageValidationError.invalidFormat)
                    return
                }
                
                guard image.size.width > 0 && image.size.height > 0 else {
                    continuation.resume(throwing: OpenedImageValidationError.invalidDimensions)
                    return
                }
                
                continuation.resume(returning: image.size)
            }
        }
    }
    
    private func decodeImage(_ data: Data) async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let image = UIImage(data: data) else {
                    continuation.resume(throwing: CameraManager.CameraError.processingFailed("Could not create UIImage from captured data."))
                    return
                }
                continuation.resume(returning: image)
            }
        }
    }
    
    private func capturePhoto() {
        guard !isLoading else { return }

        errorMessage = nil
        showErrorAlert = false
        retryableImageData = nil
        showRetryOption = false
        
        play(.shutter)
        
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred(intensity: 0.9)
        
        isLoading = true
        currentQuote = notebookQuotes.randomElement()
        
        // Start performance logging session for the entire photo-to-note pipeline
        let sessionId = PerformanceLogger.shared.startSession()
        let captureTimingToken = PerformanceLogger.shared.startTiming("Photo Capture Pipeline", sessionId: sessionId)
        
        cameraManager.capturePhoto { result in
            Task {
                await handlePhotoCapture(
                    result: result,
                    sessionId: sessionId,
                    captureTimingToken: captureTimingToken
                )
            }
        }
    }
    
    private func processOpenedImage(url: URL) async {
        #if DEBUG
        print("📎 Processing opened URL: \(url)")
        print("📎 URL scheme: \(url.scheme ?? "none"), isFileURL: \(url.isFileURL)")
        #endif

        await MainActor.run {
            errorMessage = nil
            showErrorAlert = false
            clearRetryState()
        }
        
        // Check if this is just a deep link to open the app (not an actual file)
        if url.scheme == "notebooksaver" || !url.isFileURL {
            #if DEBUG
            print("📎 URL is a deep link to open the app, not a file. Ignoring.")
            #endif
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
        
        #if DEBUG
        print("📎 Processing image file from URL: \(url.lastPathComponent)")
        print("📎 Security-scoped access: \(needsSecurityScope)")
        #endif
        
        do {
            // Load image data from URL
            let imageData: Data
            do {
                imageData = try await readImageData(from: url)
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
            
            let imageSize: CGSize
            do {
                imageSize = try await validateOpenedImageData(imageData)
            } catch OpenedImageValidationError.invalidFormat {
                await handleError("Invalid image format. Please select a JPEG, PNG, or HEIC image.")
                appState.clearOpenedImage()
                return
            } catch OpenedImageValidationError.invalidDimensions {
                await handleError("Invalid image dimensions. The image appears to be corrupted.")
                appState.clearOpenedImage()
                return
            } catch {
                await handleError("Failed to validate image file: \(error.localizedDescription)")
                appState.clearOpenedImage()
                return
            }
            
            #if DEBUG
            print("Successfully loaded image from URL: \(url.lastPathComponent)")
            print("Image size: \(imageData.count) bytes, dimensions: \(imageSize.width)x\(imageSize.height)")
            #endif
            
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
                sessionId: sessionId,
                captureTimingToken: nil
            )
            
            // Clear state after successful processing
            appState.clearOpenedImage()
        }
    }
    
    private func handlePhotoCapture(
        result: Result<Data, CameraManager.CameraError>,
        sessionId: UUID,
        captureTimingToken: TimingToken?
    ) async {
        var capturedImageData: Data?

        do {
            let imageData: Data
            switch result {
            case .success(let data):
                imageData = data
                if let captureTimingToken {
                    PerformanceLogger.shared.endTiming(captureTimingToken, success: true)
                }
            case .failure(let error):
                if let captureTimingToken {
                    PerformanceLogger.shared.endTiming(captureTimingToken, error: error)
                }
                throw error
            }
            capturedImageData = imageData
            await MainActor.run {
                retryableImageData = imageData
            }
            #if DEBUG
            print("Photo captured successfully, size: \(imageData.count) bytes")
            #endif

            // 1. Process image once and cache it - eliminates redundant UIImage creations
            let processedImage = try await processImageOnce(from: imageData, sessionId: sessionId)
            #if DEBUG
            print("Image processed and cached, size: \(processedImage.size)")
            #endif

            // 2. Run parallel processing using cached image - eliminates sequential blocking
            async let photoSaveTask = savePhotoIfNeeded(image: processedImage, sessionId: sessionId)
            async let textExtractionTask = extractTextFromProcessedImage(processedImage, sessionId: sessionId)
            
            // Wait for both operations to complete
            let (photoURL, extractedText) = try await (photoSaveTask, textExtractionTask)
            #if DEBUG
            print("Parallel processing completed - Photo: \(photoURL?.absoluteString ?? "not saved"), Text: \(extractedText.prefix(50))...")
            #endif

            // 3. Send to target app
            try await sendToTargetApp(text: extractedText, sessionId: sessionId)

            // 4. Complete the performance logging session
            PerformanceLogger.shared.endSession(sessionId, success: true)

            // 5. Single state update at the end - eliminates multiple MainActor calls
            await MainActor.run { 
                isLoading = false
                clearRetryState()
                let notif = UINotificationFeedbackGenerator()
                notif.prepare()
                notif.notificationOccurred(.success)
                #if DEBUG
                print("Processing pipeline completed successfully")
                #endif
            }

        } catch let error as CameraManager.CameraError {
            PerformanceLogger.shared.endSession(sessionId, success: false)
            await handleError(error.localizedDescription, allowsRetry: capturedImageData != nil)
        } catch APIError.apiKeyExpired {
            PerformanceLogger.shared.endSession(sessionId, success: false)
            await handleError("Gemini Error: \(APIError.apiKeyExpired.localizedDescription)", allowsRetry: false, showApiKeyLink: true)
        } catch let error as APIError {
            PerformanceLogger.shared.endSession(sessionId, success: false)
            await handleError("Gemini Error: \(error.localizedDescription)", allowsRetry: capturedImageData != nil)
        } catch let error as VisionError {
            PerformanceLogger.shared.endSession(sessionId, success: false)
            await handleError("Vision Error: \(error.localizedDescription)", allowsRetry: capturedImageData != nil)
        } catch let error as DraftsError {
            PerformanceLogger.shared.endSession(sessionId, success: false)
            await handleError(error.localizedDescription, allowsRetry: capturedImageData != nil)
        } catch {
            PerformanceLogger.shared.endSession(sessionId, success: false)
            await handleError("An unexpected error occurred: \(error.localizedDescription)", allowsRetry: capturedImageData != nil)
        }
    }
    
    // MARK: - Optimized Image Processing
    
    private func processImageOnce(from data: Data, sessionId: UUID) async throws -> UIImage {
        return try await PerformanceLogger.shared.measureOperation(
            "Image Decode",
            sessionId: sessionId
        ) {
            // Decode on a background queue to avoid UI-thread stalls on large images.
            try await decodeImage(data)
        }
    }
    
    private func extractTextFromProcessedImage(_ processedImage: UIImage, sessionId: UUID) async throws -> String {
        let extractedText = try await TextExtractionPipeline.extractText(from: processedImage, sessionId: sessionId)
        #if DEBUG
        print("Successfully extracted text: \(extractedText.prefix(100))...")
        #endif
        return extractedText
    }
    
    private func savePhotoIfNeeded(image: UIImage, sessionId: UUID) async throws -> URL? {
        let savePhotosEnabled = UserDefaults.standard.bool(forKey: SettingsKey.savePhotosEnabled)
        let photoFolder = UserDefaults.standard.string(forKey: SettingsKey.photoFolderName) ?? "notebook"
        let shouldSavePhoto = savePhotosEnabled && !photoFolder.isEmpty
        
        guard shouldSavePhoto else { return nil }
        
        #if DEBUG
        print("Saving photo to album: \(photoFolder)")
        #endif
        guard let processedImageData = image.jpegData(compressionQuality: 0.9) else {
            throw CameraManager.CameraError.processingFailed("Could not encode processed image for saving.")
        }
        
        let token = PerformanceLogger.shared.startTiming("Photo Saving", sessionId: sessionId)
        let localIdentifier = try await cameraManager.savePhotoToAlbum(imageData: processedImageData, albumName: photoFolder)
        let photoURL = cameraManager.generatePhotoURL(for: localIdentifier)
        if let token = token {
            PerformanceLogger.shared.endTiming(token, success: true)
        }
        #if DEBUG
        print("Photo saved with URL: \(photoURL?.absoluteString ?? "none")")
        #endif
        return photoURL
    }
    
    private func sendToTargetApp(text: String, sessionId: UUID) async throws {
        try await PerformanceLogger.shared.measureVoidOperation(
            "Drafts App Integration",
            sessionId: sessionId
        ) {
            let draftsTag = UserDefaults.standard.string(forKey: SettingsKey.draftsTag) ?? "notebook"
            let addDraftTagEnabled = UserDefaults.standard.bool(forKey: SettingsKey.addDraftTagEnabled)
            #if DEBUG
            print("Using draftsTag: \(draftsTag), addDraftTagEnabled: \(addDraftTagEnabled)")
            #endif

            let finalText = text
            
            var tagsToSend = [String]()
            if addDraftTagEnabled && !draftsTag.isEmpty {
                tagsToSend.append(draftsTag)
            }

            let uniqueTags = Set(tagsToSend)
            let combinedTags = uniqueTags.joined(separator: ",")

            if await isDraftsAppInstalled() {
                #if DEBUG
                print("Drafts app is installed. Sending text to Drafts.")
                #endif
                try await sendToDraftsApp(text: finalText, tags: combinedTags)
            } else {
                #if DEBUG
                print("Drafts app is not installed. Presenting share sheet.")
                #endif
                try await presentShareSheet(text: finalText, sessionId: sessionId)
            }
        }
    }
    
    @MainActor private func isDraftsAppInstalled() -> Bool {
        guard let draftsURL = URL(string: "drafts://") else { return false }
        return UIApplication.shared.canOpenURL(draftsURL)
    }
    
    private func sendToDraftsApp(text: String, tags: String) async throws {
        try await DraftsHelper.createDraftAsync(with: text, tag: tags)
    }

    @MainActor
    private func currentSharePresenter() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else {
            return nil
        }
        guard let keyWindow = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first,
              let rootViewController = keyWindow.rootViewController else {
            return nil
        }

        var presenter = rootViewController
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        return presenter
    }

    @MainActor
    private func stableSharePresenter(maxAttempts: Int = 6) async -> UIViewController? {
        for _ in 0..<maxAttempts {
            guard let presenter = currentSharePresenter() else { return nil }
            if !presenter.isBeingPresented && !presenter.isBeingDismissed {
                return presenter
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return currentSharePresenter()
    }
    
    @MainActor
    private func presentShareSheet(text: String, sessionId: UUID) async throws {
        let activityItems: [Any] = [text]

        let timingToken = PerformanceLogger.shared.startTiming(
            "Share Sheet Presentation",
            sessionId: sessionId
        )

        guard UIApplication.shared.applicationState == .active else {
            if let timingToken {
                PerformanceLogger.shared.endTiming(timingToken, error: DraftsError.handoffFailed)
            }
            throw DraftsError.handoffFailed
        }

        guard let presenter = await stableSharePresenter() else {
            #if DEBUG
            print("Error: Could not find a stable presenter for share sheet.")
            #endif
            if let timingToken {
                PerformanceLogger.shared.endTiming(timingToken, error: DraftsError.handoffFailed)
            }
            throw DraftsError.handoffFailed
        }

        if presenter is UIAlertController {
            #if DEBUG
            print("Share sheet deferred because an alert is currently presented.")
            #endif
            if let timingToken {
                PerformanceLogger.shared.endTiming(timingToken, error: DraftsError.handoffFailed)
            }
            throw DraftsError.handoffFailed
        }

        let activityViewController = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )

        if let popoverController = activityViewController.popoverPresentationController {
            popoverController.sourceView = presenter.view
            popoverController.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.midY,
                width: 0,
                height: 0
            )
            popoverController.permittedArrowDirections = []
        }

        presenter.present(activityViewController, animated: true, completion: nil)

        if let timingToken {
            PerformanceLogger.shared.endTiming(timingToken, success: true)
        }
    }
    
    @MainActor
    private func handleError(_ message: String, allowsRetry: Bool = false, showApiKeyLink: Bool = false) async {
        self.errorMessage = message
        self.showApiKeyLink = showApiKeyLink
        self.showRetryOption = allowsRetry && self.retryableImageData != nil
        self.showErrorAlert = !appState.showOnboarding
        self.isLoading = false
        let notif = UINotificationFeedbackGenerator()
        notif.prepare()
        notif.notificationOccurred(.error)
        play(.softClick)
    }

}

// MARK: - Custom Capture Button Component
struct CaptureButtonView: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // Outer ring
                Circle()
                    .stroke(Color.white.opacity(0.9), lineWidth: 2.5)
                    .frame(width: 100, height: 100)

                // Inner circle
                Circle()
                    .fill(Color.white.opacity(0.95))
                    .frame(width: 86, height: 86)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Capture")
        .accessibilityHint("Takes a photo and extracts text")
    }
}

// MARK: - Preview
#Preview {
    struct PreviewWrapper: View {
        @State var showSettings = false
        @StateObject private var previewCameraManager = CameraManager(setupOnInit: false)
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

import Foundation
@preconcurrency import AVFoundation
import SwiftUI // Needed for UIImage processing
import Photos // For saving to photo library

@MainActor
class CameraManager: NSObject, ObservableObject, @MainActor AVCapturePhotoCaptureDelegate {

    @Published var session = AVCaptureSession()
    @Published var isAuthorized = false
    @Published var errorMessage: String? // Published for CameraView to observe
    @Published var permissionRequested = false // Track if permission has been asked
    @Published var isSetupComplete = false // Track if setup has completed

    // --- Flash Control ---
    @Published var flashMode: AVCaptureDevice.FlashMode = .auto // Default to Auto
    @Published var isFlashAvailable = false
    // ---------------------

    // Removed zoom and multi-camera support for simplicity

    // --- Photo Saving ---
    @Published var lastSavedPhotoLocalIdentifier: String? // For linking to saved photos
    // -------------------

    private var photoOutput = AVCapturePhotoOutput()
    private var videoDeviceInput: AVCaptureDeviceInput?
    private let sessionQueue = DispatchQueue(label: "com.notebooksaver.camera.session", qos: .userInitiated)
    // Define CameraError enum
    enum CameraError: Error {
        case authorizationDenied
        case captureError
        case noDeviceFound
        case setupError
        case invalidInput
        case invalidOutput
        case setupFailed
        case captureFailed(Error?)
        case processingFailed(String)
        case photoLibraryAccessDenied
        case albumCreationFailed(Error)
        case photoSavingFailed(String)
        
        var localizedDescription: String {
            switch self {
            case .authorizationDenied:
                return "Camera access was denied"
            case .captureError:
                return "Failed to capture photo"
            case .noDeviceFound:
                return "No camera device found"
            case .setupError:
                return "Failed to setup camera"
            case .invalidInput:
                return "Invalid camera input device"
            case .invalidOutput:
                return "Invalid camera output"
            case .setupFailed:
                return "Camera setup failed"
            case .captureFailed(let error):
                return "Photo capture failed: \(error?.localizedDescription ?? "Unknown error")"
            case .processingFailed(let message):
                return "Photo processing failed: \(message)"
            case .photoLibraryAccessDenied:
                return "Photo library access denied"
            case .albumCreationFailed(let error):
                return "Failed to create album: \(error.localizedDescription)"
            case .photoSavingFailed(let message):
                return "Failed to save photo: \(message)"
            }
        }
    }

    // Store the completion handler for the capture request
    private var photoCaptureCompletion: ((Result<Data, CameraError>) -> Void)?

    // MARK: - Initialization & Setup
    
    nonisolated init(setupOnInit: Bool = true) {
        super.init()
        if setupOnInit {
            // Start permission check and setup immediately on background queue
            Task { @MainActor [weak self] in
                await self?.checkPermissionsAndSetup()
            }
        }
    }
    
    // MARK: - Setup and Permissions
    
    func checkPermissionsAndSetup() async {
        self.permissionRequested = true
        
        switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                // Permission already granted - setup immediately
                if await setupSession() {
                    self.isAuthorized = true
                    self.isSetupComplete = true
                    // Clear any stale error messages when camera becomes ready
                    self.errorMessage = nil
                    // Auto-start session after state is properly set
                    await self.startSession()
                } else {
                    self.isAuthorized = false
                    self.isSetupComplete = false
                }
            case .notDetermined:
                // Request permission
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                if granted {
                    if await self.setupSession() {
                        self.isAuthorized = true
                        self.isSetupComplete = true
                        // Clear any stale error messages when camera becomes ready
                        self.errorMessage = nil
                        // Auto-start session after state is properly set
                        await self.startSession()
                    } else {
                        self.isAuthorized = false
                        self.isSetupComplete = false
                    }
                } else {
                    self.isAuthorized = false
                    self.errorMessage = CameraError.authorizationDenied.localizedDescription
                    print("Camera permission denied.")
                }
            case .denied, .restricted:
                // Permission denied or restricted
                self.isAuthorized = false
                self.errorMessage = CameraError.authorizationDenied.localizedDescription
                print("Camera permission was denied or restricted previously.")
            @unknown default:
                // Handle future cases
                self.isAuthorized = false
                self.errorMessage = "Unknown camera authorization status."
                print("Unknown camera authorization status.")
        }
    }

    private func setupSession() async -> Bool {
        let captureSession = session
        let captureOutput = photoOutput
        
        let setupResult: (error: CameraError?, input: AVCaptureDeviceInput?, hasFlash: Bool) = await withCheckedContinuation {
            (continuation: CheckedContinuation<(error: CameraError?, input: AVCaptureDeviceInput?, hasFlash: Bool), Never>) in
            sessionQueue.async {
                guard !captureSession.isRunning else {
                    print("Session is already running.")
                    continuation.resume(returning: (nil, nil, false))
                    return
                }
                
                captureSession.beginConfiguration()
                defer { captureSession.commitConfiguration() }
                
                captureSession.inputs.forEach { captureSession.removeInput($0) }
                captureSession.outputs.forEach { captureSession.removeOutput($0) }
                
                // Set session preset to .photo for high resolution capture
                captureSession.sessionPreset = .photo
                print("CameraManager: Using .photo preset for high resolution capture")

                // Try to get a virtual device that supports automatic camera switching (including macro)
                // This allows the system to automatically switch to ultra-wide for macro when close to subject
                let device: AVCaptureDevice
                if let dualWideCamera = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) {
                    device = dualWideCamera
                    print("CameraManager: Using dual wide camera (supports automatic macro switching)")
                } else if let tripleCamera = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back) {
                    device = tripleCamera
                    print("CameraManager: Using triple camera (supports automatic macro switching)")
                } else if let dualCamera = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) {
                    device = dualCamera
                    print("CameraManager: Using dual camera")
                } else if let wideCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
                    device = wideCamera
                    print("CameraManager: Using wide-angle camera (no automatic macro)")
                } else {
                    print("Error: No back camera device found.")
                    continuation.resume(returning: (.noDeviceFound, nil, false))
                    return
                }
                
                guard let input = try? AVCaptureDeviceInput(device: device) else {
                    print("Error: Could not create camera input.")
                    continuation.resume(returning: (.invalidInput, nil, false))
                    return
                }
                
                guard captureSession.canAddInput(input) else {
                    print("Error: Cannot add camera input to session.")
                    continuation.resume(returning: (.invalidInput, nil, false))
                    return
                }
                captureSession.addInput(input)

                // Simplified focus and exposure configuration for faster startup
                do {
                    try device.lockForConfiguration()

                    // Set focus mode - prefer continuous autofocus for responsiveness
                    if device.isFocusModeSupported(.continuousAutoFocus) {
                        device.focusMode = .continuousAutoFocus
                        print("CameraManager: Set focusMode to .continuousAutoFocus")
                    } else if device.isFocusModeSupported(.autoFocus) {
                        device.focusMode = .autoFocus
                        print("CameraManager: Set focusMode to .autoFocus")
                    }
                    
                    // Set focus range restriction to near for close-up document scanning
                    if device.isAutoFocusRangeRestrictionSupported {
                        device.autoFocusRangeRestriction = .near
                        print("CameraManager: Set autoFocusRangeRestriction to .near for close focus")
                    }
                    
                    // Enable automatic macro mode switching on supported devices (iOS 15.4+)
                    // This allows the system to automatically switch to ultra-wide camera for macro
                    if #available(iOS 15.4, *) {
                        if device.isAutoFocusRangeRestrictionSupported {
                            // When using virtual devices (dual/triple camera), the system can automatically
                            // switch to the ultra-wide camera for macro photography when close to subject
                            device.automaticallyAdjustsVideoHDREnabled = true
                            print("CameraManager: Enabled automatic video HDR (enables macro switching)")
                        }
                        
                        // Check if device supports automatic macro switching
                        // Note: This property exists on virtual devices that can switch to ultra-wide for macro
                        let deviceType = device.deviceType
                        if deviceType == .builtInDualWideCamera || deviceType == .builtInTripleCamera {
                            print("CameraManager: Device supports automatic macro mode switching")
                        }
                    }

                    // Optimize exposure for document scanning
                    if device.isExposureModeSupported(.continuousAutoExposure) {
                        device.exposureMode = .continuousAutoExposure
                        
                        // Set exposure point to center
                        if device.isExposurePointOfInterestSupported {
                            device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
                        }

                        // Slightly increase exposure for better text readability
                        let desiredBias: Float = 0.3
                        if device.minExposureTargetBias <= desiredBias && desiredBias <= device.maxExposureTargetBias {
                            device.setExposureTargetBias(desiredBias, completionHandler: nil)
                            print("CameraManager: Set exposure target bias to \(desiredBias)")
                        }
                    }

                    // Enable low light boost if available
                    if device.isLowLightBoostSupported {
                        device.automaticallyEnablesLowLightBoostWhenAvailable = true
                        print("CameraManager: Enabled automatic low-light boost")
                    }

                    // Set zoom to 2.0x on virtual devices to get 1x equivalent field of view
                    // Virtual devices (dual-wide, triple) default to 0.5x (ultra-wide), so 2.0x gives us 1x
                    let deviceType = device.deviceType
                    if deviceType == .builtInDualWideCamera || deviceType == .builtInTripleCamera || deviceType == .builtInDualCamera {
                        let targetZoom: CGFloat = 2.0
                        if targetZoom >= device.minAvailableVideoZoomFactor && targetZoom <= device.maxAvailableVideoZoomFactor {
                            device.videoZoomFactor = targetZoom
                            print("CameraManager: Set zoom to \(targetZoom)x for 1x equivalent field of view")
                        }
                    }

                    device.unlockForConfiguration()
                } catch {
                    print("CameraManager: Error configuring focus/exposure: \(error.localizedDescription)")
                }

                // Output setup - streamlined
                guard captureSession.canAddOutput(captureOutput) else {
                    print("Error: Cannot add photo output to session.")
                    continuation.resume(returning: (.invalidOutput, nil, false))
                    return
                }
                captureOutput.maxPhotoQualityPrioritization = .quality
                captureSession.addOutput(captureOutput)
                
                continuation.resume(returning: (nil, input, device.hasFlash))
            }
        }
        
        if let error = setupResult.error {
            self.errorMessage = error.localizedDescription
            return false
        }
        
        // Already configured and running.
        if setupResult.input == nil {
            return true
        }
        
        self.videoDeviceInput = setupResult.input
        self.isFlashAvailable = setupResult.hasFlash
        if !setupResult.hasFlash {
            self.flashMode = .off
        }
        
        print("Camera session setup complete.")
        return true
    }
    


    // MARK: - Session Control

    func startSession() async {
        await startSessionWithRetry()
    }
    
    private func startSessionWithRetry(attempts: Int = 3) async {
        guard isAuthorized else {
            print("Cannot start session: Not authorized.")
            if self.errorMessage == nil {
                self.errorMessage = CameraError.authorizationDenied.localizedDescription
            }
            return
        }
        
        guard !session.isRunning else { 
            print("Session is already running.")
            return 
        }

        // Start the session off the main actor; startRunning() is blocking.
        let captureSession = session
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                captureSession.startRunning()
                continuation.resume()
            }
        }
        
        if self.session.isRunning {
            print("Camera session started successfully.")
            self.isSetupComplete = true
        } else {
            print("Camera session failed to start, attempt \(4 - attempts) of 3")
            
            if attempts > 1 {
                // Retry with exponential backoff
                let delay = Double(4 - attempts) * 0.5 // 0.5s, 1.0s, 1.5s
                print("Retrying camera session start in \(delay) seconds...")
                
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                await self.startSessionWithRetry(attempts: attempts - 1)
            } else {
                // Max attempts reached
                print("Camera session failed to start after 3 attempts")
                self.errorMessage = "Failed to start camera after multiple attempts. Please restart the app."
            }
        }
    }

    func stopSession() {
        let captureSession = self.session
        let queue = self.sessionQueue
        queue.async {
            guard captureSession.isRunning else { return }
            captureSession.stopRunning()
            print("Camera session stopped.")
        }
    }

    // MARK: - Photo Capture

    /// Capture a photo with current settings. Runs on the main actor to safely access properties.
    @MainActor
    func capturePhoto(completion: @escaping (Result<Data, CameraError>) -> Void) {
        guard session.isRunning else {
            print("Cannot capture photo: Session not running.")
            completion(.failure(.setupFailed)) // Or a more specific error
            return
        }

        guard let _ = photoOutput.connection(with: .video) else {
            print("Cannot capture photo: No video connection for photo output.")
            completion(.failure(.invalidOutput))
            return
        }

        // Orientation is typically handled automatically for photo output by embedding metadata.
        // Setting connection.videoOrientation is deprecated (iOS 17+) and often unnecessary for photos.

        // Determine the desired codec type
        var codecType = AVVideoCodecType.jpeg // Default to JPEG
        if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            codecType = .hevc
            print("Using HEVC codec.")
        } else {
            print("Using JPEG codec.")
        }

        // Initialize settings with the chosen codec
        let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: codecType])

        // Set photo quality prioritization to ensure high quality captures
        settings.photoQualityPrioritization = .quality
        print("Set photo quality prioritization to .quality for capture.")

        // Apply Flash Setting from our published property
        if isFlashAvailable && photoOutput.supportedFlashModes.contains(flashMode) {
            settings.flashMode = flashMode
            print("Setting flash mode for capture: \(flashMode)")
        } else if isFlashAvailable {
            print("Warning: Selected flash mode (\(flashMode)) not supported by current output. Using default.")
            // Optionally set to a known supported mode like .off or .auto if needed
            // settings.flashMode = .off
        }

        // Store the completion handler on main actor
        photoCaptureCompletion = completion

        // Perform capture
        photoOutput.capturePhoto(with: settings, delegate: self)
        print("Photo capture initiated.")
    }

    // MARK: - AVCapturePhotoCaptureDelegate

    @MainActor
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        // Retrieve the completion handler on main actor
        guard let completion = photoCaptureCompletion else {
            print("Error: Photo capture completion handler is nil.")
            return
        }
        // Clear the stored handler immediately
        photoCaptureCompletion = nil

        if let error = error {
            print("Error capturing photo: \(error.localizedDescription)")
            completion(.failure(.captureFailed(error)))
            return
        }

        guard let imageData = photo.fileDataRepresentation() else {
            print("Error: Could not get image data from captured photo.")
            completion(.failure(.captureFailed(nil)))
            return
        }

        print("Photo captured successfully. Data size: \(imageData.count) bytes")
        completion(.success(imageData))
    }

     // Optional delegate method for when capture begins/ends, etc.
     // func photoOutput(_ output: AVCapturePhotoOutput, willBeginCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings)
     // func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?)

    // MARK: - Photo Saving Functions

    // Save a photo to the specified album and return the local identifier
    func savePhotoToAlbum(imageData: Data, albumName: String) async throws -> String {
        // Convert data to UIImage
        guard let _ = UIImage(data: imageData) else {
            throw CameraError.processingFailed("Failed to create image from captured data")
        }

        // Check photo library permission
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            // Request permission
            let granted = await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                    continuation.resume(returning: status == .authorized)
                }
            }

            if !granted {
                throw CameraError.photoLibraryAccessDenied
            }
        } else if status != .authorized {
            throw CameraError.photoLibraryAccessDenied
        }

        // Create or get album
        var album: PHAssetCollection?

        // Find album
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "title = %@", albumName)
        let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)

        if collections.count > 0 {
            // Album exists
            album = collections.firstObject
        } else {
            // Create album
            do {
                var albumPlaceholder: PHObjectPlaceholder?

                try await PHPhotoLibrary.shared().performChanges {
                    let createRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumName)
                    albumPlaceholder = createRequest.placeholderForCreatedAssetCollection
                }

                if let placeholder = albumPlaceholder {
                    let fetchResult = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [placeholder.localIdentifier], options: nil)
                    album = fetchResult.firstObject
                }
            } catch {
                throw CameraError.albumCreationFailed(error)
            }
        }

        // Save image
        var localIdentifier = ""
        var assetPlaceholder: PHObjectPlaceholder? // Declare placeholder outside

        do {
            try await PHPhotoLibrary.shared().performChanges {
                let creationRequest = PHAssetCreationRequest.forAsset()
                creationRequest.addResource(with: .photo, data: imageData, options: nil)

                // Get the placeholder *after* adding the resource
                assetPlaceholder = creationRequest.placeholderForCreatedAsset

                // Add to album using placeholder if album exists
                if let album = album, let placeholder = assetPlaceholder {
                    guard let albumChangeRequest = PHAssetCollectionChangeRequest(for: album) else {
                        // This might happen if the album was deleted between fetch and change request
                        print("Warning: Could not get change request for album '\(albumName)'. Photo saved to library but not added to album.")
                        return
                    }
                    albumChangeRequest.addAssets([placeholder] as NSArray)
                }
            }

            // Fetch the saved asset using the placeholder's identifier (more reliable)
            if let placeholderIdentifier = assetPlaceholder?.localIdentifier {
                let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [placeholderIdentifier], options: nil)
                if let savedAsset = fetchResult.firstObject {
                    let finalLocalIdentifier = savedAsset.localIdentifier // Capture the value
                    print("Successfully fetched saved asset with localID: \(finalLocalIdentifier)")
                    // Update the published property
                    self.lastSavedPhotoLocalIdentifier = finalLocalIdentifier // Use captured value
                    localIdentifier = finalLocalIdentifier // Update the variable to be returned
                } else {
                    // This case should be rare if performChanges succeeded
                    print("Error: Could not fetch saved asset using placeholder identifier.")
                    throw CameraError.photoSavingFailed("Could not retrieve saved photo reference after saving.")
                }
            } else {
                // This case is also rare if performChanges succeeded without error
                print("Error: Could not get placeholder identifier after saving.")
                throw CameraError.photoSavingFailed("Could not get identifier for saved photo.")
            }
        } catch let error as CameraError {
            // Re-throw known camera errors
            print("Caught CameraError during photo saving: \(error.localizedDescription)")
            throw error
        } catch {
            // Wrap unknown errors
            print("Caught unknown error during photo saving: \(error.localizedDescription)")
            throw CameraError.photoSavingFailed("An unexpected error occurred while saving: \(error.localizedDescription)")
        }

        return localIdentifier
    }

    // Generate a Photos app URL for a given local identifier
    nonisolated func generatePhotoURL(for localIdentifier: String) -> URL? {
        // The URL format follows Apple's Photos app URL scheme
        // Format: photos-redirect://<localIdentifier>
        let urlString = "photos-redirect://\(localIdentifier)"
        return URL(string: urlString)
    }

}

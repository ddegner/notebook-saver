import Foundation
import AVFoundation
import SwiftUI // Needed for UIImage processing
import Photos // For saving to photo library

class CameraManager: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {

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
    private var sessionQueue = DispatchQueue(label: "com.example.notebooksaver.sessionQueue")
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

    // Reference to the active video device (needed for flash check)
    private var videoDevice: AVCaptureDevice? { videoDeviceInput?.device }

    // MARK: - Initialization & Setup
    
    init(setupOnInit: Bool = true) {
        super.init()
        if setupOnInit {
            // Start permission check and setup immediately on background queue
            sessionQueue.async { [weak self] in
                self?.checkPermissionsAndSetup()
            }
        }
    }
    
    // MARK: - Setup and Permissions

    func checkPermissionsAndSetup() {
        DispatchQueue.main.async { [weak self] in
            self?.permissionRequested = true
        }
        
        switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                // Permission already granted - setup immediately
                setupSession()
                DispatchQueue.main.async { [weak self] in
                    self?.isAuthorized = true
                    self?.isSetupComplete = true
                    // Clear any stale error messages when camera becomes ready
                    self?.errorMessage = nil
                    // Auto-start session after state is properly set
                    self?.startSession()
                }
            case .notDetermined:
                // Request permission
                AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                    if granted {
                        self?.sessionQueue.async {
                            self?.setupSession()
                            DispatchQueue.main.async {
                                self?.isAuthorized = true
                                self?.isSetupComplete = true
                                // Clear any stale error messages when camera becomes ready
                                self?.errorMessage = nil
                                // Auto-start session after state is properly set
                                self?.startSession()
                            }
                        }
                    } else {
                        DispatchQueue.main.async {
                            self?.isAuthorized = false
                            self?.errorMessage = CameraError.authorizationDenied.localizedDescription
                        }
                        print("Camera permission denied.")
                    }
                }
            case .denied, .restricted:
                // Permission denied or restricted
                DispatchQueue.main.async { [weak self] in
                    self?.isAuthorized = false
                    self?.errorMessage = CameraError.authorizationDenied.localizedDescription
                }
                print("Camera permission was denied or restricted previously.")
            @unknown default:
                // Handle future cases
                DispatchQueue.main.async { [weak self] in
                    self?.isAuthorized = false
                    self?.errorMessage = "Unknown camera authorization status."
                }
                print("Unknown camera authorization status.")
        }
    }

    private func setupSession() {
         guard !session.isRunning else {
             print("Session is already running.")
             return
         }

        session.beginConfiguration()

        // Set session preset to .photo for high resolution capture
        session.sessionPreset = .photo
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
            DispatchQueue.main.async {
                self.errorMessage = CameraError.noDeviceFound.localizedDescription
            }
            session.commitConfiguration()
            return
        }
        
        guard let input = try? AVCaptureDeviceInput(device: device) else {
            print("Error: Could not create camera input.")
            DispatchQueue.main.async {
                self.errorMessage = CameraError.invalidInput.localizedDescription
            }
            session.commitConfiguration()
            return
        }
        
        guard session.canAddInput(input) else {
            print("Error: Cannot add camera input to session.")
            DispatchQueue.main.async {
                self.errorMessage = CameraError.invalidInput.localizedDescription
            }
            session.commitConfiguration()
            return
        }
        
        self.videoDeviceInput = input
        session.addInput(input)

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

            device.unlockForConfiguration()
        } catch {
            print("CameraManager: Error configuring focus/exposure: \(error.localizedDescription)")
        }

        // Configure device settings and check flash availability
        let hasFlash = device.hasFlash
        
        DispatchQueue.main.async {
            self.isFlashAvailable = hasFlash
            if !hasFlash { self.flashMode = .off }
        }
        
        // Set zoom to 2.0x on virtual devices to get 1x equivalent field of view
        // Virtual devices (dual-wide, triple) default to 0.5x (ultra-wide), so 2.0x gives us 1x
        let deviceType = device.deviceType
        if deviceType == .builtInDualWideCamera || deviceType == .builtInTripleCamera || deviceType == .builtInDualCamera {
            do {
                try device.lockForConfiguration()
                // 2.0x on the virtual device = 1x field of view (standard wide camera)
                let targetZoom: CGFloat = 2.0
                if targetZoom >= device.minAvailableVideoZoomFactor && targetZoom <= device.maxAvailableVideoZoomFactor {
                    device.videoZoomFactor = targetZoom
                    print("CameraManager: Set zoom to \(targetZoom)x for 1x equivalent field of view")
                }
                device.unlockForConfiguration()
            } catch {
                print("CameraManager: Error setting zoom: \(error.localizedDescription)")
            }
        }

        // Output setup - streamlined
        guard session.canAddOutput(photoOutput) else {
            print("Error: Cannot add photo output to session.")
            DispatchQueue.main.async {
                self.errorMessage = CameraError.invalidOutput.localizedDescription
            }
            session.commitConfiguration()
            return
        }
        
        photoOutput.maxPhotoQualityPrioritization = .quality
        session.addOutput(photoOutput)

        session.commitConfiguration()
        print("Camera session setup complete.")
    }
    


    // MARK: - Session Control

    func startSession() {
        // If called from main thread, dispatch to session queue
        if Thread.isMainThread {
            sessionQueue.async { [weak self] in
                self?.startSessionWithRetry()
            }
        } else {
            startSessionWithRetry()
        }
    }
    
    private func startSessionWithRetry(attempts: Int = 3) {
        guard isAuthorized else {
            print("Cannot start session: Not authorized.")
            DispatchQueue.main.async { [weak self] in
                if self?.errorMessage == nil {
                    self?.errorMessage = CameraError.authorizationDenied.localizedDescription
                }
            }
            return
        }
        
        guard !session.isRunning else { 
            print("Session is already running.")
            return 
        }

        // Start the session - setup should already be complete
        session.startRunning()
        
        // Verify session actually started
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            
            if self.session.isRunning {
                print("Camera session started successfully.")
                self.isSetupComplete = true
            } else {
                print("Camera session failed to start, attempt \(4 - attempts) of 3")
                
                if attempts > 1 {
                    // Retry with exponential backoff
                    let delay = Double(4 - attempts) * 0.5 // 0.5s, 1.0s, 1.5s
                    print("Retrying camera session start in \(delay) seconds...")
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        self.startSessionWithRetry(attempts: attempts - 1)
                    }
                } else {
                    // Max attempts reached
                    print("Camera session failed to start after 3 attempts")
                    DispatchQueue.main.async {
                        self.errorMessage = "Failed to start camera after multiple attempts. Please restart the app."
                    }
                }
            }
        }
    }

    func stopSession() {
        sessionQueue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
            print("Camera session stopped.")
        }
    }

    // MARK: - Photo Capture

    func capturePhoto(completion: @escaping (Result<Data, CameraError>) -> Void) {
         sessionQueue.async {
             guard self.session.isRunning else {
                 print("Cannot capture photo: Session not running.")
                 completion(.failure(.setupFailed)) // Or a more specific error
                 return
             }

             guard let _ = self.photoOutput.connection(with: .video) else {
                 print("Cannot capture photo: No video connection for photo output.")
                 completion(.failure(.invalidOutput))
                 return
             }

            // Orientation is typically handled automatically for photo output by embedding metadata.
            // Setting connection.videoOrientation is deprecated (iOS 17+) and often unnecessary for photos.

             // Determine the desired codec type
             var codecType = AVVideoCodecType.jpeg // Default to JPEG
             if self.photoOutput.availablePhotoCodecTypes.contains(.hevc) {
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
              if self.isFlashAvailable && self.photoOutput.supportedFlashModes.contains(self.flashMode) {
                 settings.flashMode = self.flashMode
                 print("Setting flash mode for capture: \(self.flashMode)")
             } else if self.isFlashAvailable {
                 print("Warning: Selected flash mode (\(self.flashMode)) not supported by current output. Using default.")
                 // Optionally set to a known supported mode like .off or .auto if needed
                 // settings.flashMode = .off
             }

             // Store the completion handler
             self.photoCaptureCompletion = completion

             // Perform capture
             self.photoOutput.capturePhoto(with: settings, delegate: self)
             print("Photo capture initiated.")
         }
     }

    // MARK: - AVCapturePhotoCaptureDelegate

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        // Retrieve the completion handler
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
                    // Update the published property on the main thread
                    await MainActor.run {
                        self.lastSavedPhotoLocalIdentifier = finalLocalIdentifier // Use captured value
                    }
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
    func generatePhotoURL(for localIdentifier: String) -> URL? {
        // The URL format follows Apple's Photos app URL scheme
        // Format: photos-redirect://<localIdentifier>
        let urlString = "photos-redirect://\(localIdentifier)"
        return URL(string: urlString)
    }

    /// Proactively request camera and photo library permissions. Calls completion with (cameraGranted, photoGranted).
    static func requestAllPermissions(completion: @escaping (_ cameraGranted: Bool, _ photoGranted: Bool) -> Void) {
        // Camera permission
        AVCaptureDevice.requestAccess(for: .video) { cameraGranted in
            // Photo library permission (addOnly is sufficient for saving)
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { photoStatus in
                let photoGranted = (photoStatus == .authorized)
                DispatchQueue.main.async {
                    completion(cameraGranted, photoGranted)
                }
            }
        }
    }
    
}

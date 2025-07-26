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
            checkPermissionsAndSetup()
        }
    }
    
    // MARK: - Setup and Permissions

    func checkPermissionsAndSetup() {
        permissionRequested = true // Mark that we are about to check/request
        switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                // Permission already granted
                // Run the configuration first, then publish state changes.
                sessionQueue.async { [weak self] in
                    self?.setupSession()
                    DispatchQueue.main.async { [weak self] in
                        // Mark as authorized and fully set up only after configuration completes.
                        self?.isAuthorized = true
                        self?.isSetupComplete = true
                    }
                }
            case .notDetermined:
                // Request permission
                 sessionQueue.async { // Perform blocking request off the main thread
                     AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                         DispatchQueue.main.async {
                                     if granted {
                                         self?.sessionQueue.async {
                                              self?.setupSession()
                                              DispatchQueue.main.async {
                                                  self?.isAuthorized = true
                                                  self?.isSetupComplete = true
                                              }
                                          }
                                     } else {
                                         self?.isAuthorized = false
                                         print("Camera permission denied.")
                                         self?.errorMessage = CameraError.authorizationDenied.localizedDescription
                                     }
                         }
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

        // Set session preset to .photo for high resolution capture (up to 2048px)
        session.sessionPreset = .photo
        print("CameraManager: Using .photo preset for high resolution capture")

        // Input Device (Back Camera)
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
             print("Error setting up camera input.")
             DispatchQueue.main.async {
                 self.errorMessage = CameraError.invalidInput.localizedDescription
             }
             session.commitConfiguration()
             return
        }
        self.videoDeviceInput = input
        session.addInput(input)

        // Pre-focus at approximately 1 foot (30.48 cm) since most notebook pages are captured at this distance
        if device.isFocusModeSupported(.autoFocus) { // General check if any autofocus mode is supported
            do {
                try device.lockForConfiguration()

                // Set focus range restriction to near for document scanning
                if device.isAutoFocusRangeRestrictionSupported {
                    device.autoFocusRangeRestriction = .near
                    print("CameraManager: Set autoFocusRangeRestriction to .near")
                } else {
                    print("CameraManager: autoFocusRangeRestriction.near is not supported.")
                }

                // Optimize exposure for document scanning
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    // Use continuous auto exposure for dynamic lighting
                    device.exposureMode = .continuousAutoExposure

                    // Slightly increase exposure compensation for better text readability
                    if device.isExposurePointOfInterestSupported {
                        device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5) // Center of frame
                    }

                    let desiredBias: Float = 0.3
                    if device.minExposureTargetBias <= desiredBias && desiredBias <= device.maxExposureTargetBias {
                        device.setExposureTargetBias(desiredBias, completionHandler: nil)
                        print("CameraManager: Set exposure target bias to \(desiredBias) for better text contrast")
                    } else {
                        print("CameraManager: Desired exposure bias \(desiredBias) is out of range [\(device.minExposureTargetBias), \(device.maxExposureTargetBias)]")
                    }
                }


                // Set initial focus to approximately 1 foot (0.3048 meters)
                if device.isLockingFocusWithCustomLensPositionSupported {
                    // Try to set an initial lens position
                    // The completion handler for setFocusModeLocked is important.
                    // It ensures that the lens position change is complete before we try to switch to continuous autofocus.
                    device.setFocusModeLocked(lensPosition: 0.35) { [weak self] _ in
                        guard let self = self else { return }
                        print("CameraManager: Initial lens position set to 0.35.")

                        // Now, try to switch to continuous autofocus.
                        // This should be done on the sessionQueue.
                        self.sessionQueue.async {
                            do {
                                try device.lockForConfiguration()
                                if device.isFocusModeSupported(.continuousAutoFocus) {
                                    device.focusMode = .continuousAutoFocus
                                    print("CameraManager: Switched to .continuousAutoFocus")

                                    if device.isLowLightBoostSupported {
                                        device.automaticallyEnablesLowLightBoostWhenAvailable = true
                                        print("CameraManager: Enabled automatic low-light boost.")
                                    }
                                } else {
                                    print("CameraManager: .continuousAutoFocus is not supported after setting lens position.")
                                    // Fallback: If continuous autofocus is not supported, try .autoFocus.
                                    if device.isFocusModeSupported(.autoFocus) {
                                        device.focusMode = .autoFocus
                                        print("CameraManager: Fallback to .autoFocus as .continuousAutoFocus is not supported here.")
                                    }
                                }
                                device.unlockForConfiguration()
                            } catch {
                                print("CameraManager: Error switching to continuous autofocus: \(error.localizedDescription)")
                            }
                        }
                    }
                    print("CameraManager: Attempted to set initial lens position (async completion).")

                } else {
                    print("CameraManager: Locking focus with custom lens position is not supported.")
                    // If we can't set a custom lens position, try to go directly to continuous autofocus.
                    // This part of the configuration is still protected by the outer lockForConfiguration.
                    if device.isFocusModeSupported(.continuousAutoFocus) {
                        device.focusMode = .continuousAutoFocus
                        print("CameraManager: Set focusMode to .continuousAutoFocus (custom lens position not supported).")
                        if device.isLowLightBoostSupported {
                            device.automaticallyEnablesLowLightBoostWhenAvailable = true
                            print("CameraManager: Enabled automatic low-light boost.")
                        }
                    } else {
                        print("CameraManager: .continuousAutoFocus is not supported (and custom lens position not supported).")
                        // As a last resort, if .autoFocus is supported, use that.
                        if device.isFocusModeSupported(.autoFocus) {
                            device.focusMode = .autoFocus
                            print("CameraManager: Set focusMode to .autoFocus as a fallback.")
                        } else {
                            print("CameraManager: No suitable autofocus mode supported.")
                        }
                    }
                }
                device.unlockForConfiguration() // Corresponds to the lock at the start of this 'do' block for focus and exposure.
            } catch {
                print("CameraManager: Error configuring focus/exposure: \(error.localizedDescription)")
            }
        } else {
            print("CameraManager: .autoFocus mode is not supported on this device at all.")
        }

        // Check for Flash availability *after* setting up the input device
        // Update the published property on the main thread
        let hasFlash = device.hasFlash
        print("[CameraManager] Device has flash: \(hasFlash)") // Log check result
        DispatchQueue.main.async {
            self.isFlashAvailable = hasFlash
            // Set initial flash mode based on availability
            if !hasFlash { self.flashMode = .off }
            print("[CameraManager] Updated isFlashAvailable on main thread: \(self.isFlashAvailable)") // Log state update
        }

        // Output
        guard session.canAddOutput(photoOutput) else {
            print("Error setting up photo output.")
            DispatchQueue.main.async {
                 self.errorMessage = CameraError.invalidOutput.localizedDescription
             }
            session.commitConfiguration()
            return
        }
        photoOutput.maxPhotoQualityPrioritization = .quality // Prioritize quality

        // Note: isAutoStillImageStabilizationEnabled and isHighResolutionCaptureEnabled
        // were removed as they are either deprecated or set on AVCapturePhotoSettings.
        // High resolution is typically handled by the sessionPreset = .photo and
        // photoQualityPrioritization on the settings object during capture.
        // Stabilization is also set on AVCapturePhotoSettings.

        session.addOutput(photoOutput)

        session.commitConfiguration()
        print("Camera session setup complete.")
    }

    // MARK: - Session Control

    func startSession() {
        sessionQueue.async {
            guard self.isAuthorized else {
                 print("Cannot start session: Not authorized.")
                 // Ensure error message is set if called inappropriately
                 DispatchQueue.main.async {
                     if self.errorMessage == nil {
                         self.errorMessage = CameraError.authorizationDenied.localizedDescription
                     }
                 }
                 return
             }
            guard !self.session.isRunning else { return }

            // Check if setup is needed (e.g., if it failed previously or wasn't run)
             if self.session.inputs.isEmpty || self.session.outputs.isEmpty {
                 print("Session inputs/outputs are empty, running setup.")
                 self.setupSession()
                 // If setup fails again, it will set the error message.
                 // Re-check authorization status after potential setup failure
                 guard self.isAuthorized && !self.session.inputs.isEmpty && !self.session.outputs.isEmpty else {
                      print("Setup failed, cannot start session.")
                      return
                  }
             }

            self.session.startRunning()
            print("Camera session started.")
            // Mark setup as complete on main thread
            DispatchQueue.main.async {
                self.isSetupComplete = true
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

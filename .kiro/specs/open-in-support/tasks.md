# Implementation Plan

- [x] 1. Configure document type support in Info.plist
  - Add CFBundleDocumentTypes array with image type declarations
  - Include public.image, public.jpeg, public.png, and public.heic UTIs
  - Set LSHandlerRank to "Alternate" and CFBundleTypeRole to "Viewer"
  - _Requirements: 1.1, 1.2, 4.1, 4.2, 4.3, 4.4, 4.5_

- [x] 2. Extend AppStateManager for opened image handling
  - Add @Published var imageToProcess: URL? property
  - Add @Published var isProcessingOpenedImage: Bool property
  - Implement processOpenedImage(url: URL) method
  - Implement clearOpenedImage() method
  - _Requirements: 1.3, 1.5, 5.1_

- [x] 3. Add URL handling to NotebookSaverApp
  - Add .onOpenURL() modifier to WindowGroup
  - Call appState.processOpenedImage(url:) when URL is received
  - Add logging to track when images are opened with the app
  - _Requirements: 1.2, 1.3_

- [x] 4. Implement image processing in CameraView
  - Add .onChange(of: appState.imageToProcess) observer
  - Implement processOpenedImage(url: URL) async method
  - Add security-scoped resource access with startAccessingSecurityScopedResource()
  - Load image data from URL using Data(contentsOf:)
  - Validate image data by creating UIImage
  - Set isLoading and currentQuote to show quotes overlay
  - Call existing handlePhotoCapture() with loaded image data
  - Add proper cleanup with stopAccessingSecurityScopedResource() in defer block
  - Call appState.clearOpenedImage() after processing completes
  - _Requirements: 1.3, 1.4, 1.5, 2.1, 2.2, 2.3, 3.1, 3.2, 3.3, 3.5, 5.2, 5.3_

- [x] 5. Add error handling for opened images
  - Handle file access errors (security-scoped resource failure)
  - Handle invalid image format errors
  - Handle file read errors
  - Display user-friendly error messages using existing handleError() method
  - Ensure app returns to camera view after errors
  - _Requirements: 1.4, 2.4, 2.5, 3.4, 5.4, 5.5_

- [x] 6. Remove unnecessary share extension files
  - Delete NotebookSaverShareExtension folder and its contents
  - Remove share extension target from Xcode project if configured
  - Clean up any build artifacts in build/ShareExtension-Info.plist
  - _Requirements: N/A (cleanup task)_

- [x] 7. Manual testing and validation
  - Test opening JPEG images from Files app
  - Test opening PNG images from Photos app
  - Test opening HEIC images from other apps
  - Verify quotes overlay displays during processing
  - Verify draft creation works correctly
  - Test error scenarios (invalid files, missing API key)
  - Verify app appears in "Open With" menu for images
  - Test cold start (app not running), warm start (background), and hot start (active)
  - _Requirements: All requirements_

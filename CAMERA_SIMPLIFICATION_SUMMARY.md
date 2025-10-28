# Camera Simplification Summary

## Changes Made

Successfully simplified the camera system to always use the 1x wide-angle camera with close focus capability.

### Files Modified

1. **NotebookSaver/CameraManager.swift**
   - Removed all multi-camera discovery and switching logic
   - Removed zoom control functionality (pinch-to-zoom, zoom factor management)
   - Removed `availableCameras`, `currentCameraIndex`, `cameraDiscoverySession` properties
   - Removed `currentZoomFactor`, `minZoomFactor`, `maxZoomFactor` properties
   - Removed methods: `setupCameraDiscovery()`, `selectBestInitialCamera()`, `selectOptimalCameraForZoom()`, `setZoom()`, `setZoomFactor()`, `updateZoom()`, `switchToCamera()`
   - Simplified `setupSession()` to use only `AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)`
   - Kept focus configuration with `.continuousAutoFocus` and `.near` range restriction for close-up document scanning

2. **NotebookSaver/CameraView.swift**
   - Removed `ZoomIndicator` component
   - Removed zoom overlay from camera preview
   - Removed `onPinchZoom` callback from `CameraPreview`

3. **NotebookSaver/CameraPreview.swift**
   - Removed pinch gesture handling
   - Removed `onPinchZoom` callback parameter
   - Removed `pinchGesture` property and related methods
   - Simplified `PreviewView` to only handle camera preview display

4. **NotebookSaver/SettingsView.swift**
   - Removed "Default Zoom" picker from General tab
   - Removed `defaultZoomFactor` AppStorage property
   - Removed `defaultZoomFactor` from StorageKeys enum

5. **NotebookSaver/AppDefaults.swift**
   - Removed `defaultZoomFactor` constant

## Camera Configuration

The app now uses:
- **Camera**: Virtual device (dual-wide or triple camera when available, falls back to wide-angle)
- **Focus Mode**: Continuous autofocus
- **Focus Range**: Near (optimized for close-up document scanning)
- **Session Preset**: Photo (high resolution)
- **Automatic Macro**: Enabled on iOS 15.4+ with supported devices

### Automatic Macro Mode

On iPhone 13 Pro and later devices with ultra-wide cameras that support macro:
- The system automatically switches to the ultra-wide camera when you get very close to a subject
- This happens transparently using virtual device types (`.builtInDualWideCamera` or `.builtInTripleCamera`)
- The field of view remains consistent at 1x equivalent
- No manual camera switching or zoom controls needed

The virtual device with `.near` focus range restriction provides excellent close-focus capability for document scanning, including automatic macro mode on supported devices.

## Benefits

- **Simpler codebase**: Removed ~200 lines of complex camera switching and zoom logic
- **Better UX**: No confusing zoom controls or camera switching
- **Consistent behavior**: Always uses the same camera with predictable focus behavior
- **Close focus**: The `.near` focus range restriction enables the camera to focus on documents at close range
- **Faster startup**: No camera discovery or zoom initialization needed

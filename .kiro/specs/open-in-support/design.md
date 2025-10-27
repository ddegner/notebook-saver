# Design Document

## Overview

This design implements document type support for NotebookSaver, allowing users to open image files directly with the app from Files, Photos, or other applications. The implementation leverages the existing image processing pipeline (ImagePreprocessor, GeminiService/VisionService, DraftsHelper) and adds URL handling to receive and process opened images.

The design follows iOS best practices for document-based apps by:
- Declaring supported document types in Info.plist using UTIs (Uniform Type Identifiers)
- Implementing URL handling in the app lifecycle to receive opened files
- Reusing the existing image processing pipeline for consistency
- Displaying the same quotes overlay UI for a unified user experience

## Architecture

### High-Level Flow

```
User selects "Open With NotebookSaver" on an image
    ↓
iOS launches app and passes file URL via .onOpenURL modifier
    ↓
App validates file is an image and loads data
    ↓
Existing image processing pipeline handles the image:
    - ImagePreprocessor prepares the image
    - GeminiService/VisionService extracts text
    - DraftsHelper creates note
    ↓
Quotes overlay displays during processing
    ↓
App returns to camera view when complete
```

### Component Interaction

```
┌─────────────────────────────────────────────────────────────┐
│                      NotebookSaverApp                        │
│  - Adds .onOpenURL() modifier to WindowGroup                │
│  - Receives URL from iOS when image is opened                │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ↓
┌─────────────────────────────────────────────────────────────┐
│                    AppStateManager                           │
│  - New: @Published var imageToProcess: URL?                 │
│  - New: func processOpenedImage(url: URL)                   │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ↓
┌─────────────────────────────────────────────────────────────┐
│                      CameraView                              │
│  - Observes imageToProcess state                            │
│  - Triggers processing when URL is set                      │
│  - Reuses existing handlePhotoCapture() logic               │
│  - Shows quotes overlay during processing                   │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ↓
┌─────────────────────────────────────────────────────────────┐
│              Existing Processing Pipeline                    │
│  - processImageOnce()                                        │
│  - extractTextFromProcessedImage()                          │
│  - sendToTargetApp()                                        │
│  - PerformanceLogger for metrics                            │
└─────────────────────────────────────────────────────────────┘
```

## Components and Interfaces

### 1. Info.plist Configuration

**Purpose**: Declare supported document types so iOS knows NotebookSaver can open images

**Implementation**:
```xml
<key>CFBundleDocumentTypes</key>
<array>
    <dict>
        <key>CFBundleTypeName</key>
        <string>Image</string>
        <key>LSHandlerRank</key>
        <string>Alternate</string>
        <key>LSItemContentTypes</key>
        <array>
            <string>public.image</string>
            <string>public.jpeg</string>
            <string>public.png</string>
            <string>public.heic</string>
        </array>
        <key>CFBundleTypeRole</key>
        <string>Viewer</string>
    </dict>
</array>
```

**Key Decisions**:
- `LSHandlerRank: Alternate` - App appears as an option but not the default
- `CFBundleTypeRole: Viewer` - Indicates read-only access (we don't modify the original)
- Support common formats: JPEG, PNG, HEIC, and generic public.image

### 2. AppStateManager Extensions

**Purpose**: Manage state for opened images and coordinate processing

**New Properties**:
```swift
@Published var imageToProcess: URL?
@Published var isProcessingOpenedImage: Bool = false
```

**New Methods**:
```swift
func processOpenedImage(url: URL) {
    imageToProcess = url
    isProcessingOpenedImage = true
}

func clearOpenedImage() {
    imageToProcess = nil
    isProcessingOpenedImage = false
}
```

**Rationale**: 
- Using `@Published` properties allows CameraView to reactively observe when an image needs processing
- Separate flag for processing state helps distinguish between camera captures and opened images

### 3. NotebookSaverApp URL Handling

**Purpose**: Receive URLs from iOS when images are opened with the app

**Implementation**:
```swift
WindowGroup {
    ContentView()
        .environmentObject(appState)
        .environmentObject(cameraManager)
        .onOpenURL { url in
            print("Received URL: \(url)")
            appState.processOpenedImage(url: url)
        }
        // ... existing modifiers
}
```

**Rationale**:
- `.onOpenURL()` is the SwiftUI-native way to handle document opening
- Delegates to AppStateManager to maintain separation of concerns
- Works whether app is already running or needs to launch

### 4. CameraView Processing Integration

**Purpose**: Detect opened images and process them through the existing pipeline

**New State Observation**:
```swift
.onChange(of: appState.imageToProcess) { _, newURL in
    guard let url = newURL else { return }
    Task {
        await processOpenedImage(url: url)
    }
}
```

**New Processing Method**:
```swift
private func processOpenedImage(url: URL) async {
    guard url.startAccessingSecurityScopedResource() else {
        await handleError("Cannot access the selected image file")
        appState.clearOpenedImage()
        return
    }
    defer { url.stopAccessingSecurityScopedResource() }
    
    do {
        // Load image data from URL
        let imageData = try Data(contentsOf: url)
        
        // Validate it's an image
        guard UIImage(data: imageData) != nil else {
            throw CameraManager.CameraError.processingFailed("Invalid image file")
        }
        
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
        
        // Clear state
        appState.clearOpenedImage()
        
    } catch {
        await handleError("Failed to process image: \(error.localizedDescription)")
        appState.clearOpenedImage()
    }
}
```

**Key Design Decisions**:
- **Security-scoped resources**: Required for accessing files outside app sandbox
- **Reuse existing pipeline**: Call `handlePhotoCapture()` with image data to maintain consistency
- **Same UI experience**: Set `isLoading` and `currentQuote` to show quotes overlay
- **Performance logging**: Track opened image processing same as camera captures
- **Error handling**: Use existing error handling infrastructure

### 5. Image Validation

**Purpose**: Ensure opened files are valid images before processing

**Implementation**:
```swift
private func validateImageFile(url: URL) -> Bool {
    // Check file extension
    let validExtensions = ["jpg", "jpeg", "png", "heic", "heif"]
    let fileExtension = url.pathExtension.lowercased()
    guard validExtensions.contains(fileExtension) else {
        return false
    }
    
    // Verify UTI matches image types
    if let uti = try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier {
        return uti.hasPrefix("public.image")
    }
    
    return false
}
```

**Rationale**:
- Double validation (extension + UTI) prevents processing non-image files
- Graceful failure with clear error messages
- Prevents crashes from malformed data

## Data Models

No new data models are required. The design reuses existing structures:

- **Image data**: `Data` type (same as camera captures)
- **Processing state**: Managed by existing `@State` variables in CameraView
- **Performance metrics**: Logged via existing `PerformanceLogger`
- **Error handling**: Uses existing error types (`CameraManager.CameraError`, `APIError`, etc.)

## Error Handling

### Error Scenarios and Responses

| Error Scenario | Detection | User Message | Recovery |
|---------------|-----------|--------------|----------|
| File access denied | `startAccessingSecurityScopedResource()` returns false | "Cannot access the selected image file" | Return to camera view |
| Invalid file format | `UIImage(data:)` returns nil | "Invalid image file" | Return to camera view |
| File read failure | `Data(contentsOf:)` throws | "Failed to read image file" | Return to camera view |
| Processing failure | Existing pipeline errors | Existing error messages | Return to camera view |
| Missing API key | Existing validation | "Please configure API key in Settings" | Return to camera view |

### Error Handling Flow

```swift
do {
    // Attempt processing
} catch let error as CameraManager.CameraError {
    await handleError(error.localizedDescription)
} catch let error as APIError {
    await handleError("Gemini Error: \(error.localizedDescription)")
} catch let error as VisionError {
    await handleError("Vision Error: \(error.localizedDescription)")
} catch {
    await handleError("Failed to process image: \(error.localizedDescription)")
}
```

**Rationale**: Reuse existing error handling infrastructure for consistency

## Testing Strategy

### Manual Testing Checklist

1. **Document Type Registration**
   - Verify NotebookSaver appears in "Open With" menu for JPEG images
   - Verify NotebookSaver appears in "Open With" menu for PNG images
   - Verify NotebookSaver appears in "Open With" menu for HEIC images
   - Verify app does NOT appear for non-image files (PDF, TXT, etc.)

2. **App Launch Scenarios**
   - Test opening image when app is not running (cold start)
   - Test opening image when app is in background (warm start)
   - Test opening image when app is already active (hot start)

3. **Processing Pipeline**
   - Verify quotes overlay appears when processing opened image
   - Verify text extraction works with Gemini service
   - Verify text extraction works with Vision service
   - Verify draft is created in Drafts app
   - Verify performance logging captures metrics

4. **Error Handling**
   - Test with corrupted image file
   - Test with renamed non-image file (e.g., .txt renamed to .jpg)
   - Test with missing API key configuration
   - Test when Drafts app is not installed

5. **User Experience**
   - Verify app returns to camera view after successful processing
   - Verify app returns to camera view after error
   - Verify error messages are clear and actionable
   - Verify no crashes or hangs during processing

### Integration Testing

Since the design reuses existing components, integration testing focuses on:

1. **URL handling integration**: Verify `.onOpenURL()` correctly passes URLs to AppStateManager
2. **State management integration**: Verify AppStateManager correctly triggers CameraView processing
3. **Pipeline integration**: Verify opened images flow through same pipeline as camera captures
4. **Performance logging integration**: Verify metrics are captured for opened images

### Edge Cases

1. **Multiple rapid opens**: User opens multiple images in quick succession
   - Expected: Queue processing or ignore subsequent opens while processing
   - Implementation: Check `isLoading` flag before starting new processing

2. **Large image files**: User opens very large image (e.g., 50MB RAW file)
   - Expected: Existing ImagePreprocessor handles resizing
   - Fallback: Timeout or memory error handled by existing error handling

3. **Network unavailable**: User opens image while offline (Gemini service)
   - Expected: Existing network error handling displays appropriate message
   - Fallback: User can retry or switch to Vision service

4. **App in background**: iOS suspends app while processing opened image
   - Expected: Processing continues when app returns to foreground
   - Implementation: Existing async/await handles suspension gracefully

## Security Considerations

1. **File Access Permissions**
   - Use `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()` for proper sandbox access
   - Always call in defer block to ensure cleanup

2. **Data Validation**
   - Validate file is actually an image before processing
   - Check file size limits to prevent memory issues
   - Sanitize file paths in error messages

3. **Privacy**
   - No image data is stored permanently (same as camera captures)
   - Performance logs don't include image content
   - API calls follow existing privacy practices

## Performance Considerations

1. **File Loading**
   - Loading image data from URL is synchronous but fast for typical image sizes
   - Existing ImagePreprocessor handles resizing for large images
   - Performance logging tracks total time including file loading

2. **Memory Management**
   - Security-scoped resource access is properly released in defer block
   - Image data is processed through existing pipeline (no additional memory overhead)
   - UIImage creation validates data before full processing

3. **User Experience**
   - Quotes overlay appears immediately to provide feedback
   - Processing happens asynchronously (no UI blocking)
   - App remains responsive during processing

## Implementation Notes

### Phase 1: Info.plist Configuration
- Add CFBundleDocumentTypes declaration
- Test that app appears in "Open With" menu

### Phase 2: URL Handling Infrastructure
- Add properties to AppStateManager
- Implement .onOpenURL() in NotebookSaverApp
- Test URL reception and state updates

### Phase 3: Processing Integration
- Add onChange observer in CameraView
- Implement processOpenedImage() method
- Integrate with existing pipeline

### Phase 4: Testing and Refinement
- Manual testing of all scenarios
- Error handling verification
- Performance validation

### Dependencies
- No new external dependencies required
- Reuses all existing services and utilities
- Compatible with current iOS deployment target

### Backward Compatibility
- Changes are purely additive (no breaking changes)
- Existing camera capture flow unchanged
- Existing settings and configuration unchanged

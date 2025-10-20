# Design Document

## Overview

The performance logging system will add comprehensive timing and model tracking to the NotebookSaver app's photo-to-note processing pipeline. The system will be designed as a lightweight, non-intrusive logging layer that captures detailed performance metrics without impacting the user experience. The logged data will be accessible through the existing About page in the Settings view, providing users with copyable performance insights for analysis.

## Architecture

### Core Components

1. **PerformanceLogger**: A singleton service responsible for recording timing data and model information
2. **LogEntry**: A data structure representing individual performance measurements
3. **LogSession**: A container for related log entries representing one complete photo-to-note operation
4. **PerformanceLogView**: A new SwiftUI view integrated into the About page for displaying and copying logs
5. **LogFormatter**: A utility for converting log data into human-readable, copyable text format

### Integration Points

The performance logging system will integrate with the existing processing pipeline at these key points:

- **CameraView.capturePhoto()**: Start of photo capture timing
- **CameraView.handlePhotoCapture()**: Overall pipeline timing and coordination
- **CameraView.processImageOnce()**: Image preprocessing timing
- **GeminiService.extractText()**: AI processing timing and model tracking
- **VisionService.extractText()**: Local OCR timing and model tracking
- **CameraView.sendToTargetApp()**: Note creation and delivery timing

## Components and Interfaces

### PerformanceLogger

```swift
class PerformanceLogger: ObservableObject {
    static let shared = PerformanceLogger()
    
    // MARK: - Public Interface
    func startSession() -> UUID
    func logOperation(_ operation: String, duration: TimeInterval, sessionId: UUID, modelInfo: ModelInfo? = nil)
    func endSession(_ sessionId: UUID)
    func getRecentSessions(limit: Int = 50) -> [LogSession]
    func getFormattedLogs() -> String
    func clearOldLogs()
    
    // MARK: - Convenience Methods
    func measureOperation<T>(_ operation: String, sessionId: UUID, modelInfo: ModelInfo? = nil, block: () async throws -> T) async throws -> T
}
```

### Data Models

```swift
struct LogEntry: Codable, Identifiable {
    let id: UUID
    let operation: String
    let startTime: Date
    let duration: TimeInterval
    let modelInfo: ModelInfo?
    let deviceContext: DeviceContext
}

struct LogSession: Codable, Identifiable {
    let id: UUID
    let startTime: Date
    let endTime: Date?
    let entries: [LogEntry]
    let totalDuration: TimeInterval?
    let deviceContext: DeviceContext
}

struct ModelInfo: Codable {
    let serviceName: String // "Gemini" or "Vision"
    let modelName: String // e.g., "gemini-2.5-flash" or "Apple Vision"
    let configuration: [String: String]? // Additional model settings
}

struct DeviceContext: Codable {
    let deviceModel: String
    let osVersion: String
    let appVersion: String
    let timestamp: Date
}
```

### PerformanceLogView

```swift
struct PerformanceLogView: View {
    @StateObject private var logger = PerformanceLogger.shared
    @State private var showingFullLogs = false
    @State private var copySuccess = false
    
    var body: some View {
        // Summary statistics and detailed log access
    }
}
```

## Data Models

### Storage Strategy

- **In-Memory Storage**: Active session data stored in memory for fast access
- **UserDefaults Persistence**: Completed sessions stored in UserDefaults with automatic cleanup
- **Size Limits**: Maximum 50 sessions stored, oldest automatically removed
- **Data Compression**: JSON encoding with minimal overhead

### Data Structure Hierarchy

```
PerformanceLogger
├── currentSessions: [UUID: LogSession]
├── completedSessions: [LogSession] (persisted)
└── deviceContext: DeviceContext (cached)

LogSession
├── metadata (id, timestamps, device context)
└── entries: [LogEntry]

LogEntry
├── operation details (name, timing)
├── model information (optional)
└── device context snapshot
```

## Error Handling

### Logging Failures

- **Graceful Degradation**: If logging fails, the main app functionality continues unaffected
- **Silent Failures**: Logging errors are printed to console but don't surface to users
- **Automatic Recovery**: Logger reinitializes if corruption is detected
- **Memory Protection**: Automatic cleanup prevents memory leaks from failed sessions

### Data Integrity

- **Validation**: All log entries validated before storage
- **Corruption Handling**: Invalid data automatically discarded
- **Version Compatibility**: Data model versioning for future updates
- **Atomic Operations**: Session updates are atomic to prevent partial data

## Testing Strategy

### Unit Testing

- **Logger Functionality**: Test timing accuracy, session management, and data persistence
- **Data Models**: Verify encoding/decoding and validation logic
- **Formatter**: Test log output formatting and copyable text generation
- **Memory Management**: Verify proper cleanup and size limits

### Integration Testing

- **Pipeline Integration**: Test logging integration with existing photo processing flow
- **Performance Impact**: Measure logging overhead to ensure minimal impact
- **UI Integration**: Test About page integration and user interactions
- **Data Flow**: Verify end-to-end data flow from capture to display

### Performance Testing

- **Timing Accuracy**: Verify millisecond-precision timing measurements
- **Memory Usage**: Ensure logging doesn't significantly increase memory footprint
- **Storage Efficiency**: Test data compression and cleanup mechanisms
- **Concurrent Access**: Test thread safety with multiple simultaneous operations

## Implementation Details

### Timing Measurement Strategy

The system will use `Date()` and `CFAbsoluteTimeGetCurrent()` for high-precision timing:

```swift
private func measureOperation<T>(_ operation: String, sessionId: UUID, modelInfo: ModelInfo? = nil, block: () async throws -> T) async throws -> T {
    let startTime = Date()
    let startCFTime = CFAbsoluteTimeGetCurrent()
    
    do {
        let result = try await block()
        let duration = CFAbsoluteTimeGetCurrent() - startCFTime
        logOperation(operation, duration: duration, sessionId: sessionId, modelInfo: modelInfo)
        return result
    } catch {
        let duration = CFAbsoluteTimeGetCurrent() - startCFTime
        logOperation("\(operation) (failed)", duration: duration, sessionId: sessionId, modelInfo: modelInfo)
        throw error
    }
}
```

### Integration with Existing Code

The logging will be integrated using minimal code changes:

1. **Wrapper Methods**: Existing async operations wrapped with timing measurement
2. **Session Tracking**: Session IDs passed through the processing pipeline
3. **Model Detection**: Automatic detection of which service/model is being used
4. **Non-Blocking**: All logging operations performed asynchronously

### About Page Integration

The performance logs will be added to the existing About page as a new section:

```swift
// In aboutTabView
VStack(spacing: 20) {
    // ... existing content ...
    
    // Performance Logs Section
    Button("Performance Logs") {
        showingFullLogs = true
    }
    .buttonStyle(.borderedProminent)
    .tint(Color.orangeTabbyAccent)
}
.sheet(isPresented: $showingFullLogs) {
    PerformanceLogView()
}
```

### Data Format for Copy/Paste

The copyable log format will be structured for easy analysis:

```
NotebookSaver Performance Log
Generated: 2024-01-15 14:30:22
Device: iPhone 15 Pro (iOS 17.2.1)
App Version: 1.0.0

=== SESSION 1 ===
Started: 2024-01-15 14:29:45.123
Total Duration: 3.456s

Operations:
- Photo Capture: 0.123s
- Image Preprocessing: 0.234s  
- Text Extraction (Gemini/gemini-2.5-flash): 2.890s
- Note Creation: 0.209s

=== SESSION 2 ===
...
```

This design provides comprehensive performance monitoring while maintaining the app's existing architecture and user experience.
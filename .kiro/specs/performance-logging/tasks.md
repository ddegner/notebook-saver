# Implementation Plan

- [x] 1. Create core performance logging infrastructure
  - Create PerformanceLogger singleton class with session management
  - Implement LogEntry, LogSession, ModelInfo, and DeviceContext data models
  - Add data persistence using UserDefaults with automatic cleanup
  - Implement thread-safe logging operations with minimal performance overhead
  - _Requirements: 1.1, 1.2, 1.3, 4.1, 4.2, 4.3, 4.4_

- [x] 2. Implement timing measurement utilities
  - Create high-precision timing wrapper methods using CFAbsoluteTimeGetCurrent()
  - Add convenience methods for measuring async operations
  - Implement automatic error handling that logs failed operations
  - Add session lifecycle management (start, log, end)
  - _Requirements: 1.1, 1.4, 1.5, 4.1, 4.2_

- [x] 3. Integrate logging into photo capture pipeline
  - Add session tracking to CameraView.capturePhoto() method
  - Instrument CameraView.handlePhotoCapture() with overall pipeline timing
  - Add timing measurement to CameraView.processImageOnce() for image preprocessing
  - Pass session IDs through the processing pipeline for operation correlation
  - _Requirements: 1.1, 1.2, 1.3, 1.4_

- [x] 4. Add model tracking to AI services
  - Integrate logging into GeminiService.extractText() with model name detection
  - Add logging to VisionService.extractText() with Apple Vision model info
  - Capture model configuration and service selection information
  - Record model switching or fallback behavior during processing
  - _Requirements: 2.1, 2.2, 2.3, 2.4_

- [x] 5. Instrument note creation and delivery
  - Add timing measurement to CameraView.sendToTargetApp() method
  - Log photo saving operations in CameraView.savePhotoIfNeeded()
  - Track Drafts app integration timing in DraftsHelper methods
  - Measure share sheet presentation timing for non-Drafts workflows
  - _Requirements: 1.1, 1.4, 1.5_

- [x] 6. Create performance log display interface
  - Create PerformanceLogView SwiftUI component for log display
  - Implement summary statistics showing average processing times
  - Add detailed log viewer with expandable session information
  - Create copyable text formatter for external analysis
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 5.2, 5.3_

- [x] 7. Integrate performance logs into About page
  - Add "Performance Logs" button to existing About page in SettingsView
  - Implement sheet presentation for PerformanceLogView
  - Add copy-to-clipboard functionality with user feedback
  - Ensure consistent styling with existing About page design
  - _Requirements: 3.1, 3.2, 3.4_

- [x] 8. Implement log management and cleanup
  - Add automatic cleanup of old log entries (keep last 50 sessions)
  - Implement storage size limits to prevent excessive memory usage
  - Add log clearing functionality for user privacy
  - Create device context collection for session metadata
  - _Requirements: 4.3, 5.1, 5.4, 5.5_

- [x] 9. Add comprehensive testing
  - Write unit tests for PerformanceLogger timing accuracy and session management
  - Create integration tests for pipeline logging without performance impact
  - Add UI tests for About page integration and copy functionality
  - Test memory management and cleanup mechanisms
  - _Requirements: 4.1, 4.2, 4.3, 4.4_

- [x] 10. Performance validation and optimization
  - Measure logging overhead to ensure minimal impact on processing speed
  - Validate timing accuracy across different device types and iOS versions
  - Test concurrent logging scenarios for thread safety
  - Optimize data storage format for minimal memory footprint
  - _Requirements: 4.1, 4.2, 4.3, 4.4_
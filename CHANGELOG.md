# Changelog

All notable changes to NotebookSaver (Cat Scribe) will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1] - 2025-10-28

### Changed
- **Simplified camera system**: Removed complex multi-camera switching and zoom controls
  - Now uses a single wide-angle camera with automatic close focus
  - Removed pinch-to-zoom functionality
  - Removed zoom indicator overlay
  - Removed default zoom setting from preferences
  - Camera automatically switches to macro mode on supported devices (iPhone 13 Pro and later)
- **Code cleanup and optimization**: Removed ~175 lines of unused and redundant code
  - Simplified GeminiService with better error handling and cleaner request flow
  - Removed duplicate image processing methods
  - Cleaned up excessive logging statements
  - Better separation of concerns in network request handling

### Improved
- **Faster app startup**: No camera discovery or zoom initialization needed
- **More consistent behavior**: Predictable camera focus for document scanning
- **Better maintainability**: Cleaner, more readable codebase
- **Enhanced close-focus capability**: Optimized for scanning documents at close range

### Technical Details
- Camera now uses virtual device (dual-wide or triple camera when available)
- Focus mode set to continuous autofocus with near range restriction
- Automatic macro mode enabled on iOS 15.4+ with supported devices
- Reduced binary size through code elimination

## [1.0] - Initial Release

### Added
- AI-powered text extraction using Google Gemini models
- Multi-camera system with automatic switching
- Pinch-to-zoom with visual indicators
- Seamless Drafts app integration
- Customizable AI prompts and model selection
- Secure API key storage via Keychain
- Image preprocessing for better OCR accuracy
- Background draft processing queue
- Widget support for quick access
- Comprehensive error handling and retry logic

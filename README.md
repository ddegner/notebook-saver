# NotebookSaver

A powerful iOS app that transforms handwritten notes and documents into digital text using AI-powered optical character recognition (OCR). Capture images with your camera and instantly extract text using Google's Gemini AI models.

## Features

### 📸 Smart Camera Capture
- **Multi-Camera System**: Automatically uses all available cameras including macro for close focus
- **Intelligent Camera Switching**: Seamlessly switches between wide, ultra-wide, telephoto, and macro cameras based on zoom level
- **Pinch-to-Zoom**: Smooth pinch gestures with automatic camera selection for optimal image quality
- **Macro Photography**: Enhanced close-focus capabilities for detailed document capture
- Real-time camera preview with optimized capture settings
- Automatic image preprocessing for better OCR accuracy
- High-quality HEIC image encoding for efficient processing

### 🤖 AI-Powered Text Extraction
- Integration with Google Gemini AI models (2.5 Flash, 2.0 Flash, 1.5 Pro, and more)
- Customizable prompts to guide AI text extraction
- Support for multiple Gemini model variants
- Automatic model discovery and caching
- "Thinking mode" for enhanced AI reasoning

### 📝 Drafts Integration
- Seamless integration with the Drafts app
- Automatic text export with customizable tags
- Background processing with pending draft queue
- URL scheme support for deep linking

### ⚙️ Advanced Configuration
- Custom API endpoint configuration
- Model selection and custom model support
- Adjustable image quality and processing settings
- Secure API key storage using Keychain
- Comprehensive error handling and retry logic

### 🎨 Intuitive Interface
- Gesture-based navigation between camera and settings
- Smooth animations and haptic feedback
- Onboarding flow for new users
- Widget support for quick access

## Requirements

- iOS 18.0 or later
- iPhone with camera
- Google Gemini API key
- Drafts app (optional, for text export)

## Setup

### 1. Get a Gemini API Key
1. Visit the [Google AI Studio](https://aistudio.google.com/)
2. Create a new project or select an existing one
3. Generate an API key for the Gemini API
4. Keep your API key secure

### 2. Configure the App
1. Launch NotebookSaver
2. Complete the onboarding process
3. Go to Settings (swipe up from camera view)
4. Enter your Gemini API key
5. Select your preferred AI model
6. Customize the text extraction prompt
7. Configure Drafts integration (optional)

### 3. Start Capturing
1. Point your camera at handwritten text or documents
2. Use pinch gestures to zoom in/out - the app automatically selects the best camera
3. For close-up text, zoom in to activate macro mode for enhanced detail
4. Tap the capture button
5. Wait for AI processing
6. Review and use the extracted text

### Camera Features
- **Multi-Camera Support**: Automatically discovers and uses the best available camera (triple, dual, or wide)
- **Smart Zoom Switching**: Switches to telephoto camera for zoom levels above 3x when available
- **Pinch-to-Zoom**: Smooth gesture control with haptic feedback
- **Visual Zoom Indicator**: Shows current zoom level when zoomed in
- **Optimized Focus**: Automatic near-focus restriction for document scanning

## Configuration Options

### AI Models
- **Gemini 2.5 Flash** (recommended) - Fast and accurate
- **Gemini 2.5 Flash Lite** - Lightweight version
- **Gemini 2.5 Pro** - Most capable model
- **Gemini 2.0 Flash** - Latest generation
- **Gemini 1.5 Pro** - Previous generation pro model
- **Gemini 1.5 Flash** - Previous generation fast model
- **Custom Model** - Enter any compatible model name

### Text Extraction Settings
- **Custom Prompt**: Guide the AI on how to process your images
- **Thinking Mode**: Enable enhanced AI reasoning for complex documents
- **API Endpoint**: Use custom or regional API endpoints

### Drafts Integration
- **Auto-Export**: Automatically send extracted text to Drafts
- **Custom Tags**: Add tags to organize your drafts
- **Background Processing**: Queue drafts when app is in background

## Technical Details

### Image Processing
- Automatic image resizing (max 1500px dimension)
- HEIC compression for optimal file size
- Core Image-based preprocessing
- Quality optimization for OCR accuracy

### Network & Reliability
- Automatic retry with exponential backoff
- Network connectivity monitoring
- Comprehensive error handling
- Connection warming for faster requests

### Security
- API keys stored securely in iOS Keychain
- No text data stored locally
- Secure HTTPS communication

## Architecture

The app follows a clean architecture pattern with:

- **SwiftUI** for the user interface
- **Combine** for reactive programming
- **Core Image** for image processing
- **URLSession** for network requests
- **Keychain Services** for secure storage

### Key Components

- `GeminiService`: Handles AI API communication
- `CameraManager`: Manages camera capture and settings
- `ImageProcessor`: Handles image preprocessing
- `DraftsHelper`: Manages Drafts app integration
- `AppStateManager`: Coordinates app state and navigation

## Privacy

NotebookSaver respects your privacy:
- Images are processed by Google's Gemini API according to their privacy policy
- No images or text are stored locally on your device
- API keys are stored securely in the iOS Keychain
- No analytics or tracking

## Troubleshooting

### Common Issues

**"API Key is missing"**
- Ensure you've entered a valid Gemini API key in Settings

**"Model not found"**
- Try refreshing the models list in Settings
- Check if your custom model name is correct

**"Service Unavailable"**
- The app will automatically retry failed requests
- Check your internet connection
- Google's servers may be experiencing high load

**"Drafts app not installed"**
- Install the Drafts app from the App Store
- Ensure Drafts integration is enabled in Settings

### Performance Tips
- Use Gemini 2.5 Flash for the best speed/accuracy balance
- Ensure good lighting when capturing images
- Keep text images clear and well-focused
- Use the highest quality camera settings

## Contributing

This is a personal project, but feedback and suggestions are welcome. Please ensure any contributions follow iOS development best practices and maintain the app's focus on simplicity and reliability.

## License

This project is for personal use. Please respect Google's Gemini API terms of service and usage limits.

---

**Note**: This app requires a Google Gemini API key and active internet connection to function. API usage may incur costs based on Google's pricing structure.
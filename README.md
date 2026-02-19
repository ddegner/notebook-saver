# NotebookSaver

A powerful iOS app that transforms handwritten notes and documents into digital text using AI-powered optical character recognition (OCR). Capture images with your camera and instantly extract text using Google's Gemini API.

## Simple by Design

NotebookSaver focuses on a single workflow: capture text, extract it, and move on.  
It uses the Gemini API for OCR and can send results to Drafts if you want.

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
5. Adjust AI processing settings for your workflow
6. Customize the text extraction prompt
7. Configure Drafts integration (optional)

### 3. Start Capturing
1. Point your camera at handwritten text or documents
2. Tap the capture button
3. Wait for AI processing
4. Review and use the extracted text

## Configuration Options

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

**"Service Unavailable"**
- The app will automatically retry failed requests
- Check your internet connection
- Google's servers may be experiencing high load

**"Drafts app not installed"**
- Install the Drafts app from the App Store
- Ensure Drafts integration is enabled in Settings

### Performance Tips
- Start with the default AI settings for the best speed/accuracy balance
- Ensure good lighting when capturing images
- Keep text images clear and well-focused
- Use the highest quality camera settings

## Contributing

This is a personal project, but feedback and suggestions are welcome. Please ensure any contributions follow iOS development best practices and maintain the app's focus on simplicity and reliability.

## License

This project is for personal use. Please respect Google's Gemini API terms of service and usage limits.

---

**Note**: This app requires a Google Gemini API key and active internet connection to function. API usage may incur costs based on Google's pricing structure.

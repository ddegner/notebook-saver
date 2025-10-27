# Requirements Document

## Introduction

This feature enables NotebookSaver to be declared as a handler for image document types, allowing users to open images directly with the app from Files, Photos, or other applications. When an image is opened with NotebookSaver, the app will launch (if not already running) and process the image through the existing image-to-text extraction pipeline, displaying the same inspirational quotes overlay that appears during camera capture.

## Glossary

- **Document Type Declaration**: iOS Info.plist configuration that registers the app as a handler for specific file types
- **UTI (Uniform Type Identifier)**: Apple's system for identifying data types (e.g., public.image, public.jpeg)
- **Image Processing Pipeline**: The existing workflow that takes an image, preprocesses it, extracts text using AI services (Gemini or Vision), and creates a draft note
- **Quotes Overlay**: The inspirational notebook-themed quotes that display during image processing to provide user feedback
- **Drafts App**: The third-party note-taking application where extracted text is sent
- **Main App**: The NotebookSaver application that handles image processing

## Requirements

### Requirement 1

**User Story:** As a user, I want to open images with NotebookSaver from other apps, so that I can quickly extract text from notebook pages without using the camera

#### Acceptance Criteria

1. WHEN a user selects "Open With" on an image file, THE Main App SHALL appear as an available application option
2. WHEN a user selects NotebookSaver from the "Open With" menu, THE Main App SHALL launch and receive the image file URL
3. WHEN the Main App receives an image URL, THE Main App SHALL validate that the file represents a valid image format (JPEG, PNG, HEIC)
4. WHERE the file is not a valid image format, THE Main App SHALL display an error message to the user
5. WHEN a valid image is received, THE Main App SHALL load the image data and pass it to the image processing pipeline

### Requirement 2

**User Story:** As a user, I want to see the same inspirational quotes when opening images, so that I have a consistent experience whether I'm using the camera or opening existing images

#### Acceptance Criteria

1. WHEN the Main App begins processing an opened image, THE Main App SHALL display the quotes overlay view
2. WHILE image processing is in progress, THE Main App SHALL rotate through inspirational notebook quotes at regular intervals
3. WHEN text extraction completes successfully, THE Main App SHALL dismiss the quotes overlay and return to the main view
4. IF text extraction fails, THEN THE Main App SHALL display an appropriate error message to the user
5. WHEN the user dismisses the error message, THE Main App SHALL return to the main camera view

### Requirement 3

**User Story:** As a user, I want opened images to be processed using my configured AI service settings, so that I get consistent text extraction quality regardless of how I capture images

#### Acceptance Criteria

1. WHEN the Main App processes an opened image, THE Main App SHALL use the existing ImagePreprocessor with current settings
2. WHEN the Main App extracts text, THE Main App SHALL use the user's selected service (Gemini or Vision) with their configured model and prompt
3. WHEN the Main App creates a draft, THE Main App SHALL use the user's configured Drafts tag from settings
4. WHERE the user has not configured an API key, THE Main App SHALL display an error message directing them to configure settings
5. WHEN processing completes, THE Main App SHALL log performance metrics using the existing PerformanceLogger

### Requirement 4

**User Story:** As a developer, I want the app to declare support for common image formats, so that users can open various image types with NotebookSaver

#### Acceptance Criteria

1. THE Main App SHALL declare support for public.image as a document type
2. THE Main App SHALL declare support for public.jpeg as a document type
3. THE Main App SHALL declare support for public.png as a document type
4. THE Main App SHALL declare support for public.heic as a document type
5. THE Main App SHALL set the document role to "Viewer" to indicate read-only access

### Requirement 5

**User Story:** As a user, I want the app to handle the opened image gracefully, so that I can continue using the app normally after processing

#### Acceptance Criteria

1. WHEN image processing completes successfully, THE Main App SHALL create a draft note with the extracted text
2. WHEN the draft is created, THE Main App SHALL display a success message or indicator
3. WHEN processing is complete, THE Main App SHALL remain open at the main camera view
4. WHERE the Drafts app is not available, THE Main App SHALL store the pending draft for later creation
5. WHEN an error occurs, THE Main App SHALL display a user-friendly error message and remain at the camera view

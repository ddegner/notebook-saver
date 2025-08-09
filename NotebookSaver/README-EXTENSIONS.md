# Extensions

- Share Extension: Share a single photo from Photos to NotebookSaver to extract text with current settings.
- App Intent: "Process Photo" accepts an image file and returns extracted text. Appears in Shortcuts and Spotlight.

Setup Notes:
- Ensure App Group `group.com.daviddegner.NotebookSaver` is enabled for app and extension.
- The app must be launched once to save API key and settings before extensions can use them.
- The API key is stored in Keychain with access group `$(AppIdentifierPrefix)com.daviddegner.NotebookSaver`.

Usage:
- From Photos: Share > NotebookSaver — waits, then shows extracted text with Copy/Share.
- From Shortcuts: Use the "Process Photo" intent with an image input; result is the extracted text string.
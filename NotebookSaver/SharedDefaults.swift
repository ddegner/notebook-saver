import Foundation

// Shared App Group UserDefaults for app and extensions
// Update the App Group identifier if you change your Bundle ID
public enum SharedDefaults {
    public static let appGroupId = "group.com.daviddegner.NotebookSaver"
    public static let suite: UserDefaults = {
        guard let defaults = UserDefaults(suiteName: appGroupId) else {
            // Fallback to standard to avoid crashes if misconfigured
            return .standard
        }
        return defaults
    }()
}
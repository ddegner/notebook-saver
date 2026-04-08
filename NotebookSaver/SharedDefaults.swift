import Foundation

/// Shared App Group container for communication between main app and extensions.
/// Both targets must have the App Groups capability with this identifier.
enum SharedDefaults {
    static let appGroupId = "group.com.daviddegner.NotebookSaver"

    /// UserDefaults suite shared between the app and its extensions.
    /// Falls back to .standard if the App Group is misconfigured.
    nonisolated(unsafe) static let suite: UserDefaults = {
        guard let defaults = UserDefaults(suiteName: appGroupId) else {
            return .standard
        }
        return defaults
    }()

    /// Shared keychain service identifier used by both the main app and extensions.
    /// Using a fixed string (not Bundle.main.bundleIdentifier) ensures both targets
    /// access the same keychain item.
    static let keychainService = "com.daviddegner.NotebookSaver"
}

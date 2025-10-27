import UIKit
import SwiftUI
import Foundation

// MARK: - Custom Drafts Errors
enum DraftsError: LocalizedError {
    case notInstalled
    case invalidURL
    
    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "The Drafts app is not installed. Please install it to use this feature."
        case .invalidURL:
            return "Could not construct a valid URL to send data to Drafts."
        }
    }
}

// MARK: - Drafts Helper

class DraftsHelper {
    // MARK: - Constants
    private static let scheme = "drafts"
    private static let createAction = "create"
    private static let pendingDraftsKey = "pendingDrafts"
    
    // MARK: - Pending Draft Structure
    private struct PendingDraft: Codable {
        let text: String
        let tag: String?
        let timestamp: Date
    }
    
    // MARK: - Public Methods
    
    /// Creates a new draft in the Drafts app
    /// - Parameters:
    ///   - text: The text content to create in Drafts
    ///   - tag: Optional tag(s) to apply to the draft (comma-separated for multiple tags)
    ///   - completion: Optional completion handler with success status
    /// - Throws: DraftsError if Drafts isn't installed or URL creation fails
    @MainActor
    static func createDraft(with text: String, tag: String? = nil, completion: ((Bool) -> Void)? = nil) throws {
        // Check if Drafts is installed
        try checkDraftsInstalled()
        
        // Build and open URL
        let url = try buildDraftsURL(text: text, tag: tag)
        print("Opening URL: \(url.absoluteString)")
        
        UIApplication.shared.open(url) { success in
            if success {
                print("Successfully opened Drafts URL.")
            } else {
                print("Warning: There may have been an issue opening Drafts.")
            }
            completion?(success)
        }
    }
    
    /// Async version of createDraft that returns success status
    /// - Parameters:
    ///   - text: The text content to create in Drafts
    ///   - tag: Optional tag(s) to apply to the draft
    ///   - sessionId: Optional performance logging session ID
    /// - Returns: Boolean indicating success
    /// - Throws: DraftsError if Drafts isn't installed or URL creation fails
    static func createDraftAsync(with text: String, tag: String? = nil, sessionId: UUID? = nil) async throws -> Bool {
        // Direct call to internal implementation (performance logging handled at higher level)
        return try await _createDraftAsyncInternal(with: text, tag: tag)
    }
    
    private static func _createDraftAsyncInternal(with text: String, tag: String? = nil) async throws -> Bool {
        try await checkDraftsInstalledAsync()
        
        let appState = await MainActor.run {
            UIApplication.shared.applicationState
        }
        
        if appState != .active {
            storePendingDraft(text: text, tag: tag)
            return true
        }
        
        let url = try await buildDraftsURLAsync(text: text, tag: tag)
        
        return await withCheckedContinuation { continuation in
            Task { @MainActor in
                UIApplication.shared.open(url) { success in
                    continuation.resume(returning: success)
                }
            }
        }
    }
    
    // MARK: - Private Helper Methods
    
    /// Checks if the Drafts app is installed
    /// - Throws: DraftsError.notInstalled if Drafts is not installed
    @MainActor
    private static func checkDraftsInstalled() throws {
        guard let checkURL = URL(string: "\(scheme)://"),
              UIApplication.shared.canOpenURL(checkURL) else {
            print("Error: Drafts app does not appear to be installed.")
            throw DraftsError.notInstalled
        }
    }
    
    /// Async version of checkDraftsInstalled that can be called from background tasks
    private static func checkDraftsInstalledAsync() async throws {
        try await MainActor.run {
            guard let checkURL = URL(string: "\(scheme)://"),
                  UIApplication.shared.canOpenURL(checkURL) else {
                print("Error: Drafts app does not appear to be installed.")
                throw DraftsError.notInstalled
            }
        }
    }
    
    /// Builds a URL to create a draft with the specified parameters
    /// - Parameters:
    ///   - text: The text content to create in Drafts
    ///   - tag: Optional tag(s) to apply to the draft
    /// - Returns: URL to open Drafts with the specified content
    /// - Throws: DraftsError.invalidURL if URL construction fails
    @MainActor
    private static func buildDraftsURL(text: String, tag: String?) throws -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = createAction
        
        var queryItems = [URLQueryItem(name: "text", value: text)]
        
        if let tag = tag, !tag.isEmpty {
            queryItems.append(URLQueryItem(name: "tag", value: tag))
        }
        
        components.queryItems = queryItems
        
        guard let url = components.url else {
            throw DraftsError.invalidURL
        }
        
        return url
    }
    
    /// Async version of buildDraftsURL that can be called from background tasks
    private static func buildDraftsURLAsync(text: String, tag: String?) async throws -> URL {
        return try await MainActor.run {
            var components = URLComponents()
            components.scheme = scheme
            components.host = createAction
            
            var queryItems = [URLQueryItem(name: "text", value: text)]
            
            if let tag = tag, !tag.isEmpty {
                queryItems.append(URLQueryItem(name: "tag", value: tag))
            }
            
            components.queryItems = queryItems
            
            guard let url = components.url else {
                throw DraftsError.invalidURL
            }
            
            return url
        }
    }
    
    // MARK: - Pending Draft Management
    
    /// Store a draft to be created when the app returns to foreground
    private static func storePendingDraft(text: String, tag: String?) {
        let pendingDraft = PendingDraft(text: text, tag: tag, timestamp: Date())
        
        var pendingDrafts = loadPendingDrafts()
        pendingDrafts.append(pendingDraft)
        
        do {
            let data = try JSONEncoder().encode(pendingDrafts)
            UserDefaults.standard.set(data, forKey: pendingDraftsKey)
            UserDefaults.standard.synchronize()
        } catch {
            print("DraftsHelper: Failed to store pending draft: \(error)")
        }
    }
    
    /// Load all pending drafts from storage
    private static func loadPendingDrafts() -> [PendingDraft] {
        guard let data = UserDefaults.standard.data(forKey: pendingDraftsKey) else {
            return []
        }
        
        do {
            return try JSONDecoder().decode([PendingDraft].self, from: data)
        } catch {
            print("DraftsHelper: Failed to load pending drafts: \(error)")
            return []
        }
    }
    
    /// Create all pending drafts (call when app returns to foreground)
    @MainActor
    static func createPendingDrafts() async {
        let pendingDrafts = loadPendingDrafts()
        
        guard !pendingDrafts.isEmpty else {
            return
        }
        
        do {
            try checkDraftsInstalled()
        } catch {
            return
        }
        
        let sessionId = PerformanceLogger.shared.startSession()
        
        for draft in pendingDrafts {
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
                try await PerformanceLogger.shared.measureVoidOperation(
                    "Create Pending Draft",
                    sessionId: sessionId
                ) {
                    try createDraft(with: draft.text, tag: draft.tag)
                }
            } catch {
                if error is DraftsError {
                    PerformanceLogger.shared.cancelSession(sessionId)
                    return
                }
            }
        }
        
        UserDefaults.standard.removeObject(forKey: pendingDraftsKey)
        PerformanceLogger.shared.endSession(sessionId)
    }
    
    /// Get count of pending drafts
    static func pendingDraftCount() -> Int {
        return loadPendingDrafts().count
    }
    
    /// Debug method to manually add a test pending draft
    static func addTestPendingDraft() {
        storePendingDraft(text: "Test draft created at \(Date())", tag: "test")
    }
}
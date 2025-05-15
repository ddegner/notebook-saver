import UIKit
import SwiftUI

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
    /// - Returns: Boolean indicating success
    /// - Throws: DraftsError if Drafts isn't installed or URL creation fails
    @MainActor
    static func createDraftAsync(with text: String, tag: String? = nil) async throws -> Bool {
        // Check if Drafts is installed
        try checkDraftsInstalled()
        
        // Build and open URL
        let url = try buildDraftsURL(text: text, tag: tag)
        return await UIApplication.shared.open(url)
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
        
        // Add required and optional parameters
        var queryItems = [URLQueryItem(name: "text", value: text)]
        
        if let tag = tag, !tag.isEmpty {
            queryItems.append(URLQueryItem(name: "tag", value: tag))
            print("Adding tag(s) to URL query: \(tag)")
        }
        
        components.queryItems = queryItems
        
        guard let url = components.url else {
            print("Error: Failed to create URL using URLComponents.")
            throw DraftsError.invalidURL
        }
        
        return url
    }
}
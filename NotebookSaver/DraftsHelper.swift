import UIKit
import SwiftUI
import Foundation

// MARK: - Custom Drafts Errors
enum DraftsError: LocalizedError {
    case notInstalled
    case invalidURL
    case handoffFailed
    
    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "The Drafts app is not installed. Please install it to use this feature."
        case .invalidURL:
            return "Could not construct a valid URL to send data to Drafts."
        case .handoffFailed:
            return "Could not hand off the note to Drafts."
        }
    }
}

// MARK: - Drafts Helper

class DraftsHelper {
    // MARK: - Constants
    private static let scheme = "drafts"
    private static let createAction = "create"
    
    // MARK: - Pending Draft Structure
    private struct PendingDraft: Codable {
        let text: String
        let tag: String?
        let timestamp: Date
    }
    
    // MARK: - Public Methods
    
    /// Creates a new draft in the Drafts app.
    /// If the app is backgrounded, the draft is queued for the next foreground transition.
    /// - Parameters:
    ///   - text: The text content to create in Drafts
    ///   - tag: Optional tag(s) to apply to the draft
    /// - Throws: DraftsError if Drafts isn't installed, URL construction fails, or handoff fails.
    static func createDraftAsync(with text: String, tag: String? = nil) async throws {
        try await checkDraftsInstalledAsync()
        
        let appState = await MainActor.run {
            UIApplication.shared.applicationState
        }
        
        if appState != .active {
            storePendingDraft(text: text, tag: tag)
            return
        }
        
        try await openDraftDirectly(text: text, tag: tag)
    }
    
    private static func openDraftDirectly(text: String, tag: String?) async throws {
        let url = try buildDraftsURL(text: text, tag: tag)
        let opened = await openURL(url)
        guard opened else {
            throw DraftsError.handoffFailed
        }
    }
    
    @MainActor
    private static func openURL(_ url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            UIApplication.shared.open(url) { success in
                continuation.resume(returning: success)
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
    
    // MARK: - Pending Draft Management
    
    private static func savePendingDrafts(_ drafts: [PendingDraft]) {
        if drafts.isEmpty {
            UserDefaults.standard.removeObject(forKey: SettingsKey.pendingDrafts)
            return
        }
        
        do {
            let data = try JSONEncoder().encode(drafts)
            UserDefaults.standard.set(data, forKey: SettingsKey.pendingDrafts)
        } catch {
            print("DraftsHelper: Failed to save pending drafts: \(error)")
        }
    }
    
    /// Store a draft to be created when the app returns to foreground
    private static func storePendingDraft(text: String, tag: String?) {
        let pendingDraft = PendingDraft(text: text, tag: tag, timestamp: Date())
        
        var pendingDrafts = loadPendingDrafts()
        pendingDrafts.append(pendingDraft)
        savePendingDrafts(pendingDrafts)
    }
    
    /// Load all pending drafts from storage
    private static func loadPendingDrafts() -> [PendingDraft] {
        guard let data = UserDefaults.standard.data(forKey: SettingsKey.pendingDrafts) else {
            return []
        }
        
        do {
            return try JSONDecoder().decode([PendingDraft].self, from: data)
        } catch {
            print("DraftsHelper: Failed to load pending drafts: \(error)")
            return []
        }
    }
    
    /// Attempt to create the next pending draft (call when app returns to foreground).
    @MainActor
    static func createPendingDrafts() async {
        var pendingDrafts = loadPendingDrafts()
        guard let draft = pendingDrafts.first else {
            return
        }
        
        do {
            try checkDraftsInstalled()
        } catch {
            return
        }
        
        let sessionId = PerformanceLogger.shared.startSession()
        let token = PerformanceLogger.shared.startTiming("Create Pending Draft", sessionId: sessionId)
        
        do {
            guard UIApplication.shared.applicationState == .active else {
                PerformanceLogger.shared.cancelSession(sessionId)
                return
            }
            
            try await openDraftDirectly(text: draft.text, tag: draft.tag)
            pendingDrafts.removeFirst()
            savePendingDrafts(pendingDrafts)
            
            if let token {
                PerformanceLogger.shared.endTiming(token, success: true)
            }
            PerformanceLogger.shared.endSession(sessionId, success: true)
        } catch {
            if let token {
                PerformanceLogger.shared.endTiming(token, error: error)
            }
            PerformanceLogger.shared.endSession(sessionId, success: false)
        }
    }
    
}

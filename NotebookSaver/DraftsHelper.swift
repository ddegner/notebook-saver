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
    private static let pendingDraftsKey = "pendingDrafts"
    
    // MARK: - Pending Draft Structure
    private struct PendingDraft: Codable {
        let text: String
        let tag: String?
        let timestamp: Date
    }
    
    // MARK: - Public Methods
    
    @MainActor
    static func createDraft(with text: String, tag: String? = nil, completion: ((Bool) -> Void)? = nil) throws {
        try checkDraftsInstalled()
        let url = try buildDraftsURL(text: text, tag: tag)
        print("Opening URL: \(url.absoluteString)")
        UIApplication.shared.open(url) { success in
            if success { print("Successfully opened Drafts URL.") }
            else { print("Warning: There may have been an issue opening Drafts.") }
            completion?(success)
        }
    }
    
    static func createDraftAsync(with text: String, tag: String? = nil) async throws -> Bool {
        try await checkDraftsInstalledAsync()
        let appState = await MainActor.run { UIApplication.shared.applicationState }
        print("DraftsHelper: Current app state: \(appState.rawValue) (0=active, 1=inactive, 2=background)")
        if appState != .active {
            print("DraftsHelper: App is not active (state: \(appState)), storing draft for later creation")
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
    @MainActor
    private static func checkDraftsInstalled() throws {
        guard let checkURL = URL(string: "\(scheme)://"),
              UIApplication.shared.canOpenURL(checkURL) else {
            print("Error: Drafts app does not appear to be installed.")
            throw DraftsError.notInstalled
        }
    }
    
    private static func checkDraftsInstalledAsync() async throws {
        try await MainActor.run {
            guard let checkURL = URL(string: "\(scheme)://"),
                  UIApplication.shared.canOpenURL(checkURL) else {
                print("Error: Drafts app does not appear to be installed.")
                throw DraftsError.notInstalled
            }
        }
    }
    
    @MainActor
    private static func buildDraftsURL(text: String, tag: String?) throws -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = createAction
        var queryItems = [URLQueryItem(name: "text", value: text)]
        if let tag = tag, !tag.isEmpty { queryItems.append(URLQueryItem(name: "tag", value: tag)) }
        components.queryItems = queryItems
        guard let url = components.url else {
            print("Error: Failed to create URL using URLComponents.")
            throw DraftsError.invalidURL
        }
        return url
    }
    
    private static func buildDraftsURLAsync(text: String, tag: String?) async throws -> URL {
        return try await MainActor.run {
            var components = URLComponents()
            components.scheme = scheme
            components.host = createAction
            var queryItems = [URLQueryItem(name: "text", value: text)]
            if let tag = tag, !tag.isEmpty { queryItems.append(URLQueryItem(name: "tag", value: tag)) }
            components.queryItems = queryItems
            guard let url = components.url else {
                print("Error: Failed to create URL using URLComponents.")
                throw DraftsError.invalidURL
            }
            return url
        }
    }
    
    // MARK: - Pending Draft Management
    private static func storePendingDraft(text: String, tag: String?) {
        let pendingDraft = PendingDraft(text: text, tag: tag, timestamp: Date())
        var pendingDrafts = loadPendingDrafts()
        pendingDrafts.append(pendingDraft)
        do {
            let data = try JSONEncoder().encode(pendingDrafts)
            SharedDefaults.suite.set(data, forKey: pendingDraftsKey)
            SharedDefaults.suite.synchronize()
            print("DraftsHelper: Stored pending draft with \(text.count) characters, total pending: \(pendingDrafts.count)")
        } catch {
            print("DraftsHelper: Failed to store pending draft: \(error)")
        }
    }
    
    private static func loadPendingDrafts() -> [PendingDraft] {
        guard let data = SharedDefaults.suite.data(forKey: pendingDraftsKey) else {
            return []
        }
        do {
            return try JSONDecoder().decode([PendingDraft].self, from: data)
        } catch {
            print("DraftsHelper: Failed to load pending drafts: \(error)")
            return []
        }
    }
    
    @MainActor
    static func createPendingDrafts() async {
        let pendingDrafts = loadPendingDrafts()
        guard !pendingDrafts.isEmpty else { return }
        do { try checkDraftsInstalled() } catch {
            print("DraftsHelper: Drafts app not available, keeping \(pendingDrafts.count) pending drafts")
            return
        }
        print("DraftsHelper: Creating \(pendingDrafts.count) pending drafts")
        for draft in pendingDrafts {
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
                try createDraft(with: draft.text, tag: draft.tag)
                print("DraftsHelper: Successfully created pending draft from \(draft.timestamp)")
            } catch {
                print("DraftsHelper: Failed to create pending draft: \(error)")
                if error is DraftsError { return }
            }
        }
        SharedDefaults.suite.removeObject(forKey: pendingDraftsKey)
        print("DraftsHelper: Cleared all pending drafts")
    }
    
    static func pendingDraftCount() -> Int {
        return loadPendingDrafts().count
    }
    
    static func addTestPendingDraft() {
        storePendingDraft(text: "Test draft created at \(Date())", tag: "test")
    }
}
import Foundation
import SwiftUI // For @Published

// MARK: - Model Management Service

@MainActor
class GeminiModelService: ObservableObject {
    static let shared = GeminiModelService()
    private init() {}
    
    // Cached models from API
    @Published var availableModels: [String] = []
    
    // Check if we should fetch models (first launch only)
    var shouldFetchModels: Bool {
        return !UserDefaults.standard.bool(forKey: SettingsKey.hasInitiallyFetchedModels)
    }
    
    // Fetch available models from API
    func fetchAvailableModels() async throws -> [String] {
        let (apiKey, apiEndpointUrl, _, _, _, _, _) = GeminiService.getSettings()
        
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw APIError.missingApiKey
        }
        
        guard let baseUrl = apiEndpointUrl else {
            throw APIError.invalidApiEndpoint("Invalid URL configuration")
        }
        
        guard let finalUrl = GeminiService.buildURLWithAPIKey(baseURL: baseUrl, apiKey: apiKey) else {
            throw APIError.invalidApiEndpoint("Failed to construct URL with API key")
        }
        
        var request = URLRequest(url: finalUrl)
        request.httpMethod = "GET"
        request.timeoutInterval = 30.0
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }
        
        guard httpResponse.statusCode == 200 else {
            throw httpResponse.statusCode == 401 ? APIError.authenticationError : APIError.serverError(httpResponse.statusCode)
        }
        
        let modelsResponse = try JSONDecoder().decode(GeminiModelsResponse.self, from: data)
        let models = modelsResponse.models.map(convertToModelIds) ?? getDefaultModelIds()
        
        await cacheModelIds(models)
        return models
    }
    
    // Convert API response to model ID strings
    private func convertToModelIds(_ apiModels: [GeminiModelInfo]) -> [String] {
        return apiModels
            .filter { modelInfo in
                // Prefer authoritative API capability signal; older endpoints may omit the field.
                let methods = modelInfo.supportedGenerationMethods?.map { $0.lowercased() } ?? []
                let supportsGenerateContent = methods.isEmpty || methods.contains("generatecontent")
                
                let modelName = modelInfo.name.lowercased()
                let isUnsupportedFamily = modelName.contains("embedding")
                    || modelName.contains("imagen")
                    || modelName.contains("veo")
                    || modelName.contains("tts")
                
                return supportsGenerateContent && !isUnsupportedFamily
            }
            .map { $0.name.replacingOccurrences(of: "models/", with: "") }
    }
    
    // Cache model IDs to UserDefaults
    private func cacheModelIds(_ modelIds: [String]) async {
        let data = try? JSONEncoder().encode(modelIds)
        UserDefaults.standard.set(data, forKey: SettingsKey.cachedGeminiModels)
        UserDefaults.standard.set(true, forKey: SettingsKey.hasInitiallyFetchedModels)
        
        // Update published property
        self.availableModels = modelIds
    }
    
    // Load cached model IDs
    func loadCachedModelIds() -> [String] {
        guard let data = UserDefaults.standard.data(forKey: SettingsKey.cachedGeminiModels) else {
            return getDefaultModelIds()
        }
        
        guard let modelIds = try? JSONDecoder().decode([String].self, from: data) else {
            return getDefaultModelIds()
        }
        
        self.availableModels = modelIds
        return modelIds
    }
    
    // Fallback default model IDs
    private func getDefaultModelIds() -> [String] {
        return [
            "gemini-3-pro-preview",
            "gemini-2.5-flash-lite",
            "gemini-2.5-flash",
            "gemini-2.5-pro",
            "gemini-1.5-pro",
            "gemini-1.5-flash",
            "gemini-1.5-flash-8b"
        ]
    }
}

// MARK: - API Response Structures

struct GeminiModelsResponse: Codable {
    let models: [GeminiModelInfo]?
}

struct GeminiModelInfo: Codable {
    let name: String
    let displayName: String?
    let description: String?
    let version: String?
    let inputTokenLimit: Int?
    let outputTokenLimit: Int?
    let supportedGenerationMethods: [String]?
    
    private enum CodingKeys: String, CodingKey {
        case name
        case displayName = "display_name"
        case description
        case version
        case inputTokenLimit = "input_token_limit"
        case outputTokenLimit = "output_token_limit"
        case supportedGenerationMethods = "supported_generation_methods"
    }
}

import Foundation
import SwiftUI // For @Published
import UIKit // For UIImage
import CoreImage // Import Core Image

// MARK: - Model Management Service

class GeminiModelService: ObservableObject {
    static let shared = GeminiModelService()
    private init() {}
    
    // Storage keys
    private enum StorageKeys {
        static let cachedModels = "cachedGeminiModels"
        static let hasInitiallyFetchedModels = "hasInitiallyFetchedModels"
    }
    
    // Cached models from API
    @Published var availableModels: [String] = []
    
    // Check if we should fetch models (first launch only)
    var shouldFetchModels: Bool {
        return !UserDefaults.standard.bool(forKey: StorageKeys.hasInitiallyFetchedModels)
    }
    
    // Fetch available models from API
    func fetchAvailableModels() async throws -> [String] {
        let (apiKey, apiEndpointUrl, _, _, _, _) = GeminiService.getSettings()
        
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
        let knownModels: Set<String> = [
            "gemini-2.5-flash", "gemini-2.5-flash-lite", "gemini-2.5-pro", 
            "gemini-2.0-flash", "gemini-1.5-pro", "gemini-1.5-flash", "gemini-1.5-flash-8b"
        ]
        
        return apiModels
            .map { $0.name.replacingOccurrences(of: "models/", with: "") }
            .filter { modelName in
                !modelName.contains("embedding") && 
                !modelName.contains("imagen") && 
                !modelName.contains("veo") &&
                knownModels.contains(modelName)
            }
    }
    
    // Cache model IDs to UserDefaults
    @MainActor
    private func cacheModelIds(_ modelIds: [String]) async {
        let data = try? JSONEncoder().encode(modelIds)
        UserDefaults.standard.set(data, forKey: StorageKeys.cachedModels)
        UserDefaults.standard.set(true, forKey: StorageKeys.hasInitiallyFetchedModels)
        
        // Update published property
        self.availableModels = modelIds
    }
    
    // Load cached model IDs
    func loadCachedModelIds() -> [String] {
        guard let data = UserDefaults.standard.data(forKey: StorageKeys.cachedModels) else {
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
            "gemini-2.5-flash-lite",
            "gemini-2.5-flash",
            "gemini-2.5-pro",
            "gemini-2.0-flash",
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

class GeminiService: ImageTextExtractor {
    // Track if connection has been verified to avoid redundant warm-ups
    private static var connectionVerified = false

    // Defaults
    private let defaultModelId = "gemini-2.5-flash-lite" // Default model if nothing is set
    private let defaultPrompt = "Extract text accurately from this image of a notebook page."
    private static let defaultApiEndpoint = "https://generativelanguage.googleapis.com/v1beta/models/"
    private let defaultDraftsTag = "notebook"

    private let targetImageWidth: CGFloat = 1365.0 // Target width for Gemini uploads
    private let targetImageHeight: CGFloat = 1536.0 // Target height for Gemini uploads
    
    // Retry configuration
    private let maxRetryAttempts = 2 // Reduced from 3 for faster failure detection
    private let initialRetryDelay: TimeInterval = 0.5 // Reduced from 1.0 for faster retries

    private let imageProcessor = ImageProcessor()

    // Helper to get settings from UserDefaults
    static func getSettings() -> (apiKey: String?, apiEndpointUrl: URL?, modelToUse: String?, prompt: String, draftsTag: String, thinkingEnabled: Bool) {
        let defaults = UserDefaults.standard

        let apiKey = KeychainService.loadAPIKey()

        let endpointString = defaults.string(forKey: "apiEndpointUrlString") ?? GeminiService.defaultApiEndpoint
        let apiEndpointUrl = URL(string: endpointString)

        let selectedId = defaults.string(forKey: "selectedModelId") ?? "gemini-2.5-flash-lite"
        var modelToUse: String?
        if selectedId == "Custom" {
            modelToUse = defaults.string(forKey: "customModelName")?.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            modelToUse = selectedId
        }
        if modelToUse?.isEmpty ?? true {
            modelToUse = nil // Treat empty custom model as invalid
        }

        let prompt = defaults.string(forKey: "userPrompt") ?? "Extract text accurately from this image of a notebook page."
        let draftsTag = defaults.string(forKey: "draftsTag") ?? "notebook"
        let thinkingEnabled = defaults.bool(forKey: "thinkingEnabled")

        return (apiKey, apiEndpointUrl, modelToUse, prompt, draftsTag, thinkingEnabled)
    }

    // MARK: - URL Construction Helper
    
    static func buildURLWithAPIKey(baseURL: URL, apiKey: String) -> URL? {
        var urlComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        urlComponents?.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        return urlComponents?.url
    }

    // MARK: - Connection Warming

    public static func warmUpConnection() async -> Bool {
        let apiKey = KeychainService.loadAPIKey()
        let endpointString = UserDefaults.standard.string(forKey: "apiEndpointUrlString") ?? defaultApiEndpoint
        
        guard let apiBaseUrl = URL(string: endpointString) else { return false }
        guard let key = apiKey, !key.isEmpty else { return false }
        guard let finalUrl = buildURLWithAPIKey(baseURL: apiBaseUrl, apiKey: key) else { return false }

        var request = URLRequest(url: finalUrl)
        request.httpMethod = "GET"
        request.timeoutInterval = 10.0

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            
            connectionVerified = (200...299).contains(httpResponse.statusCode)
            return connectionVerified
        } catch {
            connectionVerified = false
            return false
        }
    }

    // MARK: - Public API

    func extractText(from imageData: Data, sessionId: UUID? = nil) async throws -> String {
        var retryCount = 0
        
        while true {
            do {
                return try await attemptExtractText(from: imageData, sessionId: sessionId)
            } catch {
                // Check if this is a retryable error
                let shouldRetry: Bool
                if let apiError = error as? APIError {
                    switch apiError {
                    case .serviceUnavailable, .serverError:
                        shouldRetry = true
                    default:
                        shouldRetry = false
                    }
                } else {
                    shouldRetry = false
                }
                
                guard shouldRetry && retryCount < maxRetryAttempts else { throw error }
                
                retryCount += 1
                let delay = initialRetryDelay * pow(2.0, Double(retryCount - 1))
                
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                continue
            }
        }
    }
    
    private func attemptExtractText(from imageData: Data, sessionId: UUID? = nil) async throws -> String {
        // Create UIImage from data and delegate to optimized method
        guard let originalUIImage = UIImage(data: imageData) else {
            throw PreprocessingError.invalidImageData
        }
        return try await attemptExtractText(from: originalUIImage, sessionId: sessionId)
    }
    
    // MARK: - Optimized method for pre-processed images
    private func attemptExtractText(from originalUIImage: UIImage, sessionId: UUID? = nil) async throws -> String {
        let settings = GeminiService.getSettings()

        guard let apiKey = settings.apiKey, !apiKey.isEmpty else {
            throw APIError.missingApiKey
        }
        guard let apiBaseUrl = settings.apiEndpointUrl else {
             throw APIError.invalidApiEndpoint(settings.apiEndpointUrl?.absoluteString ?? "<empty>")
         }
        guard let model = settings.modelToUse else {
            throw APIError.missingModelConfiguration
        }
        let basePrompt = settings.prompt
        let thinkingEnabled = settings.thinkingEnabled
        
        // Create model info for performance logging (will be updated with image metadata later)
        let modelInfoConfiguration = [
            "thinking_enabled": String(thinkingEnabled),
            "endpoint": apiBaseUrl.absoluteString
        ]
        
        // Use base prompt directly - thinking is enabled via API parameter, not prompt text
        let prompt = basePrompt
        // Quality setting is not currently user-configurable, use a default
        let heicQuality: CGFloat = 0.6 // Set to 0.6 as requested

        // Capture original image metadata
        let originalSize = originalUIImage.size
        let originalImageData = originalUIImage.jpegData(compressionQuality: 1.0) ?? Data()
        let originalFileSizeBytes = originalImageData.count

        // 1. Prepare Image using the new ImageProcessor workflow
        let preparedImageData: Data
        let resizedUIImage: UIImage
        do {
            // Use specific target dimensions
            print("GeminiService: Using target image dimensions: \(targetImageWidth)x\(targetImageHeight)")

            // Resize the UIImage using the Core Image based method
            resizedUIImage = try imageProcessor.resizeImageToDimensions(originalUIImage, targetWidth: targetImageWidth, targetHeight: targetImageHeight)

            // Encode the resized UIImage to HEIC
            preparedImageData = try imageProcessor.encodeToHEICData(resizedUIImage, compressionQuality: heicQuality)

        } catch let error as PreprocessingError {
            // Map PreprocessingError to APIError.preprocessingFailed
            throw APIError.preprocessingFailed(reason: error.localizedDescription)
        } catch {
            // Catch other potential errors during image processing
            throw APIError.preprocessingFailed(reason: "An unexpected error occurred during image preparation: \(error.localizedDescription)")
        }
        
        // Create image metadata for performance logging
        let imageMetadata = ImageMetadata(
            originalWidth: originalSize.width,
            originalHeight: originalSize.height,
            processedWidth: resizedUIImage.size.width,
            processedHeight: resizedUIImage.size.height,
            originalFileSizeBytes: originalFileSizeBytes,
            processedFileSizeBytes: preparedImageData.count,
            compressionQuality: heicQuality,
            imageFormat: "HEIC"
        )
        let base64ImageString = preparedImageData.base64EncodedString()

        // 2. Construct Request
        let requestUrl = apiBaseUrl.appendingPathComponent("\(model):generateContent")
        guard let finalUrl = Self.buildURLWithAPIKey(baseURL: requestUrl, apiKey: apiKey) else {
            throw APIError.invalidApiEndpoint("Failed to append API key to URL")
        }
        
        var request = URLRequest(url: finalUrl)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30.0

        let requestBody = createRequestBody(prompt: prompt, base64Image: base64ImageString, thinkingEnabled: thinkingEnabled, model: model)
        request.httpBody = try JSONEncoder().encode(requestBody)

        // 3. Perform Network Request
        let (data, response) = try await performRequest(
            request: request,
            model: model,
            sessionId: sessionId,
            modelInfoConfiguration: modelInfoConfiguration,
            imageMetadata: imageMetadata
        )
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }
        
        // 4. Handle Response
        return try handleResponse(httpResponse: httpResponse, data: data, model: model)
    }
    
    // MARK: - Network Request Helper
    
    private func performRequest(
        request: URLRequest,
        model: String,
        sessionId: UUID?,
        modelInfoConfiguration: [String: String],
        imageMetadata: ImageMetadata
    ) async throws -> (Data, URLResponse) {
        if let sessionId = sessionId {
            let modelInfo = ModelInfo(
                serviceName: "Gemini",
                modelName: model,
                configuration: modelInfoConfiguration,
                imageMetadata: imageMetadata
            )
            
            return try await PerformanceLogger.shared.measureOperation(
                "Gemini API Request (\(model))",
                sessionId: sessionId,
                modelInfo: modelInfo
            ) {
                try await URLSession.shared.data(for: request)
            }
        } else {
            return try await URLSession.shared.data(for: request)
        }
    }
    
    // MARK: - Response Handler
    
    private func handleResponse(httpResponse: HTTPURLResponse, data: Data, model: String) throws -> String {
        switch httpResponse.statusCode {
        case 200...299:
            let decodedResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)
            let allPartsText = decodedResponse.candidates?.first?.content?.parts?
                .compactMap { $0.text }
                .joined(separator: "\n\n")
            
            guard let text = allPartsText, !text.isEmpty else {
                throw APIError.noTextFound
            }
            return text
            
        case 400:
            throw APIError.badRequest(String(data: data, encoding: .utf8))
        case 401, 403:
            throw APIError.authenticationError
        case 404:
            throw APIError.modelNotFound(model)
        case 429:
            throw APIError.rateLimitExceeded
        case 503:
            throw APIError.serviceUnavailable
        case 500...599:
            throw APIError.serverError(httpResponse.statusCode)
        default:
            throw APIError.unknownError(httpResponse.statusCode)
        }
    }

    // MARK: - Optimized method for pre-processed images
    func extractText(from processedImage: UIImage, sessionId: UUID? = nil) async throws -> String {
        return try await attemptExtractText(from: processedImage, sessionId: sessionId)
    }

    // MARK: - Request Body Construction

    private func createRequestBody(prompt: String, base64Image: String, thinkingEnabled: Bool, model: String) -> GeminiRequest {
        // Construct the request body based on API documentation
        let imagePart = GeminiRequest.Part(inlineData: GeminiRequest.Part.InlineData(mimeType: "image/heic", data: base64Image))
        let textPart = GeminiRequest.Part(text: prompt)
        
        // Only include thinking_config if thinking is enabled AND model supports it
        let generationConfig: GeminiRequest.GenerationConfig?
        if thinkingEnabled && modelSupportsThinking(model) {
            let thinkingConfig = GeminiRequest.GenerationConfig.ThinkingConfig(thinkingBudget: nil)
            generationConfig = GeminiRequest.GenerationConfig(thinkingConfig: thinkingConfig)
        } else {
            generationConfig = nil
        }
        
        return GeminiRequest(contents: [GeminiRequest.Content(parts: [textPart, imagePart])], generationConfig: generationConfig)
    }
    
    // Check if model supports thinking (2.5+ series models)
    private func modelSupportsThinking(_ model: String) -> Bool {
        let modelLower = model.lowercased()
        
        // Match 2.5 and higher versions (2.5, 2.6, 3.0, etc.)
        // Pattern: gemini-X.Y where X >= 2 and (X > 2 OR Y >= 5)
        if let range = modelLower.range(of: #"gemini-(\d+)\.(\d+)"#, options: .regularExpression) {
            let versionString = String(modelLower[range])
            let components = versionString.replacingOccurrences(of: "gemini-", with: "").split(separator: ".")
            
            if components.count >= 2,
               let major = Int(components[0]),
               let minor = Int(components[1]) {
                return major > 2 || (major == 2 && minor >= 5)
            }
        }
        
        return false
    }
}

// MARK: - Codable Structs for API Request/Response

struct GeminiRequest: Codable {
    struct Content: Codable {
        let parts: [Part]
    }

    struct Part: Codable {
        let text: String?
        let inlineData: InlineData?

         init(text: String) {
             self.text = text
             self.inlineData = nil
         }

         init(inlineData: InlineData) {
             self.text = nil
             self.inlineData = inlineData
         }

        struct InlineData: Codable {
            let mimeType: String
            let data: String // Base64 encoded data

             enum CodingKeys: String, CodingKey {
                 case mimeType = "mime_type"
                 case data
             }
        }
    }
    
    struct GenerationConfig: Codable {
        let thinkingConfig: ThinkingConfig?
        
        struct ThinkingConfig: Codable {
            let thinkingBudget: Int?
            
            enum CodingKeys: String, CodingKey {
                case thinkingBudget = "thinking_budget"
            }
        }
        
        enum CodingKeys: String, CodingKey {
            case thinkingConfig = "thinking_config"
        }
    }

    let contents: [Content]
    let generationConfig: GenerationConfig?
    
    enum CodingKeys: String, CodingKey {
        case contents
        case generationConfig = "generation_config"
    }
}

struct GeminiResponse: Codable {
    struct Candidate: Codable {
        let content: Content?
    }

    struct Content: Codable {
        let parts: [Part]?
    }

    struct Part: Codable {
        let text: String?
    }

    let candidates: [Candidate]?
}

// MARK: - Custom API Errors
enum APIError: LocalizedError {
    case missingApiKey
    case invalidApiEndpoint(String)
    case missingModelConfiguration
    case modelNotFound(String) // New error for 404s
    case imageProcessingFailed
    case requestEncodingFailed(Error)
    case networkError(Error)
    case badRequest(String?) // Include details if available
    case authenticationError // 401, 403
    case rateLimitExceeded // 429
    case serverError(Int)
    case serviceUnavailable // 503
    case responseDecodingFailed(Error)
    case noTextFound
    case unknownError(Int)
    case preprocessingFailed(reason: String)

    var errorDescription: String? {
        switch self {
        case .missingApiKey:
            return "API Key is missing. Please set it in Settings."
        case .invalidApiEndpoint(let endpoint):
            return "Invalid API Endpoint URL configured: \(endpoint)"
        case .missingModelConfiguration:
            return "No valid model configured. Please select or enter a model in Settings."
        case .modelNotFound(let modelName):
            return "Model '\(modelName)' not found. The model may have been deprecated or renamed. Try refreshing the models list in Settings."
        case .imageProcessingFailed:
            return "Failed to process the image for the API."
        case .requestEncodingFailed(let error):
            return "Failed to encode the API request: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network request failed: \(error.localizedDescription)"
        case .badRequest(let detail):
            var message = "Bad request (400)."
            if let detail = detail, !detail.isEmpty {
                message += " Details: \(detail)"
            } else {
                 message += " Check API Key, model name, and request format."
             }
            return message
         case .authenticationError:
             return "Authentication failed (401/403). Check your API Key."
         case .rateLimitExceeded:
             return "API rate limit exceeded (429). Please try again later."
        case .serverError(let statusCode):
            return "API server error (\(statusCode)). Please try again later."
        case .serviceUnavailable:
            return "Gemini service is temporarily unavailable (503). The app will automatically retry a few times. If this persists, Google's servers may be experiencing maintenance or high load."
        case .responseDecodingFailed(let error):
            return "Failed to decode the API response: \(error.localizedDescription)"
        case .noTextFound:
            return "No text could be extracted from the image by the API."
        case .unknownError(let statusCode):
            return "An unknown API error occurred (Status Code: \(statusCode))."
        case .preprocessingFailed(let reason):
            // Use the specific reason from the wrapped PreprocessingError
            return "Image processing failed: \(reason)"
        }
    }
}



// MARK: - Network Reachability Helper

import SystemConfiguration
import Network

class Reachability {
    enum Connection {
        case wifi
        case cellular
        case unavailable
    }
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    private var _connection: Connection = .unavailable
    
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            if path.status == .satisfied {
                if path.usesInterfaceType(.cellular) {
                    self?._connection = .cellular
                } else if path.usesInterfaceType(.wifi) {
                    self?._connection = .wifi
                } else {
                    // Other connection types like wired, loopback
                    self?._connection = .wifi
                }
            } else {
                self?._connection = .unavailable
            }
        }
        monitor.start(queue: queue)
    }
    
    deinit {
        monitor.cancel()
    }
    
    var connection: Connection {
        // For simplicity, check synchronously - for a more robust implementation,
        // you might want to add callbacks for connection changes
        return _connection
    }
}

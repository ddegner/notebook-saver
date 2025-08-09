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
        
        // The base URL already ends with "models/", so we don't append "models" again
        let modelsUrl = baseUrl
        var request = URLRequest(url: modelsUrl)
        request.httpMethod = "GET"
        request.timeoutInterval = 30.0
        
        // Use query parameter for API key (consistent with other Gemini API calls)
        var urlComponents = URLComponents(url: modelsUrl, resolvingAgainstBaseURL: false)
        urlComponents?.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        
        guard let finalUrl = urlComponents?.url else {
            throw APIError.invalidApiEndpoint("Failed to construct URL with API key")
        }
        request.url = finalUrl
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }
        
        // Handle 401 specifically for better error messaging
        if httpResponse.statusCode == 401 {
            throw APIError.authenticationError
        }
        
        guard httpResponse.statusCode == 200 else {
            throw APIError.serverError(httpResponse.statusCode)
        }
        
        let modelsResponse = try JSONDecoder().decode(GeminiModelsResponse.self, from: data)
        guard let apiModels = modelsResponse.models else {
            return getDefaultModelIds()
        }
        
        let models = convertToModelIds(apiModels)
        await cacheModelIds(models)
        
        return models
    }
    
    // Convert API response to model ID strings
    private func convertToModelIds(_ apiModels: [GeminiModelInfo]) -> [String] {
        var modelIds: [String] = []
        
        for apiModel in apiModels {
            // Extract model name from the full path (e.g., "models/gemini-2.5-flash" -> "gemini-2.5-flash")
            let modelName = apiModel.name.replacingOccurrences(of: "models/", with: "")
            
            // Skip certain models (embedding, etc.)
            if modelName.contains("embedding") || modelName.contains("imagen") || modelName.contains("veo") {
                continue
            }
            
            // Only include known models
            switch modelName {
            case "gemini-2.5-flash", "gemini-2.5-flash-lite", "gemini-2.5-pro", "gemini-2.0-flash", 
                 "gemini-1.5-pro", "gemini-1.5-flash", "gemini-1.5-flash-8b":
                modelIds.append(modelName)
            default:
                // Skip unknown models
                break
            }
        }
        
        return modelIds
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
            "gemini-2.5-flash",
            "gemini-2.5-flash-lite", 
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

// MARK: - Existing GeminiService class continues below...
class GeminiService: ImageTextExtractor /*: APIServiceProtocol*/ {
    // Track if connection has been verified to avoid redundant warm-ups
    private static var connectionVerified = false

    // Defaults
    private let defaultModelId = "gemini-2.5-flash" // Default model if nothing is set
    private static let defaultApiEndpoint = "https://generativelanguage.googleapis.com/v1beta/models/"
    private let defaultDraftsTag = "notebook"

    private let highMaxImageDimension: CGFloat = 1280.0 // Reduced for faster upload
    
    // Retry configuration
    private let maxRetryAttempts = 2 // Reduced from 3 for faster failure detection
    private let initialRetryDelay: TimeInterval = 0.5 // Reduced from 1.0 for faster retries

    // Instantiate the shared preprocessor - RENAME to ImageProcessor
    private let imageProcessor = ImageProcessor()

    // Helper to get settings from UserDefaults
    static func getSettings() -> (apiKey: String?, apiEndpointUrl: URL?, modelToUse: String?, prompt: String?, draftsTag: String, thinkingEnabled: Bool) {
        let defaults = UserDefaults.standard

        let apiKey = KeychainService.loadAPIKey()

        let endpointString = defaults.string(forKey: "apiEndpointUrlString") ?? GeminiService.defaultApiEndpoint
        let apiEndpointUrl = URL(string: endpointString)

        let selectedId = defaults.string(forKey: "selectedModelId") ?? "gemini-2.5-flash"
        var modelToUse: String?
        if selectedId == "Custom" {
            modelToUse = defaults.string(forKey: "customModelName")?.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            modelToUse = selectedId
        }
        if modelToUse?.isEmpty ?? true {
            modelToUse = nil // Treat empty custom model as invalid
        }

        let prompt = defaults.string(forKey: "userPrompt")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let validPrompt = (prompt?.isEmpty == false) ? prompt : nil
        let draftsTag = defaults.string(forKey: "draftsTag") ?? "notebook"
        let thinkingEnabled = defaults.bool(forKey: "thinkingEnabled")

        return (apiKey, apiEndpointUrl, modelToUse, validPrompt, draftsTag, thinkingEnabled)
    }

    // MARK: - Connection Warming

    public static func warmUpConnection() async -> Bool {
        print("GeminiService: Warming up exact generateContent endpoint...")
        let settings = GeminiService.getSettings()

        guard let apiKey = settings.apiKey, !apiKey.isEmpty else {
            print("GeminiService (WarmUp): API Key is missing. Skipping warm-up.")
            return false
        }
        guard let baseUrl = settings.apiEndpointUrl else {
            print("GeminiService (WarmUp): Invalid API Endpoint URL.")
            return false
        }
        guard let model = settings.modelToUse, !model.isEmpty else {
            print("GeminiService (WarmUp): No model configured. Skipping warm-up.")
            return false
        }

        // Build exact generateContent URL for the configured model
        let requestUrl = baseUrl.appendingPathComponent("\(model):generateContent")
        var request = URLRequest(url: requestUrl)
        request.httpMethod = "POST"
        request.timeoutInterval = 10.0

        var urlComponents = URLComponents(url: requestUrl, resolvingAgainstBaseURL: false)
        urlComponents?.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let finalUrl = urlComponents?.url else {
            print("GeminiService (WarmUp): Failed to append API key to URL.")
            return false
        }
        request.url = finalUrl
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        // Minimal text-only request with temperature 0 and tiny output to reduce cost/time
        let warmupBody = GeminiRequest(
            contents: [GeminiRequest.Content(parts: [GeminiRequest.Part(text: "ping")])],
            generationConfig: GeminiRequest.GenerationConfig(temperature: 0, maxOutputTokens: 1)
        )

        do {
            let jsonData = try JSONEncoder().encode(warmupBody)
            request.httpBody = jsonData
        } catch {
            print("GeminiService (WarmUp): Failed to encode warm-up request: \(error.localizedDescription)")
            return false
        }

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                print("GeminiService (WarmUp): Invalid response type.")
                return false
            }
            if (200...299).contains(httpResponse.statusCode) {
                print("GeminiService (WarmUp): Ready (Status: \(httpResponse.statusCode)).")
                connectionVerified = true
                return true
            } else {
                print("GeminiService (WarmUp): Warm-up failed (Status: \(httpResponse.statusCode)).")
                connectionVerified = false
                return false
            }
        } catch {
            print("GeminiService (WarmUp): Network error: \(error.localizedDescription)")
            connectionVerified = false
            return false
        }
    }

    // MARK: - Public API

    func extractText(from imageData: Data) async throws -> String {
        var retryCount = 0
        
        // Function to implement exponential backoff
        func calculateBackoff(attempt: Int) -> TimeInterval {
            return initialRetryDelay * pow(2.0, Double(attempt))
        }
        
        // Keep retrying until max attempts reached
        while true {
            do {
                return try await attemptExtractText(from: imageData)
            } catch APIError.serviceUnavailable where retryCount < maxRetryAttempts {
                retryCount += 1
                let delay = calculateBackoff(attempt: retryCount - 1)
                print("GeminiService: API Service Unavailable (503). Implementing exponential backoff.")
                print("GeminiService: Retry \(retryCount)/\(maxRetryAttempts) will occur after \(String(format: "%.2f", delay))s")
                
                // Check network connectivity before retrying
                let reachability = Reachability()
                print("GeminiService: Network status before retry: \(reachability.connection == .unavailable ? "Offline" : "Online")")
                
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                print("GeminiService: Executing retry attempt \(retryCount)...")
                continue
            } catch APIError.serverError where retryCount < maxRetryAttempts {
                retryCount += 1
                let delay = calculateBackoff(attempt: retryCount - 1)
                print("GeminiService: API Server Error (5xx). Implementing exponential backoff.")
                print("GeminiService: Retry \(retryCount)/\(maxRetryAttempts) will occur after \(String(format: "%.2f", delay))s")
                
                // Check network connectivity before retrying
                let reachability = Reachability()
                print("GeminiService: Network status before retry: \(reachability.connection == .unavailable ? "Offline" : "Online")")
                
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                print("GeminiService: Executing retry attempt \(retryCount)...")
                continue
            } catch {
                throw error
            }
        }
    }
    
    private func attemptExtractText(from imageData: Data) async throws -> String {
        // Create UIImage from data and delegate to optimized method
        guard let originalUIImage = UIImage(data: imageData) else {
            throw PreprocessingError.invalidImageData
        }
        return try await attemptExtractText(from: originalUIImage)
    }
    
    // MARK: - Optimized method for pre-processed images
    private func attemptExtractText(from originalUIImage: UIImage) async throws -> String {
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
        guard let basePrompt = settings.prompt else {
            throw APIError.missingPromptConfiguration
        }
        let thinkingEnabled = settings.thinkingEnabled
        
        // Add thinking directives to the prompt if thinking is enabled
        let prompt: String
        if thinkingEnabled {
            prompt = """
                THINKING: on
                REASONING: on
                PLANNING: on
                
                Take time to think through the image carefully. Analyze the content thoroughly and provide thoughtful, accurate text extraction.
                
                \(basePrompt)
                """
        } else {
            prompt = basePrompt
        }
        // Quality setting is not currently user-configurable, use a default
        let heicQuality: CGFloat = 0.5 // Set to 0.5 as requested

        // 1. Prepare Image using the new ImageProcessor workflow
        let preparedImageData: Data
        do {
            // Use the high resolution max dimension
            let maxDimension = highMaxImageDimension
            print("GeminiService: Using max image dimension: \(maxDimension)")

            // Resize the UIImage using the Core Image based method
            let resizedUIImage = try imageProcessor.resizeImage(originalUIImage, maxDimension: maxDimension)

            // Encode the resized UIImage to HEIC
            preparedImageData = try imageProcessor.encodeToHEICData(resizedUIImage, compressionQuality: heicQuality)

        } catch let error as PreprocessingError {
            // Map PreprocessingError to APIError.preprocessingFailed
            throw APIError.preprocessingFailed(reason: error.localizedDescription)
        } catch {
            // Catch other potential errors during image processing
            throw APIError.preprocessingFailed(reason: "An unexpected error occurred during image preparation: \(error.localizedDescription)")
        }
        let base64ImageString = preparedImageData.base64EncodedString()

        // 2. Construct Request
        // Append model and action to the base URL
        let requestUrl = apiBaseUrl.appendingPathComponent("\(model):generateContent")
        var request = URLRequest(url: requestUrl)

        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30.0 // Add 30-second timeout to prevent hanging requests
        // Add API Key
        // Note: Ensure the key placement (header vs query param) matches the API requirements
        // Using query parameter for simplicity, header is often preferred.
        var urlComponents = URLComponents(url: requestUrl, resolvingAgainstBaseURL: false)
        urlComponents?.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let finalUrl = urlComponents?.url else {
             throw APIError.invalidApiEndpoint("Failed to append API key to URL")
         }
        request.url = finalUrl
        // If using header: request.addValue("x-goog-api-key", forHTTPHeaderField: apiKey)

        let requestBody = createRequestBody(prompt: prompt, base64Image: base64ImageString)

        do {
            let jsonData = try JSONEncoder().encode(requestBody)
            request.httpBody = jsonData
        } catch {
            throw APIError.requestEncodingFailed(error)
        }

        // 3. Perform Network Request
        do {
            print("GeminiService: Sending request to API...")
            print("GeminiService: Target model: \(model)")
            print("GeminiService: Image size: \(preparedImageData.count) bytes")
            
            let startTime = Date()
            let (data, response) = try await URLSession.shared.data(for: request)
            let requestDuration = Date().timeIntervalSince(startTime)

            guard let httpResponse = response as? HTTPURLResponse else {
                print("GeminiService: Invalid response type received")
                throw APIError.networkError(URLError(.badServerResponse))
            }

            print("GeminiService: Received response with status code: \(httpResponse.statusCode) in \(String(format: "%.2f", requestDuration))s")
            
            // Log headers for troubleshooting
            print("GeminiService: Response Headers: \(httpResponse.allHeaderFields)")
            
            // Debug log response body for error cases
            if httpResponse.statusCode >= 400 {
                print("GeminiService: Error Response Body: \(String(data: data, encoding: .utf8) ?? "Invalid response data")")
            }

            // 4. Handle Response
            switch httpResponse.statusCode {
            case 200...299:
                do {
                    let decodedResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)

                    // The Gemini API might split the response text into multiple parts
                    // within the first candidate's content.
                    // We need to concatenate the text from all parts to ensure the full result is captured.
                    let allPartsText = decodedResponse.candidates?.first?.content?.parts?
                        .compactMap { $0.text }
                        .joined(separator: "\n\n")

                    guard let text = allPartsText, !text.isEmpty else {
                        throw APIError.noTextFound
                    }

                    print("Successfully extracted text from API.")
                    return text
                } catch {
                    throw APIError.responseDecodingFailed(error)
                }
            case 400:
                 // Check response body for specific error message if possible
                 let errorDetail = String(data: data, encoding: .utf8)
                 throw APIError.badRequest(errorDetail)
            case 401, 403:
                 throw APIError.authenticationError
            case 404:
                // Model not found - suggest refreshing models list
                throw APIError.modelNotFound(model)
             case 429:
                 throw APIError.rateLimitExceeded
            case 503:
                print("GeminiService: Service Unavailable (503) - The Gemini API service is temporarily down or overloaded")
                throw APIError.serviceUnavailable
            case 500...599:
                print("GeminiService: Server Error (\(httpResponse.statusCode)) - Details: \(String(data: data, encoding: .utf8) ?? "No details available")")
                throw APIError.serverError(httpResponse.statusCode)
            default:
                throw APIError.unknownError(httpResponse.statusCode)
            }
        } catch let error as APIError {
             print("API Error: \(error.localizedDescription)")
             throw error // Re-throw specific API errors
         } catch {
             print("Network or Unknown Error: \(error.localizedDescription)")
            throw APIError.networkError(error)
        }
    }

    // MARK: - Optimized method for pre-processed images
    func extractText(from processedImage: UIImage) async throws -> String {
        return try await attemptExtractText(from: processedImage)
    }

    // MARK: - Request Body Construction

    private func createRequestBody(prompt: String, base64Image: String?) -> GeminiRequest {
        var parts: [GeminiRequest.Part] = [GeminiRequest.Part(text: prompt)]
        if let base64 = base64Image {
            parts.append(GeminiRequest.Part(inlineData: GeminiRequest.Part.InlineData(mimeType: "image/heic", data: base64)))
        }
        return GeminiRequest(
            contents: [GeminiRequest.Content(parts: parts)],
            generationConfig: GeminiRequest.GenerationConfig(temperature: 0, maxOutputTokens: nil)
        )
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
        let temperature: Double?
        let maxOutputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case temperature
            case maxOutputTokens = "max_output_tokens"
        }
    }

    let contents: [Content]
    let generationConfig: GenerationConfig?
    // thinkingBudget not supported in current API version
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
    case missingPromptConfiguration
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
        case .missingPromptConfiguration:
            return "No prompt configured. Please set a prompt in Settings to tell the AI how to process your images."
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

// MARK: - Data Extension Helper

extension Data {
    var isJPEG: Bool {
        guard count >= 2 else { return false }
        // Check for JPEG magic bytes FF D8
        return self[0] == 0xFF && self[1] == 0xD8
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

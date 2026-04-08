import Foundation
import SwiftUI // For @Published
import UIKit // For UIImage
import CoreImage // Import Core Image

enum ScanMode: String, CaseIterable, Identifiable {
    case fast = "fast"
    case precise = "precise"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fast: return "Fast"
        case .precise: return "Precise"
        }
    }

    var iconName: String {
        switch self {
        case .fast: return "hare"
        case .precise: return "magnifyingglass"
        }
    }
}

enum GeminiPhotoTokenBudget: String, CaseIterable, Identifiable {
    case unspecified = "MEDIA_RESOLUTION_UNSPECIFIED"
    case low = "MEDIA_RESOLUTION_LOW"
    case medium = "MEDIA_RESOLUTION_MEDIUM"
    case high = "MEDIA_RESOLUTION_HIGH"
    case ultraHigh = "MEDIA_RESOLUTION_ULTRA_HIGH"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .unspecified:
            return "Auto (Default)"
        case .low:
            return "Low (280 tokens)"
        case .medium:
            return "Medium (560 tokens)"
        case .high:
            return "High (1120 tokens)"
        case .ultraHigh:
            return "Ultra High (2240 tokens)"
        }
    }
}

enum GeminiThinkingLevel: String, CaseIterable, Identifiable {
    case none = "none"
    case minimal = "minimal"
    case low = "low"
    case medium = "medium"
    case high = "high"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "Off"
        case .minimal: return "Minimal"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }
}

class GeminiService: ImageTextExtractor {
    // Track if connection has been verified to avoid redundant warm-ups
    nonisolated(unsafe) private static var connectionVerified = false

    // Defaults
    private let defaultModelId = "gemini-3.1-flash-lite-preview" // Default model if nothing is set
    static let defaultPrompt = """
        You are an expert at reading handwritten notes. Follow these rules:
        - Return a JSON object with a single key "lines" containing an array of strings, one per line of text.
        - Transcribe EVERY piece of handwritten text visible in the image, including titles, margin notes, and annotations.
        - Do NOT skip any text, even if it appears small or unimportant.
        - This is handwritten text — pay extra attention to letter shapes and context to distinguish similar-looking letters (e.g. a/o, u/n, r/v, t/l).
        - Use surrounding words and sentence context to resolve ambiguous letters.
        - Identify the language and script automatically.
        - Preserve the original script — do not transliterate to Latin characters.
        - Preserve original wording, spelling, punctuation, and order.
        - If any text is unreadable, make your best guess based on context.
        - If anything is scratched out, ignore it.
        - Do not summarize or add content.
        """
    static let defaultUserMessagePrompt = "Transcribe ALL handwritten text from this notebook page. Include every line, title, annotation, and margin note. Do not skip anything."
    private static let defaultApiEndpoint = "https://generativelanguage.googleapis.com/v1beta/models/"
    private let defaultDraftsTag = "notebook"

    private var targetImageLongEdge: CGFloat {
        let defaults = SharedDefaults.suite
        let useCustom = defaults.bool(forKey: SettingsKey.useCustomSettings)
        if !useCustom {
            let modeRaw = defaults.string(forKey: SettingsKey.scanMode) ?? ScanMode.fast.rawValue
            let mode = ScanMode(rawValue: modeRaw) ?? .fast
            return mode == .precise ? 3456.0 : 2304.0
        }
        return 2304.0 // Custom mode uses standard resolution
    }
    
    // Retry configuration
    private let maxRetryAttempts = 2 // Reduced from 3 for faster failure detection
    private let initialRetryDelay: TimeInterval = 0.5 // Reduced from 1.0 for faster retries

    private let imageProcessor = ImageProcessor()

    // Helper to get settings from UserDefaults
    static func getSettings() -> (apiKey: String?, apiEndpointUrl: URL?, modelToUse: String?, systemPrompt: String, userMessagePrompt: String, draftsTag: String, thinkingLevel: GeminiThinkingLevel, photoTokenBudget: GeminiPhotoTokenBudget) {
        let defaults = SharedDefaults.suite

        let apiKey = KeychainService.loadAPIKey()

        let endpointString = defaults.string(forKey: SettingsKey.apiEndpointUrlString) ?? GeminiService.defaultApiEndpoint
        let apiEndpointUrl = URL(string: endpointString)

        let systemPrompt = defaults.string(forKey: SettingsKey.userPrompt) ?? GeminiService.defaultPrompt
        let userMessagePrompt = defaults.string(forKey: SettingsKey.userMessagePrompt) ?? GeminiService.defaultUserMessagePrompt
        let draftsTag = defaults.string(forKey: SettingsKey.draftsTag) ?? "notebook"

        let useCustomSettings = defaults.bool(forKey: SettingsKey.useCustomSettings)

        if useCustomSettings {
            // Custom mode: use all stored individual settings
            let selectedId = defaults.string(forKey: SettingsKey.selectedModelId) ?? "gemini-2.5-flash-lite"
            var modelToUse: String?
            if selectedId == "Custom" {
                modelToUse = defaults.string(forKey: "customModelName")?.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                modelToUse = selectedId
            }
            if modelToUse?.isEmpty ?? true {
                modelToUse = nil
            }

            let thinkingLevelRaw = defaults.string(forKey: SettingsKey.thinkingLevel) ?? GeminiThinkingLevel.none.rawValue
            let thinkingLevel = GeminiThinkingLevel(rawValue: thinkingLevelRaw) ?? .none
            let budgetRaw = defaults.string(forKey: SettingsKey.geminiPhotoTokenBudget) ?? GeminiPhotoTokenBudget.medium.rawValue
            let photoTokenBudget = GeminiPhotoTokenBudget(rawValue: budgetRaw) ?? .medium

            return (apiKey, apiEndpointUrl, modelToUse, systemPrompt, userMessagePrompt, draftsTag, thinkingLevel, photoTokenBudget)
        } else {
            // Preset mode: hardcoded settings based on scan mode
            let modeRaw = defaults.string(forKey: SettingsKey.scanMode) ?? ScanMode.fast.rawValue
            let mode = ScanMode(rawValue: modeRaw) ?? .fast

            let modelToUse: String
            let thinkingLevel: GeminiThinkingLevel
            let photoTokenBudget: GeminiPhotoTokenBudget

            switch mode {
            case .fast:
                modelToUse = "gemini-3.1-flash-lite-preview"
                thinkingLevel = .none
                photoTokenBudget = .medium
            case .precise:
                modelToUse = "gemini-3.1-pro-preview"
                thinkingLevel = .medium
                photoTokenBudget = .high
            }

            return (apiKey, apiEndpointUrl, modelToUse, systemPrompt, userMessagePrompt, draftsTag, thinkingLevel, photoTokenBudget)
        }
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
        let endpointString = SharedDefaults.suite.string(forKey: SettingsKey.apiEndpointUrlString) ?? defaultApiEndpoint
        
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
                    case .serviceUnavailable, .serverError, .networkError:
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
        let systemPrompt = settings.systemPrompt
        let userMessagePrompt = settings.userMessagePrompt
        let thinkingLevel = settings.thinkingLevel
        let photoTokenBudget = settings.photoTokenBudget

        // Create model info for performance logging (will be updated with image metadata later)
        var modelInfoConfiguration = [
            "thinking_level": thinkingLevel.rawValue,
            "endpoint": apiBaseUrl.absoluteString
        ]
        if isGemini3Model(model) {
            modelInfoConfiguration["photo_token_budget"] = photoTokenBudget.rawValue
        }
        // JPEG 0.50 produces identical OCR quality to 0.80 at 2304px resolution
        // while cutting file size ~53% (838KB → 394KB avg). Verified across 7 test images.
        let jpegQuality: CGFloat = 0.50
        let prepTimingToken = sessionId.flatMap { PerformanceLogger.shared.startTiming("Gemini Image Preparation", sessionId: $0) }
        let imageMetadata: ImageMetadata
        let base64ImageString: String
        do {
            // Capture original image metadata
            let originalSize = originalUIImage.size
            // Estimate original size from pixel dimensions (avoids expensive full-res JPEG encode
            // that was only used for logging — ~50-100ms wasted on 12MP photos)
            let originalFileSizeBytes = Int(originalSize.width * originalSize.height) * 3 // ~RGB estimate

            // 1. Prepare Image using the new ImageProcessor workflow
            let originalW = max(originalSize.width, CGFloat(1))
            let originalH = max(originalSize.height, CGFloat(1))
            let longEdge = targetImageLongEdge

            // Compute orientation-aware target box that preserves aspect ratio
            let targetW: CGFloat
            let targetH: CGFloat
            if originalW >= originalH {
                // Landscape: long edge maps to width
                targetW = longEdge
                targetH = max(CGFloat(1), floor(longEdge * (originalH / originalW)))
            } else {
                // Portrait: long edge maps to height
                targetH = longEdge
                targetW = max(CGFloat(1), floor(longEdge * (originalW / originalH)))
            }

            print("GeminiService: Using target image long edge: \(Int(longEdge)) -> \(Int(targetW))x\(Int(targetH))")

            // Resize using the computed target box (uniform scaling inside the processor)
            let resizedUIImage = try imageProcessor.resizeImageToDimensions(originalUIImage, targetWidth: targetW, targetHeight: targetH)

            // Encode the resized UIImage to JPEG
            guard let preparedImageData = resizedUIImage.jpegData(compressionQuality: jpegQuality) else {
                throw PreprocessingError.encodingFailed(nil)
            }

            // Create image metadata for performance logging
            // Get actual pixel dimensions from CGImage, not logical UIImage size
            let processedPixelWidth = resizedUIImage.cgImage?.width ?? Int(resizedUIImage.size.width * resizedUIImage.scale)
            let processedPixelHeight = resizedUIImage.cgImage?.height ?? Int(resizedUIImage.size.height * resizedUIImage.scale)

            let localImageMetadata = ImageMetadata(
                originalWidth: originalSize.width,
                originalHeight: originalSize.height,
                processedWidth: CGFloat(processedPixelWidth),
                processedHeight: CGFloat(processedPixelHeight),
                originalFileSizeBytes: originalFileSizeBytes,
                processedFileSizeBytes: preparedImageData.count,
                compressionQuality: jpegQuality,
                imageFormat: "JPEG"
            )
            imageMetadata = localImageMetadata
            base64ImageString = preparedImageData.base64EncodedString()

            if let prepTimingToken {
                let prepModelInfo = ModelInfo(
                    serviceName: "Gemini",
                    modelName: model,
                    configuration: modelInfoConfiguration,
                    imageMetadata: localImageMetadata
                )
                PerformanceLogger.shared.endTiming(prepTimingToken, modelInfo: prepModelInfo, success: true)
            }
        } catch {
            if let prepTimingToken {
                PerformanceLogger.shared.endTiming(prepTimingToken, error: error)
            }
            throw error
        }

        // 2. Construct Request
        let requestUrl = apiBaseUrl.appendingPathComponent("\(model):generateContent")
        guard let finalUrl = Self.buildURLWithAPIKey(baseURL: requestUrl, apiKey: apiKey) else {
            throw APIError.invalidApiEndpoint("Failed to append API key to URL")
        }
        
        var request = URLRequest(url: finalUrl)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60.0

        let requestBody = createRequestBody(
            systemPrompt: systemPrompt,
            userMessagePrompt: userMessagePrompt,
            base64Image: base64ImageString,
            thinkingLevel: thinkingLevel,
            model: model,
            photoTokenBudget: photoTokenBudget
        )
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
    
    // Hard deadline for the API request — URLRequest.timeoutInterval only covers idle time,
    // so a server that trickles data can keep the request alive indefinitely.
    // Flash-lite normally responds in 2-4s; 30s is generous enough for retries while
    // preventing the 40s-1800s stalls seen in production logs.
    private static let requestDeadline: TimeInterval = 30.0

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

            let deadline = Self.requestDeadline
            return try await PerformanceLogger.shared.measureOperation(
                "Gemini API Request (\(model))",
                sessionId: sessionId,
                modelInfo: modelInfo
            ) {
                try await GeminiService.withDeadline(deadline) {
                    try await URLSession.shared.data(for: request)
                }
            }
        } else {
            return try await GeminiService.withDeadline(Self.requestDeadline) {
                try await URLSession.shared.data(for: request)
            }
        }
    }

    /// Runs an async operation with a hard timeout, cancelling if the deadline is exceeded.
    private static func withDeadline<T: Sendable>(
        _ timeout: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw APIError.networkError(URLError(.timedOut))
            }
            // First to finish wins; cancel the other
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
    
    // MARK: - Response Handler
    
    /// Decode structured JSON response {"lines": ["..."]} into plain text
    private func parseStructuredResponse(_ rawText: String) -> String {
        guard let data = rawText.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let lines = json["lines"] as? [String] else {
            // Not valid JSON or missing "lines" key — return raw text as-is
            return rawText
        }
        return lines.joined(separator: "\n")
    }

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
            return parseStructuredResponse(text)
            
        case 400:
            let bodyString = String(data: data, encoding: .utf8)
            // Check if this is an expired/invalid API key (returns 400, not 401)
            if let body = bodyString,
               body.contains("API_KEY_INVALID") || body.contains("API key expired") {
                throw APIError.apiKeyExpired
            }
            throw APIError.badRequest(bodyString)
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

    private func createRequestBody(
        systemPrompt: String,
        userMessagePrompt: String,
        base64Image: String,
        thinkingLevel: GeminiThinkingLevel,
        model: String,
        photoTokenBudget: GeminiPhotoTokenBudget
    ) -> GeminiRequest {
        // Image part first, then user message (Google's recommended order)
        let imagePart = GeminiRequest.Part(inlineData: GeminiRequest.Part.InlineData(mimeType: "image/jpeg", data: base64Image))
        let textPart = GeminiRequest.Part(text: userMessagePrompt)

        // System instruction as top-level field (separates behavior from content)
        let systemInstruction = GeminiRequest.Content(parts: [GeminiRequest.Part(text: systemPrompt)])

        // Only include thinking_config if thinking is not "none" AND model supports it
        let thinkingConfig: GeminiRequest.GenerationConfig.ThinkingConfig?
        if thinkingLevel != .none && modelSupportsThinking(model) {
            thinkingConfig = GeminiRequest.GenerationConfig.ThinkingConfig(thinkingLevel: thinkingLevel.rawValue)
        } else {
            thinkingConfig = nil
        }

        let mediaResolution: String?
        if modelSupportsMediaResolutionControl(model) {
            mediaResolution = photoTokenBudget.rawValue
        } else {
            mediaResolution = nil
        }

        // Temperature=0 for deterministic OCR output (greedy decoding)
        let temperature: Double = 0.0

        // JSON structured output for clean line-by-line transcription
        // Only used when thinking is off — thinking models may not support response_mime_type
        let responseMimeType: String? = (thinkingConfig == nil) ? "application/json" : nil

        let generationConfig = GeminiRequest.GenerationConfig(
            thinkingConfig: thinkingConfig,
            mediaResolution: mediaResolution,
            temperature: temperature,
            responseMimeType: responseMimeType
        )

        return GeminiRequest(
            systemInstruction: systemInstruction,
            contents: [GeminiRequest.Content(parts: [imagePart, textPart])],
            generationConfig: generationConfig
        )
    }
    
    // Check if model supports thinking (2.5+ series models)
    private func modelSupportsThinking(_ model: String) -> Bool {
        let modelLower = model.lowercased()
        
        // Match version patterns:
        // - gemini-X.Y (e.g., gemini-2.5-flash)
        // - gemini-X (e.g., gemini-3-pro-preview)
        // Supports thinking for: version >= 2.5 (i.e., 2.5, 2.6, 3, 4, etc.)
        
        // Try matching X.Y pattern first
        if let range = modelLower.range(of: #"gemini-(\d+)\.(\d+)"#, options: .regularExpression) {
            let versionString = String(modelLower[range])
            let components = versionString.replacingOccurrences(of: "gemini-", with: "").split(separator: ".")
            
            if components.count >= 2,
               let major = Int(components[0]),
               let minor = Int(components[1]) {
                return major > 2 || (major == 2 && minor >= 5)
            }
        }
        
        // Try matching X pattern (e.g., gemini-3-xxx)
        if let range = modelLower.range(of: #"gemini-(\d+)-"#, options: .regularExpression) {
            let versionString = String(modelLower[range])
            let majorStr = versionString.replacingOccurrences(of: "gemini-", with: "").replacingOccurrences(of: "-", with: "")
            
            if let major = Int(majorStr) {
                return major >= 3 // Gemini 3 and higher support thinking
            }
        }
        
        return false
    }

    private func modelSupportsMediaResolutionControl(_ model: String) -> Bool {
        return isGemini3Model(model)
    }

    private func isGemini3Model(_ model: String) -> Bool {
        let modelLower = model.lowercased()
        return modelLower.hasPrefix("gemini-3")
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
        let mediaResolution: String?
        let temperature: Double?
        let responseMimeType: String?

        struct ThinkingConfig: Codable {
            let thinkingLevel: String?

            enum CodingKeys: String, CodingKey {
                case thinkingLevel = "thinking_level"
            }
        }

        enum CodingKeys: String, CodingKey {
            case thinkingConfig = "thinking_config"
            case mediaResolution = "media_resolution"
            case temperature
            case responseMimeType = "response_mime_type"
        }
    }

    let systemInstruction: Content?
    let contents: [Content]
    let generationConfig: GenerationConfig?

    enum CodingKeys: String, CodingKey {
        case systemInstruction = "system_instruction"
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
    case apiKeyExpired
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
        case .apiKeyExpired:
            return "Your Gemini API key has expired or is invalid. Please generate a new key at aistudio.google.com/apikey and update it in Settings."
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

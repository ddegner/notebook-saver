import Foundation
// Removed SwiftUI import as direct AppStorage access isn't needed here
import UIKit // For UIImage
import CoreImage // Import Core Image
class GeminiService: ImageTextExtractor /*: APIServiceProtocol*/ {
    // Track if connection has been verified to avoid redundant warm-ups
    private static var connectionVerified = false

    // Constants for UserDefaults keys (matching SettingsView)
    private enum StorageKeys {
        static let selectedModelId = "selectedModelId"
        static let customModelName = "customModelName"
        static let userPrompt = "userPrompt"
        static let apiEndpoint = "apiEndpointUrlString"
        static let draftsTag = "draftsTag" // Added key for Drafts tag
    }

    // Defaults
    private let defaultModelId = "gemini-2.5-flash-preview-04-17" // Default model if nothing is set
    private let defaultPrompt = "Extract text accurately from this image of a notebook page."
    private static let defaultApiEndpoint = "https://generativelanguage.googleapis.com/v1beta/models/"
    private let defaultDraftsTag = "notebook"

    private let highMaxImageDimension: CGFloat = 2048.0 // Max dimension for high res
    
    // Retry configuration
    private let maxRetryAttempts = 3
    private let initialRetryDelay: TimeInterval = 1.0 // 1 second initial delay

    // Instantiate the shared preprocessor - RENAME to ImageProcessor
    private let imageProcessor = ImageProcessor()

    // Helper to get settings from UserDefaults
    private func getSettings() -> (apiKey: String?, apiEndpointUrl: URL?, modelToUse: String?, prompt: String, draftsTag: String) {
        let defaults = UserDefaults.standard

        let apiKey = KeychainService.loadAPIKey()

        let endpointString = defaults.string(forKey: StorageKeys.apiEndpoint) ?? GeminiService.defaultApiEndpoint
        let apiEndpointUrl = URL(string: endpointString)

        let selectedId = defaults.string(forKey: StorageKeys.selectedModelId) ?? defaultModelId
        var modelToUse: String?
        if selectedId == "Custom" {
            modelToUse = defaults.string(forKey: StorageKeys.customModelName)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            modelToUse = selectedId
        }
        if modelToUse?.isEmpty ?? true {
            modelToUse = nil // Treat empty custom model as invalid
        }

        let prompt = defaults.string(forKey: StorageKeys.userPrompt) ?? defaultPrompt
        let draftsTag = defaults.string(forKey: StorageKeys.draftsTag) ?? defaultDraftsTag

        return (apiKey, apiEndpointUrl, modelToUse, prompt, draftsTag)
    }

    // MARK: - Connection Warming

    public static func warmUpConnection() async {
        // Skip if already verified
        if connectionVerified {
            print("GeminiService: Connection already verified, skipping warm-up")
            return
        }
        
        print("GeminiService: Attempting to warm up connection...")
        let defaults = UserDefaults.standard
        let apiKey = KeychainService.loadAPIKey()

        let endpointString = defaults.string(forKey: StorageKeys.apiEndpoint) ?? defaultApiEndpoint
        guard let apiBaseUrl = URL(string: endpointString) else {
            print("GeminiService (WarmUp): Invalid API Endpoint URL configured: \(endpointString)")
            return
        }

        guard let key = apiKey, !key.isEmpty else {
            print("GeminiService (WarmUp): API Key is missing. Skipping connection warm-up.")
            return
        }

        // Use a lightweight endpoint, like listing models
        let warmUpUrl = apiBaseUrl.appendingPathComponent("models")
        var request = URLRequest(url: warmUpUrl)
        request.httpMethod = "GET" // Typically, listing models is a GET request

        var urlComponents = URLComponents(url: warmUpUrl, resolvingAgainstBaseURL: false)
        urlComponents?.queryItems = [URLQueryItem(name: "key", value: key)]

        guard let finalUrl = urlComponents?.url else {
            print("GeminiService (WarmUp): Failed to construct URL with API key.")
            return
        }
        request.url = finalUrl

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                print("GeminiService (WarmUp): Invalid response from server.")
                return
            }

            if (200...299).contains(httpResponse.statusCode) {
                print("GeminiService (WarmUp): Connection successful (Status: \(httpResponse.statusCode)). Ready for requests.")
                connectionVerified = true
                // You could optionally decode the response if needed, but for warming, a 2xx is often enough.
                // For example, to verify it's a valid model list:
                // if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any], json["models"] != nil {
                //     print("GeminiService (WarmUp): Successfully fetched model list.")
                // } else {
                //     print("GeminiService (WarmUp): Connection successful, but response format unexpected.")
                // }
            } else {
                print("GeminiService (WarmUp): Connection attempt failed with status code: \(httpResponse.statusCode). Response: \(String(data: data, encoding: .utf8) ?? "No response body")")
            }
        } catch {
            print("GeminiService (WarmUp): Network error during connection warm-up: \(error.localizedDescription)")
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
        let settings = getSettings()

        guard let apiKey = settings.apiKey, !apiKey.isEmpty else {
            throw APIError.missingApiKey
        }
        guard let apiBaseUrl = settings.apiEndpointUrl else {
             throw APIError.invalidApiEndpoint(settings.apiEndpointUrl?.absoluteString ?? "<empty>")
         }
        guard let model = settings.modelToUse else {
            throw APIError.missingModelConfiguration
        }
        let prompt = settings.prompt
        // Quality setting is not currently user-configurable, use a default
        let heicQuality: CGFloat = 0.4 // Renamed for clarity, using same default quality

        // 1. Prepare Image using the new ImageProcessor workflow
        let preparedImageData: Data
        do {
            // a. Create UIImage from original data
            guard let originalUIImage = UIImage(data: imageData) else {
                throw PreprocessingError.invalidImageData
            }

            // b. Use the high resolution max dimension
            let maxDimension = highMaxImageDimension
            print("GeminiService: Using max image dimension: \(maxDimension)")

            // c. Resize the UIImage using the Core Image based method
            let resizedUIImage = try imageProcessor.resizeImage(originalUIImage, maxDimension: maxDimension)

            // d. Encode the resized UIImage to HEIC
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
            // print("Using Endpoint: \(finalUrl.absoluteString)") // Debugging
            // print("Request Body JSON: \(String(data: jsonData, encoding: .utf8) ?? "Invalid JSON")") // Debugging
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
                        .compactMap { $0.text } // Get text from each part, ignoring nil
                        .joined(separator: "\\\\n\\\\n") // Join parts, maybe with double newline

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

    // MARK: - Request Body Construction

    private func createRequestBody(prompt: String, base64Image: String) -> GeminiRequest {
        // Construct the request body based on API documentation
        let imagePart = GeminiRequest.Part(inlineData: GeminiRequest.Part.InlineData(mimeType: "image/heic", data: base64Image))
        let textPart = GeminiRequest.Part(text: prompt)
        return GeminiRequest(contents: [GeminiRequest.Content(parts: [textPart, imagePart])])
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

    let contents: [Content]
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

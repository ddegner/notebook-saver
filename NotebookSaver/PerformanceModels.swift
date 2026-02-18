import Foundation
import UIKit
import Darwin

// MARK: - Performance Logging Data Models

/// Information about image data sent to AI APIs
struct ImageMetadata: Codable, Equatable {
    let originalWidth: CGFloat
    let originalHeight: CGFloat
    let processedWidth: CGFloat
    let processedHeight: CGFloat
    let originalFileSizeBytes: Int
    let processedFileSizeBytes: Int
    let compressionQuality: CGFloat?
    let imageFormat: String // "HEIC", "JPEG", "PNG", etc.
    
    init(originalWidth: CGFloat, originalHeight: CGFloat, 
         processedWidth: CGFloat, processedHeight: CGFloat,
         originalFileSizeBytes: Int, processedFileSizeBytes: Int,
         compressionQuality: CGFloat? = nil, imageFormat: String) {
        self.originalWidth = originalWidth
        self.originalHeight = originalHeight
        self.processedWidth = processedWidth
        self.processedHeight = processedHeight
        self.originalFileSizeBytes = originalFileSizeBytes
        self.processedFileSizeBytes = processedFileSizeBytes
        self.compressionQuality = compressionQuality
        self.imageFormat = imageFormat
    }
    
    /// Convenience computed properties for analysis
    var originalPixelCount: Int {
        return Int(originalWidth * originalHeight)
    }
    
    var processedPixelCount: Int {
        return Int(processedWidth * processedHeight)
    }
    
    var compressionRatio: Double {
        guard originalFileSizeBytes > 0 else { return 0 }
        return Double(processedFileSizeBytes) / Double(originalFileSizeBytes)
    }
    
    var resolutionReductionRatio: Double {
        guard originalPixelCount > 0 else { return 0 }
        return Double(processedPixelCount) / Double(originalPixelCount)
    }
}

/// Information about the AI model used for processing
struct ModelInfo: Codable, Equatable {
    let serviceName: String // "Gemini" or "Vision"
    let modelName: String // e.g., "gemini-2.5-flash" or "Apple Vision"
    let configuration: [String: String]? // Additional model settings
    let imageMetadata: ImageMetadata? // Image processing details
    
    init(serviceName: String, modelName: String, configuration: [String: String]? = nil, imageMetadata: ImageMetadata? = nil) {
        self.serviceName = serviceName
        self.modelName = modelName
        self.configuration = configuration
        self.imageMetadata = imageMetadata
    }
}

/// Device and app context information
struct DeviceContext: Codable, Equatable {
    let deviceModel: String
    let osVersion: String
    let appVersion: String
    let timestamp: Date
    let memoryPressure: String
    let thermalState: String
    
    init() {
        self.deviceModel = Self.getDeviceModel()
        self.osVersion = Self.getOSVersion()
        self.appVersion = Self.getAppVersion()
        self.timestamp = Date()
        self.memoryPressure = Self.getMemoryPressure()
        self.thermalState = Self.getThermalState()
    }
    
    private static func getDeviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(format: "%c", value)
        }
        return identifier.isEmpty ? "Unknown" : identifier
    }
    
    private static func getOSVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
    
    private static func getAppVersion() -> String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
    
    private static func getMemoryPressure() -> String {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            let memoryMB = info.resident_size / (1024 * 1024)
            if memoryMB > 500 {
                return "High (\(memoryMB)MB)"
            } else if memoryMB > 200 {
                return "Medium (\(memoryMB)MB)"
            } else {
                return "Low (\(memoryMB)MB)"
            }
        }
        return "Unknown"
    }
    
    private static func getThermalState() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:
            return "Normal"
        case .fair:
            return "Fair"
        case .serious:
            return "Serious"
        case .critical:
            return "Critical"
        @unknown default:
            return "Unknown"
        }
    }
}

/// A single performance measurement entry
struct LogEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let operation: String
    let startTime: Date
    let duration: TimeInterval
    let modelInfo: ModelInfo?
    let deviceContext: DeviceContext
    
    init(operation: String, startTime: Date, duration: TimeInterval, modelInfo: ModelInfo? = nil, deviceContext: DeviceContext) {
        self.id = UUID()
        self.operation = operation
        self.startTime = startTime
        self.duration = duration
        self.modelInfo = modelInfo
        self.deviceContext = deviceContext
    }
}

/// A collection of related log entries representing one complete operation
struct LogSession: Codable, Identifiable, Equatable {
    let id: UUID
    let startTime: Date
    var endTime: Date?
    var wasSuccessful: Bool?
    var entries: [LogEntry]
    let deviceContext: DeviceContext
    
    var totalDuration: TimeInterval? {
        guard let endTime = endTime else { return nil }
        return endTime.timeIntervalSince(startTime)
    }
    
    var isCompleted: Bool {
        return endTime != nil
    }
    
    init(deviceContext: DeviceContext) {
        self.id = UUID()
        self.startTime = Date()
        self.endTime = nil
        self.wasSuccessful = nil
        self.entries = []
        self.deviceContext = deviceContext
    }
    
    mutating func addEntry(_ entry: LogEntry) {
        entries.append(entry)
    }
    
    mutating func complete() {
        if endTime == nil {
            endTime = Date()
        }
    }
}

/// Storage metrics for tracking log storage usage and cleanup
struct StorageMetrics: Codable {
    let sessionCount: Int
    let estimatedSizeBytes: Int
    let lastCleanupDate: Date
    
    init(sessionCount: Int, estimatedSizeBytes: Int, lastCleanupDate: Date) {
        self.sessionCount = sessionCount
        self.estimatedSizeBytes = estimatedSizeBytes
        self.lastCleanupDate = lastCleanupDate
    }
}


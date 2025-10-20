import Foundation

/// Utility for formatting performance logs into human-readable text
struct PerformanceLogFormatter {
    
    /// Generate a formatted, copyable text representation of performance logs
    /// - Parameter sessions: Array of log sessions to format
    /// - Returns: Formatted string suitable for copying and external analysis
    static func formatLogs(_ sessions: [LogSession]) -> String {
        var output = ""
        
        // Header
        output += "NotebookSaver Performance Log\n"
        output += "Generated: \(DateFormatter.logTimestamp.string(from: Date()))\n"
        
        if let firstSession = sessions.first {
            let context = firstSession.deviceContext
            output += "Device: \(context.deviceModel) (iOS \(context.osVersion))\n"
            output += "App Version: \(context.appVersion)\n"
        }
        
        output += "\n"
        
        // Sessions
        if sessions.isEmpty {
            output += "No performance data available.\n"
        } else {
            for (index, session) in sessions.enumerated() {
                output += formatSession(session, index: index + 1)
                if index < sessions.count - 1 {
                    output += "\n"
                }
            }
            
            // Summary statistics
            output += "\n"
            output += formatSummaryStatistics(sessions)
        }
        
        return output
    }
    
    /// Format a single session
    private static func formatSession(_ session: LogSession, index: Int) -> String {
        var output = ""
        
        output += "=== SESSION \(index) ===\n"
        output += "Started: \(DateFormatter.logTimestamp.string(from: session.startTime))\n"
        
        if let totalDuration = session.totalDuration {
            output += "Total Duration: \(String(format: "%.3f", totalDuration))s\n"
        } else {
            output += "Status: Incomplete\n"
        }
        
        if session.entries.isEmpty {
            output += "No operations recorded.\n"
        } else {
            output += "\nOperations:\n"
            for entry in session.entries {
                output += formatLogEntry(entry)
            }
        }
        
        output += "\n"
        return output
    }
    
    /// Format a single log entry
    private static func formatLogEntry(_ entry: LogEntry) -> String {
        var line = "- \(entry.operation): \(String(format: "%.3f", entry.duration))s"
        
        if let modelInfo = entry.modelInfo {
            line += " (\(modelInfo.serviceName)/\(modelInfo.modelName)"
            if let config = modelInfo.configuration, !config.isEmpty {
                let configStr = config.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
                line += ", \(configStr)"
            }
            
            // Add image metadata if available
            if let imageMetadata = modelInfo.imageMetadata {
                line += ", img: \(Int(imageMetadata.processedWidth))x\(Int(imageMetadata.processedHeight))"
                line += " (\(formatFileSize(imageMetadata.processedFileSizeBytes)))"
                
                // Show compression info if different from original
                if imageMetadata.originalFileSizeBytes != imageMetadata.processedFileSizeBytes {
                    let compressionRatio = imageMetadata.compressionRatio
                    line += " [compressed \(String(format: "%.1f", compressionRatio * 100))%]"
                }
                
                // Show resolution reduction if applicable
                if imageMetadata.originalWidth != imageMetadata.processedWidth || 
                   imageMetadata.originalHeight != imageMetadata.processedHeight {
                    line += " [from \(Int(imageMetadata.originalWidth))x\(Int(imageMetadata.originalHeight))]"
                }
            }
            
            line += ")"
        }
        
        line += "\n"
        return line
    }
    
    /// Format file size in human-readable format
    private static func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    /// Format pixel count in human-readable format
    private static func formatPixelCount(_ pixels: Int) -> String {
        if pixels >= 1_000_000 {
            return String(format: "%.1fM", Double(pixels) / 1_000_000)
        } else if pixels >= 1_000 {
            return String(format: "%.1fK", Double(pixels) / 1_000)
        } else {
            return "\(pixels)"
        }
    }
    
    /// Generate summary statistics
    private static func formatSummaryStatistics(_ sessions: [LogSession]) -> String {
        var output = "=== SUMMARY STATISTICS ===\n"
        
        let completedSessions = sessions.filter { $0.isCompleted }
        output += "Total Sessions: \(sessions.count)\n"
        output += "Completed Sessions: \(completedSessions.count)\n"
        
        if !completedSessions.isEmpty {
            let totalDurations = completedSessions.compactMap { $0.totalDuration }
            if !totalDurations.isEmpty {
                let avgDuration = totalDurations.reduce(0, +) / Double(totalDurations.count)
                let minDuration = totalDurations.min() ?? 0
                let maxDuration = totalDurations.max() ?? 0
                
                output += "Average Session Duration: \(String(format: "%.3f", avgDuration))s\n"
                output += "Fastest Session: \(String(format: "%.3f", minDuration))s\n"
                output += "Slowest Session: \(String(format: "%.3f", maxDuration))s\n"
            }
        }
        
        // Operation statistics
        let allEntries = sessions.flatMap { $0.entries }
        if !allEntries.isEmpty {
            output += "\nOperation Statistics:\n"
            
            let operationGroups = Dictionary(grouping: allEntries) { entry in
                // Group by base operation name (remove " (failed)" suffix)
                entry.operation.replacingOccurrences(of: " (failed)", with: "")
            }
            
            for (operation, entries) in operationGroups.sorted(by: { $0.key < $1.key }) {
                let durations = entries.map { $0.duration }
                let avgDuration = durations.reduce(0, +) / Double(durations.count)
                let failedCount = entries.filter { $0.operation.contains("(failed)") }.count
                
                output += "- \(operation): \(entries.count) times, avg \(String(format: "%.3f", avgDuration))s"
                if failedCount > 0 {
                    output += " (\(failedCount) failed)"
                }
                output += "\n"
            }
            
            // Image processing statistics
            let entriesWithImages = allEntries.filter { $0.modelInfo?.imageMetadata != nil }
            if !entriesWithImages.isEmpty {
                output += "\nImage Processing Statistics:\n"
                
                let imageSizes = entriesWithImages.compactMap { $0.modelInfo?.imageMetadata?.processedFileSizeBytes }
                let imageResolutions = entriesWithImages.compactMap { entry -> Int? in
                    guard let metadata = entry.modelInfo?.imageMetadata else { return nil }
                    return Int(metadata.processedWidth * metadata.processedHeight)
                }
                
                if !imageSizes.isEmpty {
                    let avgSize = imageSizes.reduce(0, +) / imageSizes.count
                    let minSize = imageSizes.min() ?? 0
                    let maxSize = imageSizes.max() ?? 0
                    
                    output += "- Images Processed: \(entriesWithImages.count)\n"
                    output += "- Average File Size: \(formatFileSize(avgSize))\n"
                    output += "- Size Range: \(formatFileSize(minSize)) - \(formatFileSize(maxSize))\n"
                }
                
                if !imageResolutions.isEmpty {
                    let avgResolution = imageResolutions.reduce(0, +) / imageResolutions.count
                    let minResolution = imageResolutions.min() ?? 0
                    let maxResolution = imageResolutions.max() ?? 0
                    
                    output += "- Average Resolution: \(formatPixelCount(avgResolution)) pixels\n"
                    output += "- Resolution Range: \(formatPixelCount(minResolution)) - \(formatPixelCount(maxResolution)) pixels\n"
                }
                
                // Compression statistics
                let compressionRatios = entriesWithImages.compactMap { entry -> Double? in
                    guard let metadata = entry.modelInfo?.imageMetadata,
                          metadata.originalFileSizeBytes != metadata.processedFileSizeBytes else { return nil }
                    return metadata.compressionRatio
                }
                
                if !compressionRatios.isEmpty {
                    let avgCompression = compressionRatios.reduce(0, +) / Double(compressionRatios.count)
                    output += "- Average Compression: \(String(format: "%.1f", avgCompression * 100))% of original size\n"
                }
            }
        }
        
        return output
    }
}

// MARK: - DateFormatter Extensions

private extension DateFormatter {
    static let logTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()
}
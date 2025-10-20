import XCTest
@testable import Cat_Scribe

/// Integration tests for performance logging in the photo processing pipeline
final class PerformanceLoggerIntegrationTests: XCTestCase {
    
    // MARK: - Pipeline Integration Tests
    
    @MainActor
    func testCameraViewIntegration() async throws {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        // Simulate camera view photo capture pipeline
        let sessionId = logger.startSession()
        
        // Test photo capture timing
        let photoData = try await logger.measureOperation("Photo Capture", sessionId: sessionId) {
            // Simulate camera capture delay
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            return Data([0x01, 0x02, 0x03]) // Mock photo data
        }
        
        XCTAssertFalse(photoData.isEmpty)
        
        // Test image preprocessing timing
        let processedImage = try await logger.measureOperation("Image Preprocessing", sessionId: sessionId) {
            // Simulate image processing delay
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
            return "processed_image_data"
        }
        
        XCTAssertEqual(processedImage, "processed_image_data")
        
        logger.endSession(sessionId)
        
        // Verify pipeline operations were logged
        let sessions = await logger.getRecentSessions(limit: 1)
        let session = sessions.first!
        
        XCTAssertEqual(session.entries.count, 2)
        XCTAssertTrue(session.entries.contains { $0.operation == "Photo Capture" })
        XCTAssertTrue(session.entries.contains { $0.operation == "Image Preprocessing" })
        XCTAssertTrue(session.isCompleted)
    }
    
    @MainActor
    func testGeminiServiceIntegration() async throws {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        let sessionId = logger.startSession()
        
        // Simulate Gemini service text extraction
        let geminiModel = ModelInfo(
            serviceName: "Gemini",
            modelName: "gemini-2.5-flash",
            configuration: ["temperature": "0.1", "max_tokens": "1000"]
        )
        
        let extractedText = try await logger.measureOperation(
            "Gemini Text Extraction",
            sessionId: sessionId,
            modelInfo: geminiModel
        ) {
            // Simulate AI processing delay
            try await Task.sleep(nanoseconds: 300_000_000) // 300ms
            return "Extracted text from image using Gemini AI"
        }
        
        XCTAssertEqual(extractedText, "Extracted text from image using Gemini AI")
        
        logger.endSession(sessionId)
        
        // Verify Gemini integration was logged with model info
        let sessions = await logger.getRecentSessions(limit: 1)
        let session = sessions.first!
        
        XCTAssertEqual(session.entries.count, 1)
        
        let geminiEntry = session.entries.first!
        XCTAssertEqual(geminiEntry.operation, "Gemini Text Extraction")
        XCTAssertNotNil(geminiEntry.modelInfo)
        XCTAssertEqual(geminiEntry.modelInfo?.serviceName, "Gemini")
        XCTAssertEqual(geminiEntry.modelInfo?.modelName, "gemini-2.5-flash")
        XCTAssertEqual(geminiEntry.modelInfo?.configuration?["temperature"], "0.1")
    }
    
    @MainActor
    func testVisionServiceIntegration() async throws {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        let sessionId = logger.startSession()
        
        // Simulate Vision service text extraction
        let visionModel = ModelInfo(
            serviceName: "Vision",
            modelName: "Apple Vision Framework",
            configuration: ["recognition_level": "accurate"]
        )
        
        let visionText = try await logger.measureOperation(
            "Vision Text Recognition",
            sessionId: sessionId,
            modelInfo: visionModel
        ) {
            // Simulate Vision processing delay
            try await Task.sleep(nanoseconds: 150_000_000) // 150ms
            return "Text recognized by Apple Vision"
        }
        
        XCTAssertEqual(visionText, "Text recognized by Apple Vision")
        
        logger.endSession(sessionId)
        
        // Verify Vision integration was logged with model info
        let sessions = await logger.getRecentSessions(limit: 1)
        let session = sessions.first!
        
        XCTAssertEqual(session.entries.count, 1)
        
        let visionEntry = session.entries.first!
        XCTAssertEqual(visionEntry.operation, "Vision Text Recognition")
        XCTAssertNotNil(visionEntry.modelInfo)
        XCTAssertEqual(visionEntry.modelInfo?.serviceName, "Vision")
        XCTAssertEqual(visionEntry.modelInfo?.modelName, "Apple Vision Framework")
    }
    
    @MainActor
    func testDraftsHelperIntegration() async throws {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        let sessionId = logger.startSession()
        
        // Simulate Drafts app integration timing
        let noteCreated = try await logger.measureOperation("Drafts Note Creation", sessionId: sessionId) {
            // Simulate note creation delay
            try await Task.sleep(nanoseconds: 75_000_000) // 75ms
            return true
        }
        
        XCTAssertTrue(noteCreated)
        
        // Simulate share sheet timing for non-Drafts workflow
        let shareSheetPresented = try await logger.measureOperation("Share Sheet Presentation", sessionId: sessionId) {
            // Simulate share sheet delay
            try await Task.sleep(nanoseconds: 25_000_000) // 25ms
            return true
        }
        
        XCTAssertTrue(shareSheetPresented)
        
        logger.endSession(sessionId)
        
        // Verify note creation operations were logged
        let sessions = await logger.getRecentSessions(limit: 1)
        let session = sessions.first!
        
        XCTAssertEqual(session.entries.count, 2)
        XCTAssertTrue(session.entries.contains { $0.operation == "Drafts Note Creation" })
        XCTAssertTrue(session.entries.contains { $0.operation == "Share Sheet Presentation" })
    }
    
    @MainActor
    func testCompletePhotoProcessingPipeline() async throws {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        // Simulate complete end-to-end photo processing pipeline
        let sessionId = logger.startSession()
        
        // 1. Photo Capture
        let photoData = try await logger.measureOperation("Photo Capture", sessionId: sessionId) {
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            return Data([0x01, 0x02, 0x03])
        }
        
        // 2. Image Preprocessing
        let processedImage = try await logger.measureOperation("Image Preprocessing", sessionId: sessionId) {
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
            return "processed_image"
        }
        
        // 3. Text Extraction (with model fallback simulation)
        var extractedText: String
        
        do {
            // Try Gemini first
            let geminiModel = ModelInfo(serviceName: "Gemini", modelName: "gemini-2.5-flash")
            extractedText = try await logger.measureOperation(
                "Gemini Text Extraction",
                sessionId: sessionId,
                modelInfo: geminiModel
            ) {
                try await Task.sleep(nanoseconds: 200_000_000) // 200ms
                return "Text extracted by Gemini"
            }
        } catch {
            // Fallback to Vision
            let visionModel = ModelInfo(serviceName: "Vision", modelName: "Apple Vision")
            extractedText = try await logger.measureOperation(
                "Vision Text Extraction (Fallback)",
                sessionId: sessionId,
                modelInfo: visionModel
            ) {
                try await Task.sleep(nanoseconds: 150_000_000) // 150ms
                return "Text extracted by Vision"
            }
        }
        
        // 4. Note Creation
        let noteCreated = try await logger.measureOperation("Note Creation", sessionId: sessionId) {
            try await Task.sleep(nanoseconds: 30_000_000) // 30ms
            return true
        }
        
        // 5. Photo Saving (optional)
        let photoSaved = try await logger.measureOperation("Photo Saving", sessionId: sessionId) {
            try await Task.sleep(nanoseconds: 20_000_000) // 20ms
            return true
        }
        
        logger.endSession(sessionId)
        
        // Verify complete pipeline
        XCTAssertFalse(photoData.isEmpty)
        XCTAssertEqual(processedImage, "processed_image")
        XCTAssertFalse(extractedText.isEmpty)
        XCTAssertTrue(noteCreated)
        XCTAssertTrue(photoSaved)
        
        // Verify all operations were logged
        let sessions = await logger.getRecentSessions(limit: 1)
        let session = sessions.first!
        
        XCTAssertEqual(session.entries.count, 5)
        XCTAssertTrue(session.isCompleted)
        XCTAssertNotNil(session.totalDuration)
        XCTAssertGreaterThan(session.totalDuration!, 0.4) // Should be at least 400ms
        
        // Verify operation order and timing
        let operations = session.entries.map { $0.operation }
        XCTAssertEqual(operations[0], "Photo Capture")
        XCTAssertEqual(operations[1], "Image Preprocessing")
        XCTAssertTrue(operations[2].contains("Text Extraction"))
        XCTAssertEqual(operations[3], "Note Creation")
        XCTAssertEqual(operations[4], "Photo Saving")
    }
    
    // MARK: - Performance Impact Tests
    
    @MainActor
    func testLoggingPerformanceImpact() async throws {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        let iterations = 50
        let operationDuration: UInt64 = 10_000_000 // 10ms
        
        // Measure baseline performance without logging
        let baselineStart = CFAbsoluteTimeGetCurrent()
        for i in 0..<iterations {
            try await Task.sleep(nanoseconds: operationDuration)
        }
        let baselineDuration = CFAbsoluteTimeGetCurrent() - baselineStart
        
        // Measure performance with logging
        let sessionId = logger.startSession()
        let loggedStart = CFAbsoluteTimeGetCurrent()
        
        for i in 0..<iterations {
            _ = try await logger.measureOperation("Performance Impact Test \(i)", sessionId: sessionId) {
                try await Task.sleep(nanoseconds: operationDuration)
                return i
            }
        }
        
        let loggedDuration = CFAbsoluteTimeGetCurrent() - loggedStart
        logger.endSession(sessionId)
        
        // Calculate overhead
        let overhead = (loggedDuration - baselineDuration) / baselineDuration
        
        // Logging should add minimal overhead (less than 20%)
        XCTAssertLessThan(overhead, 0.2, "Logging overhead (\(String(format: "%.1f", overhead * 100))%) should be less than 20%")
        
        // Verify all operations were logged correctly
        let sessions = await logger.getRecentSessions(limit: 1)
        XCTAssertEqual(sessions.first!.entries.count, iterations)
        
        print("Performance Impact Test Results:")
        print("Baseline duration: \(String(format: "%.3f", baselineDuration))s")
        print("Logged duration: \(String(format: "%.3f", loggedDuration))s")
        print("Overhead: \(String(format: "%.1f", overhead * 100))%")
    }
    
    @MainActor
    func testConcurrentLoggingPerformance() async throws {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        let sessionCount = 5
        let operationsPerSession = 10
        
        // Create multiple concurrent sessions
        let sessionIds = (0..<sessionCount).map { _ in logger.startSession() }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Run concurrent operations across multiple sessions
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (sessionIndex, sessionId) in sessionIds.enumerated() {
                group.addTask {
                    for operationIndex in 0..<operationsPerSession {
                        _ = try await logger.measureOperation(
                            "Concurrent Op \(sessionIndex)-\(operationIndex)",
                            sessionId: sessionId
                        ) {
                            try await Task.sleep(nanoseconds: UInt64.random(in: 5_000_000...15_000_000)) // 5-15ms
                            return operationIndex
                        }
                    }
                }
            }
            
            try await group.waitForAll()
        }
        
        let totalDuration = CFAbsoluteTimeGetCurrent() - startTime
        
        // End all sessions
        for sessionId in sessionIds {
            logger.endSession(sessionId)
        }
        
        // Verify all operations were logged correctly
        let sessions = await logger.getRecentSessions(limit: sessionCount)
        XCTAssertEqual(sessions.count, sessionCount)
        
        for session in sessions {
            XCTAssertEqual(session.entries.count, operationsPerSession)
            XCTAssertTrue(session.isCompleted)
        }
        
        // Performance should be reasonable even with concurrent logging
        let expectedMinimumDuration = 0.05 // 50ms minimum (5ms * 10 operations)
        let expectedMaximumDuration = 2.0 // 2s maximum (reasonable upper bound)
        
        XCTAssertGreaterThan(totalDuration, expectedMinimumDuration)
        XCTAssertLessThan(totalDuration, expectedMaximumDuration)
        
        print("Concurrent Logging Test Results:")
        print("Sessions: \(sessionCount), Operations per session: \(operationsPerSession)")
        print("Total duration: \(String(format: "%.3f", totalDuration))s")
        print("Average per operation: \(String(format: "%.3f", totalDuration / Double(sessionCount * operationsPerSession) * 1000))ms")
    }
    
    @MainActor
    func testMemoryUsageUnderLoad() async {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        let initialStorageInfo = await logger.getStorageInfo()
        
        // Create many sessions with operations to test memory usage
        let sessionCount = 20
        let operationsPerSession = 25
        
        for sessionIndex in 0..<sessionCount {
            let sessionId = logger.startSession()
            
            for operationIndex in 0..<operationsPerSession {
                let modelInfo = ModelInfo(
                    serviceName: "TestService",
                    modelName: "test-model-v\(operationIndex % 3)",
                    configuration: ["param1": "value\(operationIndex)", "param2": "test"]
                )
                
                logger.logOperation(
                    "Memory Test Session \(sessionIndex) Op \(operationIndex)",
                    duration: Double(operationIndex) * 0.01,
                    sessionId: sessionId,
                    modelInfo: modelInfo
                )
            }
            
            logger.endSession(sessionId)
        }
        
        let finalStorageInfo = await logger.getStorageInfo()
        
        // Verify memory usage is within reasonable bounds
        XCTAssertLessThanOrEqual(finalStorageInfo.sessionCount, 50) // Should be limited by maxStoredSessions
        XCTAssertLessThan(finalStorageInfo.estimatedSizeBytes, finalStorageInfo.maxSizeBytes)
        
        // Verify automatic cleanup occurred if needed
        if sessionCount > 50 {
            XCTAssertEqual(finalStorageInfo.sessionCount, 50)
        } else {
            XCTAssertEqual(finalStorageInfo.sessionCount, sessionCount)
        }
        
        print("Memory Usage Test Results:")
        print("Initial sessions: \(initialStorageInfo.sessionCount)")
        print("Final sessions: \(finalStorageInfo.sessionCount)")
        print("Final storage size: \(finalStorageInfo.estimatedSizeBytes) bytes")
        print("Storage limit: \(finalStorageInfo.maxSizeBytes) bytes")
    }
    
    // MARK: - Error Handling Integration Tests
    
    @MainActor
    func testPipelineErrorHandling() async throws {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        let sessionId = logger.startSession()
        
        // Simulate successful operation
        _ = try await logger.measureOperation("Successful Operation", sessionId: sessionId) {
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            return "success"
        }
        
        // Simulate failed operation
        do {
            _ = try await logger.measureOperation("Failed Operation", sessionId: sessionId) {
                try await Task.sleep(nanoseconds: 5_000_000) // 5ms
                throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Simulated failure"])
            }
            XCTFail("Expected error to be thrown")
        } catch {
            // Expected error
        }
        
        // Simulate recovery operation
        _ = try await logger.measureOperation("Recovery Operation", sessionId: sessionId) {
            try await Task.sleep(nanoseconds: 8_000_000) // 8ms
            return "recovered"
        }
        
        logger.endSession(sessionId)
        
        // Verify error handling was logged correctly
        let sessions = await logger.getRecentSessions(limit: 1)
        let session = sessions.first!
        
        XCTAssertEqual(session.entries.count, 3)
        XCTAssertEqual(session.entries[0].operation, "Successful Operation")
        XCTAssertTrue(session.entries[1].operation.contains("Failed Operation"))
        XCTAssertTrue(session.entries[1].operation.contains("failed"))
        XCTAssertEqual(session.entries[2].operation, "Recovery Operation")
        
        // Verify session completed despite error
        XCTAssertTrue(session.isCompleted)
    }
    
    @MainActor
    func testModelSwitchingScenario() async throws {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        let sessionId = logger.startSession()
        
        // Simulate trying Gemini first
        let geminiModel = ModelInfo(serviceName: "Gemini", modelName: "gemini-2.5-flash")
        
        do {
            _ = try await logger.measureOperation("Gemini Processing", sessionId: sessionId, modelInfo: geminiModel) {
                try await Task.sleep(nanoseconds: 50_000_000) // 50ms
                // Simulate Gemini failure
                throw NSError(domain: "GeminiError", code: 429, userInfo: [NSLocalizedDescriptionKey: "Rate limit exceeded"])
            }
        } catch {
            // Expected Gemini failure
        }
        
        // Fallback to Vision
        let visionModel = ModelInfo(serviceName: "Vision", modelName: "Apple Vision")
        let result = try await logger.measureOperation("Vision Processing (Fallback)", sessionId: sessionId, modelInfo: visionModel) {
            try await Task.sleep(nanoseconds: 75_000_000) // 75ms
            return "Vision processing successful"
        }
        
        XCTAssertEqual(result, "Vision processing successful")
        
        logger.endSession(sessionId)
        
        // Verify model switching was logged
        let sessions = await logger.getRecentSessions(limit: 1)
        let session = sessions.first!
        
        XCTAssertEqual(session.entries.count, 2)
        
        let geminiEntry = session.entries[0]
        XCTAssertTrue(geminiEntry.operation.contains("Gemini Processing"))
        XCTAssertTrue(geminiEntry.operation.contains("failed"))
        XCTAssertEqual(geminiEntry.modelInfo?.serviceName, "Gemini")
        
        let visionEntry = session.entries[1]
        XCTAssertEqual(visionEntry.operation, "Vision Processing (Fallback)")
        XCTAssertEqual(visionEntry.modelInfo?.serviceName, "Vision")
    }
}
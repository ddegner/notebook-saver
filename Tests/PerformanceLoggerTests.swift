import XCTest
@testable import Cat_Scribe

final class PerformanceLoggerTests: XCTestCase {
    
    @MainActor
    func testPerformanceLoggerBasicFunctionality() async {
        let logger = PerformanceLogger.shared
        
        // Clear any existing logs
        logger.clearOldLogs()
        
        // Start a session
        let sessionId = logger.startSession()
        XCTAssertNotNil(sessionId)
        
        // Log an operation
        logger.logOperation("Test Operation", duration: 0.123, sessionId: sessionId)
        
        // End the session
        logger.endSession(sessionId)
        
        // Verify session was recorded
        let sessions = await logger.getRecentSessions(limit: 1)
        XCTAssertEqual(sessions.count, 1)
        
        let session = sessions.first!
        XCTAssertEqual(session.id, sessionId)
        XCTAssertEqual(session.entries.count, 1)
        XCTAssertTrue(session.isCompleted)
        
        let entry = session.entries.first!
        XCTAssertEqual(entry.operation, "Test Operation")
        XCTAssertEqual(entry.duration, 0.123, accuracy: 0.001)
    }
    
    @MainActor
    func testModelInfoLogging() async {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        let sessionId = logger.startSession()
        let modelInfo = ModelInfo(serviceName: "Gemini", modelName: "gemini-2.5-flash")
        
        logger.logOperation("AI Processing", duration: 1.5, sessionId: sessionId, modelInfo: modelInfo)
        logger.endSession(sessionId)
        
        let sessions = await logger.getRecentSessions(limit: 1)
        let entry = sessions.first!.entries.first!
        
        XCTAssertNotNil(entry.modelInfo)
        XCTAssertEqual(entry.modelInfo?.serviceName, "Gemini")
        XCTAssertEqual(entry.modelInfo?.modelName, "gemini-2.5-flash")
    }
    
    @MainActor
    func testMeasureOperation() async throws {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        let sessionId = logger.startSession()
        
        // Test async operation measurement
        let result = try await logger.measureOperation("Async Test", sessionId: sessionId) {
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            return "Success"
        }
        
        XCTAssertEqual(result, "Success")
        logger.endSession(sessionId)
        
        let sessions = await logger.getRecentSessions(limit: 1)
        let entry = sessions.first!.entries.first!
        
        XCTAssertEqual(entry.operation, "Async Test")
        XCTAssertGreaterThan(entry.duration, 0.05) // Should be at least 0.05 seconds
    }
    
    @MainActor
    func testDeviceContextCreation() {
        let context = DeviceContext()
        
        XCTAssertFalse(context.deviceModel.isEmpty)
        XCTAssertFalse(context.osVersion.isEmpty)
        XCTAssertFalse(context.appVersion.isEmpty)
        XCTAssertNotNil(context.timestamp)
    }
    
    @MainActor
    func testLogFormatting() async {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        let sessionId = logger.startSession()
        logger.logOperation("Test Op 1", duration: 0.5, sessionId: sessionId)
        logger.logOperation("Test Op 2", duration: 1.0, sessionId: sessionId)
        logger.endSession(sessionId)
        
        let formattedLogs = await logger.getFormattedLogs()
        
        XCTAssertTrue(formattedLogs.contains("NotebookSaver Performance Log"))
        XCTAssertTrue(formattedLogs.contains("Test Op 1"))
        XCTAssertTrue(formattedLogs.contains("Test Op 2"))
        XCTAssertTrue(formattedLogs.contains("0.500s"))
        XCTAssertTrue(formattedLogs.contains("1.000s"))
    }
    
    // MARK: - New Timing Utilities Tests
    
    @MainActor
    func testManualTiming() async {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        let sessionId = logger.startSession()
        
        // Test manual timing with success
        let token = logger.startTiming("Manual Operation", sessionId: sessionId)
        XCTAssertNotNil(token)
        
        // Simulate some work
        try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
        
        logger.endTiming(token!, success: true)
        logger.endSession(sessionId)
        
        let sessions = await logger.getRecentSessions(limit: 1)
        let entry = sessions.first!.entries.first!
        
        XCTAssertEqual(entry.operation, "Manual Operation")
        XCTAssertGreaterThan(entry.duration, 0.03) // Should be at least 0.03 seconds
    }
    
    @MainActor
    func testManualTimingWithError() async {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        let sessionId = logger.startSession()
        
        let token = logger.startTiming("Manual Error Operation", sessionId: sessionId)
        XCTAssertNotNil(token)
        
        // Simulate error scenario
        let testError = NSError(domain: "TestError", code: 1, userInfo: nil)
        logger.endTiming(token!, error: testError)
        logger.endSession(sessionId)
        
        let sessions = await logger.getRecentSessions(limit: 1)
        let entry = sessions.first!.entries.first!
        
        XCTAssertTrue(entry.operation.contains("Manual Error Operation"))
        XCTAssertTrue(entry.operation.contains("failed"))
    }
    
    @MainActor
    func testSequentialOperations() async throws {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        let sessionId = logger.startSession()
        
        let operations: [(name: String, block: () async throws -> String)] = [
            ("Op 1", { try await Task.sleep(nanoseconds: 10_000_000); return "Result 1" }),
            ("Op 2", { try await Task.sleep(nanoseconds: 20_000_000); return "Result 2" }),
            ("Op 3", { return "Result 3" })
        ]
        
        let results = try await logger.measureSequentialOperations(operations, sessionId: sessionId)
        logger.endSession(sessionId)
        
        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[0], "Result 1")
        XCTAssertEqual(results[1], "Result 2")
        XCTAssertEqual(results[2], "Result 3")
        
        let sessions = await logger.getRecentSessions(limit: 1)
        XCTAssertEqual(sessions.first!.entries.count, 3)
    }
    
    @MainActor
    func testOperationWithCondition() async throws {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        let sessionId = logger.startSession()
        
        // Test successful condition
        let result1 = try await logger.measureOperationWithCondition(
            "Conditional Success",
            sessionId: sessionId,
            successCondition: { (value: Int) in value > 5 }
        ) {
            return 10
        }
        
        XCTAssertEqual(result1, 10)
        
        // Test failed condition
        let result2 = try await logger.measureOperationWithCondition(
            "Conditional Failure",
            sessionId: sessionId,
            successCondition: { (value: Int) in value > 5 }
        ) {
            return 3
        }
        
        XCTAssertEqual(result2, 3)
        logger.endSession(sessionId)
        
        let sessions = await logger.getRecentSessions(limit: 1)
        let entries = sessions.first!.entries
        
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].operation, "Conditional Success")
        XCTAssertTrue(entries[1].operation.contains("condition failed"))
    }
    
    @MainActor
    func testOperationWithTimeout() async throws {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        let sessionId = logger.startSession()
        
        // Test successful operation within timeout
        let result = try await logger.measureOperationWithTimeout(
            "Quick Operation",
            sessionId: sessionId,
            timeout: 1.0
        ) {
            try await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
            return "Success"
        }
        
        XCTAssertEqual(result, "Success")
        logger.endSession(sessionId)
        
        let sessions = await logger.getRecentSessions(limit: 1)
        let entry = sessions.first!.entries.first!
        
        XCTAssertEqual(entry.operation, "Quick Operation")
        XCTAssertLessThan(entry.duration, 1.0)
    }
    
    @MainActor
    func testTimestampUtilities() {
        let logger = PerformanceLogger.shared
        
        let start = logger.getCurrentTimestamp()
        Thread.sleep(forTimeInterval: 0.01) // 0.01 seconds
        let end = logger.getCurrentTimestamp()
        
        let duration = logger.calculateDuration(from: start, to: end)
        
        XCTAssertGreaterThan(duration, 0.005) // Should be at least 0.005 seconds
        XCTAssertLessThan(duration, 0.1) // Should be less than 0.1 seconds
    }
    
    @MainActor
    func testPreCalculatedOperation() async {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        let sessionId = logger.startSession()
        
        let start = logger.getCurrentTimestamp()
        Thread.sleep(forTimeInterval: 0.05) // 0.05 seconds
        let end = logger.getCurrentTimestamp()
        
        logger.logPreCalculatedOperation(
            "Pre-calculated Op",
            startTimestamp: start,
            endTimestamp: end,
            sessionId: sessionId,
            success: true
        )
        
        logger.endSession(sessionId)
        
        let sessions = await logger.getRecentSessions(limit: 1)
        let entry = sessions.first!.entries.first!
        
        XCTAssertEqual(entry.operation, "Pre-calculated Op")
        XCTAssertGreaterThan(entry.duration, 0.03) // Should be at least 0.03 seconds
    }
    
    @MainActor
    func testBatchLogOperations() async {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        let sessionId = logger.startSession()
        
        let operations = [
            (name: "Batch Op 1", duration: 0.1, modelInfo: nil as ModelInfo?, success: true),
            (name: "Batch Op 2", duration: 0.2, modelInfo: nil as ModelInfo?, success: false),
            (name: "Batch Op 3", duration: 0.3, modelInfo: nil as ModelInfo?, success: true)
        ]
        
        logger.batchLogOperations(operations, sessionId: sessionId)
        logger.endSession(sessionId)
        
        let sessions = await logger.getRecentSessions(limit: 1)
        let entries = sessions.first!.entries
        
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0].operation, "Batch Op 1")
        XCTAssertTrue(entries[1].operation.contains("failed"))
        XCTAssertEqual(entries[2].operation, "Batch Op 3")
    }
    
    @MainActor
    func testSessionManagement() async {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        // Test regular session
        let sessionId = logger.startSession()
        
        // Test session duration
        let duration = await logger.getSessionDuration(sessionId)
        XCTAssertNotNil(duration)
        XCTAssertGreaterThanOrEqual(duration!, 0)
        
        // Test session has no operations initially
        var hasOps = await logger.sessionHasOperations(sessionId)
        XCTAssertFalse(hasOps) // Should have no operations initially
        
        // Add an operation to test
        logger.logOperation("Test Operation", duration: 1.0, sessionId: sessionId)
        hasOps = await logger.sessionHasOperations(sessionId)
        XCTAssertTrue(hasOps) // Should now have operations
        
        // Test session cancellation
        let cancelSessionId = logger.startSession()
        logger.cancelSession(cancelSessionId)
        
        let cancelDuration = await logger.getSessionDuration(cancelSessionId)
        XCTAssertNil(cancelDuration) // Should be nil after cancellation
        
        logger.endSession(sessionId)
    }
    
    @MainActor
    func testSyncOperationMeasurement() throws {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        let sessionId = logger.startSession()
        
        // Test sync operation measurement
        let result = try logger.measureSyncOperation("Sync Test", sessionId: sessionId) {
            Thread.sleep(forTimeInterval: 0.01) // 0.01 seconds
            return "Sync Success"
        }
        
        XCTAssertEqual(result, "Sync Success")
        logger.endSession(sessionId)
    }
    
    @MainActor
    func testVoidOperations() async throws {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        let sessionId = logger.startSession()
        
        // Test void async operation
        try await logger.measureVoidOperation("Void Async", sessionId: sessionId) {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        
        // Test void sync operation
        try logger.measureVoidSyncOperation("Void Sync", sessionId: sessionId) {
            Thread.sleep(forTimeInterval: 0.01)
        }
        
        logger.endSession(sessionId)
        
        let sessions = await logger.getRecentSessions(limit: 1)
        XCTAssertEqual(sessions.first!.entries.count, 2)
    }
    
    // MARK: - Log Management and Cleanup Tests
    
    @MainActor
    func testStorageInfo() async {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        // Create some test sessions
        for i in 0..<5 {
            let sessionId = logger.startSession()
            logger.logOperation("Test Op \(i)", duration: 0.1, sessionId: sessionId)
            logger.endSession(sessionId)
        }
        
        let storageInfo = await logger.getStorageInfo()
        
        XCTAssertEqual(storageInfo.sessionCount, 5)
        XCTAssertGreaterThan(storageInfo.estimatedSizeBytes, 0)
        XCTAssertGreaterThan(storageInfo.maxSizeBytes, 0)
    }
    
    @MainActor
    func testAutomaticCleanup() async {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        // Create more sessions than the limit (50+)
        for i in 0..<55 {
            let sessionId = logger.startSession()
            logger.logOperation("Test Op \(i)", duration: 0.1, sessionId: sessionId)
            logger.endSession(sessionId)
        }
        
        let sessions = await logger.getRecentSessions(limit: 100)
        
        // Should be limited to maxStoredSessions (50)
        XCTAssertLessThanOrEqual(sessions.count, 50)
    }
    
    @MainActor
    func testClearOldLogsOnly() async {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        // Create some sessions
        for i in 0..<10 {
            let sessionId = logger.startSession()
            logger.logOperation("Test Op \(i)", duration: 0.1, sessionId: sessionId)
            logger.endSession(sessionId)
        }
        
        let sessionsBefore = await logger.getRecentSessions(limit: 100)
        XCTAssertEqual(sessionsBefore.count, 10)
        
        // Clear old logs only (should not remove anything since we're under limit)
        logger.clearOldLogsOnly()
        
        let sessionsAfter = await logger.getRecentSessions(limit: 100)
        XCTAssertEqual(sessionsAfter.count, 10)
    }
    
    @MainActor
    func testEnhancedDeviceContext() {
        let context = DeviceContext()
        
        // Test original fields
        XCTAssertFalse(context.deviceModel.isEmpty)
        XCTAssertFalse(context.osVersion.isEmpty)
        XCTAssertFalse(context.appVersion.isEmpty)
        XCTAssertNotNil(context.timestamp)
        
        // Test new fields
        XCTAssertFalse(context.memoryPressure.isEmpty)
        XCTAssertGreaterThanOrEqual(context.batteryLevel, -1.0) // -1 means unknown, >= 0 means valid
        XCTAssertFalse(context.thermalState.isEmpty)
    }
    
    @MainActor
    func testCompleteAllActiveSessions() async {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        // Start multiple sessions without ending them
        let sessionId1 = logger.startSession()
        let sessionId2 = logger.startSession()
        let sessionId3 = logger.startSession()
        
        logger.logOperation("Op 1", duration: 0.1, sessionId: sessionId1)
        logger.logOperation("Op 2", duration: 0.2, sessionId: sessionId2)
        logger.logOperation("Op 3", duration: 0.3, sessionId: sessionId3)
        
        // Verify sessions are active
        let activeInfo = await logger.getActiveSessionInfo()
        XCTAssertEqual(activeInfo.count, 3)
        
        // Complete all active sessions
        logger.completeAllActiveSessions()
        
        // Verify no active sessions remain
        let activeInfoAfter = await logger.getActiveSessionInfo()
        XCTAssertEqual(activeInfoAfter.count, 0)
        
        // Verify sessions were completed and saved
        let completedSessions = await logger.getRecentSessions(limit: 10)
        XCTAssertEqual(completedSessions.count, 3)
        
        for session in completedSessions {
            XCTAssertTrue(session.isCompleted)
        }
    }
    
    @MainActor
    func testSessionCancellation() async {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        let sessionId = logger.startSession()
        logger.logOperation("Test Op", duration: 0.1, sessionId: sessionId)
        
        // Verify session exists
        let activeInfo = await logger.getActiveSessionInfo()
        XCTAssertEqual(activeInfo.count, 1)
        
        // Cancel the session
        logger.cancelSession(sessionId)
        
        // Verify session was removed but not saved as completed
        let activeInfoAfter = await logger.getActiveSessionInfo()
        XCTAssertEqual(activeInfoAfter.count, 0)
        
        let completedSessions = await logger.getRecentSessions(limit: 10)
        XCTAssertEqual(completedSessions.count, 0)
    }
    
    // MARK: - Timing Accuracy Tests
    
    @MainActor
    func testTimingAccuracy() async throws {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        let sessionId = logger.startSession()
        
        // Test timing accuracy with known sleep duration
        let expectedDuration: TimeInterval = 0.1 // 100ms
        let tolerance: TimeInterval = 0.05 // 50ms tolerance
        
        let result = try await logger.measureOperation("Timing Accuracy Test", sessionId: sessionId) {
            try await Task.sleep(nanoseconds: UInt64(expectedDuration * 1_000_000_000))
            return "Success"
        }
        
        XCTAssertEqual(result, "Success")
        logger.endSession(sessionId)
        
        let sessions = await logger.getRecentSessions(limit: 1)
        let entry = sessions.first!.entries.first!
        
        // Verify timing is within acceptable tolerance
        XCTAssertEqual(entry.duration, expectedDuration, accuracy: tolerance)
    }
    
    @MainActor
    func testHighPrecisionTiming() {
        let logger = PerformanceLogger.shared
        
        // Test getCurrentTimestamp precision
        let start = logger.getCurrentTimestamp()
        Thread.sleep(forTimeInterval: 0.001) // 1ms
        let end = logger.getCurrentTimestamp()
        
        let duration = logger.calculateDuration(from: start, to: end)
        
        // Should be at least 1ms but less than 10ms
        XCTAssertGreaterThan(duration, 0.0005) // 0.5ms minimum
        XCTAssertLessThan(duration, 0.01) // 10ms maximum
    }
    
    @MainActor
    func testConcurrentTimingOperations() async throws {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        let sessionId = logger.startSession()
        
        // Run multiple concurrent operations
        let operations = (0..<5).map { index in
            Task {
                try await logger.measureOperation("Concurrent Op \(index)", sessionId: sessionId) {
                    try await Task.sleep(nanoseconds: UInt64.random(in: 10_000_000...50_000_000)) // 10-50ms
                    return index
                }
            }
        }
        
        let results = try await withThrowingTaskGroup(of: Int.self) { group in
            for operation in operations {
                group.addTask { try await operation.value }
            }
            
            var results: [Int] = []
            for try await result in group {
                results.append(result)
            }
            return results.sorted()
        }
        
        XCTAssertEqual(results, [0, 1, 2, 3, 4])
        logger.endSession(sessionId)
        
        let sessions = await logger.getRecentSessions(limit: 1)
        XCTAssertEqual(sessions.first!.entries.count, 5)
    }
    
    // MARK: - Session Management Tests
    
    @MainActor
    func testSessionLifecycle() async {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        // Test complete session lifecycle
        let sessionId = logger.startSession()
        
        // Verify session is active
        let activeInfo = await logger.getActiveSessionInfo()
        XCTAssertEqual(activeInfo.count, 1)
        XCTAssertEqual(activeInfo[sessionId], 0) // No operations yet
        
        // Add operations
        logger.logOperation("Op 1", duration: 0.1, sessionId: sessionId)
        logger.logOperation("Op 2", duration: 0.2, sessionId: sessionId)
        
        // Verify operations were added
        let activeInfoWithOps = await logger.getActiveSessionInfo()
        XCTAssertEqual(activeInfoWithOps[sessionId], 2)
        
        // Check session duration
        let duration = await logger.getSessionDuration(sessionId)
        XCTAssertNotNil(duration)
        XCTAssertGreaterThan(duration!, 0)
        
        // End session
        logger.endSession(sessionId)
        
        // Verify session is no longer active
        let finalActiveInfo = await logger.getActiveSessionInfo()
        XCTAssertEqual(finalActiveInfo.count, 0)
        
        // Verify session is in completed sessions
        let completedSessions = await logger.getRecentSessions(limit: 1)
        XCTAssertEqual(completedSessions.count, 1)
        XCTAssertTrue(completedSessions.first!.isCompleted)
    }
    
    @MainActor
    func testInvalidSessionOperations() async {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        let invalidSessionId = UUID()
        
        // Test logging to non-existent session
        logger.logOperation("Invalid Session Op", duration: 0.1, sessionId: invalidSessionId)
        
        // Test ending non-existent session
        logger.endSession(invalidSessionId)
        
        // Test canceling non-existent session
        logger.cancelSession(invalidSessionId)
        
        // Verify no sessions were created
        let sessions = await logger.getRecentSessions(limit: 10)
        XCTAssertEqual(sessions.count, 0)
        
        let activeInfo = await logger.getActiveSessionInfo()
        XCTAssertEqual(activeInfo.count, 0)
    }
    
    @MainActor
    func testSessionValidation() async throws {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        let sessionId = logger.startSession()
        
        // Test operation with invalid session should throw
        let invalidSessionId = UUID()
        
        do {
            _ = try await logger.measureOperation("Invalid Session", sessionId: invalidSessionId) {
                return "Should not succeed"
            }
            XCTFail("Expected PerformanceLoggerError.sessionNotFound")
        } catch PerformanceLoggerError.sessionNotFound {
            // Expected error
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        
        logger.endSession(sessionId)
    }
    
    // MARK: - Memory Management and Cleanup Tests
    
    @MainActor
    func testMemoryManagement() async {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        // Create many sessions to test memory management
        let sessionCount = 100
        
        for i in 0..<sessionCount {
            let sessionId = logger.startSession()
            
            // Add multiple operations per session
            for j in 0..<10 {
                logger.logOperation("Op \(j)", duration: Double(j) * 0.01, sessionId: sessionId)
            }
            
            logger.endSession(sessionId)
        }
        
        // Verify automatic cleanup occurred
        let sessions = await logger.getRecentSessions(limit: 200)
        XCTAssertLessThanOrEqual(sessions.count, 50) // Should be limited to maxStoredSessions
        
        // Verify storage info is reasonable
        let storageInfo = await logger.getStorageInfo()
        XCTAssertLessThanOrEqual(storageInfo.sessionCount, 50)
        XCTAssertGreaterThan(storageInfo.estimatedSizeBytes, 0)
        XCTAssertLessThan(storageInfo.estimatedSizeBytes, storageInfo.maxSizeBytes)
    }
    
    @MainActor
    func testStorageLimits() async {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        // Test storage size calculation
        let initialStorageInfo = await logger.getStorageInfo()
        XCTAssertEqual(initialStorageInfo.sessionCount, 0)
        XCTAssertEqual(initialStorageInfo.estimatedSizeBytes, 0)
        
        // Create a session with large operation names to test size limits
        let sessionId = logger.startSession()
        let largeOperationName = String(repeating: "A", count: 1000) // 1KB operation name
        
        for i in 0..<10 {
            logger.logOperation("\(largeOperationName)_\(i)", duration: 0.1, sessionId: sessionId)
        }
        
        logger.endSession(sessionId)
        
        let afterStorageInfo = await logger.getStorageInfo()
        XCTAssertEqual(afterStorageInfo.sessionCount, 1)
        XCTAssertGreaterThan(afterStorageInfo.estimatedSizeBytes, 0)
    }
    
    @MainActor
    func testCleanupMechanisms() async {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        // Create some test sessions
        for i in 0..<10 {
            let sessionId = logger.startSession()
            logger.logOperation("Test Op \(i)", duration: 0.1, sessionId: sessionId)
            logger.endSession(sessionId)
        }
        
        let beforeCleanup = await logger.getRecentSessions(limit: 100)
        XCTAssertEqual(beforeCleanup.count, 10)
        
        // Test clearOldLogsOnly (should not remove anything since we're under limit)
        logger.clearOldLogsOnly()
        
        let afterOldCleanup = await logger.getRecentSessions(limit: 100)
        XCTAssertEqual(afterOldCleanup.count, 10)
        
        // Test clearOldLogs (should remove everything)
        logger.clearOldLogs()
        
        let afterFullCleanup = await logger.getRecentSessions(limit: 100)
        XCTAssertEqual(afterFullCleanup.count, 0)
    }
    
    // MARK: - Error Handling Tests
    
    @MainActor
    func testErrorHandling() async throws {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        let sessionId = logger.startSession()
        
        // Test operation that throws an error
        do {
            _ = try await logger.measureOperation("Error Operation", sessionId: sessionId) {
                throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test error"])
            }
            XCTFail("Expected error to be thrown")
        } catch {
            // Expected error
        }
        
        logger.endSession(sessionId)
        
        // Verify error was logged
        let sessions = await logger.getRecentSessions(limit: 1)
        let entry = sessions.first!.entries.first!
        
        XCTAssertTrue(entry.operation.contains("Error Operation"))
        XCTAssertTrue(entry.operation.contains("failed"))
    }
    
    @MainActor
    func testInvalidOperationData() {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        let sessionId = logger.startSession()
        
        // Test logging with empty operation name
        logger.logOperation("", duration: 0.1, sessionId: sessionId)
        logger.logOperation("   ", duration: 0.1, sessionId: sessionId) // Whitespace only
        
        // Test logging with invalid duration
        logger.logOperation("Negative Duration", duration: -1.0, sessionId: sessionId)
        logger.logOperation("Excessive Duration", duration: 7200.0, sessionId: sessionId) // 2 hours
        
        // Test logging with valid operation
        logger.logOperation("Valid Operation", duration: 0.1, sessionId: sessionId)
        
        logger.endSession(sessionId)
        
        // Only the valid operation should be logged
        Task {
            let sessions = await logger.getRecentSessions(limit: 1)
            let entries = sessions.first?.entries ?? []
            
            // Should only have the valid operation
            XCTAssertEqual(entries.count, 1)
            XCTAssertEqual(entries.first?.operation, "Valid Operation")
        }
    }
    
    // MARK: - Integration Tests
    
    @MainActor
    func testPipelineIntegration() async throws {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        // Simulate a complete photo processing pipeline
        let sessionId = logger.startSession()
        
        // Simulate camera capture
        _ = try await logger.measureOperation("Photo Capture", sessionId: sessionId) {
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
            return "photo_data"
        }
        
        // Simulate image preprocessing
        _ = try await logger.measureOperation("Image Preprocessing", sessionId: sessionId) {
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            return "processed_image"
        }
        
        // Simulate AI processing with model info
        let geminiModel = ModelInfo(serviceName: "Gemini", modelName: "gemini-2.5-flash")
        _ = try await logger.measureOperation("Text Extraction", sessionId: sessionId, modelInfo: geminiModel) {
            try await Task.sleep(nanoseconds: 200_000_000) // 200ms
            return "extracted_text"
        }
        
        // Simulate note creation
        _ = try await logger.measureOperation("Note Creation", sessionId: sessionId) {
            try await Task.sleep(nanoseconds: 30_000_000) // 30ms
            return "note_created"
        }
        
        logger.endSession(sessionId)
        
        // Verify complete pipeline was logged
        let sessions = await logger.getRecentSessions(limit: 1)
        let session = sessions.first!
        
        XCTAssertEqual(session.entries.count, 4)
        XCTAssertTrue(session.isCompleted)
        XCTAssertNotNil(session.totalDuration)
        XCTAssertGreaterThan(session.totalDuration!, 0.3) // Should be at least 380ms
        
        // Verify model info was captured
        let aiEntry = session.entries.first { $0.operation == "Text Extraction" }
        XCTAssertNotNil(aiEntry?.modelInfo)
        XCTAssertEqual(aiEntry?.modelInfo?.serviceName, "Gemini")
    }
    
    @MainActor
    func testPerformanceImpact() async throws {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        // Measure the overhead of logging itself
        let iterations = 100
        
        // Measure without logging
        let startWithoutLogging = CFAbsoluteTimeGetCurrent()
        for i in 0..<iterations {
            try await Task.sleep(nanoseconds: 1_000_000) // 1ms
        }
        let durationWithoutLogging = CFAbsoluteTimeGetCurrent() - startWithoutLogging
        
        // Measure with logging
        let sessionId = logger.startSession()
        let startWithLogging = CFAbsoluteTimeGetCurrent()
        
        for i in 0..<iterations {
            _ = try await logger.measureOperation("Performance Test \(i)", sessionId: sessionId) {
                try await Task.sleep(nanoseconds: 1_000_000) // 1ms
                return i
            }
        }
        
        let durationWithLogging = CFAbsoluteTimeGetCurrent() - startWithLogging
        logger.endSession(sessionId)
        
        // Logging overhead should be minimal (less than 50% increase)
        let overhead = (durationWithLogging - durationWithoutLogging) / durationWithoutLogging
        XCTAssertLessThan(overhead, 0.5, "Logging overhead should be less than 50%")
        
        // Verify all operations were logged
        let sessions = await logger.getRecentSessions(limit: 1)
        XCTAssertEqual(sessions.first!.entries.count, iterations)
    }
    
    // MARK: - Data Model Tests
    
    func testModelInfoEquality() {
        let model1 = ModelInfo(serviceName: "Gemini", modelName: "gemini-2.5-flash")
        let model2 = ModelInfo(serviceName: "Gemini", modelName: "gemini-2.5-flash")
        let model3 = ModelInfo(serviceName: "Vision", modelName: "Apple Vision")
        
        XCTAssertEqual(model1, model2)
        XCTAssertNotEqual(model1, model3)
    }
    
    func testImageMetadata() {
        // Test ImageMetadata creation and computed properties
        let imageMetadata = ImageMetadata(
            originalWidth: 1920,
            originalHeight: 1080,
            processedWidth: 800,
            processedHeight: 600,
            originalFileSizeBytes: 1_000_000, // 1MB
            processedFileSizeBytes: 200_000,  // 200KB
            compressionQuality: 0.6,
            imageFormat: "HEIC"
        )
        
        // Test basic properties
        XCTAssertEqual(imageMetadata.originalWidth, 1920)
        XCTAssertEqual(imageMetadata.originalHeight, 1080)
        XCTAssertEqual(imageMetadata.processedWidth, 800)
        XCTAssertEqual(imageMetadata.processedHeight, 600)
        XCTAssertEqual(imageMetadata.originalFileSizeBytes, 1_000_000)
        XCTAssertEqual(imageMetadata.processedFileSizeBytes, 200_000)
        XCTAssertEqual(imageMetadata.compressionQuality, 0.6)
        XCTAssertEqual(imageMetadata.imageFormat, "HEIC")
        
        // Test computed properties
        XCTAssertEqual(imageMetadata.originalPixelCount, 1920 * 1080)
        XCTAssertEqual(imageMetadata.processedPixelCount, 800 * 600)
        XCTAssertEqual(imageMetadata.compressionRatio, 0.2, accuracy: 0.001) // 200KB / 1MB = 0.2
        
        let expectedResolutionRatio = Double(800 * 600) / Double(1920 * 1080)
        XCTAssertEqual(imageMetadata.resolutionReductionRatio, expectedResolutionRatio, accuracy: 0.001)
    }
    
    func testModelInfoWithImageMetadata() {
        let imageMetadata = ImageMetadata(
            originalWidth: 1024,
            originalHeight: 768,
            processedWidth: 512,
            processedHeight: 384,
            originalFileSizeBytes: 500_000,
            processedFileSizeBytes: 100_000,
            compressionQuality: 0.8,
            imageFormat: "JPEG"
        )
        
        let modelInfo = ModelInfo(
            serviceName: "Gemini",
            modelName: "gemini-2.5-flash",
            configuration: ["thinking_enabled": "true"],
            imageMetadata: imageMetadata
        )
        
        XCTAssertEqual(modelInfo.serviceName, "Gemini")
        XCTAssertEqual(modelInfo.modelName, "gemini-2.5-flash")
        XCTAssertEqual(modelInfo.configuration?["thinking_enabled"], "true")
        XCTAssertNotNil(modelInfo.imageMetadata)
        XCTAssertEqual(modelInfo.imageMetadata?.originalWidth, 1024)
        XCTAssertEqual(modelInfo.imageMetadata?.processedWidth, 512)
        XCTAssertEqual(modelInfo.imageMetadata?.imageFormat, "JPEG")
    }
    
    func testPerformanceLogFormatterWithImageMetadata() {
        // Create a log session with image metadata
        let deviceContext = DeviceContext()
        var session = LogSession(deviceContext: deviceContext)
        
        // Create image metadata
        let imageMetadata = ImageMetadata(
            originalWidth: 1920,
            originalHeight: 1080,
            processedWidth: 800,
            processedHeight: 600,
            originalFileSizeBytes: 1_000_000, // 1MB
            processedFileSizeBytes: 200_000,  // 200KB
            compressionQuality: 0.6,
            imageFormat: "HEIC"
        )
        
        // Create model info with image metadata
        let modelInfo = ModelInfo(
            serviceName: "Gemini",
            modelName: "gemini-2.5-flash",
            configuration: ["thinking_enabled": "true"],
            imageMetadata: imageMetadata
        )
        
        // Create a log entry
        let entry = LogEntry(
            operation: "Gemini API Request",
            startTime: Date(),
            duration: 2.5,
            modelInfo: modelInfo,
            deviceContext: deviceContext
        )
        
        session.addEntry(entry)
        session.complete()
        
        // Format the logs
        let formattedLogs = PerformanceLogFormatter.formatLogs([session])
        
        // Verify the formatted output contains image metadata
        XCTAssertTrue(formattedLogs.contains("Gemini API Request: 2.500s"))
        XCTAssertTrue(formattedLogs.contains("Gemini/gemini-2.5-flash"))
        XCTAssertTrue(formattedLogs.contains("img: 800x600"))
        XCTAssertTrue(formattedLogs.contains("compressed 20.0%")) // 200KB / 1MB = 20%
        XCTAssertTrue(formattedLogs.contains("from 1920x1080"))
        XCTAssertTrue(formattedLogs.contains("thinking_enabled=true"))
        
        // Verify image processing statistics section
        XCTAssertTrue(formattedLogs.contains("Image Processing Statistics:"))
        XCTAssertTrue(formattedLogs.contains("Images Processed: 1"))
        
        print("Sample formatted log output:")
        print(formattedLogs)
    }
    
    func testLogEntryEquality() {
        let deviceContext = DeviceContext()
        let modelInfo = ModelInfo(serviceName: "Test", modelName: "test-model")
        
        let entry1 = LogEntry(operation: "Test Op", startTime: Date(), duration: 1.0, modelInfo: modelInfo, deviceContext: deviceContext)
        let entry2 = LogEntry(operation: "Test Op", startTime: Date(), duration: 1.0, modelInfo: modelInfo, deviceContext: deviceContext)
        
        // Should not be equal due to different UUIDs
        XCTAssertNotEqual(entry1, entry2)
        XCTAssertNotEqual(entry1.id, entry2.id)
    }
    
    func testLogSessionEquality() {
        let deviceContext = DeviceContext()
        
        let session1 = LogSession(deviceContext: deviceContext)
        let session2 = LogSession(deviceContext: deviceContext)
        
        // Should not be equal due to different UUIDs and timestamps
        XCTAssertNotEqual(session1, session2)
        XCTAssertNotEqual(session1.id, session2.id)
    }
    
    func testDeviceContextFields() {
        let context = DeviceContext()
        
        // Test all required fields are populated
        XCTAssertFalse(context.deviceModel.isEmpty)
        XCTAssertFalse(context.osVersion.isEmpty)
        XCTAssertFalse(context.appVersion.isEmpty)
        XCTAssertNotNil(context.timestamp)
        XCTAssertFalse(context.memoryPressure.isEmpty)
        XCTAssertGreaterThanOrEqual(context.batteryLevel, -1.0)
        XCTAssertFalse(context.thermalState.isEmpty)
        
        // Test OS version format
        XCTAssertTrue(context.osVersion.contains("."))
        
        // Test memory pressure format
        XCTAssertTrue(context.memoryPressure.contains("MB") || context.memoryPressure == "Unknown")
        
        // Test thermal state values
        let validThermalStates = ["Normal", "Fair", "Serious", "Critical", "Unknown"]
        XCTAssertTrue(validThermalStates.contains(context.thermalState))
    }
}
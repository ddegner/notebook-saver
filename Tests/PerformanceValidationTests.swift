import XCTest
@testable import Cat_Scribe

/// Performance validation and optimization tests for the PerformanceLogger
/// These tests validate that logging has minimal performance impact and maintains accuracy
final class PerformanceValidationTests: XCTestCase {
    
    // MARK: - Logging Overhead Measurement Tests
    
    @MainActor
    func testMinimalLoggingOverhead() async throws {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        let iterations = 1000
        let baseOperationDuration: UInt64 = 1_000_000 // 1ms
        
        // Measure baseline performance without any logging
        let baselineStart = CFAbsoluteTimeGetCurrent()
        for i in 0..<iterations {
            try await Task.sleep(nanoseconds: baseOperationDuration)
        }
        let baselineDuration = CFAbsoluteTimeGetCurrent() - baselineStart
        
        // Measure performance with full logging
        let sessionId = logger.startSession()
        let loggedStart = CFAbsoluteTimeGetCurrent()
        
        for i in 0..<iterations {
            _ = try await logger.measureOperation("Overhead Test \(i)", sessionId: sessionId) {
                try await Task.sleep(nanoseconds: baseOperationDuration)
                return i
            }
        }
        
        let loggedDuration = CFAbsoluteTimeGetCurrent() - loggedStart
        logger.endSession(sessionId)
        
        // Calculate and validate overhead
        let overhead = (loggedDuration - baselineDuration) / baselineDuration
        let overheadPercentage = overhead * 100
        
        // Logging overhead should be less than 10% for requirement 4.1 (minimal performance impact)
        XCTAssertLessThan(overhead, 0.10, "Logging overhead (\(String(format: "%.2f", overheadPercentage))%) exceeds 10% threshold")
        
        // Verify all operations were logged correctly
        let sessions = await logger.getRecentSessions(limit: 1)
        XCTAssertEqual(sessions.first!.entries.count, iterations)
        
        print("Logging Overhead Test Results:")
        print("Iterations: \(iterations)")
        print("Baseline duration: \(String(format: "%.3f", baselineDuration))s")
        print("Logged duration: \(String(format: "%.3f", loggedDuration))s")
        print("Overhead: \(String(format: "%.2f", overheadPercentage))%")
        print("Per-operation overhead: \(String(format: "%.3f", (loggedDuration - baselineDuration) / Double(iterations) * 1000))ms")
    }
    
    @MainActor
    func testSyncOperationOverhead() throws {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        let iterations = 500
        let operationDuration: TimeInterval = 0.002 // 2ms
        
        // Measure baseline sync performance
        let baselineStart = CFAbsoluteTimeGetCurrent()
        for i in 0..<iterations {
            Thread.sleep(forTimeInterval: operationDuration)
        }
        let baselineDuration = CFAbsoluteTimeGetCurrent() - baselineStart
        
        // Measure sync performance with logging
        let sessionId = logger.startSession()
        let loggedStart = CFAbsoluteTimeGetCurrent()
        
        for i in 0..<iterations {
            _ = try logger.measureSyncOperation("Sync Overhead Test \(i)", sessionId: sessionId) {
                Thread.sleep(forTimeInterval: operationDuration)
                return i
            }
        }
        
        let loggedDuration = CFAbsoluteTimeGetCurrent() - loggedStart
        logger.endSession(sessionId)
        
        // Calculate overhead for sync operations
        let overhead = (loggedDuration - baselineDuration) / baselineDuration
        
        // Sync operations should also have minimal overhead
        XCTAssertLessThan(overhead, 0.15, "Sync logging overhead (\(String(format: "%.2f", overhead * 100))%) exceeds 15% threshold")
        
        print("Sync Operation Overhead Test Results:")
        print("Overhead: \(String(format: "%.2f", overhead * 100))%")
    }
    
    @MainActor
    func testManualTimingOverhead() {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        let iterations = 1000
        let sessionId = logger.startSession()
        
        // Measure manual timing overhead
        let overheadStart = CFAbsoluteTimeGetCurrent()
        
        for i in 0..<iterations {
            let token = logger.startTiming("Manual Timing Test \(i)", sessionId: sessionId)
            // Simulate minimal work
            let _ = CFAbsoluteTimeGetCurrent()
            logger.endTiming(token!, success: true)
        }
        
        let overheadDuration = CFAbsoluteTimeGetCurrent() - overheadStart
        logger.endSession(sessionId)
        
        // Manual timing should be very fast (less than 0.1ms per operation)
        let perOperationOverhead = overheadDuration / Double(iterations)
        XCTAssertLessThan(perOperationOverhead, 0.0001, "Manual timing overhead (\(String(format: "%.4f", perOperationOverhead * 1000))ms) is too high")
        
        print("Manual Timing Overhead: \(String(format: "%.4f", perOperationOverhead * 1000))ms per operation")
    }
    
    // MARK: - Timing Accuracy Validation Tests
    
    @MainActor
    func testTimingAccuracyPrecision() async throws {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        let sessionId = logger.startSession()
        
        // Test various sleep durations for accuracy
        let testDurations: [TimeInterval] = [0.001, 0.005, 0.010, 0.050, 0.100, 0.500] // 1ms to 500ms
        let tolerance: TimeInterval = 0.010 // 10ms tolerance
        
        for expectedDuration in testDurations {
            let result = try await logger.measureOperation("Accuracy Test \(expectedDuration)s", sessionId: sessionId) {
                try await Task.sleep(nanoseconds: UInt64(expectedDuration * 1_000_000_000))
                return expectedDuration
            }
            
            XCTAssertEqual(result, expectedDuration)
        }
        
        logger.endSession(sessionId)
        
        // Verify timing accuracy
        let sessions = await logger.getRecentSessions(limit: 1)
        let entries = sessions.first!.entries
        
        for (index, entry) in entries.enumerated() {
            let expectedDuration = testDurations[index]
            let measuredDuration = entry.duration
            let accuracy = abs(measuredDuration - expectedDuration)
            
            XCTAssertLessThan(accuracy, tolerance, 
                "Timing accuracy for \(expectedDuration)s operation: expected \(expectedDuration)s, got \(measuredDuration)s (error: \(accuracy)s)")
        }
        
        print("Timing Accuracy Results:")
        for (index, entry) in entries.enumerated() {
            let expected = testDurations[index]
            let measured = entry.duration
            let error = abs(measured - expected)
            print("Expected: \(String(format: "%.3f", expected))s, Measured: \(String(format: "%.3f", measured))s, Error: \(String(format: "%.3f", error))s")
        }
    }
    
    @MainActor
    func testHighPrecisionTimingAccuracy() {
        let logger = PerformanceLogger.shared
        
        // Test high-precision timing utilities
        let measurements: [(expected: TimeInterval, actual: TimeInterval)] = []
        var results: [(expected: TimeInterval, actual: TimeInterval)] = []
        
        for expectedMs in [1, 2, 5, 10, 20] {
            let expectedDuration = TimeInterval(expectedMs) / 1000.0 // Convert to seconds
            
            let start = logger.getCurrentTimestamp()
            Thread.sleep(forTimeInterval: expectedDuration)
            let end = logger.getCurrentTimestamp()
            
            let measuredDuration = logger.calculateDuration(from: start, to: end)
            results.append((expected: expectedDuration, actual: measuredDuration))
        }
        
        // Validate high-precision measurements
        for (expected, actual) in results {
            let error = abs(actual - expected)
            let errorPercentage = (error / expected) * 100
            
            // High-precision timing should be within 20% for short durations
            XCTAssertLessThan(errorPercentage, 20.0, 
                "High-precision timing error (\(String(format: "%.1f", errorPercentage))%) exceeds 20% for \(expected)s duration")
        }
        
        print("High-Precision Timing Results:")
        for (expected, actual) in results {
            let error = abs(actual - expected)
            print("Expected: \(String(format: "%.3f", expected))s, Actual: \(String(format: "%.3f", actual))s, Error: \(String(format: "%.3f", error))s")
        }
    }
    
    @MainActor
    func testTimingConsistency() async throws {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        let sessionId = logger.startSession()
        let fixedDuration: TimeInterval = 0.050 // 50ms
        let iterations = 20
        
        var measurements: [TimeInterval] = []
        
        // Perform multiple measurements of the same operation
        for i in 0..<iterations {
            _ = try await logger.measureOperation("Consistency Test \(i)", sessionId: sessionId) {
                try await Task.sleep(nanoseconds: UInt64(fixedDuration * 1_000_000_000))
                return i
            }
        }
        
        logger.endSession(sessionId)
        
        // Analyze consistency
        let sessions = await logger.getRecentSessions(limit: 1)
        measurements = sessions.first!.entries.map { $0.duration }
        
        let average = measurements.reduce(0, +) / Double(measurements.count)
        let variance = measurements.map { pow($0 - average, 2) }.reduce(0, +) / Double(measurements.count)
        let standardDeviation = sqrt(variance)
        let coefficientOfVariation = standardDeviation / average
        
        // Timing should be consistent (CV < 10%)
        XCTAssertLessThan(coefficientOfVariation, 0.10, 
            "Timing consistency poor: CV = \(String(format: "%.2f", coefficientOfVariation * 100))%")
        
        print("Timing Consistency Results:")
        print("Average: \(String(format: "%.3f", average))s")
        print("Standard Deviation: \(String(format: "%.3f", standardDeviation))s")
        print("Coefficient of Variation: \(String(format: "%.2f", coefficientOfVariation * 100))%")
    }
    
    // MARK: - Concurrent Logging Thread Safety Tests
    
    @MainActor
    func testConcurrentSessionCreation() async throws {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        let concurrentSessions = 50
        let operationsPerSession = 10
        
        // Create sessions concurrently
        let sessionIds = await withTaskGroup(of: UUID.self) { group in
            for i in 0..<concurrentSessions {
                group.addTask {
                    return logger.startSession()
                }
            }
            
            var ids: [UUID] = []
            for await sessionId in group {
                ids.append(sessionId)
            }
            return ids
        }
        
        XCTAssertEqual(sessionIds.count, concurrentSessions)
        XCTAssertEqual(Set(sessionIds).count, concurrentSessions) // All should be unique
        
        // Log operations concurrently across all sessions
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (index, sessionId) in sessionIds.enumerated() {
                group.addTask {
                    for opIndex in 0..<operationsPerSession {
                        _ = try await logger.measureOperation(
                            "Concurrent Session \(index) Op \(opIndex)",
                            sessionId: sessionId
                        ) {
                            try await Task.sleep(nanoseconds: UInt64.random(in: 1_000_000...5_000_000)) // 1-5ms
                            return opIndex
                        }
                    }
                }
            }
            
            try await group.waitForAll()
        }
        
        // End all sessions concurrently
        await withTaskGroup(of: Void.self) { group in
            for sessionId in sessionIds {
                group.addTask {
                    logger.endSession(sessionId)
                }
            }
        }
        
        // Verify thread safety - all operations should be logged correctly
        let sessions = await logger.getRecentSessions(limit: concurrentSessions)
        XCTAssertEqual(sessions.count, concurrentSessions)
        
        for session in sessions {
            XCTAssertEqual(session.entries.count, operationsPerSession)
            XCTAssertTrue(session.isCompleted)
        }
        
        print("Concurrent Session Test: \(concurrentSessions) sessions with \(operationsPerSession) operations each completed successfully")
    }
    
    @MainActor
    func testConcurrentOperationLogging() async throws {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        let sessionId = logger.startSession()
        let concurrentOperations = 100
        
        // Log many operations concurrently to the same session
        try await withThrowingTaskGroup(of: Int.self) { group in
            for i in 0..<concurrentOperations {
                group.addTask {
                    return try await logger.measureOperation("Concurrent Op \(i)", sessionId: sessionId) {
                        try await Task.sleep(nanoseconds: UInt64.random(in: 1_000_000...3_000_000)) // 1-3ms
                        return i
                    }
                }
            }
            
            var results: [Int] = []
            for try await result in group {
                results.append(result)
            }
            
            XCTAssertEqual(results.count, concurrentOperations)
            XCTAssertEqual(Set(results).count, concurrentOperations) // All should be unique
        }
        
        logger.endSession(sessionId)
        
        // Verify all operations were logged despite concurrency
        let sessions = await logger.getRecentSessions(limit: 1)
        let session = sessions.first!
        
        XCTAssertEqual(session.entries.count, concurrentOperations)
        XCTAssertTrue(session.isCompleted)
        
        // Verify no duplicate operations
        let operationNames = session.entries.map { $0.operation }
        XCTAssertEqual(operationNames.count, Set(operationNames).count)
        
        print("Concurrent Operation Test: \(concurrentOperations) operations logged successfully to single session")
    }
    
    @MainActor
    func testConcurrentSessionManagement() async {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        let sessionCount = 20
        
        // Test concurrent session lifecycle operations
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<sessionCount {
                group.addTask {
                    let sessionId = logger.startSession()
                    
                    // Add some operations
                    logger.logOperation("Test Op 1", duration: 0.001, sessionId: sessionId)
                    logger.logOperation("Test Op 2", duration: 0.002, sessionId: sessionId)
                    
                    // Randomly either end or cancel the session
                    if i % 2 == 0 {
                        logger.endSession(sessionId)
                    } else {
                        logger.cancelSession(sessionId)
                    }
                }
            }
        }
        
        // Verify thread safety in session management
        let completedSessions = await logger.getRecentSessions(limit: sessionCount)
        let activeSessionInfo = await logger.getActiveSessionInfo()
        
        // Should have sessionCount/2 completed sessions (the ones that were ended, not cancelled)
        XCTAssertEqual(completedSessions.count, sessionCount / 2)
        XCTAssertEqual(activeSessionInfo.count, 0) // No active sessions should remain
        
        print("Concurrent Session Management: \(completedSessions.count) sessions completed, \(sessionCount - completedSessions.count) cancelled")
    }
    
    @MainActor
    func testThreadSafetyUnderStress() async throws {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        let stressTestDuration: TimeInterval = 2.0 // 2 seconds of stress testing
        let startTime = CFAbsoluteTimeGetCurrent()
        
        var operationCount = 0
        var sessionCount = 0
        
        // Run stress test for specified duration
        try await withThrowingTaskGroup(of: Void.self) { group in
            // Task 1: Continuously create and end sessions
            group.addTask {
                while CFAbsoluteTimeGetCurrent() - startTime < stressTestDuration {
                    let sessionId = logger.startSession()
                    sessionCount += 1
                    
                    try await Task.sleep(nanoseconds: 10_000_000) // 10ms
                    logger.endSession(sessionId)
                }
            }
            
            // Task 2: Continuously log operations to random sessions
            group.addTask {
                var activeSessions: [UUID] = []
                
                while CFAbsoluteTimeGetCurrent() - startTime < stressTestDuration {
                    // Create a session for operations
                    let sessionId = logger.startSession()
                    activeSessions.append(sessionId)
                    
                    // Log some operations
                    for i in 0..<5 {
                        _ = try await logger.measureOperation("Stress Op \(operationCount)", sessionId: sessionId) {
                            try await Task.sleep(nanoseconds: 1_000_000) // 1ms
                            operationCount += 1
                            return operationCount
                        }
                    }
                    
                    logger.endSession(sessionId)
                    
                    // Occasionally clear old logs
                    if activeSessions.count % 10 == 0 {
                        logger.clearOldLogsOnly()
                    }
                }
            }
            
            // Task 3: Continuously query logger state
            group.addTask {
                while CFAbsoluteTimeGetCurrent() - startTime < stressTestDuration {
                    let _ = await logger.getRecentSessions(limit: 10)
                    let _ = await logger.getStorageInfo()
                    let _ = await logger.getActiveSessionInfo()
                    
                    try await Task.sleep(nanoseconds: 50_000_000) // 50ms
                }
            }
            
            try await group.waitForAll()
        }
        
        // Verify system remained stable under stress
        let finalSessions = await logger.getRecentSessions(limit: 100)
        let storageInfo = await logger.getStorageInfo()
        let activeInfo = await logger.getActiveSessionInfo()
        
        XCTAssertGreaterThan(operationCount, 0)
        XCTAssertEqual(activeInfo.count, 0) // No sessions should be left active
        XCTAssertLessThanOrEqual(storageInfo.sessionCount, 50) // Should respect limits
        
        print("Stress Test Results:")
        print("Duration: \(stressTestDuration)s")
        print("Operations logged: \(operationCount)")
        print("Final sessions: \(finalSessions.count)")
        print("Storage size: \(storageInfo.estimatedSizeBytes) bytes")
    }
    
    // MARK: - Data Storage Optimization Tests
    
    @MainActor
    func testStorageEfficiency() async {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        // Create sessions with varying amounts of data
        let testCases = [
            (sessions: 1, operationsPerSession: 1, description: "Minimal"),
            (sessions: 5, operationsPerSession: 10, description: "Small"),
            (sessions: 20, operationsPerSession: 25, description: "Medium"),
            (sessions: 50, operationsPerSession: 50, description: "Large")
        ]
        
        for testCase in testCases {
            logger.clearOldLogs()
            
            // Create test data
            for sessionIndex in 0..<testCase.sessions {
                let sessionId = logger.startSession()
                
                for opIndex in 0..<testCase.operationsPerSession {
                    let modelInfo = ModelInfo(
                        serviceName: "TestService",
                        modelName: "model-v\(opIndex % 3)",
                        configuration: ["param": "value\(opIndex)"]
                    )
                    
                    logger.logOperation(
                        "Storage Test S\(sessionIndex) Op\(opIndex)",
                        duration: Double(opIndex) * 0.001,
                        sessionId: sessionId,
                        modelInfo: modelInfo
                    )
                }
                
                logger.endSession(sessionId)
            }
            
            // Measure storage efficiency
            let storageInfo = await logger.getStorageInfo()
            let totalOperations = testCase.sessions * testCase.operationsPerSession
            let bytesPerOperation = Double(storageInfo.estimatedSizeBytes) / Double(totalOperations)
            
            // Storage should be efficient (less than 1KB per operation on average)
            XCTAssertLessThan(bytesPerOperation, 1024, 
                "\(testCase.description) test: \(String(format: "%.1f", bytesPerOperation)) bytes per operation exceeds 1KB limit")
            
            print("\(testCase.description) Storage Test:")
            print("  Sessions: \(testCase.sessions), Operations: \(totalOperations)")
            print("  Total size: \(storageInfo.estimatedSizeBytes) bytes")
            print("  Bytes per operation: \(String(format: "%.1f", bytesPerOperation))")
        }
    }
    
    @MainActor
    func testStorageLimitEnforcement() async {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        let initialStorageInfo = await logger.getStorageInfo()
        XCTAssertEqual(initialStorageInfo.sessionCount, 0)
        
        // Create more sessions than the limit (50+)
        let excessSessions = 75
        
        for i in 0..<excessSessions {
            let sessionId = logger.startSession()
            
            // Add operations with varying sizes
            for j in 0..<(i % 10 + 1) { // 1-10 operations per session
                let operationName = "Limit Test Session \(i) Operation \(j) with extra data to increase size"
                logger.logOperation(operationName, duration: Double(j) * 0.01, sessionId: sessionId)
            }
            
            logger.endSession(sessionId)
        }
        
        // Verify automatic cleanup occurred
        let finalStorageInfo = await logger.getStorageInfo()
        
        XCTAssertLessThanOrEqual(finalStorageInfo.sessionCount, 50) // Should be limited to maxStoredSessions
        XCTAssertLessThan(finalStorageInfo.estimatedSizeBytes, finalStorageInfo.maxSizeBytes) // Should be under size limit
        
        // Verify most recent sessions are kept
        let recentSessions = await logger.getRecentSessions(limit: 10)
        XCTAssertGreaterThan(recentSessions.count, 0)
        
        print("Storage Limit Test:")
        print("Created: \(excessSessions) sessions")
        print("Retained: \(finalStorageInfo.sessionCount) sessions")
        print("Storage size: \(finalStorageInfo.estimatedSizeBytes) / \(finalStorageInfo.maxSizeBytes) bytes")
    }
    
    @MainActor
    func testMemoryFootprintOptimization() async {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        // Test memory usage with large amounts of data
        let sessionCount = 30
        let operationsPerSession = 40
        
        // Create sessions with realistic operation names and model info
        for sessionIndex in 0..<sessionCount {
            let sessionId = logger.startSession()
            
            for opIndex in 0..<operationsPerSession {
                let modelInfo = ModelInfo(
                    serviceName: ["Gemini", "Vision", "OpenAI"][opIndex % 3],
                    modelName: ["gemini-2.5-flash", "apple-vision-v1", "gpt-4-vision"][opIndex % 3],
                    configuration: [
                        "temperature": "0.\(opIndex % 10)",
                        "max_tokens": "\(1000 + opIndex * 100)",
                        "model_version": "v\(opIndex % 5)"
                    ]
                )
                
                let operationName = [
                    "Photo Capture",
                    "Image Preprocessing", 
                    "Text Extraction",
                    "AI Processing",
                    "Note Creation",
                    "Share Sheet Presentation"
                ][opIndex % 6]
                
                logger.logOperation(
                    "\(operationName) (Session \(sessionIndex))",
                    duration: Double.random(in: 0.001...2.0),
                    sessionId: sessionId,
                    modelInfo: modelInfo
                )
            }
            
            logger.endSession(sessionId)
        }
        
        // Measure final memory footprint
        let storageInfo = await logger.getStorageInfo()
        let totalOperations = sessionCount * operationsPerSession
        let avgBytesPerOperation = Double(storageInfo.estimatedSizeBytes) / Double(totalOperations)
        
        // Memory footprint should be reasonable
        XCTAssertLessThan(avgBytesPerOperation, 500, "Average bytes per operation (\(String(format: "%.1f", avgBytesPerOperation))) exceeds 500 byte target")
        XCTAssertLessThan(storageInfo.estimatedSizeBytes, storageInfo.maxSizeBytes, "Total storage exceeds maximum limit")
        
        // Test cleanup efficiency
        let beforeCleanup = storageInfo.estimatedSizeBytes
        logger.clearOldLogsOnly()
        let afterCleanupInfo = await logger.getStorageInfo()
        
        print("Memory Footprint Optimization Results:")
        print("Total operations: \(totalOperations)")
        print("Storage before cleanup: \(beforeCleanup) bytes")
        print("Storage after cleanup: \(afterCleanupInfo.estimatedSizeBytes) bytes")
        print("Average bytes per operation: \(String(format: "%.1f", avgBytesPerOperation))")
        print("Sessions retained: \(afterCleanupInfo.sessionCount)")
    }
    
    @MainActor
    func testDataCompressionEfficiency() async {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        // Create sessions with repetitive data to test compression benefits
        let sessionId = logger.startSession()
        
        // Log operations with repetitive patterns
        for i in 0..<100 {
            let modelInfo = ModelInfo(
                serviceName: "TestService", // Repetitive
                modelName: "test-model-v1", // Repetitive
                configuration: ["param1": "value1", "param2": "value2"] // Repetitive
            )
            
            logger.logOperation(
                "Repetitive Operation Pattern \(i % 10)", // Some repetition
                duration: 0.001 * Double(i % 5), // Some repetition
                sessionId: sessionId,
                modelInfo: modelInfo
            )
        }
        
        logger.endSession(sessionId)
        
        // Measure compression efficiency
        let storageInfo = await logger.getStorageInfo()
        let bytesPerOperation = Double(storageInfo.estimatedSizeBytes) / 100.0
        
        // With repetitive data, compression should be effective
        XCTAssertLessThan(bytesPerOperation, 300, "Compression not effective: \(String(format: "%.1f", bytesPerOperation)) bytes per operation")
        
        print("Data Compression Test:")
        print("100 operations with repetitive data")
        print("Total size: \(storageInfo.estimatedSizeBytes) bytes")
        print("Bytes per operation: \(String(format: "%.1f", bytesPerOperation))")
    }
    
    // MARK: - Performance Regression Tests
    
    @MainActor
    func testPerformanceRegression() async throws {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        // Baseline performance targets (these should not regress)
        let maxOverheadPercentage: Double = 10.0 // 10% max overhead
        let maxTimingErrorMs: Double = 10.0 // 10ms max timing error
        let maxBytesPerOperation: Double = 500.0 // 500 bytes max per operation
        
        // Test 1: Overhead regression
        let iterations = 100
        let baseOperationDuration: UInt64 = 5_000_000 // 5ms
        
        let baselineStart = CFAbsoluteTimeGetCurrent()
        for _ in 0..<iterations {
            try await Task.sleep(nanoseconds: baseOperationDuration)
        }
        let baselineDuration = CFAbsoluteTimeGetCurrent() - baselineStart
        
        let sessionId = logger.startSession()
        let loggedStart = CFAbsoluteTimeGetCurrent()
        
        for i in 0..<iterations {
            _ = try await logger.measureOperation("Regression Test \(i)", sessionId: sessionId) {
                try await Task.sleep(nanoseconds: baseOperationDuration)
                return i
            }
        }
        
        let loggedDuration = CFAbsoluteTimeGetCurrent() - loggedStart
        logger.endSession(sessionId)
        
        let overhead = ((loggedDuration - baselineDuration) / baselineDuration) * 100
        XCTAssertLessThan(overhead, maxOverheadPercentage, "Performance regression: overhead \(String(format: "%.2f", overhead))% exceeds \(maxOverheadPercentage)%")
        
        // Test 2: Timing accuracy regression
        let sessions = await logger.getRecentSessions(limit: 1)
        let avgMeasuredDuration = sessions.first!.entries.map { $0.duration }.reduce(0, +) / Double(iterations)
        let expectedDuration = Double(baseOperationDuration) / 1_000_000_000.0
        let timingError = abs(avgMeasuredDuration - expectedDuration) * 1000 // Convert to ms
        
        XCTAssertLessThan(timingError, maxTimingErrorMs, "Timing regression: error \(String(format: "%.2f", timingError))ms exceeds \(maxTimingErrorMs)ms")
        
        // Test 3: Memory usage regression
        let storageInfo = await logger.getStorageInfo()
        let bytesPerOperation = Double(storageInfo.estimatedSizeBytes) / Double(iterations)
        
        XCTAssertLessThan(bytesPerOperation, maxBytesPerOperation, "Memory regression: \(String(format: "%.1f", bytesPerOperation)) bytes per operation exceeds \(maxBytesPerOperation)")
        
        print("Performance Regression Test Results:")
        print("Overhead: \(String(format: "%.2f", overhead))% (limit: \(maxOverheadPercentage)%)")
        print("Timing error: \(String(format: "%.2f", timingError))ms (limit: \(maxTimingErrorMs)ms)")
        print("Memory per operation: \(String(format: "%.1f", bytesPerOperation)) bytes (limit: \(maxBytesPerOperation))")
    }
}
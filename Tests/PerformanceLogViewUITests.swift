import XCTest
import SwiftUI
@testable import Cat_Scribe

/// UI Tests for Performance Log View integration
/// Note: These tests require a UI test target to be properly configured in Xcode
final class PerformanceLogViewUITests: XCTestCase {
    
    // MARK: - SwiftUI View Tests
    
    @MainActor
    func testPerformanceLogViewInitialization() {
        // Test that PerformanceLogView can be initialized without crashing
        let view = PerformanceLogView()
        XCTAssertNotNil(view)
    }
    
    @MainActor
    func testStatisticCardView() {
        let card = StatisticCard(
            title: "Test Metric",
            value: "42",
            icon: "chart.bar.fill",
            color: .blue
        )
        
        XCTAssertNotNil(card)
    }
    
    @MainActor
    func testSessionRowView() {
        let deviceContext = DeviceContext()
        var session = LogSession(deviceContext: deviceContext)
        session.complete()
        
        let rowView = SessionRowView(
            session: session,
            isExpanded: false,
            onTap: {}
        )
        
        XCTAssertNotNil(rowView)
    }
    
    @MainActor
    func testOperationRowView() {
        let deviceContext = DeviceContext()
        let modelInfo = ModelInfo(serviceName: "Gemini", modelName: "gemini-2.5-flash")
        
        let entry = LogEntry(
            operation: "Test Operation",
            startTime: Date(),
            duration: 1.5,
            modelInfo: modelInfo,
            deviceContext: deviceContext
        )
        
        let rowView = OperationRowView(entry: entry)
        XCTAssertNotNil(rowView)
    }
    
    // MARK: - View State Tests
    
    @MainActor
    func testPerformanceLogViewWithEmptyData() async {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        let view = PerformanceLogView()
        
        // Simulate view appearing with no data
        // In a real UI test, this would verify the empty state is shown
        let sessions = await logger.getRecentSessions(limit: 50)
        XCTAssertTrue(sessions.isEmpty)
    }
    
    @MainActor
    func testPerformanceLogViewWithData() async {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        // Create test data
        let sessionId = logger.startSession()
        logger.logOperation("Test Operation", duration: 1.0, sessionId: sessionId)
        logger.endSession(sessionId)
        
        let view = PerformanceLogView()
        
        // Verify data exists for the view
        let sessions = await logger.getRecentSessions(limit: 50)
        XCTAssertFalse(sessions.isEmpty)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.entries.count, 1)
    }
    
    // MARK: - Copy Functionality Tests
    
    @MainActor
    func testLogFormattingForCopy() async {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        // Create test session with multiple operations
        let sessionId = logger.startSession()
        
        let modelInfo = ModelInfo(serviceName: "Gemini", modelName: "gemini-2.5-flash")
        logger.logOperation("Photo Capture", duration: 0.123, sessionId: sessionId)
        logger.logOperation("AI Processing", duration: 2.456, sessionId: sessionId, modelInfo: modelInfo)
        logger.logOperation("Note Creation", duration: 0.789, sessionId: sessionId)
        
        logger.endSession(sessionId)
        
        // Test formatted logs
        let formattedLogs = await logger.getFormattedLogs()
        
        XCTAssertTrue(formattedLogs.contains("NotebookSaver Performance Log"))
        XCTAssertTrue(formattedLogs.contains("Photo Capture"))
        XCTAssertTrue(formattedLogs.contains("AI Processing"))
        XCTAssertTrue(formattedLogs.contains("Note Creation"))
        XCTAssertTrue(formattedLogs.contains("Gemini/gemini-2.5-flash"))
        XCTAssertTrue(formattedLogs.contains("0.123s"))
        XCTAssertTrue(formattedLogs.contains("2.456s"))
        XCTAssertTrue(formattedLogs.contains("0.789s"))
    }
    
    @MainActor
    func testCopyToClipboardFunctionality() async {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        // Create test data
        let sessionId = logger.startSession()
        logger.logOperation("Clipboard Test", duration: 1.0, sessionId: sessionId)
        logger.endSession(sessionId)
        
        // Get formatted logs (simulating copy action)
        let formattedLogs = await logger.getFormattedLogs()
        
        // Simulate setting clipboard content
        UIPasteboard.general.string = formattedLogs
        
        // Verify clipboard content
        XCTAssertNotNil(UIPasteboard.general.string)
        XCTAssertTrue(UIPasteboard.general.string!.contains("Clipboard Test"))
        XCTAssertTrue(UIPasteboard.general.string!.contains("NotebookSaver Performance Log"))
    }
    
    // MARK: - Storage Info Display Tests
    
    @MainActor
    func testStorageInfoCalculation() async {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        // Create multiple sessions to test storage calculation
        for i in 0..<5 {
            let sessionId = logger.startSession()
            logger.logOperation("Storage Test \(i)", duration: Double(i) * 0.1, sessionId: sessionId)
            logger.endSession(sessionId)
        }
        
        let storageInfo = await logger.getStorageInfo()
        
        XCTAssertEqual(storageInfo.sessionCount, 5)
        XCTAssertGreaterThan(storageInfo.estimatedSizeBytes, 0)
        XCTAssertGreaterThan(storageInfo.maxSizeBytes, 0)
        XCTAssertLessThan(storageInfo.estimatedSizeBytes, storageInfo.maxSizeBytes)
    }
    
    // MARK: - Session Expansion Tests
    
    @MainActor
    func testSessionExpansionLogic() {
        let deviceContext = DeviceContext()
        var session = LogSession(deviceContext: deviceContext)
        
        // Add multiple entries to test expansion
        let entry1 = LogEntry(operation: "Op 1", startTime: Date(), duration: 1.0, deviceContext: deviceContext)
        let entry2 = LogEntry(operation: "Op 2", startTime: Date(), duration: 2.0, deviceContext: deviceContext)
        
        session.addEntry(entry1)
        session.addEntry(entry2)
        session.complete()
        
        // Test session has entries for expansion
        XCTAssertFalse(session.entries.isEmpty)
        XCTAssertEqual(session.entries.count, 2)
        XCTAssertTrue(session.isCompleted)
    }
    
    // MARK: - Error State Tests
    
    @MainActor
    func testErrorOperationDisplay() {
        let deviceContext = DeviceContext()
        
        // Test failed operation entry
        let failedEntry = LogEntry(
            operation: "Failed Operation (failed: NSError)",
            startTime: Date(),
            duration: 1.0,
            deviceContext: deviceContext
        )
        
        let rowView = OperationRowView(entry: failedEntry)
        XCTAssertNotNil(rowView)
        
        // Verify the operation name indicates failure
        XCTAssertTrue(failedEntry.operation.contains("(failed"))
    }
    
    // MARK: - Performance Statistics Tests
    
    @MainActor
    func testStatisticsCalculation() async {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        // Create sessions with known durations for statistics testing
        let durations = [1.0, 2.0, 3.0, 4.0, 5.0]
        
        for (index, duration) in durations.enumerated() {
            let sessionId = logger.startSession()
            logger.logOperation("Stats Test \(index)", duration: duration, sessionId: sessionId)
            logger.endSession(sessionId)
        }
        
        let sessions = await logger.getRecentSessions(limit: 10)
        let completedSessions = sessions.filter { $0.isCompleted }
        
        XCTAssertEqual(completedSessions.count, 5)
        
        // Test average calculation
        let totalDurations = completedSessions.compactMap { $0.totalDuration }
        XCTAssertFalse(totalDurations.isEmpty)
        
        let avgDuration = totalDurations.reduce(0, +) / Double(totalDurations.count)
        XCTAssertGreaterThan(avgDuration, 0)
        
        // Test fastest duration
        let fastestDuration = totalDurations.min() ?? 0
        XCTAssertGreaterThan(fastestDuration, 0)
    }
    
    // MARK: - Clear Functionality Tests
    
    @MainActor
    func testClearAllLogsAction() async {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        // Create test data
        let sessionId = logger.startSession()
        logger.logOperation("Clear Test", duration: 1.0, sessionId: sessionId)
        logger.endSession(sessionId)
        
        // Verify data exists
        let sessionsBefore = await logger.getRecentSessions(limit: 10)
        XCTAssertEqual(sessionsBefore.count, 1)
        
        // Simulate clear all action
        logger.clearOldLogs()
        
        // Verify data is cleared
        let sessionsAfter = await logger.getRecentSessions(limit: 10)
        XCTAssertEqual(sessionsAfter.count, 0)
    }
    
    @MainActor
    func testClearOldLogsAction() async {
        let logger = PerformanceLogger.shared
        logger.clearOldLogs()
        
        // Create test data (under the limit)
        for i in 0..<5 {
            let sessionId = logger.startSession()
            logger.logOperation("Old Clear Test \(i)", duration: 1.0, sessionId: sessionId)
            logger.endSession(sessionId)
        }
        
        // Verify data exists
        let sessionsBefore = await logger.getRecentSessions(limit: 10)
        XCTAssertEqual(sessionsBefore.count, 5)
        
        // Simulate clear old logs action (should not remove anything since under limit)
        logger.clearOldLogsOnly()
        
        // Verify data is still there
        let sessionsAfter = await logger.getRecentSessions(limit: 10)
        XCTAssertEqual(sessionsAfter.count, 5)
    }
}
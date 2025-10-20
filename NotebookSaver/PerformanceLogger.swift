import Foundation
import os.log

/// Errors that can occur during performance logging
enum PerformanceLoggerError: Error, LocalizedError {
    case sessionNotFound(UUID)
    case invalidOperation(String)
    case timingFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .sessionNotFound(let sessionId):
            return "Performance logging session not found: \(sessionId)"
        case .invalidOperation(let operation):
            return "Invalid performance logging operation: \(operation)"
        case .timingFailed(let reason):
            return "Performance timing failed: \(reason)"
        }
    }
}

/// Error thrown when an operation times out
struct TimeoutError: Error, LocalizedError {
    let timeout: TimeInterval
    
    var errorDescription: String? {
        return "Operation timed out after \(timeout) seconds"
    }
}

/// Token for manual timing operations
struct TimingToken {
    let operation: String
    let sessionId: UUID
    let startTime: CFAbsoluteTime
    
    init(operation: String, sessionId: UUID, startTime: CFAbsoluteTime) {
        self.operation = operation
        self.sessionId = sessionId
        self.startTime = startTime
    }
}

/// Thread-safe performance logging system for tracking app operations
class PerformanceLogger: ObservableObject, @unchecked Sendable {
    static let shared = PerformanceLogger()
    
    // MARK: - Private Properties
    
    private let logger = Logger(subsystem: "com.notebooksaver.performance", category: "PerformanceLogger")
    private let userDefaults = UserDefaults.standard
    private let maxStoredSessions = 50
    private let maxStorageSizeBytes = 1024 * 1024 // 1MB limit for log storage
    private let storageKey = "PerformanceLogger.Sessions"
    private let storageMetricsKey = "PerformanceLogger.StorageMetrics"
    
    // Thread-safe storage
    private let queue = DispatchQueue(label: "com.notebooksaver.performance.queue", qos: .utility)
    private var _currentSessions: [UUID: LogSession] = [:]
    private var _completedSessions: [LogSession] = []
    private let deviceContext = DeviceContext()
    
    // MARK: - Initialization
    
    private init() {
        loadPersistedSessions()
    }
    
    // MARK: - Public Interface
    
    /// Start a new performance logging session
    /// - Returns: Unique session identifier
    func startSession() -> UUID {
        let session = LogSession(deviceContext: deviceContext)
        
        queue.async { [weak self] in
            self?._currentSessions[session.id] = session
        }
        
        logger.debug("Started performance session: \(session.id)")
        return session.id
    }
    
    /// Log a completed operation within a session
    /// - Parameters:
    ///   - operation: Name of the operation
    ///   - duration: Time taken in seconds
    ///   - sessionId: Session to associate with
    ///   - modelInfo: Optional model information
    func logOperation(_ operation: String, duration: TimeInterval, sessionId: UUID, modelInfo: ModelInfo? = nil) {
        // Validate operation name
        guard !operation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logger.warning("Attempted to log operation with empty name for session \(sessionId)")
            return
        }
        
        // Validate duration is reasonable (not negative, not excessively large)
        guard duration >= 0 && duration < 3600 else { // Max 1 hour per operation
            logger.warning("Invalid duration \(duration)s for operation '\(operation)' in session \(sessionId)")
            return
        }
        
        let entry = LogEntry(
            operation: operation,
            startTime: Date().addingTimeInterval(-duration),
            duration: duration,
            modelInfo: modelInfo,
            deviceContext: deviceContext
        )
        
        queue.async { [weak self] in
            guard let self = self else { return }
            
            if var session = self._currentSessions[sessionId] {
                session.addEntry(entry)
                self._currentSessions[sessionId] = session
                
                self.logger.debug("Logged operation '\(operation)' (\(String(format: "%.3f", duration))s) for session \(sessionId)")
            } else {
                self.logger.warning("Attempted to log operation '\(operation)' for unknown session: \(sessionId)")
            }
        }
    }
    
    /// End a performance logging session
    /// - Parameter sessionId: Session to complete
    func endSession(_ sessionId: UUID) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            if var session = self._currentSessions[sessionId] {
                // Validate session hasn't already been completed
                guard !session.isCompleted else {
                    self.logger.warning("Attempted to end already completed session: \(sessionId)")
                    return
                }
                
                session.complete()
                self._currentSessions.removeValue(forKey: sessionId)
                self._completedSessions.append(session)
                
                // Maintain storage limits
                self.enforceStorageLimits()
                self.persistSessions()
                
                let totalDuration = session.totalDuration ?? 0
                self.logger.info("Completed performance session: \(sessionId) with \(session.entries.count) operations (total: \(String(format: "%.3f", totalDuration))s)")
            } else {
                self.logger.warning("Attempted to end unknown session: \(sessionId)")
            }
        }
    }
    
    /// Get recent completed sessions
    /// - Parameter limit: Maximum number of sessions to return
    /// - Returns: Array of recent sessions, most recent first
    func getRecentSessions(limit: Int = 50) async -> [LogSession] {
        return await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: [])
                    return
                }
                
                let recentSessions = Array(self._completedSessions.suffix(limit).reversed())
                continuation.resume(returning: recentSessions)
            }
        }
    }
    
    /// Get formatted logs as copyable text
    /// - Returns: Formatted string representation of all logs
    func getFormattedLogs() async -> String {
        let sessions = await getRecentSessions()
        return PerformanceLogFormatter.formatLogs(sessions)
    }
    
    /// Clear old log entries for privacy
    func clearOldLogs() {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            let completedCount = self._completedSessions.count
            let activeCount = self._currentSessions.count
            
            self._completedSessions.removeAll()
            self._currentSessions.removeAll()
            self.persistSessions()
            self.updateStorageMetrics()
            
            self.logger.info("Cleared all performance logs (\(completedCount) completed, \(activeCount) active sessions)")
        }
    }
    
    /// Clear only old log entries beyond the retention limit
    func clearOldLogsOnly() {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            let originalCount = self._completedSessions.count
            self.enforceStorageLimits()
            self.persistSessions()
            
            let removedCount = originalCount - self._completedSessions.count
            if removedCount > 0 {
                self.logger.info("Automatically removed \(removedCount) old log sessions")
            }
        }
    }
    
    /// Get storage usage information
    func getStorageInfo() async -> (sessionCount: Int, estimatedSizeBytes: Int, maxSizeBytes: Int) {
        return await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: (0, 0, self?.maxStorageSizeBytes ?? 0))
                    return
                }
                
                let sessionCount = self._completedSessions.count
                let estimatedSize = self.calculateStorageSize()
                
                continuation.resume(returning: (sessionCount, estimatedSize, self.maxStorageSizeBytes))
            }
        }
    }
    
    /// Get information about active sessions
    /// - Returns: Dictionary of session IDs to entry counts
    func getActiveSessionInfo() async -> [UUID: Int] {
        return await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: [:])
                    return
                }
                
                let sessionInfo = self._currentSessions.mapValues { $0.entries.count }
                continuation.resume(returning: sessionInfo)
            }
        }
    }
    
    /// Force complete all active sessions (useful for app backgrounding)
    func completeAllActiveSessions() {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            let activeSessionIds = Array(self._currentSessions.keys)
            
            for sessionId in activeSessionIds {
                if var session = self._currentSessions[sessionId] {
                    session.complete()
                    self._currentSessions.removeValue(forKey: sessionId)
                    self._completedSessions.append(session)
                }
            }
            
            if !activeSessionIds.isEmpty {
                self.enforceStorageLimits()
                self.persistSessions()
                self.logger.info("Force completed \(activeSessionIds.count) active sessions")
            }
        }
    }
    
    /// Cancel an active session without completing it (for error scenarios)
    /// - Parameter sessionId: Session to cancel
    func cancelSession(_ sessionId: UUID) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            if let session = self._currentSessions.removeValue(forKey: sessionId) {
                self.logger.info("Cancelled session \(sessionId) with \(session.entries.count) operations")
            } else {
                self.logger.warning("Attempted to cancel unknown session: \(sessionId)")
            }
        }
    }
    
    /// Get session duration for an active session
    /// - Parameter sessionId: Session to check
    /// - Returns: Current duration of the session, or nil if session doesn't exist
    func getSessionDuration(_ sessionId: UUID) async -> TimeInterval? {
        return await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self = self,
                      let session = self._currentSessions[sessionId] else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let duration = Date().timeIntervalSince(session.startTime)
                continuation.resume(returning: duration)
            }
        }
    }
    
    /// Check if a session has any logged operations
    /// - Parameter sessionId: Session to check
    /// - Returns: True if session has operations logged
    func sessionHasOperations(_ sessionId: UUID) async -> Bool {
        return await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self = self,
                      let session = self._currentSessions[sessionId] else {
                    continuation.resume(returning: false)
                    return
                }
                
                continuation.resume(returning: !session.entries.isEmpty)
            }
        }
    }
    

    
    // MARK: - Convenience Methods
    
    /// Measure the execution time of an async operation with high-precision timing
    /// - Parameters:
    ///   - operation: Name of the operation
    ///   - sessionId: Session to log to
    ///   - modelInfo: Optional model information
    ///   - block: The operation to measure
    /// - Returns: Result of the operation
    func measureOperation<T>(
        _ operation: String,
        sessionId: UUID,
        modelInfo: ModelInfo? = nil,
        block: @escaping () async throws -> T
    ) async throws -> T {
        // Validate session exists before starting measurement
        guard await sessionExists(sessionId) else {
            logger.warning("Cannot measure operation '\(operation)' - session \(sessionId) does not exist")
            throw PerformanceLoggerError.sessionNotFound(sessionId)
        }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        do {
            let result = try await block()
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            logOperation(operation, duration: duration, sessionId: sessionId, modelInfo: modelInfo)
            logger.debug("Successfully measured async operation '\(operation)': \(String(format: "%.3f", duration))s")
            return result
        } catch {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            let failedOperation = "\(operation) (failed: \(type(of: error)))"
            logOperation(failedOperation, duration: duration, sessionId: sessionId, modelInfo: modelInfo)
            logger.error("Failed async operation '\(operation)' after \(String(format: "%.3f", duration))s: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Measure the execution time of a synchronous operation with high-precision timing
    /// - Parameters:
    ///   - operation: Name of the operation
    ///   - sessionId: Session to log to
    ///   - modelInfo: Optional model information
    ///   - block: The operation to measure
    /// - Returns: Result of the operation
    func measureSyncOperation<T>(
        _ operation: String,
        sessionId: UUID,
        modelInfo: ModelInfo? = nil,
        block: () throws -> T
    ) throws -> T {
        // Validate session exists before starting measurement
        guard sessionExistsSync(sessionId) else {
            logger.warning("Cannot measure sync operation '\(operation)' - session \(sessionId) does not exist")
            throw PerformanceLoggerError.sessionNotFound(sessionId)
        }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        do {
            let result = try block()
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            logOperation(operation, duration: duration, sessionId: sessionId, modelInfo: modelInfo)
            logger.debug("Successfully measured sync operation '\(operation)': \(String(format: "%.3f", duration))s")
            return result
        } catch {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            let failedOperation = "\(operation) (failed: \(type(of: error)))"
            logOperation(failedOperation, duration: duration, sessionId: sessionId, modelInfo: modelInfo)
            logger.error("Failed sync operation '\(operation)' after \(String(format: "%.3f", duration))s: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Measure a void async operation (no return value)
    /// - Parameters:
    ///   - operation: Name of the operation
    ///   - sessionId: Session to log to
    ///   - modelInfo: Optional model information
    ///   - block: The operation to measure
    func measureVoidOperation(
        _ operation: String,
        sessionId: UUID,
        modelInfo: ModelInfo? = nil,
        block: @escaping () async throws -> Void
    ) async throws {
        let _: Void = try await measureOperation(operation, sessionId: sessionId, modelInfo: modelInfo, block: block)
    }
    
    /// Measure a void synchronous operation (no return value)
    /// - Parameters:
    ///   - operation: Name of the operation
    ///   - sessionId: Session to log to
    ///   - modelInfo: Optional model information
    ///   - block: The operation to measure
    func measureVoidSyncOperation(
        _ operation: String,
        sessionId: UUID,
        modelInfo: ModelInfo? = nil,
        block: () throws -> Void
    ) throws {
        let _: Void = try measureSyncOperation(operation, sessionId: sessionId, modelInfo: modelInfo, block: block)
    }
    
    /// Measure multiple operations in sequence within the same session
    /// - Parameters:
    ///   - operations: Array of operation names and blocks to execute
    ///   - sessionId: Session to log to
    ///   - modelInfo: Optional model information for all operations
    /// - Returns: Array of results from each operation
    func measureSequentialOperations<T>(
        _ operations: [(name: String, block: () async throws -> T)],
        sessionId: UUID,
        modelInfo: ModelInfo? = nil
    ) async throws -> [T] {
        var results: [T] = []
        
        for operation in operations {
            let result = try await measureOperation(
                operation.name,
                sessionId: sessionId,
                modelInfo: modelInfo,
                block: operation.block
            )
            results.append(result)
        }
        
        return results
    }
    
    /// Measure an operation with custom success/failure determination
    /// - Parameters:
    ///   - operation: Name of the operation
    ///   - sessionId: Session to log to
    ///   - modelInfo: Optional model information
    ///   - successCondition: Function to determine if result indicates success
    ///   - block: The operation to measure
    /// - Returns: Result of the operation
    func measureOperationWithCondition<T>(
        _ operation: String,
        sessionId: UUID,
        modelInfo: ModelInfo? = nil,
        successCondition: @escaping (T) -> Bool,
        block: @escaping () async throws -> T
    ) async throws -> T {
        guard await sessionExists(sessionId) else {
            logger.warning("Cannot measure conditional operation '\(operation)' - session \(sessionId) does not exist")
            throw PerformanceLoggerError.sessionNotFound(sessionId)
        }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        do {
            let result = try await block()
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            let isSuccess = successCondition(result)
            let operationName = isSuccess ? operation : "\(operation) (condition failed)"
            
            logOperation(operationName, duration: duration, sessionId: sessionId, modelInfo: modelInfo)
            
            if isSuccess {
                logger.debug("Successfully measured conditional operation '\(operation)': \(String(format: "%.3f", duration))s")
            } else {
                logger.warning("Conditional operation '\(operation)' completed but failed condition check: \(String(format: "%.3f", duration))s")
            }
            
            return result
        } catch {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            let failedOperation = "\(operation) (exception: \(type(of: error)))"
            logOperation(failedOperation, duration: duration, sessionId: sessionId, modelInfo: modelInfo)
            logger.error("Failed conditional operation '\(operation)' after \(String(format: "%.3f", duration))s: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Measure an operation with timeout handling
    /// - Parameters:
    ///   - operation: Name of the operation
    ///   - sessionId: Session to log to
    ///   - timeout: Maximum time to wait in seconds
    ///   - modelInfo: Optional model information
    ///   - block: The operation to measure
    /// - Returns: Result of the operation
    func measureOperationWithTimeout<T>(
        _ operation: String,
        sessionId: UUID,
        timeout: TimeInterval,
        modelInfo: ModelInfo? = nil,
        block: @escaping () async throws -> T
    ) async throws -> T {
        guard await sessionExists(sessionId) else {
            logger.warning("Cannot measure timed operation '\(operation)' - session \(sessionId) does not exist")
            throw PerformanceLoggerError.sessionNotFound(sessionId)
        }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        do {
            let result = try await withTimeout(seconds: timeout) {
                try await block()
            }
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            logOperation(operation, duration: duration, sessionId: sessionId, modelInfo: modelInfo)
            logger.debug("Successfully measured timed operation '\(operation)': \(String(format: "%.3f", duration))s")
            return result
        } catch {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            let isTimeout = error is TimeoutError
            let failedOperation = isTimeout ? "\(operation) (timeout)" : "\(operation) (failed: \(type(of: error)))"
            logOperation(failedOperation, duration: duration, sessionId: sessionId, modelInfo: modelInfo)
            
            if isTimeout {
                logger.error("Timed operation '\(operation)' exceeded timeout of \(timeout)s after \(String(format: "%.3f", duration))s")
            } else {
                logger.error("Failed timed operation '\(operation)' after \(String(format: "%.3f", duration))s: \(error.localizedDescription)")
            }
            throw error
        }
    }
    
    /// Start timing an operation manually (for complex scenarios)
    /// - Parameters:
    ///   - operation: Name of the operation
    ///   - sessionId: Session to log to
    /// - Returns: Timer token to use with endTiming
    func startTiming(_ operation: String, sessionId: UUID) -> TimingToken? {
        guard sessionExistsSync(sessionId) else {
            logger.warning("Cannot start timing for '\(operation)' - session \(sessionId) does not exist")
            return nil
        }
        
        let token = TimingToken(
            operation: operation,
            sessionId: sessionId,
            startTime: CFAbsoluteTimeGetCurrent()
        )
        
        logger.debug("Started manual timing for '\(operation)' in session \(sessionId)")
        return token
    }
    
    /// End timing for a manually started operation
    /// - Parameters:
    ///   - token: Timer token from startTiming
    ///   - modelInfo: Optional model information
    ///   - success: Whether the operation succeeded
    func endTiming(_ token: TimingToken, modelInfo: ModelInfo? = nil, success: Bool = true) {
        let duration = CFAbsoluteTimeGetCurrent() - token.startTime
        let operation = success ? token.operation : "\(token.operation) (failed)"
        
        logOperation(operation, duration: duration, sessionId: token.sessionId, modelInfo: modelInfo)
        
        let status = success ? "completed" : "failed"
        logger.debug("Ended manual timing for '\(token.operation)': \(String(format: "%.3f", duration))s (\(status))")
    }
    
    /// End timing for a manually started operation with error information
    /// - Parameters:
    ///   - token: Timer token from startTiming
    ///   - error: The error that occurred
    ///   - modelInfo: Optional model information
    func endTiming(_ token: TimingToken, error: Error, modelInfo: ModelInfo? = nil) {
        let duration = CFAbsoluteTimeGetCurrent() - token.startTime
        let operation = "\(token.operation) (failed: \(type(of: error)))"
        
        logOperation(operation, duration: duration, sessionId: token.sessionId, modelInfo: modelInfo)
        logger.error("Ended manual timing for '\(token.operation)' with error: \(String(format: "%.3f", duration))s - \(error.localizedDescription)")
    }
    
    /// Get current high-precision timestamp
    /// - Returns: Current CFAbsoluteTime for manual timing calculations
    func getCurrentTimestamp() -> CFAbsoluteTime {
        return CFAbsoluteTimeGetCurrent()
    }
    
    /// Calculate duration between two timestamps
    /// - Parameters:
    ///   - start: Start timestamp from getCurrentTimestamp()
    ///   - end: End timestamp from getCurrentTimestamp()
    /// - Returns: Duration in seconds
    func calculateDuration(from start: CFAbsoluteTime, to end: CFAbsoluteTime) -> TimeInterval {
        return end - start
    }
    
    /// Log a pre-calculated operation duration
    /// - Parameters:
    ///   - operation: Name of the operation
    ///   - startTimestamp: When the operation started
    ///   - endTimestamp: When the operation ended
    ///   - sessionId: Session to log to
    ///   - modelInfo: Optional model information
    ///   - success: Whether the operation succeeded
    func logPreCalculatedOperation(
        _ operation: String,
        startTimestamp: CFAbsoluteTime,
        endTimestamp: CFAbsoluteTime,
        sessionId: UUID,
        modelInfo: ModelInfo? = nil,
        success: Bool = true
    ) {
        let duration = endTimestamp - startTimestamp
        let operationName = success ? operation : "\(operation) (failed)"
        
        logOperation(operationName, duration: duration, sessionId: sessionId, modelInfo: modelInfo)
        
        let status = success ? "completed" : "failed"
        logger.debug("Logged pre-calculated operation '\(operation)': \(String(format: "%.3f", duration))s (\(status))")
    }
    
    /// Batch log multiple operations at once for efficiency
    /// - Parameters:
    ///   - operations: Array of operation data to log
    ///   - sessionId: Session to log to
    func batchLogOperations(_ operations: [(name: String, duration: TimeInterval, modelInfo: ModelInfo?, success: Bool)], sessionId: UUID) {
        for operation in operations {
            let operationName = operation.success ? operation.name : "\(operation.name) (failed)"
            logOperation(operationName, duration: operation.duration, sessionId: sessionId, modelInfo: operation.modelInfo)
        }
        
        logger.debug("Batch logged \(operations.count) operations for session \(sessionId)")
    }
    
    // MARK: - Session Validation
    
    /// Check if a session exists (async version)
    /// - Parameter sessionId: Session ID to check
    /// - Returns: True if session exists
    private func sessionExists(_ sessionId: UUID) async -> Bool {
        return await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                let exists = self?._currentSessions[sessionId] != nil
                continuation.resume(returning: exists)
            }
        }
    }
    
    /// Check if a session exists (synchronous version for sync operations)
    /// - Parameter sessionId: Session ID to check
    /// - Returns: True if session exists
    private func sessionExistsSync(_ sessionId: UUID) -> Bool {
        var exists = false
        queue.sync { [weak self] in
            exists = self?._currentSessions[sessionId] != nil
        }
        return exists
    }
    
    // MARK: - Timeout Utility
    
    /// Execute an async operation with a timeout
    /// - Parameters:
    ///   - seconds: Timeout in seconds
    ///   - operation: The async operation to execute
    /// - Returns: Result of the operation
    /// - Throws: TimeoutError if operation exceeds timeout, or original error from operation
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            // Add the main operation
            group.addTask {
                try await operation()
            }
            
            // Add the timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError(timeout: seconds)
            }
            
            // Return the first result (either success or timeout)
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
    
    // MARK: - Private Methods
    
    private func enforceStorageLimits() {
        var removedCount = 0
        
        // First, enforce session count limits
        if _completedSessions.count > maxStoredSessions {
            let excessCount = _completedSessions.count - maxStoredSessions
            _completedSessions.removeFirst(excessCount)
            removedCount += excessCount
        }
        
        // Then, enforce storage size limits
        var currentSize = calculateStorageSize()
        while currentSize > maxStorageSizeBytes && !_completedSessions.isEmpty {
            _completedSessions.removeFirst()
            removedCount += 1
            currentSize = calculateStorageSize()
        }
        
        if removedCount > 0 {
            logger.debug("Removed \(removedCount) old sessions to maintain storage limits (count: \(self._completedSessions.count), size: \(currentSize) bytes)")
            updateStorageMetrics()
        }
    }
    
    private func calculateStorageSize() -> Int {
        do {
            let data = try JSONEncoder().encode(_completedSessions)
            return data.count
        } catch {
            logger.warning("Failed to calculate storage size: \(error.localizedDescription)")
            // Fallback estimation based on session count
            return _completedSessions.count * 200 // Rough estimate: 200 bytes per session
        }
    }
    
    private func updateStorageMetrics() {
        let metrics = StorageMetrics(
            sessionCount: _completedSessions.count,
            estimatedSizeBytes: calculateStorageSize(),
            lastCleanupDate: Date()
        )
        
        do {
            let data = try JSONEncoder().encode(metrics)
            userDefaults.set(data, forKey: storageMetricsKey)
        } catch {
            logger.warning("Failed to update storage metrics: \(error.localizedDescription)")
        }
    }
    
    private func getStorageMetrics() -> StorageMetrics? {
        guard let data = userDefaults.data(forKey: storageMetricsKey) else {
            return nil
        }
        
        do {
            return try JSONDecoder().decode(StorageMetrics.self, from: data)
        } catch {
            logger.warning("Failed to decode storage metrics: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func persistSessions() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys // Consistent output for better compression
            let data = try encoder.encode(self._completedSessions)
            userDefaults.set(data, forKey: storageKey)
            updateStorageMetrics()
            logger.debug("Persisted \(self._completedSessions.count) sessions to UserDefaults (\(data.count) bytes)")
        } catch {
            logger.error("Failed to persist sessions: \(error.localizedDescription)")
            // Attempt recovery by clearing corrupted data
            userDefaults.removeObject(forKey: storageKey)
            userDefaults.removeObject(forKey: storageMetricsKey)
        }
    }
    
    private func loadPersistedSessions() {
        guard let data = userDefaults.data(forKey: storageKey) else {
            logger.debug("No persisted sessions found")
            return
        }
        
        do {
            _completedSessions = try JSONDecoder().decode([LogSession].self, from: data)
            logger.debug("Loaded \(self._completedSessions.count) persisted sessions (\(data.count) bytes)")
            
            // Enforce limits on startup in case they changed
            enforceStorageLimits()
            
            // Perform periodic cleanup if needed
            performPeriodicCleanup()
            
        } catch {
            logger.error("Failed to load persisted sessions: \(error.localizedDescription)")
            // Clear corrupted data
            userDefaults.removeObject(forKey: storageKey)
            userDefaults.removeObject(forKey: storageMetricsKey)
            _completedSessions = []
        }
    }
    
    private func performPeriodicCleanup() {
        guard let metrics = getStorageMetrics() else {
            // First time setup - update metrics
            updateStorageMetrics()
            return
        }
        
        // Perform cleanup if it's been more than 24 hours since last cleanup
        let daysSinceCleanup = Date().timeIntervalSince(metrics.lastCleanupDate) / (24 * 60 * 60)
        if daysSinceCleanup >= 1.0 {
            logger.debug("Performing periodic cleanup (last cleanup: \(daysSinceCleanup) days ago)")
            enforceStorageLimits()
            persistSessions()
        }
    }
}
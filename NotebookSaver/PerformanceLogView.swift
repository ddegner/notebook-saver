import SwiftUI

/// SwiftUI view for displaying performance logs with summary statistics and detailed session information
struct PerformanceLogView: View {
    @StateObject private var logger = PerformanceLogger.shared
    @State private var sessions: [LogSession] = []
    @State private var isLoading = true
    @State private var showingFullLogs = false
    @State private var copySuccess = false
    @State private var expandedSessions: Set<UUID> = []

    @State private var showingClearConfirmation = false
    @State private var showingOldClearConfirmation = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if isLoading {
                    loadingView
                } else if sessions.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            summaryStatisticsView
                            sessionListView
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Performance Logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: copyLogsToClipboard) {
                            Label("Copy All Logs", systemImage: "doc.on.clipboard")
                        }
                        
                        Divider()
                        
                        Button(action: { showingOldClearConfirmation = true }) {
                            Label("Clear Old Logs", systemImage: "clock.arrow.circlepath")
                        }
                        
                        Button(action: { showingClearConfirmation = true }) {
                            Label("Clear All Logs", systemImage: "trash")
                        }
                        .foregroundColor(.red)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .alert("Logs Copied", isPresented: $copySuccess) {
                Button("OK") { }
            } message: {
                Text("Performance logs have been copied to clipboard")
            }
            .alert("Clear All Logs", isPresented: $showingClearConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Clear All", role: .destructive) {
                    clearAllLogs()
                }
            } message: {
                Text("This will permanently delete all performance logs. This action cannot be undone.")
            }
            .alert("Clear Old Logs", isPresented: $showingOldClearConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Clear Old", role: .destructive) {
                    clearOldLogsOnly()
                }
            } message: {
                Text("This will remove old log entries beyond the storage limit while keeping recent logs.")
            }
        }
        .onAppear {
            loadSessions()
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading performance data...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Empty State View
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Performance Data")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Performance logs will appear here after you capture and process photos.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Summary Statistics View
    
    private var summaryStatisticsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(.blue)
                Text("Summary Statistics")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            let completedSessions = sessions.filter { $0.isCompleted }
            let totalSessions = sessions.count
            let completedCount = completedSessions.count
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                StatisticCard(
                    title: "Total Sessions",
                    value: "\(totalSessions)",
                    icon: "number.circle.fill",
                    color: .blue
                )
                
                StatisticCard(
                    title: "Completed",
                    value: "\(completedCount)",
                    icon: "checkmark.circle.fill",
                    color: .green
                )
                
                if !completedSessions.isEmpty {
                    let totalDurations = completedSessions.compactMap { $0.totalDuration }
                    if !totalDurations.isEmpty {
                        let avgDuration = totalDurations.reduce(0, +) / Double(totalDurations.count)
                        StatisticCard(
                            title: "Avg Duration",
                            value: String(format: "%.2fs", avgDuration),
                            icon: "clock.fill",
                            color: .orange
                        )
                        
                        let fastestDuration = totalDurations.min() ?? 0
                        StatisticCard(
                            title: "Fastest",
                            value: String(format: "%.2fs", fastestDuration),
                            icon: "bolt.fill",
                            color: .yellow
                        )
                    }
                }
            }
            

            
            // Operation Statistics
            if !sessions.isEmpty {
                operationStatisticsView
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }
    

    
    // MARK: - Operation Statistics View
    
    private var operationStatisticsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "gearshape.2.fill")
                    .foregroundColor(.purple)
                Text("Top Operations")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
            }
            
            let allEntries = sessions.flatMap { $0.entries }
            let operationGroups = Dictionary(grouping: allEntries) { entry in
                // Group by base operation name (remove failure suffixes)
                entry.operation
                    .replacingOccurrences(of: " (failed)", with: "")
                    .replacingOccurrences(of: " (failed: .*)", with: "", options: .regularExpression)
            }
            
            let topOperations = operationGroups
                .map { (operation, entries) in
                    let durations = entries.map { $0.duration }
                    let avgDuration = durations.reduce(0, +) / Double(durations.count)
                    let failedCount = entries.filter { $0.operation.contains("(failed") }.count
                    return (operation: operation, count: entries.count, avgDuration: avgDuration, failedCount: failedCount)
                }
                .sorted { $0.count > $1.count }
                .prefix(3)
            
            ForEach(Array(topOperations.enumerated()), id: \.offset) { index, operationData in
                HStack {
                    Text(operationData.operation)
                        .font(.caption)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(operationData.count)×")
                            .font(.caption2)
                            .fontWeight(.medium)
                        
                        Text(String(format: "%.2fs", operationData.avgDuration))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    if operationData.failedCount > 0 {
                        Text("(\(operationData.failedCount) failed)")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.top, 8)
    }
    
    // MARK: - Session List View
    
    private var sessionListView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "list.bullet.rectangle.fill")
                    .foregroundColor(.indigo)
                Text("Recent Sessions")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            LazyVStack(spacing: 12) {
                ForEach(sessions.prefix(10)) { session in
                    SessionRowView(
                        session: session,
                        isExpanded: expandedSessions.contains(session.id)
                    ) {
                        toggleSessionExpansion(session.id)
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func loadSessions() {
        Task {
            let loadedSessions = await logger.getRecentSessions(limit: 50)
            await MainActor.run {
                self.sessions = loadedSessions
                self.isLoading = false
            }
        }
    }
    
    private func copyLogsToClipboard() {
        Task {
            let formattedLogs = await logger.getFormattedLogs()
            await MainActor.run {
                UIPasteboard.general.string = formattedLogs
                copySuccess = true
            }
        }
    }
    

    
    private func clearAllLogs() {
        logger.clearOldLogs()
        sessions = []
    }
    
    private func clearOldLogsOnly() {
        logger.clearOldLogsOnly()
        loadSessions()
    }
    
    private func toggleSessionExpansion(_ sessionId: UUID) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedSessions.contains(sessionId) {
                expandedSessions.remove(sessionId)
            } else {
                expandedSessions.insert(sessionId)
            }
        }
    }
}

// MARK: - Supporting Views

/// Card view for displaying statistics
struct StatisticCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title3)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }
}

/// Row view for displaying individual sessions
struct SessionRowView: View {
    let session: LogSession
    let isExpanded: Bool
    let onTap: () -> Void
    
    private var sessionStatusColor: Color {
        if !session.isCompleted { return .orange }
        switch session.wasSuccessful {
        case true: return .green
        case false: return .red
        case nil: return .orange
        }
    }
    
    private var sessionStatusText: String {
        if !session.isCompleted { return "Incomplete" }
        switch session.wasSuccessful {
        case true: return "Completed"
        case false: return "Failed"
        case nil: return "Incomplete"
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Main session row
            Button(action: onTap) {
                HStack(spacing: 12) {
                    // Status indicator
                    Circle()
                        .fill(sessionStatusColor)
                        .frame(width: 8, height: 8)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Session")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Spacer()
                            
                            Text(sessionStatusText)
                                .font(.caption)
                                .foregroundColor(sessionStatusColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(sessionStatusColor.opacity(0.1))
                                )
                        }
                        
                        HStack {
                            Text(formatDate(session.startTime))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            if let totalDuration = session.totalDuration {
                                Text(String(format: "%.2fs", totalDuration))
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                        }
                        
                        Text("\(session.entries.count) operations")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            .buttonStyle(.plain)
            
            // Expanded content
            if isExpanded && !session.entries.isEmpty {
                VStack(spacing: 8) {
                    Divider()
                        .padding(.horizontal)
                    
                    LazyVStack(spacing: 6) {
                        ForEach(session.entries) { entry in
                            OperationRowView(entry: entry)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

/// Row view for displaying individual operations within a session
struct OperationRowView: View {
    let entry: LogEntry
    
    private var operationColor: Color {
        if entry.operation.contains("(failed") {
            return .red
        } else {
            return .primary
        }
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Operation indicator
            Circle()
                .fill(operationColor.opacity(0.3))
                .frame(width: 6, height: 6)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(entry.operation)
                        .font(.caption)
                        .foregroundColor(operationColor)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text(String(format: "%.3fs", entry.duration))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    if let modelInfo = entry.modelInfo {
                        Text("\(modelInfo.serviceName)/\(modelInfo.modelName)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        
                        // Add image metadata if available
                        if let imageMetadata = modelInfo.imageMetadata {
                            Text("•")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Text("\(Int(imageMetadata.processedWidth))×\(Int(imageMetadata.processedHeight))")
                                .font(.caption2)
                                .foregroundColor(.blue)
                            
                            Text("•")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Text(formatFileSize(imageMetadata.processedFileSizeBytes))
                                .font(.caption2)
                                .foregroundColor(.blue)
                            
                            // Show compression indicator if significant
                            if imageMetadata.compressionRatio < 0.8 {
                                Text("•")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                
                                Text("\(Int(imageMetadata.compressionRatio * 100))%")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    
                    Spacer()
                }
            }
        }
        .padding(.vertical, 2)
    }
    
    private func formatFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.includesCount = true
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Preview

#Preview {
    PerformanceLogView()
}

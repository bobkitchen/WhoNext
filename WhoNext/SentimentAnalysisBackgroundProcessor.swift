import Foundation
import CoreData
import Combine
import SwiftUI

// MARK: - Background Processing Models

struct ProcessingProgress: Equatable {
    let totalConversations: Int
    let processedConversations: Int
    let currentConversation: String?
    let estimatedTimeRemaining: TimeInterval
    let isComplete: Bool
    let errors: [String]
    
    var progressPercentage: Double {
        guard totalConversations > 0 else { return 0.0 }
        return Double(processedConversations) / Double(totalConversations)
    }
    
    static func == (lhs: ProcessingProgress, rhs: ProcessingProgress) -> Bool {
        return lhs.totalConversations == rhs.totalConversations &&
               lhs.processedConversations == rhs.processedConversations &&
               lhs.currentConversation == rhs.currentConversation &&
               lhs.estimatedTimeRemaining == rhs.estimatedTimeRemaining &&
               lhs.isComplete == rhs.isComplete &&
               lhs.errors == rhs.errors
    }
}

enum ProcessingState: Equatable {
    case idle
    case preparing
    case processing(ProcessingProgress)
    case paused
    case completed(ProcessingProgress)
    case failed(Error)
    
    static func == (lhs: ProcessingState, rhs: ProcessingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.preparing, .preparing), (.paused, .paused):
            return true
        case (.processing(let lhsProgress), .processing(let rhsProgress)):
            return lhsProgress == rhsProgress
        case (.completed(let lhsProgress), .completed(let rhsProgress)):
            return lhsProgress == rhsProgress
        case (.failed(let lhsError), .failed(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
}

// MARK: - Background Processor

class SentimentAnalysisBackgroundProcessor: ObservableObject {
    static let shared = SentimentAnalysisBackgroundProcessor()
    
    @Published var processingState: ProcessingState = .idle
    @Published var isProcessing: Bool = false
    @Published var lastError: String?
    
    private let sentimentService = SentimentAnalysisService.shared
    private var processingTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    
    // Processing configuration
    private let batchSize = 10
    private let processingDelay: TimeInterval = 0.5 // Delay between batches to prevent UI blocking
    
    init() {}
    
    // MARK: - Public Methods
    
    /// Start processing all unanalyzed conversations
    func startProcessing(context: NSManagedObjectContext) {
        guard !isProcessing else { return }
        
        isProcessing = true
        processingState = .preparing
        
        processingTask = Task { @MainActor in
            await processAllConversations(context: context)
        }
    }
    
    /// Pause the current processing
    func pauseProcessing() {
        guard isProcessing else { return }
        
        processingTask?.cancel()
        processingState = .paused
        isProcessing = false
    }
    
    /// Resume processing from where it left off
    func resumeProcessing(context: NSManagedObjectContext) {
        guard case .paused = processingState else { return }
        startProcessing(context: context)
    }
    
    /// Stop processing completely
    func stopProcessing() {
        processingTask?.cancel()
        processingState = .idle
        isProcessing = false
    }
    
    // MARK: - Private Processing Methods
    
    @MainActor
    private func processAllConversations(context: NSManagedObjectContext) async {
        do {
            let unanalyzedConversations = try fetchUnanalyzedConversations(context: context)
            
            guard !unanalyzedConversations.isEmpty else {
                processingState = .completed(ProcessingProgress(
                    totalConversations: 0,
                    processedConversations: 0,
                    currentConversation: nil,
                    estimatedTimeRemaining: 0,
                    isComplete: true,
                    errors: []
                ))
                isProcessing = false
                return
            }
            
            let startTime = Date()
            var processedCount = 0
            var errors: [String] = []
            
            // Process conversations in batches
            for batch in unanalyzedConversations.chunked(into: batchSize) {
                // Check if processing was cancelled
                if Task.isCancelled {
                    processingState = .paused
                    isProcessing = false
                    return
                }
                
                // Process current batch
                for conversation in batch {
                    let personName = conversation.person?.name ?? "Unknown"
                    let conversationDate = conversation.date?.formatted(date: .abbreviated, time: .omitted) ?? "Unknown date"
                    let currentConversationDescription = "\(personName) - \(conversationDate)"
                    
                    // Update progress
                    let estimatedTimeRemaining = calculateEstimatedTimeRemaining(
                        startTime: startTime,
                        processed: processedCount,
                        total: unanalyzedConversations.count
                    )
                    
                    let progress = ProcessingProgress(
                        totalConversations: unanalyzedConversations.count,
                        processedConversations: processedCount,
                        currentConversation: currentConversationDescription,
                        estimatedTimeRemaining: estimatedTimeRemaining,
                        isComplete: false,
                        errors: errors
                    )
                    
                    processingState = .processing(progress)
                    
                    // Perform sentiment analysis
                    do {
                        try await processConversation(conversation, context: context)
                        processedCount += 1
                    } catch {
                        let errorMessage = "Failed to analyze conversation with \(personName): \(error.localizedDescription)"
                        errors.append(errorMessage)
                        print("Sentiment analysis error: \(errorMessage)")
                        lastError = errorMessage
                    }
                }
                
                // Small delay between batches to prevent UI blocking
                try await Task.sleep(nanoseconds: UInt64(processingDelay * 1_000_000_000))
            }
            
            // Processing completed
            let finalProgress = ProcessingProgress(
                totalConversations: unanalyzedConversations.count,
                processedConversations: processedCount,
                currentConversation: nil,
                estimatedTimeRemaining: 0,
                isComplete: true,
                errors: errors
            )
            
            processingState = .completed(finalProgress)
            isProcessing = false
            
            print("Sentiment analysis completed: \(processedCount)/\(unanalyzedConversations.count) conversations processed")
            
        } catch {
            processingState = .failed(error)
            isProcessing = false
            print("Failed to start sentiment analysis processing: \(error)")
            lastError = error.localizedDescription
        }
    }
    
    private func fetchUnanalyzedConversations(context: NSManagedObjectContext) throws -> [Conversation] {
        let request = NSFetchRequest<Conversation>(entityName: "Conversation")
        
        // Fetch conversations that haven't been analyzed or need re-analysis
        request.predicate = NSPredicate(format: "lastSentimentAnalysis == nil OR analysisVersion != %@", SentimentAnalysisService.shared.currentAnalysisVersion)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Conversation.date, ascending: false)]
        
        return try context.fetch(request)
    }
    
    private func processConversation(_ conversation: Conversation, context: NSManagedObjectContext) async throws {
        // Perform sentiment analysis
        if let analysis = await sentimentService.analyzeConversation(
            summary: conversation.summary,
            notes: conversation.notes
        ) {
            // Update conversation with analysis results
            await MainActor.run {
                sentimentService.updateConversationWithAnalysis(conversation, analysis: analysis, context: context)
            }
        }
    }
    
    private func calculateEstimatedTimeRemaining(startTime: Date, processed: Int, total: Int) -> TimeInterval {
        guard processed > 0 else { return 0 }
        
        let elapsedTime = Date().timeIntervalSince(startTime)
        let averageTimePerConversation = elapsedTime / Double(processed)
        let remaining = total - processed
        
        return averageTimePerConversation * Double(remaining)
    }
}

// MARK: - Array Extension for Chunking

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Processing Status View

struct SentimentProcessingStatusView: View {
    @StateObject private var processor = SentimentAnalysisBackgroundProcessor.shared
    @Environment(\.managedObjectContext) private var viewContext
    @State private var migrationStatus: MigrationStatus?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Status Header
            HStack {
                Image(systemName: statusIcon)
                    .foregroundColor(statusColor)
                    .font(.title3)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sentiment Analysis")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if processor.isProcessing {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            
            // Progress Bar
            if let status = migrationStatus, !status.isComplete {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: status.completionPercentage)
                        .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                    
                    Text("\(status.analyzedConversations) of \(status.totalConversations) conversations analyzed")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            // Action Buttons
            HStack(spacing: 8) {
                if !processor.isProcessing && (migrationStatus?.needsAnalysis ?? 0) > 0 {
                    Button("Start Analysis") {
                        processor.startProcessing(context: viewContext)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                
                if processor.isProcessing {
                    if processor.processingState == .paused {
                        Button("Resume") {
                            processor.resumeProcessing(context: viewContext)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        Button("Pause") {
                            processor.pauseProcessing()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    Button("Stop") {
                        processor.stopProcessing()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                Button("Refresh") {
                    updateMigrationStatus()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            // Error Display
            if let error = processor.lastError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.red)
                        .font(.caption)
                    
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(2)
                }
                .padding(8)
                .background(Color.red.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear {
            updateMigrationStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)) { _ in
            updateMigrationStatus()
        }
    }
    
    private var statusIcon: String {
        switch processor.processingState {
        case .idle:
            return "circle"
        case .preparing, .processing:
            return "clock"
        case .paused:
            return "pause"
        case .completed:
            return "checkmark"
        case .failed:
            return "exclamationmark.triangle"
        }
    }
    
    private var statusColor: Color {
        switch processor.processingState {
        case .idle:
            return .gray
        case .preparing, .processing:
            return .blue
        case .paused:
            return .orange
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }
    
    private var statusText: String {
        switch processor.processingState {
        case .idle:
            return "Ready to analyze conversations for sentiment and insights."
        case .preparing:
            return "Preparing conversations for analysis..."
        case .processing(let progress):
            return "Processing: \(progress.processedConversations)/\(progress.totalConversations)"
        case .paused:
            return "Processing paused"
        case .completed(let progress):
            return "Analysis completed: \(progress.processedConversations) conversations processed"
        case .failed(let error):
            return "Analysis failed: \(error.localizedDescription)"
        }
    }
    
    private func updateMigrationStatus() {
        migrationStatus = SentimentAnalysisMigration.getMigrationStatus(context: viewContext)
    }
}

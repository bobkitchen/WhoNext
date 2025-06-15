import SwiftUI

struct TranscriptInputView: View {
    @StateObject private var processor = TranscriptProcessor()
    @State private var transcriptText = ""
    @State private var showingReviewScreen = false
    @State private var processedTranscript: ProcessedTranscript?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Import Meeting Transcript")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Paste your full meeting transcript below. The AI will extract participants, generate summary notes, and analyze sentiment.")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Transcript Input Area
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Meeting Transcript")
                            .font(.headline)
                        
                        Spacer()
                        
                        if !transcriptText.isEmpty {
                            Text("\(wordCount) words")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.textBackgroundColor))
                            .stroke(Color(.separatorColor), lineWidth: 1)
                        
                        if transcriptText.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Paste your transcript here...")
                                    .foregroundColor(.secondary)
                                
                                Text("Supported formats:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("• Zoom: John: Hello everyone...")
                                    Text("• Teams: [John] Hello everyone...")
                                    Text("• Generic: John - Hello everyone...")
                                    Text("• Manual notes")
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            .padding()
                        }
                        
                        TextEditor(text: $transcriptText)
                            .font(.system(.body, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .padding(8)
                    }
                    .frame(minHeight: 300)
                }
                
                // Format Detection
                if !transcriptText.isEmpty {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        
                        Text("Detected format: \(detectedFormat.displayName)")
                            .font(.subheadline)
                        
                        Spacer()
                        
                        if estimatedDuration > 0 {
                            Text("~\(Int(estimatedDuration)) min meeting")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(8)
                }
                
                Spacer()
                
                // Processing Status
                if processor.isProcessing {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        
                        Text(processor.processingStatus)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(12)
                }
                
                // Error Display
                if let error = processor.error {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.red)
                    }
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                }
                
                // Action Buttons
                HStack(spacing: 16) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(LiquidGlassButtonStyle(variant: .secondary, size: .medium))
                    
                    Spacer()
                    
                    Button("Process Transcript") {
                        processTranscript()
                    }
                    .buttonStyle(LiquidGlassButtonStyle(variant: .primary, size: .medium))
                    .disabled(transcriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || processor.isProcessing)
                }
            }
            .padding()
            .navigationTitle("Import Transcript")
            .alert("Processing Error", isPresented: .constant(processor.error != nil)) {
                Button("OK") { }
            } message: {
                Text(processor.error ?? "")
            }
        }
        .sheet(isPresented: $showingReviewScreen, onDismiss: {
            processedTranscript = nil
            transcriptText = ""
            processor.error = nil
        }) {
            if let processedTranscript = processedTranscript {
                TranscriptReviewView(processedTranscript: processedTranscript)
                    .environment(\.managedObjectContext, viewContext)
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var wordCount: Int {
        transcriptText.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.count
    }
    
    private var detectedFormat: TranscriptFormat {
        let lowerText = transcriptText.lowercased()
        
        if lowerText.contains("zoom") || transcriptText.contains("00:") {
            return .zoom
        } else if lowerText.contains("teams") || lowerText.contains("microsoft") {
            return .teams
        } else if transcriptText.contains(":") && transcriptText.contains("\n") {
            return .generic
        } else {
            return .manual
        }
    }
    
    private var estimatedDuration: Double {
        let wordCount = Double(self.wordCount)
        return (wordCount / 150.0) // 150 words per minute average
    }
    
    // MARK: - Methods
    
    private func processTranscript() {
        Task {
            if let result = await processor.processTranscript(transcriptText) {
                await MainActor.run {
                    self.processedTranscript = result
                    self.showingReviewScreen = true
                }
            }
        }
    }
}

// MARK: - Preview

struct TranscriptInputView_Previews: PreviewProvider {
    static var previews: some View {
        TranscriptInputView()
    }
}

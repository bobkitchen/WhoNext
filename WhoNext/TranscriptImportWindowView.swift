import SwiftUI
import CoreData

struct TranscriptImportWindowView: View {
    @StateObject private var processor = TranscriptProcessor()
    @State private var transcriptText = ""
    @State private var processedTranscript: ProcessedTranscript?
    @State private var showingReviewScreen = false
    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
        NavigationStack {
            if showingReviewScreen, let processedTranscript = processedTranscript {
                TranscriptReviewView(processedTranscript: processedTranscript)
                    .environment(\.managedObjectContext, viewContext)
                    .navigationBarBackButtonHidden(true)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Back") {
                                showingReviewScreen = false
                                self.processedTranscript = nil
                                transcriptText = ""
                                processor.error = nil
                            }
                        }
                    }
            } else {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 48))
                            .foregroundColor(.blue)
                        
                        Text("Import Meeting Transcript")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Paste your meeting transcript below and let AI extract participants, generate summaries, and analyze sentiment.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.top)
                    
                    // Transcript Input
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Meeting Transcript")
                                .font(.headline)
                            
                            Spacer()
                            
                            if !transcriptText.isEmpty {
                                Text("\(transcriptText.split(separator: " ").count) words")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        TextEditor(text: $transcriptText)
                            .font(.system(.body, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .background(Color(NSColor.textBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                            .frame(minHeight: 200)
                        
                        if transcriptText.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Supported formats:")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("• Zoom transcripts")
                                    Text("• Microsoft Teams transcripts")
                                    Text("• Generic timestamped transcripts")
                                    Text("• Manual notes")
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            .padding(.top, 8)
                        }
                        
                        // Format Detection
                        if !transcriptText.isEmpty {
                            let detectedFormat = processor.detectTranscriptFormat(transcriptText)
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Detected format: \(detectedFormat.rawValue.capitalized)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Processing Status
                    if processor.isProcessing {
                        VStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text(processor.processingStatus)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                    
                    // Action Buttons
                    HStack(spacing: 16) {
                        Button("Clear") {
                            transcriptText = ""
                        }
                        .disabled(transcriptText.isEmpty || processor.isProcessing)
                        
                        Spacer()
                        
                        Button("Process Transcript") {
                            Task {
                                if let processed = await processor.processTranscript(transcriptText) {
                                    processedTranscript = processed
                                    showingReviewScreen = true
                                }
                            }
                        }
                        .buttonStyle(LiquidGlassButtonStyle(variant: .primary, size: .medium))
                        .disabled(transcriptText.isEmpty || processor.isProcessing)
                    }
                    .padding(.bottom)
                }
                .padding()
                .navigationTitle("")
                .alert("Processing Error", isPresented: .constant(processor.error != nil)) {
                    Button("OK") { 
                        processor.error = nil
                    }
                } message: {
                    Text(processor.error ?? "")
                }
            }
        }
        .onAppear {
            transcriptText = ""
            processedTranscript = nil
            processor.error = nil
        }
    }
}

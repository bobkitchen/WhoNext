import SwiftUI
import UniformTypeIdentifiers

struct LinkedInPDFDropZone: View {
    @StateObject private var processor = LinkedInPDFProcessor()
    @State private var isDragOver = false
    @State private var droppedFiles: [URL] = []
    
    let onProfileGenerated: (String) -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            // Drop Zone
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isDragOver ? Color.blue.opacity(0.1) : Color.gray.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                isDragOver ? Color.blue : Color.gray.opacity(0.3),
                                style: StrokeStyle(lineWidth: 2, dash: isDragOver ? [] : [8, 4])
                            )
                    )
                    .frame(height: 120)
                
                VStack(spacing: 12) {
                    if processor.isProcessing {
                        VStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text(processor.processingStatus)
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    } else if !droppedFiles.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.green)
                            
                            VStack(spacing: 4) {
                                Text("Files Ready:")
                                    .font(.system(size: 13, weight: .medium))
                                ForEach(droppedFiles.indices, id: \.self) { index in
                                    Text(droppedFiles[index].lastPathComponent)
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "doc.badge.plus")
                                .font(.system(size: 24))
                                .foregroundColor(isDragOver ? .blue : .secondary)
                            
                            VStack(spacing: 4) {
                                Text("Drop LinkedIn Profile PDFs")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(isDragOver ? .blue : .primary)
                                
                                Text("Supports 1-2 PDF files (Experience + Education pages)")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                    }
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
                handleDrop(providers: providers)
                return true
            }
            
            // Process Button
            if !droppedFiles.isEmpty && !processor.isProcessing {
                Button(action: processFiles) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                        Text("Generate Profile Summary")
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Error Display
            if let error = processor.error {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            
            // Instructions
            if droppedFiles.isEmpty && !processor.isProcessing {
                VStack(alignment: .leading, spacing: 6) {
                    Text("How to use:")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("1. Find the person on LinkedIn")
                        Text("2. Print Experience page as PDF")
                        Text("3. Print Education page as PDF (optional)")
                        Text("4. Drag both PDFs here")
                    }
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !processor.isProcessing else { return false }
        
        var urls: [URL] = []
        let group = DispatchGroup()
        
        for provider in providers.prefix(2) { // Limit to 2 files
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                defer { group.leave() }
                
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil),
                   url.pathExtension.lowercased() == "pdf" {
                    urls.append(url)
                }
            }
        }
        
        group.notify(queue: .main) {
            if !urls.isEmpty {
                self.droppedFiles = urls
                print("🔍 [LinkedIn] Dropped \(urls.count) PDF files")
            }
        }
        
        return true
    }
    
    private func processFiles() {
        guard !droppedFiles.isEmpty else { return }
        
        processor.processLinkedInPDFs(droppedFiles) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let profileSummary):
                    print("✅ [LinkedIn] Profile summary generated successfully")
                    self.onProfileGenerated(profileSummary)
                    self.droppedFiles = [] // Clear files after successful processing
                    
                case .failure(let error):
                    print("❌ [LinkedIn] Profile generation failed: \(error)")
                    // Error is already displayed via the processor's @Published error property
                }
            }
        }
    }
}

#Preview {
    LinkedInPDFDropZone { summary in
        print("Generated summary: \(summary)")
    }
    .padding()
    .frame(width: 400)
}

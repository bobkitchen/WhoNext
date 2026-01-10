import SwiftUI
import UniformTypeIdentifiers
import AppKit

/// A compact, inline-friendly drop zone for importing LinkedIn profile PDFs
/// Designed to fit within PersonDetailView as a square component
struct CompactLinkedInDropZone: View {
    @StateObject private var processor = LinkedInPDFProcessor()
    @State private var isDragOver = false
    @State private var droppedFiles: [URL] = []
    @State private var showSuccess = false

    /// Callback when profile is successfully imported
    /// Returns profileMarkdown: String
    let onProfileImported: (String) -> Void

    var body: some View {
        VStack(spacing: 12) {
            // Drop Zone - Square aspect ratio
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(dropZoneBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                dropZoneBorder,
                                style: StrokeStyle(lineWidth: 2, dash: isDragOver ? [] : [6, 4])
                            )
                    )

                dropZoneContent
            }
            .frame(height: 140)
            .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
                handleDrop(providers: providers)
                return true
            }

            // Action buttons
            if !droppedFiles.isEmpty && !processor.isProcessing && !showSuccess {
                HStack(spacing: 12) {
                    // Browse button
                    Button(action: browseForFiles) {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                                .font(.system(size: 11))
                            Text("Add More")
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                    .buttonStyle(LiquidGlassButtonStyle(variant: .secondary, size: .small))

                    Spacer()

                    // Import button
                    Button(action: processFiles) {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11))
                            Text("Import Profile")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Error display
            if let error = processor.error {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 12))
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    Spacer()
                    Button(action: { processor.error = nil }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Instructions (only when empty)
            if droppedFiles.isEmpty && !processor.isProcessing && !showSuccess {
                instructionsView
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        .cornerRadius(12)
        .onChange(of: showSuccess) { _, newValue in
            if newValue {
                // Auto-hide success after 2 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showSuccess = false
                }
            }
        }
    }

    // MARK: - Drop Zone States

    @ViewBuilder
    private var dropZoneContent: some View {
        if processor.isProcessing {
            processingView
        } else if showSuccess {
            successView
        } else if !droppedFiles.isEmpty {
            filesReadyView
        } else {
            emptyStateView
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 10) {
            Image(systemName: isDragOver ? "arrow.down.doc.fill" : "doc.badge.arrow.up")
                .font(.system(size: 28))
                .foregroundColor(isDragOver ? .accentColor : .secondary)
                .symbolEffect(.bounce, value: isDragOver)

            VStack(spacing: 4) {
                Text(isDragOver ? "Release to import" : "Drop PDF(s) here")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isDragOver ? .accentColor : .primary)

                Text("or click to browse")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            browseForFiles()
        }
    }

    private var filesReadyView: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.green)

                // Clear button overlay
                Button(action: clearFiles) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear selected files")
                .offset(x: 30, y: -5)
            }

            VStack(spacing: 4) {
                Text("\(droppedFiles.count) PDF\(droppedFiles.count > 1 ? "s" : "") ready")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)

                ForEach(droppedFiles.indices, id: \.self) { index in
                    Text(droppedFiles[index].lastPathComponent)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var processingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)

            VStack(spacing: 4) {
                Text("Extracting profile...")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)

                Text(processor.processingStatus)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var successView: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 32))
                .foregroundColor(.green)

            Text("Profile imported!")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.green)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var instructionsView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("How to import:")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                instructionRow("1", "Open LinkedIn profile in browser")
                instructionRow("2", "Print to PDF (expand sections first)")
                instructionRow("3", "Drop PDF here (1-3 files for long profiles)")
            }

            Text("Photo: Use Edit to paste from clipboard")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .italic()
                .padding(.top, 2)
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func instructionRow(_ number: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Text(number)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.accentColor)
                .frame(width: 14, height: 14)
                .background(Color.accentColor.opacity(0.15))
                .clipShape(Circle())
            Text(text)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Styling

    private var dropZoneBackground: Color {
        if isDragOver {
            return Color.accentColor.opacity(0.1)
        } else if showSuccess {
            return Color.green.opacity(0.05)
        } else {
            return Color(nsColor: .controlBackgroundColor)
        }
    }

    private var dropZoneBorder: Color {
        if isDragOver {
            return Color.accentColor
        } else if showSuccess {
            return Color.green.opacity(0.5)
        } else {
            return Color.secondary.opacity(0.3)
        }
    }

    // MARK: - Actions

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !processor.isProcessing else { return false }

        var urls: [URL] = []
        let group = DispatchGroup()

        // Limit to 3 files total
        let remainingSlots = 3 - droppedFiles.count
        let providersToProcess = Array(providers.prefix(remainingSlots))

        for provider in providersToProcess {
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
                // Append to existing files (up to 3 total)
                let newFiles = (self.droppedFiles + urls).prefix(3)
                self.droppedFiles = Array(newFiles)
                print("📄 [LinkedInPDF] \(self.droppedFiles.count) PDF file(s) ready")
            }
        }

        return true
    }

    private func browseForFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.pdf]
        panel.message = "Select LinkedIn profile PDF(s)"
        panel.prompt = "Select"

        if panel.runModal() == .OK {
            let remainingSlots = 3 - droppedFiles.count
            let newFiles = Array(panel.urls.prefix(remainingSlots))
            droppedFiles = Array((droppedFiles + newFiles).prefix(3))
            print("📄 [LinkedInPDF] Selected \(droppedFiles.count) PDF file(s)")
        }
    }

    private func clearFiles() {
        droppedFiles = []
        processor.error = nil
    }

    private func processFiles() {
        guard !droppedFiles.isEmpty else { return }

        processor.processLinkedInPDFsWithOCR(droppedFiles) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let extractedData):
                    print("✅ [LinkedInPDF] Profile extracted successfully")
                    self.showSuccess = true
                    self.droppedFiles = []
                    self.onProfileImported(extractedData.markdown)

                case .failure(let error):
                    print("❌ [LinkedInPDF] Extraction failed: \(error)")
                    // Error is displayed via processor.error
                }
            }
        }
    }
}

#Preview {
    CompactLinkedInDropZone { markdown in
        print("Imported profile:")
        print(markdown)
    }
    .frame(width: 350)
    .padding()
}

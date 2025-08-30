import SwiftUI

/// View for displaying individual transcript segments with speaker identification
struct TranscriptSegmentView: View {
    let segment: TranscriptSegment
    let expanded: Bool
    
    @State private var isHovered: Bool = false
    @State private var showActions: Bool = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Timestamp
            VStack(alignment: .trailing, spacing: 4) {
                Text(segment.formattedTimestamp)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                
                // Confidence indicator
                if expanded {
                    ConfidenceIndicator(confidence: segment.confidence)
                }
            }
            .frame(width: 50)
            
            // Speaker and text
            VStack(alignment: .leading, spacing: 6) {
                // Speaker name
                if let speaker = segment.speakerName {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(colorForSpeaker(speaker))
                            .frame(width: 8, height: 8)
                        
                        Text(speaker)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(colorForSpeaker(speaker))
                        
                        if segment.isFinalized {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.green)
                                .help("Finalized by Whisper")
                        } else {
                            Image(systemName: "waveform")
                                .font(.system(size: 9))
                                .foregroundColor(.orange)
                                .help("Processing...")
                        }
                    }
                }
                
                // Transcript text
                Text(segment.text)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Actions (shown on hover in expanded mode)
                if expanded && (isHovered || showActions) {
                    segmentActions
                }
            }
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color(NSColor.controlBackgroundColor).opacity(0.5) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
    
    // MARK: - Subviews
    
    private var segmentActions: some View {
        HStack(spacing: 8) {
            // Copy button
            Button(action: copyToClipboard) {
                Label("Copy", systemImage: "doc.on.doc")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            
            // Edit speaker button
            Button(action: editSpeaker) {
                Label("Edit Speaker", systemImage: "pencil")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            
            // Flag as important
            Button(action: flagImportant) {
                Label("Flag", systemImage: "flag")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
        .padding(.top, 4)
    }
    
    // MARK: - Helper Methods
    
    private func colorForSpeaker(_ speaker: String) -> Color {
        let colors: [Color] = [
            .blue, .green, .orange, .purple, 
            .pink, .cyan, .indigo, .mint
        ]
        let index = abs(speaker.hashValue) % colors.count
        return colors[index]
    }
    
    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        var textToCopy = segment.text
        if let speaker = segment.speakerName {
            textToCopy = "\(speaker): \(segment.text)"
        }
        
        pasteboard.setString(textToCopy, forType: .string)
    }
    
    private func editSpeaker() {
        // TODO: Implement speaker editing
        showActions.toggle()
    }
    
    private func flagImportant() {
        // TODO: Implement flagging
        print("Flagged segment at \(segment.timestamp)")
    }
}

// MARK: - Confidence Indicator

struct ConfidenceIndicator: View {
    let confidence: Float
    
    var level: ConfidenceLevel {
        switch confidence {
        case 0.8...1.0:
            return .high
        case 0.5..<0.8:
            return .medium
        default:
            return .low
        }
    }
    
    enum ConfidenceLevel {
        case high, medium, low
        
        var color: Color {
            switch self {
            case .high: return .green
            case .medium: return .orange
            case .low: return .red
            }
        }
        
        var icon: String {
            switch self {
            case .high: return "circle.fill"
            case .medium: return "circle.lefthalf.filled"
            case .low: return "circle"
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                Image(systemName: levelIcon(for: index))
                    .font(.system(size: 6))
                    .foregroundColor(levelColor(for: index))
            }
        }
        .help("Confidence: \(Int(confidence * 100))%")
    }
    
    private func levelIcon(for index: Int) -> String {
        let threshold = Float(index + 1) / 3.0
        return confidence >= threshold ? "circle.fill" : "circle"
    }
    
    private func levelColor(for index: Int) -> Color {
        let threshold = Float(index + 1) / 3.0
        return confidence >= threshold ? level.color : Color.gray.opacity(0.3)
    }
}

// MARK: - Compact Variant

struct CompactTranscriptSegmentView: View {
    let segment: TranscriptSegment
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Timestamp
            Text(segment.formattedTimestamp)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 40)
            
            // Text with inline speaker
            if let speaker = segment.speakerName {
                (Text("**\(speaker):** ")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary) +
                Text(segment.text)
                    .font(.system(size: 10))
                    .foregroundColor(.primary))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(segment.text)
                    .font(.system(size: 10))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

struct TranscriptSegmentView_Previews: PreviewProvider {
    static let sampleSegment = TranscriptSegment(
        text: "This is a sample transcript segment showing how the text appears in the interface.",
        timestamp: 125.5,
        speakerID: "speaker1",
        speakerName: "Bob Kitchen",
        confidence: 0.92,
        isFinalized: true
    )
    
    static var previews: some View {
        VStack(spacing: 20) {
            TranscriptSegmentView(segment: sampleSegment, expanded: true)
                .frame(width: 400)
            
            CompactTranscriptSegmentView(segment: sampleSegment)
                .frame(width: 400)
        }
        .padding()
    }
}
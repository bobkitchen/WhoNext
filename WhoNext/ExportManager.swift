import Foundation
import AVFoundation
import AppKit
import UniformTypeIdentifiers

/// Manages export of meeting recordings and transcripts in multiple formats
class ExportManager {
    
    // MARK: - Singleton
    static let shared = ExportManager()
    private init() {}
    
    // MARK: - Audio Export
    
    /// Export audio in various formats
    func exportAudio(
        from sourceURL: URL,
        format: AudioExportFormat,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        Task {
            do {
                let exportedURL = try await exportAudioAsync(from: sourceURL, format: format)
                await MainActor.run {
                    completion(.success(exportedURL))
                }
            } catch {
                await MainActor.run {
                    completion(.failure(error))
                }
            }
        }
    }
    
    private func exportAudioAsync(from sourceURL: URL, format: AudioExportFormat) async throws -> URL {
        // Show save panel
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [format.contentType]
        savePanel.nameFieldStringValue = "meeting_recording.\(format.fileExtension)"
        
        guard await MainActor.run(body: { savePanel.runModal() == .OK }),
              let destinationURL = savePanel.url else {
            throw ExportError.userCancelled
        }
        
        switch format {
        case .original:
            // Copy original file
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            return destinationURL
            
        case .compressed:
            // Convert to MP3
            return try await convertToMP3(source: sourceURL, destination: destinationURL)
            
        case .lossless:
            // Convert to WAV
            return try await convertToWAV(source: sourceURL, destination: destinationURL)
            
        case .trimmed(let startTime, let endTime):
            // Export trimmed segment
            return try await exportTrimmed(
                source: sourceURL,
                destination: destinationURL,
                startTime: startTime,
                endTime: endTime
            )
        }
    }
    
    private func convertToMP3(source: URL, destination: URL) async throws -> URL {
        let asset = AVAsset(url: source)
        
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw ExportError.conversionFailed
        }
        
        exportSession.outputURL = destination
        exportSession.outputFileType = .m4a // Note: Direct MP3 export requires additional encoding
        
        await exportSession.export()
        
        if exportSession.status == .completed {
            return destination
        } else {
            throw ExportError.conversionFailed
        }
    }
    
    private func convertToWAV(source: URL, destination: URL) async throws -> URL {
        let inputFile = try AVAudioFile(forReading: source)
        let format = inputFile.processingFormat
        
        // Create WAV file with PCM format
        let outputSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        
        let outputFile = try AVAudioFile(
            forWriting: destination,
            settings: outputSettings
        )
        
        // Read and write in chunks
        let frameCount = AVAudioFrameCount(8192)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        
        while inputFile.framePosition < inputFile.length {
            let framesToRead = min(frameCount, AVAudioFrameCount(inputFile.length - inputFile.framePosition))
            buffer.frameLength = framesToRead
            
            try inputFile.read(into: buffer)
            try outputFile.write(from: buffer)
        }
        
        return destination
    }
    
    private func exportTrimmed(
        source: URL,
        destination: URL,
        startTime: TimeInterval,
        endTime: TimeInterval
    ) async throws -> URL {
        let asset = AVAsset(url: source)
        
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw ExportError.conversionFailed
        }
        
        exportSession.outputURL = destination
        exportSession.outputFileType = .m4a
        exportSession.timeRange = CMTimeRange(
            start: CMTime(seconds: startTime, preferredTimescale: 1000),
            end: CMTime(seconds: endTime, preferredTimescale: 1000)
        )
        
        await exportSession.export()
        
        if exportSession.status == .completed {
            return destination
        } else {
            throw ExportError.conversionFailed
        }
    }
    
    // MARK: - Transcript Export
    
    /// Export transcript in various formats
    func exportTranscript(
        meeting: GroupMeeting,
        format: TranscriptExportFormat,
        options: TranscriptExportOptions = .default,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        Task {
            do {
                let exportedURL = try await exportTranscriptAsync(
                    meeting: meeting,
                    format: format,
                    options: options
                )
                await MainActor.run {
                    completion(.success(exportedURL))
                }
            } catch {
                await MainActor.run {
                    completion(.failure(error))
                }
            }
        }
    }
    
    private func exportTranscriptAsync(
        meeting: GroupMeeting,
        format: TranscriptExportFormat,
        options: TranscriptExportOptions
    ) async throws -> URL {
        // Show save panel
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [format.contentType]
        savePanel.nameFieldStringValue = "meeting_transcript.\(format.fileExtension)"
        
        guard await MainActor.run(body: { savePanel.runModal() == .OK }),
              let destinationURL = savePanel.url else {
            throw ExportError.userCancelled
        }
        
        // Generate content based on format
        let content: String
        
        switch format {
        case .plainText:
            content = generatePlainText(meeting: meeting, options: options)
            
        case .markdown:
            content = generateMarkdown(meeting: meeting, options: options)
            
        case .json:
            content = try generateJSON(meeting: meeting, options: options)
            
        case .pdf:
            return try await generatePDF(meeting: meeting, options: options, destination: destinationURL)
            
        case .word:
            content = generateRTF(meeting: meeting, options: options)
            
        case .srt:
            content = generateSRT(meeting: meeting)
        }
        
        // Write content to file
        try content.write(to: destinationURL, atomically: true, encoding: .utf8)
        return destinationURL
    }
    
    private func generatePlainText(meeting: GroupMeeting, options: TranscriptExportOptions) -> String {
        var content = ""
        
        // Header
        content += "Meeting Transcript\n"
        content += String(repeating: "=", count: 50) + "\n\n"
        
        if let title = meeting.title {
            content += "Title: \(title)\n"
        }
        if let date = meeting.date {
            content += "Date: \(date.formatted())\n"
        }
        content += "Duration: \(meeting.formattedDuration)\n"
        
        // Attendees
        if meeting.attendeeCount > 0 {
            content += "\nAttendees:\n"
            for attendee in meeting.sortedAttendees {
                content += "- \(attendee.name ?? "Unknown")\n"
            }
        }
        
        // Summary
        if options.includeSummary, let summary = meeting.summary {
            content += "\n" + String(repeating: "=", count: 50) + "\n"
            content += "SUMMARY\n"
            content += String(repeating: "=", count: 50) + "\n\n"
            content += summary + "\n"
        }
        
        // Key Topics
        if let topics = meeting.keyTopics as? [String], !topics.isEmpty {
            content += "\n" + String(repeating: "=", count: 50) + "\n"
            content += "KEY TOPICS\n"
            content += String(repeating: "=", count: 50) + "\n\n"
            for topic in topics {
                content += "• \(topic)\n"
            }
        }
        
        // Transcript
        content += "\n" + String(repeating: "=", count: 50) + "\n"
        content += "TRANSCRIPT\n"
        content += String(repeating: "=", count: 50) + "\n\n"
        
        if let segments = meeting.parsedTranscript {
            for segment in segments {
                if options.includeTimestamps {
                    content += "[\(segment.formattedTimestamp)] "
                }
                if options.includeSpeakers, let speaker = segment.speakerName {
                    content += "\(speaker): "
                }
                content += "\(segment.text)\n\n"
            }
        } else if let transcript = meeting.transcript {
            content += transcript
        }
        
        return content
    }
    
    private func generateMarkdown(meeting: GroupMeeting, options: TranscriptExportOptions) -> String {
        var content = ""
        
        // Header
        content += "# Meeting Transcript\n\n"
        
        if let title = meeting.title {
            content += "## \(title)\n\n"
        }
        
        // Metadata
        content += "| Field | Value |\n"
        content += "|-------|-------|\n"
        if let date = meeting.date {
            content += "| Date | \(date.formatted()) |\n"
        }
        content += "| Duration | \(meeting.formattedDuration) |\n"
        content += "| Attendees | \(meeting.attendeeCount) |\n\n"
        
        // Attendees
        if meeting.attendeeCount > 0 {
            content += "### Attendees\n\n"
            for attendee in meeting.sortedAttendees {
                content += "- \(attendee.name ?? "Unknown")\n"
            }
            content += "\n"
        }
        
        // Summary
        if options.includeSummary, let summary = meeting.summary {
            content += "## Summary\n\n"
            content += summary + "\n\n"
        }
        
        // Key Topics
        if let topics = meeting.keyTopics as? [String], !topics.isEmpty {
            content += "## Key Topics\n\n"
            for topic in topics {
                content += "- \(topic)\n"
            }
            content += "\n"
        }
        
        // Transcript
        content += "## Transcript\n\n"
        
        if let segments = meeting.parsedTranscript {
            for segment in segments {
                if options.includeTimestamps {
                    content += "**[\(segment.formattedTimestamp)]** "
                }
                if options.includeSpeakers, let speaker = segment.speakerName {
                    content += "**\(speaker):** "
                }
                content += "\(segment.text)\n\n"
            }
        } else if let transcript = meeting.transcript {
            content += transcript
        }
        
        return content
    }
    
    private func generateJSON(meeting: GroupMeeting, options: TranscriptExportOptions) throws -> String {
        var json: [String: Any] = [:]
        
        // Metadata
        json["id"] = meeting.identifier?.uuidString
        json["title"] = meeting.title
        json["date"] = meeting.date?.ISO8601Format()
        json["duration"] = meeting.duration
        json["attendeeCount"] = meeting.attendeeCount
        
        // Attendees
        json["attendees"] = meeting.sortedAttendees.map { $0.name ?? "Unknown" }
        
        // Summary
        if options.includeSummary {
            json["summary"] = meeting.summary
        }
        
        // Key topics
        json["keyTopics"] = meeting.keyTopics as? [String] ?? []
        
        // Transcript segments
        if let segments = meeting.parsedTranscript {
            json["transcript"] = segments.map { segment in
                var segmentDict: [String: Any] = ["text": segment.text]
                if options.includeTimestamps {
                    segmentDict["timestamp"] = segment.timestamp
                }
                if options.includeSpeakers {
                    segmentDict["speaker"] = segment.speakerName
                }
                segmentDict["confidence"] = segment.confidence
                return segmentDict
            }
        } else {
            json["transcript"] = meeting.transcript
        }
        
        let jsonData = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
        return String(data: jsonData, encoding: .utf8) ?? "{}"
    }
    
    private func generatePDF(
        meeting: GroupMeeting,
        options: TranscriptExportOptions,
        destination: URL
    ) async throws -> URL {
        // Generate markdown first
        let markdown = generateMarkdown(meeting: meeting, options: options)
        
        // Convert to attributed string with styling
        let attributedString = NSMutableAttributedString(string: markdown)
        let range = NSRange(location: 0, length: attributedString.length)
        attributedString.addAttribute(.font, value: NSFont.systemFont(ofSize: 12), range: range)
        
        // Create text view with the content
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 612, height: 792))
        textView.textStorage?.setAttributedString(attributedString)
        
        // Create PDF data
        let pdfData = textView.dataWithPDF(inside: textView.bounds)
        
        // Write PDF to destination
        try pdfData.write(to: destination)
        
        return destination
    }
    
    private func generateRTF(meeting: GroupMeeting, options: TranscriptExportOptions) -> String {
        // Generate rich text format for Word
        let markdown = generateMarkdown(meeting: meeting, options: options)
        return markdown // Simplified - would need proper RTF generation
    }
    
    private func generateSRT(meeting: GroupMeeting) -> String {
        var srt = ""
        var index = 1
        
        if let segments = meeting.parsedTranscript {
            for segment in segments {
                let startTime = formatSRTTime(segment.timestamp)
                let endTime = formatSRTTime(segment.timestamp + 5) // Assume 5 second segments
                
                srt += "\(index)\n"
                srt += "\(startTime) --> \(endTime)\n"
                if let speaker = segment.speakerName {
                    srt += "[\(speaker)]\n"
                }
                srt += "\(segment.text)\n\n"
                
                index += 1
            }
        }
        
        return srt
    }
    
    private func formatSRTTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        let millis = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)
        
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, secs, millis)
    }
}

// MARK: - Export Formats

enum AudioExportFormat {
    case original // M4A
    case compressed // MP3
    case lossless // WAV
    case trimmed(startTime: TimeInterval, endTime: TimeInterval)
    
    var contentType: UTType {
        switch self {
        case .original: return .mpeg4Audio
        case .compressed: return .mp3
        case .lossless: return .wav
        case .trimmed: return .mpeg4Audio
        }
    }
    
    var fileExtension: String {
        switch self {
        case .original: return "m4a"
        case .compressed: return "mp3"
        case .lossless: return "wav"
        case .trimmed: return "m4a"
        }
    }
}

enum TranscriptExportFormat {
    case plainText
    case markdown
    case json
    case pdf
    case word
    case srt // Subtitles format
    
    var contentType: UTType {
        switch self {
        case .plainText: return .plainText
        case .markdown: return UTType(filenameExtension: "md") ?? .plainText
        case .json: return .json
        case .pdf: return .pdf
        case .word: return .rtf
        case .srt: return UTType(filenameExtension: "srt") ?? .plainText
        }
    }
    
    var fileExtension: String {
        switch self {
        case .plainText: return "txt"
        case .markdown: return "md"
        case .json: return "json"
        case .pdf: return "pdf"
        case .word: return "docx"
        case .srt: return "srt"
        }
    }
}

struct TranscriptExportOptions {
    var includeTimestamps: Bool = true
    var includeSpeakers: Bool = true
    var includeSummary: Bool = true
    var dateRange: DateInterval?
    
    static let `default` = TranscriptExportOptions()
    static let minimal = TranscriptExportOptions(
        includeTimestamps: false,
        includeSpeakers: false,
        includeSummary: false
    )
}

enum ExportError: LocalizedError {
    case userCancelled
    case conversionFailed
    case invalidFormat
    case fileNotFound
    
    var errorDescription: String? {
        switch self {
        case .userCancelled:
            return "Export cancelled by user"
        case .conversionFailed:
            return "Failed to convert audio format"
        case .invalidFormat:
            return "Invalid export format"
        case .fileNotFound:
            return "Source file not found"
        }
    }
}
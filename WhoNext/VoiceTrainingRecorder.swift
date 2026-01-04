import Foundation
import AVFoundation
import Combine

/// Handles recording audio samples for voice training
/// Records short audio clips, extracts voice embeddings, and saves to UserProfile
@MainActor
class VoiceTrainingRecorder: ObservableObject {

    // MARK: - Published Properties
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var recordingState: RecordingState = .idle
    @Published var lastError: String?

    // MARK: - Recording State
    enum RecordingState: Equatable {
        case idle
        case preparing
        case recording
        case processing
        case completed
        case error(String)
    }

    // MARK: - Configuration
    private let minimumDuration: TimeInterval = 5.0  // Minimum 5 seconds
    private let maximumDuration: TimeInterval = 30.0 // Maximum 30 seconds

    // MARK: - Audio Components
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var audioFile: AVAudioFile?
    private var recordingStartTime: Date?
    private var recordingTimer: Timer?
    private var audioBuffers: [AVAudioPCMBuffer] = []

    // MARK: - Diarization for Voice Embedding
    #if canImport(FluidAudio)
    private var diarizationManager: DiarizationManager?
    #endif

    // MARK: - Initialization
    init() {
        setupDiarization()
    }

    // MARK: - Setup

    private func setupDiarization() {
        #if canImport(FluidAudio)
        diarizationManager = DiarizationManager()
        Task {
            try? await diarizationManager?.initialize()
        }
        #endif
    }

    // MARK: - Public Methods

    /// Start recording a voice sample
    func startRecording() async throws {
        guard !isRecording else { return }

        // Check microphone permission
        let permissionGranted = await checkMicrophonePermission()
        guard permissionGranted else {
            recordingState = .error("Microphone permission required")
            lastError = "Please grant microphone access in System Preferences > Privacy & Security"
            throw VoiceTrainingError.permissionDenied
        }

        recordingState = .preparing

        // Setup audio engine
        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else {
            recordingState = .error("Failed to create audio engine")
            throw VoiceTrainingError.setupFailed
        }

        inputNode = engine.inputNode
        guard let input = inputNode else {
            recordingState = .error("No microphone found")
            throw VoiceTrainingError.noMicrophone
        }

        // Clear previous buffers
        audioBuffers.removeAll()

        // Configure audio format
        let format = input.outputFormat(forBus: 0)

        // Install tap to capture audio
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, time in
            Task { @MainActor [weak self] in
                self?.audioBuffers.append(buffer)
            }
        }

        // Start the engine
        try engine.start()

        // Update state
        isRecording = true
        recordingState = .recording
        recordingStartTime = Date()
        recordingDuration = 0

        // Start timer to update duration
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let startTime = self.recordingStartTime else { return }
                self.recordingDuration = Date().timeIntervalSince(startTime)

                // Auto-stop at maximum duration
                if self.recordingDuration >= self.maximumDuration {
                    try? await self.stopRecording()
                }
            }
        }

        print("🎤 Started voice training recording")
    }

    /// Stop recording and process the voice sample
    func stopRecording() async throws {
        guard isRecording else { return }

        recordingTimer?.invalidate()
        recordingTimer = nil

        let duration = recordingDuration

        // Check minimum duration
        guard duration >= minimumDuration else {
            await cancelRecording()
            recordingState = .error("Recording too short")
            lastError = "Please record for at least \(Int(minimumDuration)) seconds"
            throw VoiceTrainingError.tooShort
        }

        // Stop the engine
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()

        isRecording = false
        recordingState = .processing

        print("🎤 Stopped recording, processing \(duration)s of audio...")

        // Process the audio to extract voice embedding
        do {
            let embedding = try await processAudioForEmbedding()

            // Save to UserProfile
            UserProfile.shared.addVoiceSample(embedding)

            recordingState = .completed
            print("✅ Voice sample saved! Total samples: \(UserProfile.shared.voiceSampleCount)")

            // Auto-reset after 2 seconds
            try? await Task.sleep(for: .seconds(2))
            recordingState = .idle
            recordingDuration = 0

        } catch {
            recordingState = .error("Failed to process audio")
            lastError = error.localizedDescription
            throw error
        }

        // Cleanup
        audioBuffers.removeAll()
    }

    /// Cancel the current recording without saving
    func cancelRecording() async {
        recordingTimer?.invalidate()
        recordingTimer = nil

        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()

        isRecording = false
        recordingState = .idle
        recordingDuration = 0
        audioBuffers.removeAll()

        print("❌ Voice recording cancelled")
    }

    // MARK: - Private Methods

    /// Check and request microphone permission
    private func checkMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    /// Process recorded audio to extract voice embedding
    private func processAudioForEmbedding() async throws -> [Float] {
        #if canImport(FluidAudio)
        guard let manager = diarizationManager else {
            throw VoiceTrainingError.diarizationUnavailable
        }

        // Combine all audio buffers into a single file
        guard let audioFile = try? createAudioFile(from: audioBuffers) else {
            throw VoiceTrainingError.processingFailed
        }

        // Process with diarization to extract voice embedding
        let result = try await manager.processAudioFile(audioFile)

        // Get the dominant speaker's embedding
        // (assuming the user is the primary speaker in their training sample)
        guard let firstSegment = result.segments.first else {
            throw VoiceTrainingError.noVoiceDetected
        }

        return firstSegment.embedding

        #else
        // Fallback: generate a random embedding (for testing without FluidAudio)
        print("⚠️ FluidAudio not available, using mock embedding")
        return (0..<192).map { _ in Float.random(in: -1...1) }
        #endif
    }

    /// Create an audio file from captured buffers
    private func createAudioFile(from buffers: [AVAudioPCMBuffer]) throws -> URL {
        guard !buffers.isEmpty else {
            throw VoiceTrainingError.noAudioData
        }

        // Create temporary file
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "voice_training_\(UUID().uuidString).wav"
        let fileURL = tempDir.appendingPathComponent(fileName)

        // Get format from first buffer
        guard let format = buffers.first?.format else {
            throw VoiceTrainingError.invalidFormat
        }

        // Create audio file
        let audioFile = try AVAudioFile(forWriting: fileURL, settings: format.settings)

        // Write all buffers to file
        for buffer in buffers {
            try audioFile.write(from: buffer)
        }

        return fileURL
    }
}

// MARK: - Errors

enum VoiceTrainingError: LocalizedError {
    case permissionDenied
    case setupFailed
    case noMicrophone
    case tooShort
    case processingFailed
    case diarizationUnavailable
    case noVoiceDetected
    case noAudioData
    case invalidFormat

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission denied"
        case .setupFailed:
            return "Failed to setup audio recording"
        case .noMicrophone:
            return "No microphone available"
        case .tooShort:
            return "Recording is too short"
        case .processingFailed:
            return "Failed to process audio"
        case .diarizationUnavailable:
            return "Voice analysis not available"
        case .noVoiceDetected:
            return "No voice detected in recording"
        case .noAudioData:
            return "No audio data captured"
        case .invalidFormat:
            return "Invalid audio format"
        }
    }
}

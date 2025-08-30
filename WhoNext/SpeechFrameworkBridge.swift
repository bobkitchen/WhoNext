import Foundation
import AVFoundation
import Speech

/// Bridge to handle Speech framework APIs that exist at runtime but not in headers
/// This allows us to compile while the APIs are not yet in the SDK
@available(macOS 26.0, *)
class SpeechFrameworkBridge {
    
    /// Use the traditional SFSpeechRecognizer as a fallback
    /// Until the new APIs are properly exposed in the SDK
    class FallbackTranscriber {
        private let recognizer: SFSpeechRecognizer
        private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
        private var recognitionTask: SFSpeechRecognitionTask?
        private let audioEngine = AVAudioEngine()
        
        init(locale: Locale) {
            self.recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
        }
        
        func startTranscription(completion: @escaping (String) -> Void) throws {
            // Create request
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let recognitionRequest = recognitionRequest else {
                throw ModernSpeechError.transcriberNotInitialized
            }
            
            recognitionRequest.shouldReportPartialResults = true
            recognitionRequest.requiresOnDeviceRecognition = false
            
            // Start recognition task
            recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { result, error in
                if let result = result {
                    completion(result.bestTranscription.formattedString)
                }
            }
            
            // Configure audio engine
            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                recognitionRequest.append(buffer)
            }
            
            audioEngine.prepare()
            try audioEngine.start()
        }
        
        func processBuffer(_ buffer: AVAudioPCMBuffer) {
            recognitionRequest?.append(buffer)
        }
        
        func stopTranscription() {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
            recognitionRequest?.endAudio()
            recognitionTask?.cancel()
        }
    }
    
    /// Temporary implementation using SFSpeechRecognizer
    /// This will be replaced when the new APIs are in the SDK
    static func createTranscriber(locale: Locale) -> FallbackTranscriber {
        return FallbackTranscriber(locale: locale)
    }
}
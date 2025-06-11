import Foundation
import SwiftUI

// MARK: - Ollama Models
struct OllamaModel: Identifiable, Codable {
    var id = UUID()
    let name: String
    let displayName: String
    let size: String
    let description: String
    let supportsVision: Bool
    
    static let recommendedModels = [
        OllamaModel(
            name: "llama3.1",
            displayName: "Llama 3.1 (8B)",
            size: "4.7GB",
            description: "Fast, general-purpose model. Good for chat and analysis.",
            supportsVision: false
        ),
        OllamaModel(
            name: "llama3.1:70b",
            displayName: "Llama 3.1 (70B)",
            size: "40GB",
            description: "Larger, more capable model. Requires significant RAM.",
            supportsVision: false
        ),
        OllamaModel(
            name: "mistral",
            displayName: "Mistral 7B",
            size: "4.1GB",
            description: "Efficient model with good reasoning capabilities.",
            supportsVision: false
        ),
        OllamaModel(
            name: "llava",
            displayName: "LLaVA",
            size: "4.7GB",
            description: "Vision-capable model for image analysis (LinkedIn PDFs).",
            supportsVision: true
        ),
        OllamaModel(
            name: "codellama",
            displayName: "Code Llama",
            size: "3.8GB",
            description: "Specialized for code generation and analysis.",
            supportsVision: false
        )
    ]
}

// MARK: - Ollama Status
enum OllamaStatus: Equatable {
    case notInstalled
    case installed
    case running
    case stopped
    case error(String)
    
    var displayText: String {
        switch self {
        case .notInstalled: return "Not Installed"
        case .installed: return "Installed"
        case .running: return "Running"
        case .stopped: return "Stopped"
        case .error(let message): return "Error: \(message)"
        }
    }
    
    var color: Color {
        switch self {
        case .notInstalled: return .red
        case .installed: return .orange
        case .running: return .green
        case .stopped: return .orange
        case .error: return .red
        }
    }
}

// MARK: - Ollama Service
@MainActor
class OllamaService: ObservableObject {
    static let shared = OllamaService()
    
    @Published var status: OllamaStatus = .notInstalled
    @Published var installedModels: [String] = []
    @Published var isCheckingStatus = false
    @Published var isInstallingModel = false
    @Published var installProgress: Double = 0.0
    @Published var installMessage: String = ""
    
    @AppStorage("ollamaBaseURL") var baseURL: String = "http://localhost:11434"
    
    private init() {
        Task {
            await checkStatus()
        }
    }
    
    // MARK: - Status Checking
    func checkStatus() async {
        isCheckingStatus = true
        defer { isCheckingStatus = false }
        
        // First check if Ollama is installed
        if !(await isOllamaInstalled()) {
            status = .notInstalled
            return
        }
        
        // Check if Ollama is running
        if await isOllamaRunning() {
            status = .running
            await loadInstalledModels()
        } else {
            status = .stopped
        }
    }
    
    private func isOllamaInstalled() async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["ollama"]
        
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    private func isOllamaRunning() async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/tags") else { return false }
        
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
        } catch {
            // Ollama not running
        }
        
        return false
    }
    
    private func loadInstalledModels() async {
        guard let url = URL(string: "\(baseURL)/api/tags") else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = json["models"] as? [[String: Any]] {
                
                let modelNames = models.compactMap { $0["name"] as? String }
                installedModels = modelNames
            }
        } catch {
            print("Failed to load installed models: \(error)")
        }
    }
    
    // MARK: - Installation
    func installOllama() async {
        // Open Ollama website for manual installation
        if let url = URL(string: "https://ollama.ai/download") {
            await MainActor.run {
                _ = NSWorkspace.shared.open(url)
            }
        }
    }
    
    func startOllama() async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["ollama", "serve"]
        
        do {
            try process.run()
            // Give it a moment to start
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            await checkStatus()
        } catch {
            status = .error("Failed to start Ollama: \(error.localizedDescription)")
        }
    }
    
    func installModel(_ modelName: String) async {
        isInstallingModel = true
        installProgress = 0.0
        installMessage = "Installing \(modelName)..."
        
        defer {
            isInstallingModel = false
            installProgress = 0.0
            installMessage = ""
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["ollama", "pull", modelName]
        
        do {
            try process.run()
            
            // Simulate progress (real progress tracking would require parsing ollama output)
            for i in 1...10 {
                installProgress = Double(i) / 10.0
                installMessage = "Installing \(modelName)... \(Int(installProgress * 100))%"
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            }
            
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                installMessage = "Successfully installed \(modelName)"
                await checkStatus() // Refresh installed models
            } else {
                status = .error("Failed to install \(modelName)")
            }
        } catch {
            status = .error("Failed to install \(modelName): \(error.localizedDescription)")
        }
    }
    
    func removeModel(_ modelName: String) async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["ollama", "rm", modelName]
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                await checkStatus() // Refresh installed models
            } else {
                status = .error("Failed to remove \(modelName)")
            }
        } catch {
            status = .error("Failed to remove \(modelName): \(error.localizedDescription)")
        }
    }
    
    // MARK: - Utility Methods
    func getRecommendedModel() -> OllamaModel? {
        return OllamaModel.recommendedModels.first { model in
            installedModels.contains { $0.hasPrefix(model.name) }
        } ?? OllamaModel.recommendedModels.first
    }
    
    func isModelInstalled(_ modelName: String) -> Bool {
        return installedModels.contains { $0.hasPrefix(modelName) }
    }
    
    func getVisionModel() -> String? {
        return installedModels.first { $0.hasPrefix("llava") } ?? "llava"
    }
}

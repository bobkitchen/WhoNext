import SwiftUI

struct OllamaManagementView: View {
    @StateObject private var ollamaService = OllamaService.shared
    @AppStorage("ollamaModel") private var selectedModel: String = "llama3.1"
    @AppStorage("ollamaVisionModel") private var selectedVisionModel: String = "llava"
    @AppStorage("ollamaBaseURL") private var baseURL: String = "http://localhost:11434"
    
    @State private var showingModelInstaller = false
    @State private var showingAdvancedSettings = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Status Section
            statusSection
            
            // Model Selection Section
            if ollamaService.status == .running {
                modelSelectionSection
            }
            
            // Action Buttons
            actionButtonsSection
            
            // Advanced Settings
            if showingAdvancedSettings {
                advancedSettingsSection
            }
        }
        .task {
            await ollamaService.checkStatus()
        }
        .sheet(isPresented: $showingModelInstaller) {
            ModelInstallerView()
        }
    }
    
    // MARK: - Status Section
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Ollama Status")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(ollamaService.status.color)
                        .frame(width: 8, height: 8)
                    
                    Text(ollamaService.status.displayText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if ollamaService.isCheckingStatus {
                ProgressView()
                    .scaleEffect(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    // MARK: - Model Selection Section
    private var modelSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Model Configuration")
                .font(.subheadline)
                .fontWeight(.medium)
            
            // Chat Model Selection
            VStack(alignment: .leading, spacing: 4) {
                Text("Chat Model")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if ollamaService.installedModels.isEmpty {
                    Text("No models installed")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    Picker("Chat Model", selection: $selectedModel) {
                        ForEach(ollamaService.installedModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            
            // Vision Model Selection
            VStack(alignment: .leading, spacing: 4) {
                Text("Vision Model (for LinkedIn PDFs)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                let visionModels = ollamaService.installedModels.filter { $0.contains("llava") || $0.contains("vision") }
                
                if visionModels.isEmpty {
                    Text("No vision models installed")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    Picker("Vision Model", selection: $selectedVisionModel) {
                        ForEach(visionModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            
            // Installed Models Summary
            if !ollamaService.installedModels.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Installed Models (\(ollamaService.installedModels.count))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(ollamaService.installedModels, id: \.self) { model in
                                Text(model)
                                    .font(.caption2)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.1))
                                    .foregroundColor(.blue)
                                    .cornerRadius(4)
                            }
                        }
                        .padding(.horizontal, 1)
                    }
                }
            }
        }
    }
    
    // MARK: - Action Buttons Section
    private var actionButtonsSection: some View {
        VStack(spacing: 8) {
            switch ollamaService.status {
            case .notInstalled:
                Button("Install Ollama") {
                    Task {
                        await ollamaService.installOllama()
                    }
                }
                .buttonStyle(.borderedProminent)
                
            case .installed, .stopped:
                Button("Start Ollama") {
                    Task {
                        await ollamaService.startOllama()
                    }
                }
                .buttonStyle(.borderedProminent)
                
            case .running:
                HStack(spacing: 12) {
                    Button("Install Models") {
                        showingModelInstaller = true
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Refresh Status") {
                        Task {
                            await ollamaService.checkStatus()
                        }
                    }
                    .buttonStyle(.bordered)
                }
                
            case .error:
                Button("Retry") {
                    Task {
                        await ollamaService.checkStatus()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            
            // Advanced Settings Toggle
            Button(showingAdvancedSettings ? "Hide Advanced" : "Advanced Settings") {
                withAnimation {
                    showingAdvancedSettings.toggle()
                }
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundColor(.blue)
        }
    }
    
    // MARK: - Advanced Settings Section
    private var advancedSettingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Advanced Settings")
                .font(.subheadline)
                .fontWeight(.medium)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Ollama Base URL")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                TextField("http://localhost:11434", text: $baseURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }
            
            Text("Change this if you're running Ollama on a different port or remote server.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.top, 8)
    }
}

// MARK: - Model Installer View
struct ModelInstallerView: View {
    @StateObject private var ollamaService = OllamaService.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Install AI Models")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Choose models to install. Larger models provide better quality but require more RAM and storage.")
                    .font(.body)
                    .foregroundColor(.secondary)
                
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(OllamaModel.recommendedModels) { model in
                            ModelCard(model: model)
                        }
                    }
                    .padding(.horizontal)
                }
                
                if ollamaService.isInstallingModel {
                    VStack(spacing: 8) {
                        ProgressView(value: ollamaService.installProgress)
                            .progressViewStyle(LinearProgressViewStyle())
                        
                        Text(ollamaService.installMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            .padding()
            .navigationTitle("Model Installer")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 600, height: 500)
    }
}

// MARK: - Model Card View
struct ModelCard: View {
    let model: OllamaModel
    @StateObject private var ollamaService = OllamaService.shared
    
    var isInstalled: Bool {
        ollamaService.isModelInstalled(model.name)
    }
    
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(model.displayName)
                        .font(.headline)
                    
                    if model.supportsVision {
                        Image(systemName: "eye.fill")
                            .foregroundColor(.blue)
                            .font(.caption)
                    }
                    
                    Spacer()
                    
                    Text(model.size)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text(model.description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            VStack(spacing: 8) {
                if isInstalled {
                    Button("Remove") {
                        Task {
                            await ollamaService.removeModel(model.name)
                        }
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                } else {
                    Button("Install") {
                        Task {
                            await ollamaService.installModel(model.name)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(ollamaService.isInstallingModel)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Preview
struct OllamaManagementView_Previews: PreviewProvider {
    static var previews: some View {
        OllamaManagementView()
            .frame(width: 400)
            .padding()
    }
}

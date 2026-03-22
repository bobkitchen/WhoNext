import SwiftUI
import CoreData

/// Advanced settings including danger zone operations and app management
struct AdvancedSettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @AppStorage("dismissedPeople") private var dismissedPeopleData: Data = Data()
    @State private var showResetConfirmation = false
    @State private var showDeleteAllConfirmation = false
    @State private var showDeleteConversationsConfirmation = false
    @State private var showClearCacheConfirmation = false
    @State private var cacheSize: String = "Calculating..."
    @State private var diagnosticExportStatus: String?
    @State private var diagnosticSummary: String = ""

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Person.name, ascending: true)],
        predicate: NSPredicate(format: "isSoftDeleted == false"),
        animation: .default
    ) private var people: FetchedResults<Person>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Conversation.date, ascending: false)],
        predicate: NSPredicate(format: "isSoftDeleted == false"),
        animation: .default
    ) private var conversations: FetchedResults<Conversation>

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // App Info Section
            appInfoSection

            Divider()

            // Maintenance Section
            maintenanceSection

            Divider()

            // Diarization Diagnostics Section
            diarizationDiagnosticsSection

            Divider()

            // Danger Zone
            dangerZoneSection
        }
        .onAppear {
            calculateCacheSize()
        }
    }

    // MARK: - App Info Section

    private var appInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("App Information")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Version:")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
                }

                HStack {
                    Text("Build:")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown")
                }

                HStack {
                    Text("People Records:")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(people.count)")
                }

                HStack {
                    Text("Conversations:")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(conversations.count)")
                }

                HStack {
                    Text("Cache Size:")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(cacheSize)
                }
            }
            .font(.subheadline)
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    // MARK: - Maintenance Section

    private var maintenanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Maintenance")
                .font(.headline)

            Text("These operations help keep your app running smoothly.")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Clear Cache")
                            .font(.subheadline)
                        Text("Remove temporary files and cached data")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Clear") {
                        showClearCacheConfirmation = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reset Dismissed People")
                            .font(.subheadline)
                        Text("Show previously dismissed suggestions again")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Reset") {
                        dismissedPeopleData = Data()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rebuild Search Index")
                            .font(.subheadline)
                        Text("Fix search issues by rebuilding the index")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Rebuild") {
                        rebuildSearchIndex()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
        .alert("Clear Cache", isPresented: $showClearCacheConfirmation) {
            Button("Clear", role: .destructive) { clearCache() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will remove temporary files and cached data. Your people and conversations will not be affected.")
        }
    }

    // MARK: - Diarization Diagnostics Section

    private var diarizationDiagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Session Diagnostics")
                .font(.headline)

            Text("Export session log and diarization data for analysis.")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Export Session Log")
                            .font(.subheadline)
                        Text("App log, diarization output, energy gate decisions, speaker identification")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Export JSON") {
                        exportDiarizationDiagnostics()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if let status = diagnosticExportStatus {
                    Text(status)
                        .font(.caption)
                        .foregroundColor(status.contains("Error") ? .red : .green)
                        .textSelection(.enabled)
                }

                if !diagnosticSummary.isEmpty {
                    Text(diagnosticSummary)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(4)
                        .textSelection(.enabled)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
        .onAppear {
            diagnosticSummary = DiarizationDiagnostics.shared.summaryString()
        }
    }

    private func exportDiarizationDiagnostics() {
        do {
            let url = try DiarizationDiagnostics.shared.exportToJSON()
            diagnosticExportStatus = "Exported to: \(url.path)"

            // Also open in Finder
            NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
        } catch {
            diagnosticExportStatus = "Error: \(error.localizedDescription)"
        }
        diagnosticSummary = DiarizationDiagnostics.shared.summaryString()
    }

    // MARK: - Danger Zone Section

    private var dangerZoneSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text("Danger Zone")
                    .font(.headline)
                    .foregroundColor(.red)
            }

            Text("These actions cannot be undone. Please proceed with caution.")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                // Reset "Who You've Spoken To"
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reset Meeting Tracking")
                            .font(.subheadline)
                        Text("Clear all last-contact dates. Conversations and notes preserved.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        showResetConfirmation = true
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Divider()

                // Delete All Conversations
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Delete All Conversations")
                            .font(.subheadline)
                        Text("Remove all conversation records and notes. People preserved.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        showDeleteConversationsConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Divider()

                // Delete All People
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Delete All People")
                            .font(.subheadline)
                            .foregroundColor(.red)
                        Text("Permanently remove all people from this device and iCloud.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        showDeleteAllConfirmation = true
                    } label: {
                        Label("Delete All", systemImage: "person.crop.circle.badge.xmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.small)
                }
            }
            .padding()
            .background(Color.red.opacity(0.05))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.red.opacity(0.3), lineWidth: 1)
            )
        }
        .alert("Reset Meeting Tracking", isPresented: $showResetConfirmation) {
            Button("Reset", role: .destructive) { resetSpokenTo() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will clear all last-contact dates, resetting the \"who needs a meeting\" calculations. Your conversation notes will NOT be deleted.")
        }
        .alert("Delete All Conversations", isPresented: $showDeleteConversationsConfirmation) {
            Button("Delete All", role: .destructive) { deleteAllConversations() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete ALL \(conversations.count) conversation records and notes. This cannot be undone.")
        }
        .alert("Delete All People", isPresented: $showDeleteAllConfirmation) {
            Button("Delete All", role: .destructive) { deleteAllPeople() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete ALL \(people.count) people from both this device and iCloud. This action cannot be undone!")
        }
    }

    // MARK: - Actions

    private func calculateCacheSize() {
        DispatchQueue.global(qos: .utility).async {
            let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            var totalSize: Int64 = 0

            if let cacheURL = cacheURL {
                if let enumerator = FileManager.default.enumerator(at: cacheURL, includingPropertiesForKeys: [.fileSizeKey]) {
                    for case let fileURL as URL in enumerator {
                        if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                            totalSize += Int64(fileSize)
                        }
                    }
                }
            }

            let formatter = ByteCountFormatter()
            formatter.countStyle = .file

            DispatchQueue.main.async {
                cacheSize = formatter.string(fromByteCount: totalSize)
            }
        }
    }

    private func clearCache() {
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first

        if let cacheURL = cacheURL {
            do {
                let contents = try FileManager.default.contentsOfDirectory(at: cacheURL, includingPropertiesForKeys: nil)
                for file in contents {
                    try? FileManager.default.removeItem(at: file)
                }
            } catch {
                print("Failed to clear cache: \(error)")
            }
        }

        calculateCacheSize()
    }

    private func rebuildSearchIndex() {
        // Touch all people to trigger re-indexing
        for person in people {
            person.objectWillChange.send()
        }

        do {
            try viewContext.save()
        } catch {
            print("Failed to rebuild index: \(error)")
        }
    }

    private func resetSpokenTo() {
        for person in people {
            if let convs = person.conversations as? Set<Conversation> {
                for conversation in convs {
                    conversation.date = nil
                }
            }
        }

        do {
            try viewContext.save()
        } catch {
            print("Failed to reset spoken to dates: \(error)")
        }

        dismissedPeopleData = Data()
    }

    private func deleteAllConversations() {
        for conversation in conversations {
            viewContext.delete(conversation)
        }

        do {
            try viewContext.save()
        } catch {
            print("Failed to delete conversations: \(error)")
        }
    }

    private func deleteAllPeople() {
        for person in people {
            viewContext.delete(person)
        }

        do {
            try viewContext.save()
        } catch {
            print("Failed to delete all people: \(error)")
        }
    }
}

#Preview {
    AdvancedSettingsView()
        .frame(width: 600, height: 700)
        .padding()
}

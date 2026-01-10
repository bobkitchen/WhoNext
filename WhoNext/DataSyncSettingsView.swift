import SwiftUI
import CoreData
import CloudKit
import UniformTypeIdentifiers

/// Combined settings view for Calendar, Import/Export, and iCloud Sync
struct DataSyncSettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var selectedSection = "sync"
    @State private var importError: String?
    @State private var importSuccess: String?
    @State private var diagnosticsResult: String?
    @State private var isRunningDiagnostics = false
    @State private var showForceUploadConfirmation = false
    @State private var showAdvancedSyncOptions = false
    @StateObject private var pdfProcessor = OrgChartProcessor()
    @State private var showModelWarning = false
    @State private var pendingFileURL: URL?
    @AppStorage("openrouterModel") private var openrouterModel: String = "google/gemma-2-9b-it:free"
    @ObservedObject private var remindersIntegration = RemindersIntegration.shared

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Person.name, ascending: true)],
        predicate: nil,
        animation: .default
    ) private var people: FetchedResults<Person>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Conversation.date, ascending: false)],
        predicate: nil,
        animation: .default
    ) private var conversations: FetchedResults<Conversation>

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Section selector
            HStack(spacing: 0) {
                SectionButton(title: "iCloud Sync", icon: "icloud", isSelected: selectedSection == "sync") {
                    selectedSection = "sync"
                }
                SectionButton(title: "Calendar", icon: "calendar", isSelected: selectedSection == "calendar") {
                    selectedSection = "calendar"
                }
                SectionButton(title: "Import", icon: "square.and.arrow.down", isSelected: selectedSection == "import") {
                    selectedSection = "import"
                }
                SectionButton(title: "Export", icon: "square.and.arrow.up", isSelected: selectedSection == "export") {
                    selectedSection = "export"
                }
                SectionButton(title: "Reminders", icon: "bell", isSelected: selectedSection == "reminders") {
                    selectedSection = "reminders"
                }
                Spacer()
            }
            .padding(.bottom, 8)

            // Content based on selected section
            switch selectedSection {
            case "sync":
                syncSection
            case "calendar":
                calendarSection
            case "import":
                importSection
            case "export":
                exportSection
            case "reminders":
                remindersSection
            default:
                syncSection
            }
        }
        .alert("Recommended Model for Org Charts", isPresented: $showModelWarning) {
            Button("Switch to GPT-5") {
                openrouterModel = "openai/gpt-5"
                if let fileURL = pendingFileURL {
                    performOrgChartImport(fileURL)
                }
                pendingFileURL = nil
            }
            Button("Continue with \(openrouterModel.components(separatedBy: "/").last ?? openrouterModel)") {
                if let fileURL = pendingFileURL {
                    performOrgChartImport(fileURL)
                }
                pendingFileURL = nil
            }
            Button("Cancel", role: .cancel) {
                pendingFileURL = nil
            }
        } message: {
            Text("For best results with org chart imports, GPT-5 or GPT-5.2 are recommended.\n\nCurrent model: \(openrouterModel)")
        }
        .alert("Force Upload All Data", isPresented: $showForceUploadConfirmation) {
            Button("Upload", role: .destructive) {
                PersistenceController.shared.forceSyncAllExistingData()
                diagnosticsResult = "Force uploading all local data to CloudKit..."
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will re-upload ALL local data to CloudKit. Only use this for initial setup on a new device.\n\nWarning: This can resurrect records that were deleted on other devices.")
        }
    }

    // MARK: - Section Button

    struct SectionButton: View {
        let title: String
        let icon: String
        let isSelected: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                    Text(title)
                        .font(.subheadline)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                )
                .foregroundColor(isSelected ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Sync Section

    private var syncSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // iCloud Status
            VStack(alignment: .leading, spacing: 12) {
                Text("iCloud Sync")
                    .font(.headline)

                HStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(cloudKitStatusColor)
                            .frame(width: 12, height: 12)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(cloudKitStatusText)
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Text("Sync happens automatically via iCloud")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    Button("Refresh Status") {
                        checkCloudKitStatus()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if PersistenceController.iCloudStatus != .available {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                        Text(iCloudTroubleshootingTip)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            // Local Data Summary
            VStack(alignment: .leading, spacing: 8) {
                Text("Local Data")
                    .font(.headline)

                HStack(spacing: 24) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.2.fill")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text("People:")
                            .foregroundColor(.secondary)
                        Text("\(people.count)")
                            .fontWeight(.medium)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text("Conversations:")
                            .foregroundColor(.secondary)
                        Text("\(conversations.count)")
                            .fontWeight(.medium)
                    }
                }
                .font(.subheadline)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            // Advanced Options
            advancedSyncOptions
        }
    }

    private var advancedSyncOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showAdvancedSyncOptions.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: showAdvancedSyncOptions ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .frame(width: 12)
                    Text("Advanced Options")
                        .font(.subheadline)
                    Spacer()
                }
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)

            if showAdvancedSyncOptions {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Use these options only if sync isn't working correctly")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        Button(isRunningDiagnostics ? "Running..." : "Run Diagnostics") {
                            runSyncDiagnostics()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isRunningDiagnostics)

                        Button("Force Upload All") {
                            showForceUploadConfirmation = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if let diagnosticsResult = diagnosticsResult {
                        ScrollView {
                            Text(diagnosticsResult)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 150)
                        .padding(8)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                    }
                }
                .padding(.top, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Calendar Section

    private var calendarSection: some View {
        CalendarProviderSettings()
    }

    // MARK: - Import Section

    private var importSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Org Chart Import
            VStack(alignment: .leading, spacing: 8) {
                Text("Import Org Chart")
                    .font(.headline)
                Text("Drop a file to automatically extract team member details using AI")
                    .font(.caption)
                    .foregroundColor(.secondary)

                OrgChartDropZone(
                    isProcessing: pdfProcessor.isProcessing,
                    processingStatus: pdfProcessor.processingStatus
                ) { fileURL in
                    processOrgChartFile(fileURL)
                }
                .frame(height: 120)

                if let error = pdfProcessor.error {
                    Label(error, systemImage: "xmark.circle.fill")
                        .foregroundColor(.red)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            // CSV Import
            VStack(alignment: .leading, spacing: 8) {
                Text("Import CSV")
                    .font(.headline)
                Text("Import CSV file with columns: Name, Role, Direct Report (true/false), Timezone")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("Select CSV File") {
                    importError = nil
                    importSuccess = nil
                    importCSV()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            // Status Messages
            if let error = importError {
                Label(error, systemImage: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
            }

            if let success = importSuccess {
                Label(success, systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
            }
        }
    }

    // MARK: - Export Section

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Export People
            VStack(alignment: .leading, spacing: 8) {
                Text("Export People")
                    .font(.headline)
                Text("Export all people to a CSV file")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    Button("Export to CSV") {
                        exportPeopleCSV()
                    }
                    .buttonStyle(.bordered)

                    Text("\(people.count) people will be exported")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            // Export Conversations
            VStack(alignment: .leading, spacing: 8) {
                Text("Export Conversations")
                    .font(.headline)
                Text("Export all conversation notes to a text file")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    Button("Export Notes") {
                        exportConversations()
                    }
                    .buttonStyle(.bordered)

                    Text("\(conversations.count) conversations will be exported")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    // MARK: - Reminders Section

    private var remindersSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Authorization Status
            VStack(alignment: .leading, spacing: 12) {
                Text("Apple Reminders")
                    .font(.headline)

                HStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(remindersIntegration.isAuthorized ? Color.green : Color.red)
                            .frame(width: 12, height: 12)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(remindersIntegration.isAuthorized ? "Connected" : "Not Authorized")
                                .font(.subheadline)
                                .fontWeight(.medium)

                            Text("Sync action items with Apple Reminders")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    if !remindersIntegration.isAuthorized {
                        Button("Grant Access") {
                            Task {
                                await remindersIntegration.requestAccess()
                                if remindersIntegration.isAuthorized {
                                    remindersIntegration.fetchAvailableLists()
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                if let error = remindersIntegration.lastError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            // List Selection (only if authorized)
            if remindersIntegration.isAuthorized {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Reminders List")
                        .font(.headline)

                    Text("Choose which list to add action items to")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Picker("Save reminders to:", selection: $remindersIntegration.selectedListID) {
                        Text("Default List").tag("")
                        ForEach(remindersIntegration.availableLists, id: \.calendarIdentifier) { list in
                            Text(list.title).tag(list.calendarIdentifier)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 300)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .onAppear {
                    remindersIntegration.fetchAvailableLists()
                }
            }
        }
    }

    // MARK: - Helper Methods

    private var cloudKitStatusColor: Color {
        switch PersistenceController.iCloudStatus {
        case .available: return .green
        case .noAccount: return .red
        case .restricted, .couldNotDetermine, .temporarilyUnavailable: return .orange
        @unknown default: return .gray
        }
    }

    private var cloudKitStatusText: String {
        switch PersistenceController.iCloudStatus {
        case .available:
            if let lastChange = PersistenceController.lastRemoteChangeDate {
                let formatter = RelativeDateTimeFormatter()
                formatter.unitsStyle = .abbreviated
                return "Connected - Last change \(formatter.localizedString(for: lastChange, relativeTo: Date()))"
            }
            return "Connected"
        case .noAccount: return "Not Connected"
        case .restricted: return "iCloud Restricted"
        case .couldNotDetermine, .temporarilyUnavailable: return "Connection Issue"
        @unknown default: return "Unknown Status"
        }
    }

    private var iCloudTroubleshootingTip: String {
        switch PersistenceController.iCloudStatus {
        case .noAccount: return "Sign in to iCloud in System Settings to enable sync"
        case .restricted: return "iCloud access is restricted. Check parental controls or MDM settings"
        case .couldNotDetermine: return "Could not determine iCloud status. Try restarting the app"
        case .temporarilyUnavailable: return "iCloud is temporarily unavailable. Check your internet connection"
        default: return "Check System Settings for iCloud status"
        }
    }

    private func checkCloudKitStatus() {
        CKContainer.default().accountStatus { status, error in
            Task { @MainActor in
                PersistenceController.iCloudStatus = status
            }
        }
    }

    private func runSyncDiagnostics() {
        guard !isRunningDiagnostics else { return }

        isRunningDiagnostics = true
        diagnosticsResult = "Running diagnostics..."

        Task {
            let results = await SyncDiagnostics.shared.runDiagnostics(context: viewContext)

            await MainActor.run {
                diagnosticsResult = results.joined(separator: "\n")
                isRunningDiagnostics = false
            }
        }
    }

    // MARK: - Import Methods

    private func importCSV() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.commaSeparatedText]
        panel.allowsMultipleSelection = false

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            DispatchQueue.main.async {
                do {
                    let csvContent = try String(contentsOfFile: url.path, encoding: .utf8)
                    processCSVContent(csvContent)
                } catch {
                    importError = error.localizedDescription
                }
            }
        }
    }

    private func processOrgChartFile(_ fileURL: URL) {
        importSuccess = nil
        importError = nil

        let isGPTModel = openrouterModel.contains("gpt-") || openrouterModel.contains("openai/gpt")

        if !isGPTModel {
            pendingFileURL = fileURL
            showModelWarning = true
            return
        }

        performOrgChartImport(fileURL)
    }

    private func performOrgChartImport(_ fileURL: URL) {
        pdfProcessor.processOrgChartFile(fileURL) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let csvContent):
                    processCSVContent(csvContent)
                case .failure(let error):
                    importError = "File processing failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func processCSVContent(_ csvContent: String) {
        let lines = csvContent.components(separatedBy: .newlines)

        guard lines.count > 1 else {
            importError = "No data found in CSV content"
            return
        }

        let fetchRequest = Person.fetchRequest()
        do {
            let existingPeople = try viewContext.fetch(fetchRequest)
            let existingNames = Set(existingPeople.compactMap { ($0 as? Person)?.name?.lowercased() })

            let dataLines = Array(lines.dropFirst()).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

            var importedCount = 0
            var skippedCount = 0

            for line in dataLines {
                let components = parseCSVLine(line)

                guard components.count >= 2 else { continue }

                let name = components[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let role = components[1].trimmingCharacters(in: .whitespacesAndNewlines)

                if existingNames.contains(name.lowercased()) {
                    skippedCount += 1
                    continue
                }

                let person = Person(context: viewContext)
                person.name = name
                person.role = role
                person.isDirectReport = components.count > 2 ? components[2].lowercased() == "true" : false
                person.timezone = components.count > 4 ? components[4] : "UTC"
                importedCount += 1
            }

            try viewContext.save()

            var successMsg = "Imported \(importedCount) team member\(importedCount == 1 ? "" : "s")"
            if skippedCount > 0 {
                successMsg += " (skipped \(skippedCount) duplicate\(skippedCount == 1 ? "" : "s"))"
            }
            importSuccess = successMsg
            importError = nil

        } catch {
            importError = "Failed to import: \(error.localizedDescription)"
        }
    }

    private func parseCSVLine(_ line: String) -> [String] {
        var components = [String]()
        var currentComponent = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                components.append(currentComponent)
                currentComponent = ""
            } else {
                currentComponent.append(char)
            }
        }
        components.append(currentComponent)
        return components
    }

    // MARK: - Export Methods

    private func exportPeopleCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.commaSeparatedText]
        panel.nameFieldStringValue = "people_export.csv"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            var csv = "Name,Role,Direct Report,Timezone\n"

            for person in people {
                let name = person.name ?? ""
                let role = person.role ?? ""
                let directReport = person.isDirectReport ? "true" : "false"
                let timezone = person.timezone ?? ""

                csv += "\"\(name)\",\"\(role)\",\(directReport),\"\(timezone)\"\n"
            }

            do {
                try csv.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                print("Export failed: \(error)")
            }
        }
    }

    private func exportConversations() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.plainText]
        panel.nameFieldStringValue = "conversations_export.txt"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            var text = "CONVERSATION EXPORT\n"
            text += "Generated: \(Date().formatted())\n"
            text += "Total Conversations: \(conversations.count)\n"
            text += String(repeating: "=", count: 50) + "\n\n"

            for conversation in conversations {
                let personName = conversation.person?.name ?? "Unknown"
                let date = conversation.date?.formatted(date: .abbreviated, time: .shortened) ?? "No date"

                text += "CONVERSATION WITH: \(personName)\n"
                text += "Date: \(date)\n"
                if let summary = conversation.summary, !summary.isEmpty {
                    text += "Summary: \(summary)\n"
                }
                if let notes = conversation.notes, !notes.isEmpty {
                    text += "Notes:\n\(notes)\n"
                }
                text += String(repeating: "-", count: 50) + "\n\n"
            }

            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                print("Export failed: \(error)")
            }
        }
    }
}

#Preview {
    DataSyncSettingsView()
        .frame(width: 600, height: 700)
        .padding()
}

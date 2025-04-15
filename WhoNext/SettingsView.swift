import SwiftUI
import CoreData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @AppStorage("openaiApiKey") private var apiKey: String = ""
    @State private var isValidatingKey = false
    @State private var isKeyValid = false
    @State private var keyError: String?
    @State private var importError: String?
    @State private var importSuccess: String?
    @State private var pastedPeopleText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.largeTitle)
                .bold()
            
            // API Key Section
            VStack(alignment: .leading, spacing: 8) {
                Text("OpenAI API Key")
                    .font(.headline)
                HStack {
                    SecureField("sk-...", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                    Button("Validate") {
                        validateApiKey()
                    }
                    .disabled(isValidatingKey)
                }
                if isValidatingKey {
                    Text("Validating...")
                        .foregroundColor(.secondary)
                } else if isKeyValid {
                    Text("✓ Valid API Key")
                        .foregroundColor(.green)
                } else if let error = keyError {
                    Text("✗ \(error)")
                        .foregroundColor(.red)
                }
            }
            
            Divider()
            
            // CSV Import Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Import Team Members")
                    .font(.headline)
                Text("Import CSV file with columns: Name, Role, Direct Report (true/false), Timezone")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 12) {
                    Button("Select CSV File") {
                        importError = nil
                        importSuccess = nil
                        importCSV()
                    }
                    .buttonStyle(.borderedProminent)
                    
                    if let error = importError {
                        Label(error, systemImage: "xmark.circle.fill")
                            .foregroundColor(.red)
                    }
                    
                    if let success = importSuccess {
                        Label(success, systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }
                .padding(.vertical, 8)
            }
            
            Spacer()
        }
        .padding()
    }
    
    private func validateApiKey() {
        guard !apiKey.isEmpty else {
            keyError = "API key cannot be empty"
            isKeyValid = false
            return
        }
        
        isValidatingKey = true
        isKeyValid = false
        keyError = nil
        
        // Simple validation request to OpenAI
        let url = URL(string: "https://api.openai.com/v1/models")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { _, response, error in
            DispatchQueue.main.async {
                isValidatingKey = false
                
                if let error = error {
                    keyError = "Network error: \(error.localizedDescription)"
                    isKeyValid = false
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    switch httpResponse.statusCode {
                    case 200:
                        isKeyValid = true
                        keyError = nil
                    case 401:
                        isKeyValid = false
                        keyError = "Invalid API key"
                    default:
                        isKeyValid = false
                        keyError = "Unexpected error (HTTP \(httpResponse.statusCode))"
                    }
                }
            }
        }.resume()
    }
    
    private func importCSV() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.commaSeparatedText]
        panel.allowsMultipleSelection = false
        
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            
            // Move all Core Data operations to the main thread
            DispatchQueue.main.async {
                do {
                    print("Reading CSV from: \(url)")
                    let csvContent = try String(contentsOfFile: url.path, encoding: .utf8)
                    let rows = csvContent.components(separatedBy: .newlines)
                    
                    guard !rows.isEmpty else {
                        print("CSV file is empty")
                        importError = "CSV file is empty"
                        return
                    }
                    
                    print("Found \(rows.count) rows")
                    
                    // Parse headers
                    let headers = rows[0].components(separatedBy: ",")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    print("Headers: \(headers)")
                    
                    // Find required column indices
                    let nameIndex = headers.firstIndex(of: "name")
                    let roleIndex = headers.firstIndex(of: "role")
                    
                    guard let nameIdx = nameIndex else {
                        print("Name column not found")
                        importError = "Required 'Name' column not found in CSV"
                        return
                    }
                    
                    guard let roleIdx = roleIndex else {
                        print("Role column not found")
                        importError = "Required 'Role' column not found in CSV"
                        return
                    }
                    
                    // Find optional column indices
                    let directReportIndex = headers.firstIndex(of: "direct report")
                    let timezoneIndex = headers.firstIndex(of: "timezone")
                    
                    // Fetch existing people for duplicate checking
                    let fetchRequest = Person.fetchRequest()
                    let existingPeople = try viewContext.fetch(fetchRequest)
                    let existingNames = Set(existingPeople.compactMap { ($0 as? Person)?.name?.lowercased() })
                    
                    var importedCount = 0
                    var skippedCount = 0
                    
                    // Process each line
                    for row in rows.dropFirst() where !row.isEmpty {
                        let columns = row.components(separatedBy: ",")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        
                        guard columns.count >= max(nameIdx, roleIdx) + 1 else {
                            print("Row has missing fields: \(columns)")
                            importError = "Row has missing required fields"
                            return
                        }
                        
                        let name = columns[nameIdx]
                        if existingNames.contains(name.lowercased()) {
                            print("Skipping duplicate: \(name)")
                            skippedCount += 1
                            continue
                        }
                        
                        print("Creating person: \(name)")
                        let newPerson = Person(context: viewContext)
                        newPerson.id = UUID()
                        newPerson.name = name
                        newPerson.role = columns[roleIdx]
                        
                        // Optional fields
                        if let drIdx = directReportIndex, columns.count > drIdx {
                            newPerson.isDirectReport = columns[drIdx].lowercased() == "true"
                        }
                        
                        if let tzIdx = timezoneIndex, columns.count > tzIdx {
                            newPerson.timezone = columns[tzIdx]
                        }
                        
                        importedCount += 1
                    }
                    
                    try viewContext.save()
                    print("Import complete: \(importedCount) imported, \(skippedCount) skipped")
                    
                    importError = nil
                    // Build success message
                    var successMsg = "✓ Imported \(importedCount) team member"
                    if importedCount != 1 { successMsg += "s" }
                    if skippedCount > 0 {
                        successMsg += " (skipped \(skippedCount) duplicate"
                        if skippedCount != 1 { successMsg += "s" }
                        successMsg += ")"
                    }
                    importSuccess = successMsg
                    
                } catch {
                    print("Import failed: \(error)")
                    importError = error.localizedDescription
                    importSuccess = nil
                }
            }
        }
    }
}

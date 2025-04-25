import SwiftUI
import CoreData
import AppKit

struct NewConversationWindow: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Person.name, ascending: true)],
        animation: .default
    ) private var people: FetchedResults<Person>

    @State private var selectedPerson: Person? = nil
    @State private var date: Date = Date()
    @State private var notesAttributedString: NSAttributedString = NSAttributedString(string: "")
    @State private var isEditorFocused: Bool = false
    @State private var showMarkdownImportSheet = false
    @State private var markdownToImport = ""
    @State private var searchText: String = ""
    @Environment(\.dismiss) private var dismissSheet
    @Environment(\.dismissWindow) private var dismissWindow

    private func resetFields() {
        selectedPerson = nil
        date = Date()
        notesAttributedString = NSAttributedString(string: "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Conversation")
                .font(.title2)
                .bold()
            HStack(alignment: .center, spacing: 8) {
                Text("To:")
                    .font(.headline)
                SearchBar(searchText: $searchText) { person in
                    selectedPerson = person
                }
                .frame(height: 28)
                .disabled(selectedPerson != nil)
            }
            .padding(.bottom, 4)
            if let selectedPerson = selectedPerson {
                HStack(spacing: 8) {
                    Text(selectedPerson.name ?? "")
                        .font(.system(size: 13, weight: .medium))
                    if let role = selectedPerson.role {
                        Text(role)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Button(action: {
                        self.selectedPerson = nil
                        self.searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 2)
            }
            DatePicker("Date", selection: $date, displayedComponents: .date)
            Text("Notes:")
                .font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                RichTextToolbar { action in
                    handleRichTextAction(action)
                }
                RichTextEditor(text: $notesAttributedString, isFocused: $isEditorFocused)
                    .frame(minHeight: 150)
                    .padding(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .onTapGesture {
                        isEditorFocused = true
                    }
            }
            HStack {
                Spacer()
                Button("Cancel") {
                    print("Cancel pressed")
                    if let dismissWindow = dismissWindow {
                        print("dismissWindow is available")
                        dismissWindow()
                    } else {
                        print("dismissWindow is nil")
                    }
                    resetFields()
                }
                .keyboardShortcut(.cancelAction)
                Button("Save") {
                    print("Save pressed")
                    saveConversation()
                }
                .disabled(selectedPerson == nil)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 340)
        .onAppear {
            resetFields()
        }
        .sheet(isPresented: $showMarkdownImportSheet) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Paste Markdown to Import")
                    .font(.headline)
                TextEditor(text: $markdownToImport)
                    .frame(height: 120)
                    .padding(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                HStack {
                    Spacer()
                    Button("Import") {
                        notesAttributedString = MarkdownHelper.attributedString(from: markdownToImport)
                        showMarkdownImportSheet = false
                    }
                    Button("Cancel") {
                        showMarkdownImportSheet = false
                    }
                }
            }
            .padding()
            .frame(width: 400)
        }
    }
    
    private func handleRichTextAction(_ action: RichTextEditor.Action) {
        switch action {
        case .bold:
            NSApp.sendAction(Selector(("toggleBoldface:")), to: nil, from: nil)
        case .italic:
            NSApp.sendAction(Selector(("toggleItalics:")), to: nil, from: nil)
        case .underline:
            NSApp.sendAction(Selector(("toggleUnderline:")), to: nil, from: nil)
        case .font:
            // No-op or add custom font logic if needed
            break
        case .size:
            NSApp.sendAction(Selector(("orderFrontFontPanel:")), to: nil, from: nil)
        case .markdownImport:
            showMarkdownImportSheet = true
        case .markdownExport:
            let markdown = MarkdownHelper.markdownString(from: notesAttributedString)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(markdown, forType: .string)
        }
    }

    private func saveConversation() {
        guard let person = selectedPerson else { return }
        let newConversation = Conversation(context: viewContext)
        newConversation.date = date
        newConversation.notesRTF = try? notesAttributedString.data(from: NSRange(location: 0, length: notesAttributedString.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        newConversation.person = person
        newConversation.uuid = UUID()
        do {
            try viewContext.save()
            print("Save: dismissWindow called")
            if let dismissWindow = dismissWindow {
                print("dismissWindow is available")
                dismissWindow()
            } else {
                print("dismissWindow is nil")
            }
        } catch {
            print("Failed to save conversation: \(error)")
        }
    }
}

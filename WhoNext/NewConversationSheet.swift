//
//  NewConversationSheet.swift
//  WhoNext
//
//  Created by Bob Kitchen on 3/29/25.
//


import SwiftUI
import CoreData

struct NewConversationSheet: View {
    let person: Person
    let context: NSManagedObjectContext

    @Binding var date: Date
    @Binding var notes: String
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Conversation")
                .font(.title2)
                .bold()

            DatePicker("Date", selection: $date, displayedComponents: .date)

            Text("Notes:")
                .font(.headline)

            TextEditor(text: $notes)
                .frame(minHeight: 150)
                .padding(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )

            HStack {
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    saveConversation()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300)
    }

    private func saveConversation() {
        let newConversation = Conversation(context: context)
        newConversation.date = date
        newConversation.notes = notes
        newConversation.person = person

        do {
            try context.save()
            isPresented = false
            notes = ""
            date = Date()
        } catch {
            print("Error saving conversation: \(error.localizedDescription)")
        }
    }
}
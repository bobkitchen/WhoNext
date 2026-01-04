import SwiftUI
import AppKit

struct PersonCard: View {
    let person: Person
    let isFollowUp: Bool  // Determines if this is a follow-up card or upcoming meeting card
    @State private var isHovered = false
    var onDismiss: (() -> Void)?  // Optional dismiss action for follow-up cards

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Profile section
            HStack(spacing: 12) {
                PersonAvatar(
                    initials: person.initials,
                    size: 48,
                    showOnlineIndicator: false,
                    photoData: person.photo
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(person.name ?? "Unknown")
                        .font(.system(size: 16, weight: .semibold))
                    if let role = person.role {
                        Text(role)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }

                if isFollowUp {
                    Spacer()

                    // Email button
                    Button(action: {
                        scheduleMeeting()
                    }) {
                        Image(systemName: "envelope.fill")
                            .foregroundStyle(.blue)
                            .imageScale(.medium)
                    }
                    .buttonStyle(.plain)
                    .help("Send email to schedule meeting")

                    // Dismiss button
                    Button(action: {
                        onDismiss?()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .imageScale(.large)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Last contact or scheduled meeting info
            if isFollowUp {
                VStack(alignment: .leading, spacing: 4) {
                    if let lastContact = person.lastContactDate {
                        // Calculate days since last contact
                        let daysSince = Calendar.current.dateComponents([.day], from: lastContact, to: Date()).day ?? 0

                        HStack(spacing: 8) {
                            Image(systemName: urgencyIcon(for: daysSince))
                                .font(.system(size: 14))
                                .foregroundStyle(urgencyColor(for: daysSince))

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Last contact")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)

                                HStack(spacing: 4) {
                                    Text(lastContact.formatted(.relative(presentation: .named)))
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.primary)

                                    Text("•")
                                        .foregroundStyle(.secondary)

                                    Text(lastContact.formatted(date: .abbreviated, time: .omitted))
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()
                        }
                        .padding(10)
                        .background(urgencyColor(for: daysSince).opacity(0.08))
                        .cornerRadius(10)
                    } else {
                        // No contact date
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.orange)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("No previous contact")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.primary)

                                Text("First time reaching out")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                        .padding(10)
                        .background(Color.orange.opacity(0.08))
                        .cornerRadius(10)
                    }
                }
            } else if let scheduled = person.scheduledConversationDate {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .foregroundStyle(.blue)
                    Text(scheduled.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 13))
                }
                .padding(8)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(16)
        .shadow(color: .black.opacity(isHovered ? 0.1 : 0.05), radius: isHovered ? 12 : 8, x: 0, y: isHovered ? 4 : 2)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }

    // MARK: - Email Scheduling Functions

    private func scheduleMeeting() {
        // Get templates from UserDefaults
        let subjectTemplate = UserDefaults.standard.string(forKey: "emailSubjectTemplate") ?? "1:1 - {name} + BK"
        let bodyTemplate = UserDefaults.standard.string(forKey: "emailBodyTemplate") ?? """
        Hi {firstName},

        I wanted to follow up on our conversation and see how things are going.

        Would you have time for a quick chat this week?

        Best regards
        """

        // Replace placeholders
        let firstName = person.name?.components(separatedBy: " ").first ?? "there"
        let fullName = person.name ?? "Meeting"

        let subject = subjectTemplate
            .replacingOccurrences(of: "{name}", with: fullName)
            .replacingOccurrences(of: "{firstName}", with: firstName)

        let body = bodyTemplate
            .replacingOccurrences(of: "{name}", with: fullName)
            .replacingOccurrences(of: "{firstName}", with: firstName)

        // Get email address
        let email = inferEmailFromName(person)

        // Create email using mailto
        openEmailInOutlook(to: email, subject: subject, body: body)
    }

    private func openEmailInOutlook(to: String, subject: String, body: String) {
        // URL encode the components
        guard let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let encodedTo = to.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            print("Failed to encode email parameters")
            return
        }

        let mailtoString = "mailto:\(encodedTo)?subject=\(encodedSubject)&body=\(encodedBody)"

        if let url = URL(string: mailtoString) {
            NSWorkspace.shared.open(url)
            print("✅ Email opened in default mail client for \(person.name ?? "person")")
        }
    }

    private func inferEmailFromName(_ person: Person) -> String {
        // Simple email inference if not stored
        let nameParts = person.name?.components(separatedBy: " ") ?? []
        let firstName = nameParts.first?.lowercased() ?? "unknown"
        let lastName = nameParts.count > 1 ? nameParts[1].lowercased() : ""
        // Using organization domain
        return "\(firstName).\(lastName)@rescue.org"
    }

    // MARK: - Visual Urgency Indicators

    private func urgencyColor(for daysSince: Int) -> Color {
        switch daysSince {
        case 0...7:
            return .green  // Recent contact (within a week)
        case 8...14:
            return .blue   // Moderate (1-2 weeks)
        case 15...30:
            return .orange // Getting old (2-4 weeks)
        default:
            return .red    // Urgent (over a month)
        }
    }

    private func urgencyIcon(for daysSince: Int) -> String {
        switch daysSince {
        case 0...7:
            return "checkmark.circle.fill"  // Recent - all good
        case 8...14:
            return "clock.fill"              // Moderate - time passing
        case 15...30:
            return "exclamationmark.triangle.fill"  // Getting urgent
        default:
            return "exclamationmark.circle.fill"    // Very urgent
        }
    }
}

// Preview provider for development
struct PersonCard_Previews: PreviewProvider {
    static var previews: some View {
        PersonCard(person: Person(), isFollowUp: true)
            .frame(width: 300)
            .padding()
    }
} 

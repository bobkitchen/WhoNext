import SwiftUI
import CoreData

struct LowHealthScoreDetailView: View {
    let lowHealthRelationships: [PersonMetrics]
    @Environment(\.managedObjectContext) private var viewContext
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Low Health Score Alert")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("\(lowHealthRelationships.count) relationships need attention")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal)
            
            Divider()
            
            // Relationships List
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(lowHealthRelationships, id: \.person.objectID) { personMetrics in
                        LowHealthRelationshipRow(personMetrics: personMetrics)
                    }
                }
                .padding(.horizontal)
            }
            
            Spacer()
        }
        .padding(.top)
        .frame(minWidth: 600, minHeight: 500)
    }
}

struct LowHealthRelationshipRow: View {
    let personMetrics: PersonMetrics
    @Environment(\.managedObjectContext) private var viewContext
    @State private var windowController: NSWindowController?

    private func openPersonDetailWindow(for personMetrics: PersonMetrics) {
        DispatchQueue.main.async {
            // Get the person's objectID to ensure we can fetch it in the new context
            let personObjectID = personMetrics.person.objectID
            
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = personMetrics.person.name ?? "Person Detail"
            window.center()
            
            // Use the shared view context
            let sharedContext = PersistenceController.shared.container.viewContext
            
            // Fetch the person in the shared context
            if let person = try? sharedContext.existingObject(with: personObjectID) as? Person {
                let hostingView = NSHostingView(
                    rootView: PersonDetailView(person: person)
                        .environment(\.managedObjectContext, sharedContext)
                )
                window.contentView = hostingView
                
                // Create window controller to manage lifecycle
                let controller = NSWindowController(window: window)
                controller.showWindow(nil)
                
                // Store reference to keep window alive
                self.windowController = controller
                
                // Activate app to ensure window focus
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Avatar
            if let photoData = personMetrics.person.photo, let nsImage = NSImage(data: photoData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Text(String(personMetrics.person.name?.prefix(1) ?? "?"))
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundColor(.accentColor)
                    )
            }
            
            // Person Info
            VStack(alignment: .leading, spacing: 4) {
                Text(personMetrics.person.name ?? "Unknown")
                    .font(.headline)
                    .fontWeight(.medium)
                
                if let role = personMetrics.person.role, !role.isEmpty {
                    Text(role)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                        Text(String(format: "%.1f", personMetrics.healthScore))
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    
                    if let lastDate = personMetrics.lastConversationDate {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .foregroundColor(.secondary)
                                .font(.caption)
                            Text(lastDate, style: .relative)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            Spacer()
            
            // Action Button
            Button(action: {
                openPersonDetailWindow(for: personMetrics)
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle")
                    Text("View Details")
                }
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct LowHealthScoreDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let context = PersistenceController.preview.container.viewContext
        let person = Person(context: context)
        person.name = "John Doe"
        person.role = "Software Engineer"
        
        let conversationMetrics = ConversationMetrics(
            averageDuration: 45.0,
            totalDuration: 225.0,
            conversationCount: 5,
            averageSentimentPerMinute: 0.7,
            optimalDurationRange: 30...60
        )
        
        let metrics = PersonMetrics(
            person: person,
            metrics: conversationMetrics,
            healthScore: 0.3,
            trendDirection: "declining",
            lastConversationDate: Calendar.current.date(byAdding: .day, value: -10, to: Date()),
            daysSinceLastConversation: 10,
            relationshipType: .directReport,
            isOverdue: false,
            contextualInsights: ["Low health score indicates declining relationship quality"]
        )
        
        return LowHealthScoreDetailView(lowHealthRelationships: [metrics])
            .environment(\.managedObjectContext, context)
    }
}

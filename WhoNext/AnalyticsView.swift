import SwiftUI
import CoreData

struct AnalyticsView: View {
    @FetchRequest(
        entity: Person.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Person.name, ascending: true)]
    ) var people: FetchedResults<Person>
    
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 40) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "chart.bar.fill")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                        Text("Analytics")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                    }
                    Text("Insights into your conversation patterns and team engagement")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 32)
                .padding(.top, 24)
                
                // Timeline Section
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Image(systemName: "timeline.selection")
                            .font(.title3)
                            .foregroundColor(.blue)
                        Text("Activity Timeline")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Spacer()
                        
                        Text("Recent conversations and meetings")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 32)
                    
                    TimelineView(people: Array(people)) { person in
                        // Navigate to the person in People tab
                        appState.selectedTab = .people
                        appState.selectedPerson = person
                        appState.selectedPersonID = person.identifier
                    }
                    .padding(.horizontal, 32)
                }
                
                // Heat Map Section
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Image(systemName: "grid.circle.fill")
                            .font(.title3)
                            .foregroundColor(.green)
                        Text("Activity Heat Map")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Spacer()
                        
                        Text("Conversation patterns over the last 12 weeks")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 32)
                    
                    ActivityHeatMapView(people: Array(people))
                        .padding(.horizontal, 32)
                }
                
                // Coming Soon Section
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Image(systemName: "sparkles")
                            .font(.title3)
                            .foregroundColor(.purple)
                        Text("Coming Soon")
                            .font(.title2)
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 32)
                    
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .frame(height: 140)
                        .overlay(
                            VStack(spacing: 16) {
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                    .font(.system(size: 36))
                                    .foregroundColor(.purple)
                                
                                Text("More Analytics Coming")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                
                                Text("Team engagement trends, conversation quality metrics, and personalized insights")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 24)
                            }
                        )
                        .padding(.horizontal, 32)
                }
                
                Spacer(minLength: 40)
            }
        }
    }
}

// Preview
struct AnalyticsView_Previews: PreviewProvider {
    static var previews: some View {
        AnalyticsView()
    }
}

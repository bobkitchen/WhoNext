import SwiftUI
import CoreData

struct AnalyticsView: View {
    @EnvironmentObject var appState: AppState
    @FetchRequest(
        entity: Person.entity(),
        sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)]
    ) var people: FetchedResults<Person>
    
    @State private var selectedTimeframe: TimelineView.TimeFrame = .week
    
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
                            .padding(.trailing, 16)
                        
                        Picker("", selection: $selectedTimeframe) {
                            Text("Week").tag(TimelineView.TimeFrame.week)
                            Text("Month").tag(TimelineView.TimeFrame.month)
                            Text("Quarter").tag(TimelineView.TimeFrame.quarter)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                        .labelsHidden()
                    }
                    .padding(.horizontal, 32)
                    
                    // Timeline with safer implementation
                    TimelineView(people: Array(people), timeframe: selectedTimeframe) { person in
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

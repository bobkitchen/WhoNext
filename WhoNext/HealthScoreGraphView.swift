import SwiftUI
import Charts

struct HealthScoreGraphView: View {
    let healthScoreData: [HealthScoreDataPoint]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Average Health Score Trend")
                .font(.headline)
                .fontWeight(.semibold)
            
            if healthScoreData.isEmpty {
                Text("No health score data available")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(height: 200)
            } else {
                Chart(healthScoreData) { dataPoint in
                    // Area fill under the line
                    AreaMark(
                        x: .value("Week", dataPoint.weekStart),
                        y: .value("Health Score", dataPoint.averageScore)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            gradient: Gradient(colors: [.blue.opacity(0.3), .blue.opacity(0.1)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    
                    // Line mark
                    LineMark(
                        x: .value("Week", dataPoint.weekStart),
                        y: .value("Health Score", dataPoint.averageScore)
                    )
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 3))
                    
                    // Point marks
                    PointMark(
                        x: .value("Week", dataPoint.weekStart),
                        y: .value("Health Score", dataPoint.averageScore)
                    )
                    .foregroundStyle(.blue)
                    .symbolSize(40)
                }
                .frame(height: 200)
                .chartYScale(domain: 0...1)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel()
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel()
                    }
                }
                .chartXAxisLabel("Week Number (Calendar Year)", position: .bottom, alignment: .center)
                .chartYAxisLabel("Health Score", position: .leading, alignment: .center)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct HealthScoreDataPoint: Identifiable {
    let id = UUID()
    let weekStart: Date
    let averageScore: Double
    let relationshipCount: Int
}

struct HealthScoreGraphView_Previews: PreviewProvider {
    static var previews: some View {
        let sampleData = [
            HealthScoreDataPoint(weekStart: Calendar.current.date(byAdding: .weekOfYear, value: -24, to: Date()) ?? Date(), averageScore: 0.8, relationshipCount: 10),
            HealthScoreDataPoint(weekStart: Calendar.current.date(byAdding: .weekOfYear, value: -23, to: Date()) ?? Date(), averageScore: 0.7, relationshipCount: 12),
            HealthScoreDataPoint(weekStart: Calendar.current.date(byAdding: .weekOfYear, value: -22, to: Date()) ?? Date(), averageScore: 0.6, relationshipCount: 11),
            HealthScoreDataPoint(weekStart: Calendar.current.date(byAdding: .weekOfYear, value: -21, to: Date()) ?? Date(), averageScore: 0.65, relationshipCount: 13),
            HealthScoreDataPoint(weekStart: Calendar.current.date(byAdding: .weekOfYear, value: -20, to: Date()) ?? Date(), averageScore: 0.72, relationshipCount: 14),
            HealthScoreDataPoint(weekStart: Calendar.current.date(byAdding: .weekOfYear, value: -19, to: Date()) ?? Date(), averageScore: 0.75, relationshipCount: 15),
            HealthScoreDataPoint(weekStart: Calendar.current.date(byAdding: .weekOfYear, value: -18, to: Date()) ?? Date(), averageScore: 0.78, relationshipCount: 16),
            HealthScoreDataPoint(weekStart: Calendar.current.date(byAdding: .weekOfYear, value: -17, to: Date()) ?? Date(), averageScore: 0.81, relationshipCount: 17),
            HealthScoreDataPoint(weekStart: Calendar.current.date(byAdding: .weekOfYear, value: -16, to: Date()) ?? Date(), averageScore: 0.84, relationshipCount: 18),
            HealthScoreDataPoint(weekStart: Calendar.current.date(byAdding: .weekOfYear, value: -15, to: Date()) ?? Date(), averageScore: 0.87, relationshipCount: 19),
            HealthScoreDataPoint(weekStart: Calendar.current.date(byAdding: .weekOfYear, value: -14, to: Date()) ?? Date(), averageScore: 0.9, relationshipCount: 20),
            HealthScoreDataPoint(weekStart: Calendar.current.date(byAdding: .weekOfYear, value: -13, to: Date()) ?? Date(), averageScore: 0.93, relationshipCount: 21),
            HealthScoreDataPoint(weekStart: Calendar.current.date(byAdding: .weekOfYear, value: -12, to: Date()) ?? Date(), averageScore: 0.96, relationshipCount: 22),
            HealthScoreDataPoint(weekStart: Calendar.current.date(byAdding: .weekOfYear, value: -11, to: Date()) ?? Date(), averageScore: 0.99, relationshipCount: 23),
            HealthScoreDataPoint(weekStart: Calendar.current.date(byAdding: .weekOfYear, value: -10, to: Date()) ?? Date(), averageScore: 1, relationshipCount: 24),
            HealthScoreDataPoint(weekStart: Calendar.current.date(byAdding: .weekOfYear, value: -9, to: Date()) ?? Date(), averageScore: 0.98, relationshipCount: 25),
            HealthScoreDataPoint(weekStart: Calendar.current.date(byAdding: .weekOfYear, value: -8, to: Date()) ?? Date(), averageScore: 0.95, relationshipCount: 26),
            HealthScoreDataPoint(weekStart: Calendar.current.date(byAdding: .weekOfYear, value: -7, to: Date()) ?? Date(), averageScore: 0.92, relationshipCount: 27),
            HealthScoreDataPoint(weekStart: Calendar.current.date(byAdding: .weekOfYear, value: -6, to: Date()) ?? Date(), averageScore: 0.89, relationshipCount: 28),
            HealthScoreDataPoint(weekStart: Calendar.current.date(byAdding: .weekOfYear, value: -5, to: Date()) ?? Date(), averageScore: 0.86, relationshipCount: 29),
            HealthScoreDataPoint(weekStart: Calendar.current.date(byAdding: .weekOfYear, value: -4, to: Date()) ?? Date(), averageScore: 0.83, relationshipCount: 30),
            HealthScoreDataPoint(weekStart: Calendar.current.date(byAdding: .weekOfYear, value: -3, to: Date()) ?? Date(), averageScore: 0.8, relationshipCount: 31),
            HealthScoreDataPoint(weekStart: Calendar.current.date(byAdding: .weekOfYear, value: -2, to: Date()) ?? Date(), averageScore: 0.77, relationshipCount: 32),
            HealthScoreDataPoint(weekStart: Calendar.current.date(byAdding: .weekOfYear, value: -1, to: Date()) ?? Date(), averageScore: 0.74, relationshipCount: 33),
            HealthScoreDataPoint(weekStart: Date(), averageScore: 0.72, relationshipCount: 34)
        ]
        
        return HealthScoreGraphView(healthScoreData: sampleData)
            .frame(width: 400)
    }
}

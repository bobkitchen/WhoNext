import SwiftUI
import EventKit

struct CalendarProviderSettings: View {
    @ObservedObject private var calendarService = CalendarService.shared
    @State private var isLoadingCalendars = false
    @State private var showingGoogleSignIn = false
    @State private var errorMessage: String?
    @State private var showingError = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Provider Selection
            providerSelector
            
            Divider()
            
            // Provider-specific content
            if calendarService.currentProvider == .apple {
                appleCalendarSettings
            } else {
                googleCalendarSettings
            }
            
            // Calendar Selection (if authorized)
            if calendarService.isAuthorized && !calendarService.availableCalendars.isEmpty {
                Divider()
                calendarPicker
            }
        }
        .alert("Calendar Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
        .onAppear {
            loadCalendarsIfNeeded()
        }
    }
    
    // MARK: - Provider Selector
    
    private var providerSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Calendar Provider")
                .font(.headline)
            
            Picker("", selection: Binding(
                get: { calendarService.currentProvider },
                set: { newProvider in
                    Task {
                        do {
                            try await calendarService.switchProvider(to: newProvider)
                            loadCalendarsIfNeeded()
                        } catch {
                            errorMessage = error.localizedDescription
                            showingError = true
                        }
                    }
                }
            )) {
                ForEach(CalendarProviderType.allCases, id: \.self) { provider in
                    HStack {
                        Image(systemName: provider.icon)
                        Text(provider.rawValue)
                    }
                    .tag(provider)
                }
            }
            .pickerStyle(.segmented)
            
            Text(calendarService.currentProvider.description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Apple Calendar Settings
    
    private var appleCalendarSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(calendarService.isAuthorized ? .green : .orange)
                
                Text(calendarService.isAuthorized ? 
                     "Calendar access granted" : 
                     "Calendar access required")
                    .font(.subheadline)
            }
            
            if !calendarService.isAuthorized {
                Button("Grant Calendar Access") {
                    requestCalendarAccess()
                }
                .buttonStyle(.bordered)
                
                Text("WhoNext needs access to your calendar to display upcoming meetings.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Google Calendar Settings
    
    private var googleCalendarSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            if calendarService.isAuthorized {
                // Signed in state
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    
                    VStack(alignment: .leading) {
                        Text("Connected to Google Calendar")
                            .font(.subheadline)
                        // TODO: Show connected account email
                        Text("your.email@gmail.com")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Sign Out") {
                        Task {
                            do {
                                try await calendarService.signOutGoogle()
                            } catch {
                                errorMessage = error.localizedDescription
                                showingError = true
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                // Not signed in state
                VStack(alignment: .leading, spacing: 12) {
                    Text("Connect your Google Calendar to see your meetings")
                        .font(.subheadline)
                    
                    Button(action: {
                        showingGoogleSignIn = true
                        requestGoogleCalendarAccess()
                    }) {
                        HStack {
                            Image(systemName: "globe")
                            Text("Sign in with Google")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Text("You'll be redirected to Google to authorize access to your calendar.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    // MARK: - Calendar Picker
    
    private var calendarPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Active Calendar")
                .font(.headline)
            
            if isLoadingCalendars {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading calendars...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Picker("", selection: Binding(
                    get: { calendarService.selectedCalendarID ?? "" },
                    set: { calendarID in
                        if !calendarID.isEmpty {
                            Task {
                                do {
                                    try await calendarService.setActiveCalendar(calendarID)
                                } catch {
                                    errorMessage = error.localizedDescription
                                    showingError = true
                                }
                            }
                        }
                    }
                )) {
                    Text("All Calendars").tag("")
                    
                    ForEach(calendarService.availableCalendars) { calendar in
                        HStack {
                            if let colorHex = calendar.color {
                                Circle()
                                    .fill(Color(hex: colorHex))
                                    .frame(width: 10, height: 10)
                            }
                            
                            VStack(alignment: .leading) {
                                Text(calendar.title)
                                if let account = calendar.accountName {
                                    Text(account)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .tag(calendar.id)
                    }
                }
                .pickerStyle(.menu)
                
                if let selectedID = calendarService.selectedCalendarID,
                   let calendar = calendarService.availableCalendars.first(where: { $0.id == selectedID }) {
                    Text("Events will be fetched from: \(calendar.title)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func requestCalendarAccess() {
        calendarService.requestAccess { granted, error in
            if !granted {
                errorMessage = error?.localizedDescription ?? "Calendar access was denied"
                showingError = true
            } else {
                loadCalendarsIfNeeded()
            }
        }
    }
    
    private func requestGoogleCalendarAccess() {
        // This will trigger the OAuth flow when Google dependencies are added
        calendarService.requestAccess { granted, error in
            showingGoogleSignIn = false
            if !granted {
                errorMessage = error?.localizedDescription ?? "Google Calendar authorization failed"
                showingError = true
            } else {
                loadCalendarsIfNeeded()
            }
        }
    }
    
    private func loadCalendarsIfNeeded() {
        guard calendarService.isAuthorized else { return }
        
        isLoadingCalendars = true
        Task {
            do {
                try await calendarService.fetchAvailableCalendars()
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
            await MainActor.run {
                isLoadingCalendars = false
            }
        }
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

#Preview {
    CalendarProviderSettings()
        .padding()
        .frame(width: 600)
}
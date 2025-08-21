import SwiftUI
import EventKit

struct CalendarProviderSettings: View {
    @ObservedObject private var calendarService = CalendarService.shared
    @State private var isLoadingCalendars = false
    @State private var showingGoogleSignIn = false
    @State private var errorMessage: String?
    @State private var showingError = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Calendar Provider")
                .font(.headline)
            
            // Two separate sections for each provider
            VStack(spacing: 16) {
                // Apple Calendar Section
                appleCalendarSection
                
                // Google Calendar Section
                googleCalendarSection
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
    
    // MARK: - Apple Calendar Section
    
    private var appleCalendarSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: {
                if calendarService.currentProvider != .apple {
                    Task {
                        do {
                            try await calendarService.switchProvider(to: .apple)
                            loadCalendarsIfNeeded()
                        } catch {
                            errorMessage = error.localizedDescription
                            showingError = true
                        }
                    }
                } else if !calendarService.isAuthorized {
                    requestCalendarAccess()
                }
            }) {
                HStack {
                    Image(systemName: "applelogo")
                        .font(.title2)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Apple Calendar")
                            .font(.body)
                            .fontWeight(.medium)
                        
                        if calendarService.currentProvider == .apple {
                            Text(calendarService.isAuthorized ? "Connected" : "Tap to connect")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Use system calendar")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    if calendarService.currentProvider == .apple {
                        Image(systemName: calendarService.isAuthorized ? "checkmark.circle.fill" : "exclamationmark.circle")
                            .foregroundColor(calendarService.isAuthorized ? .green : .orange)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(calendarService.currentProvider == .apple ? Color.accentColor.opacity(0.1) : Color.gray.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(calendarService.currentProvider == .apple ? Color.accentColor : Color.clear, lineWidth: 2)
                        )
                )
            }
            .buttonStyle(.plain)
            
            if calendarService.currentProvider == .apple && !calendarService.isAuthorized {
                Text("WhoNext needs access to your calendar to display upcoming meetings.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 4)
            }
        }
    }
    
    // MARK: - Google Calendar Section
    
    private var googleCalendarSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: {
                if calendarService.currentProvider != .google {
                    Task {
                        do {
                            try await calendarService.switchProvider(to: .google)
                            loadCalendarsIfNeeded()
                        } catch {
                            errorMessage = error.localizedDescription
                            showingError = true
                        }
                    }
                } else if !calendarService.isAuthorized {
                    showingGoogleSignIn = true
                    requestGoogleCalendarAccess()
                }
            }) {
                HStack {
                    Image(systemName: "globe")
                        .font(.title2)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Google Calendar")
                            .font(.body)
                            .fontWeight(.medium)
                        
                        if calendarService.currentProvider == .google {
                            if calendarService.isAuthorized {
                                // TODO: Show actual email when OAuth is implemented
                                Text("Connected")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("Tap to sign in")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Text("Connect with Google")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    if calendarService.currentProvider == .google {
                        if calendarService.isAuthorized {
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
                        } else {
                            Image(systemName: "arrow.right.circle")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(calendarService.currentProvider == .google ? Color.accentColor.opacity(0.1) : Color.gray.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(calendarService.currentProvider == .google ? Color.accentColor : Color.clear, lineWidth: 2)
                        )
                )
            }
            .buttonStyle(.plain)
            
            if calendarService.currentProvider == .google && !calendarService.isAuthorized {
                Text("You'll be redirected to Google to authorize access to your calendar.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 4)
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
                if let error = error {
                    errorMessage = """
                    Google Calendar integration is coming soon. This feature requires additional configuration including Google API setup and OAuth credentials.
                    """
                } else {
                    errorMessage = "Unable to connect to Google Calendar. Please try again."
                }
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
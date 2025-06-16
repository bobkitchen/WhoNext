import Foundation
import SwiftUI

class ErrorManager: ObservableObject {
    @MainActor static let shared = ErrorManager()
    // MARK: - Published Properties
    @Published var currentError: AppError?
    @Published var isShowingError = false
    @Published var errorHistory: [ErrorLogEntry] = []
    
    // MARK: - Error Handling
    func handle(_ error: Error, context: String = "") {
        let appError = AppError.from(error, context: context)
        currentError = appError
        isShowingError = true
        
        // Log error for debugging
        logError(appError, context: context)
        
        // Print to console in debug builds
        #if DEBUG
        print("🚨 Error in \(context): \(appError.localizedDescription)")
        if let underlyingError = appError.underlyingError {
            print("   Underlying: \(underlyingError.localizedDescription)")
        }
        #endif
    }
    
    func handle(_ appError: AppError, context: String = "") {
        currentError = appError
        isShowingError = true
        logError(appError, context: context)
        
        #if DEBUG
        print("🚨 Error in \(context): \(appError.localizedDescription)")
        #endif
    }
    
    func clearError() {
        currentError = nil
        isShowingError = false
    }
    
    func dismissError() {
        isShowingError = false
        // Keep currentError for potential retry actions
    }
    
    // MARK: - Error Logging
    private func logError(_ error: AppError, context: String) {
        let entry = ErrorLogEntry(
            error: error,
            context: context,
            timestamp: Date()
        )
        
        errorHistory.append(entry)
        
        // Keep only last 50 errors to prevent memory issues
        if errorHistory.count > 50 {
            errorHistory.removeFirst(errorHistory.count - 50)
        }
    }
    
    // MARK: - Retry Logic
    func retry(action: @escaping () async throws -> Void) async {
        do {
            try await action()
            clearError()
        } catch {
            handle(error, context: "Retry attempt")
        }
    }
    
    // MARK: - Error Analytics
    var recentErrorCount: Int {
        let oneHourAgo = Date().addingTimeInterval(-3600)
        return errorHistory.filter { $0.timestamp > oneHourAgo }.count
    }
    
    var mostCommonErrorType: AppError.ErrorType? {
        let types = errorHistory.map { $0.error.type }
        let counts = Dictionary(grouping: types, by: { $0 })
        return counts.max(by: { $0.value.count < $1.value.count })?.key
    }
}

// MARK: - AppError Definition
enum AppError: LocalizedError {
    case networkError(Error)
    case syncError(String, Error?)
    case validationError(String)
    case coreDataError(Error)
    case fileSystemError(String, Error?)
    case calendarError(String, Error?)
    case aiServiceError(String, Error?)
    case authenticationError(String)
    case unknownError(Error)
    
    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network connection failed: \(error.localizedDescription)"
        case .syncError(let message, let error):
            return "Sync failed: \(message)" + (error != nil ? " (\(error!.localizedDescription))" : "")
        case .validationError(let message):
            return "Validation failed: \(message)"
        case .coreDataError(let error):
            return "Database error: \(error.localizedDescription)"
        case .fileSystemError(let message, let error):
            return "File system error: \(message)" + (error != nil ? " (\(error!.localizedDescription))" : "")
        case .calendarError(let message, let error):
            return "Calendar error: \(message)" + (error != nil ? " (\(error!.localizedDescription))" : "")
        case .aiServiceError(let message, let error):
            return "AI service error: \(message)" + (error != nil ? " (\(error!.localizedDescription))" : "")
        case .authenticationError(let message):
            return "Authentication error: \(message)"
        case .unknownError(let error):
            return "Unexpected error: \(error.localizedDescription)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .networkError:
            return "Check your internet connection and try again."
        case .syncError:
            return "Check your connection and sync settings."
        case .validationError:
            return "Please correct the highlighted fields and try again."
        case .coreDataError:
            return "Try restarting the app. If the problem persists, contact support."
        case .fileSystemError:
            return "Check file permissions and available storage space."
        case .calendarError:
            return "Check calendar permissions in System Settings."
        case .aiServiceError:
            return "Check your API keys and service status."
        case .authenticationError:
            return "Please sign in again."
        case .unknownError:
            return "Try restarting the app."
        }
    }
    
    var type: ErrorType {
        switch self {
        case .networkError: return .network
        case .syncError: return .sync
        case .validationError: return .validation
        case .coreDataError: return .database
        case .fileSystemError: return .fileSystem
        case .calendarError: return .calendar
        case .aiServiceError: return .aiService
        case .authenticationError: return .authentication
        case .unknownError: return .unknown
        }
    }
    
    var underlyingError: Error? {
        switch self {
        case .networkError(let error): return error
        case .syncError(_, let error): return error
        case .coreDataError(let error): return error
        case .fileSystemError(_, let error): return error
        case .calendarError(_, let error): return error
        case .aiServiceError(_, let error): return error
        case .unknownError(let error): return error
        default: return nil
        }
    }
    
    static func from(_ error: Error, context: String = "") -> AppError {
        // Try to map common error types
        if let urlError = error as? URLError {
            return .networkError(urlError)
        } else if error.localizedDescription.contains("Core Data") {
            return .coreDataError(error)
        } else if context.contains("sync") || context.contains("Supabase") {
            return .syncError(context, error)
        } else if context.contains("calendar") {
            return .calendarError(context, error)
        } else if context.contains("AI") || context.contains("OpenAI") || context.contains("Claude") {
            return .aiServiceError(context, error)
        } else {
            return .unknownError(error)
        }
    }
    
    enum ErrorType: String, CaseIterable {
        case network, sync, validation, database, fileSystem, calendar, aiService, authentication, unknown
    }
}

// MARK: - Error Log Entry
struct ErrorLogEntry: Identifiable {
    let id = UUID()
    let error: AppError
    let context: String
    let timestamp: Date
}

// MARK: - SwiftUI Integration
extension View {
    func errorAlert(_ errorManager: ErrorManager) -> some View {
        self.alert(
            "Error",
            isPresented: .constant(errorManager.isShowingError && errorManager.currentError != nil),
            presenting: errorManager.currentError
        ) { error in
            Button("OK") {
                errorManager.clearError()
            }
            
            if error.recoverySuggestion != nil {
                Button("Retry") {
                    // This would need to be customized per use case
                    errorManager.dismissError()
                }
            }
        } message: { error in
            VStack(alignment: .leading, spacing: 8) {
                if let description = error.errorDescription {
                    Text(description)
                }
                if let suggestion = error.recoverySuggestion {
                    Text(suggestion)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
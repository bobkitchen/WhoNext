import SwiftUI

// MARK: - Loading State View Component
struct LoadingStateView: View {
    let isLoading: Bool
    let loadingText: String
    let content: () -> AnyView
    
    init<Content: View>(
        isLoading: Bool,
        loadingText: String = "Loading...",
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isLoading = isLoading
        self.loadingText = loadingText
        self.content = { AnyView(content()) }
    }
    
    var body: some View {
        ZStack {
            content()
                .opacity(isLoading ? 0.3 : 1.0)
                .disabled(isLoading)
            
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text(loadingText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.regularMaterial)
                        .shadow(radius: 8, y: 4)
                )
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isLoading)
    }
}

// MARK: - Inline Loading Button
struct LoadingButton: View {
    let title: String
    let loadingTitle: String
    let isLoading: Bool
    let action: () -> Void
    let style: ButtonStyle
    let isDisabled: Bool
    
    enum ButtonStyle {
        case primary
        case secondary
        case accent
        
        var backgroundColor: Color {
            switch self {
            case .primary: return .accentColor
            case .secondary: return .secondary.opacity(0.2)
            case .accent: return .blue
            }
        }
        
        var foregroundColor: Color {
            switch self {
            case .primary: return .white
            case .secondary: return .primary
            case .accent: return .white
            }
        }
    }
    
    init(
        title: String,
        loadingTitle: String = "Loading...",
        isLoading: Bool,
        style: ButtonStyle = .primary,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.loadingTitle = loadingTitle
        self.isLoading = isLoading
        self.style = style
        self.isDisabled = isDisabled
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .medium))
                }
                
                Text(isLoading ? loadingTitle : title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(style.foregroundColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(style.backgroundColor)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isLoading || isDisabled)
        .animation(.easeInOut(duration: 0.15), value: isLoading)
    }
}

// MARK: - Loading Overlay Modifier
extension View {
    func loadingOverlay(
        isLoading: Bool,
        text: String = "Loading..."
    ) -> some View {
        self.overlay(
            LoadingStateView(isLoading: isLoading, loadingText: text) {
                EmptyView()
            }
        )
    }
}

#Preview {
    VStack(spacing: 20) {
        LoadingStateView(isLoading: true, loadingText: "Generating brief...") {
            Text("Content behind loading state")
                .frame(width: 200, height: 100)
                .background(Color.gray.opacity(0.2))
        }
        
        LoadingButton(
            title: "Generate Brief",
            loadingTitle: "Generating...",
            isLoading: true,
            style: .primary
        ) {
            print("Button tapped")
        }
        
        LoadingButton(
            title: "Save",
            loadingTitle: "Saving...",
            isLoading: false,
            style: .secondary
        ) {
            print("Save tapped")
        }
    }
    .padding()
}
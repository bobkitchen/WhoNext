import SwiftUI

// MARK: - Liquid Glass Design System Components for macOS 26

/// Enhanced material background that adapts to macOS 26 liquid glass standards
struct LiquidGlassBackground: ViewModifier {
    let cornerRadius: CGFloat
    let elevation: LiquidGlassElevation
    let isInteractive: Bool
    @State private var isHovered = false
    
    init(cornerRadius: CGFloat, elevation: LiquidGlassElevation, isInteractive: Bool = false) {
        self.cornerRadius = cornerRadius
        self.elevation = elevation
        self.isInteractive = isInteractive
    }
    
    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .background {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(.background.opacity(isHovered && isInteractive ? 0.6 : 0.4))
                            .animation(.liquidGlassFast, value: isHovered)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(.primary.opacity(isHovered && isInteractive ? 0.15 : 0.1), lineWidth: 0.5)
                            .animation(.liquidGlassFast, value: isHovered)
                    }
                    .shadow(
                        color: .black.opacity(elevation.shadowOpacity * (isHovered && isInteractive ? 1.2 : 1.0)), 
                        radius: elevation.shadowRadius * (isHovered && isInteractive ? 1.1 : 1.0), 
                        x: 0, 
                        y: elevation.shadowOffset * (isHovered && isInteractive ? 1.1 : 1.0)
                    )
                    .animation(.liquidGlass, value: isHovered)
            }
            .onHover { hovering in
                if isInteractive {
                    isHovered = hovering
                }
            }
    }
}

/// Liquid glass card component with enhanced visual hierarchy and accessibility
struct LiquidGlassCard<Content: View>: View {
    let content: Content
    let cornerRadius: CGFloat
    let elevation: LiquidGlassElevation
    let padding: EdgeInsets
    let isInteractive: Bool
    let accessibilityLabel: String?
    let accessibilityHint: String?
    
    init(
        cornerRadius: CGFloat = 16,
        elevation: LiquidGlassElevation = .medium,
        padding: EdgeInsets = EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16),
        isInteractive: Bool = false,
        accessibilityLabel: String? = nil,
        accessibilityHint: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.cornerRadius = cornerRadius
        self.elevation = elevation
        self.padding = padding
        self.isInteractive = isInteractive
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
    }
    
    var body: some View {
        content
            .padding(padding)
            .modifier(LiquidGlassBackground(cornerRadius: cornerRadius, elevation: elevation, isInteractive: isInteractive))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(accessibilityLabel ?? "")
            .accessibilityHint(accessibilityHint ?? "")
    }
}

/// Enhanced button style compliant with liquid glass design
struct LiquidGlassButtonStyle: ButtonStyle {
    let variant: LiquidGlassButtonVariant
    let size: LiquidGlassButtonSize
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(size.font)
            .padding(size.padding)
            .background {
                RoundedRectangle(cornerRadius: size.cornerRadius)
                    .fill(variant.backgroundMaterial(for: configuration.isPressed))
                    .overlay {
                        RoundedRectangle(cornerRadius: size.cornerRadius)
                            .stroke(variant.strokeColor, lineWidth: 0.5)
                    }
                    .shadow(
                        color: variant.shadowColor,
                        radius: configuration.isPressed ? 2 : 4,
                        x: 0,
                        y: configuration.isPressed ? 1 : 2
                    )
            }
            .foregroundStyle(variant.foregroundColor)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.liquidGlassFast, value: configuration.isPressed)
    }
}

/// Enhanced text field with liquid glass appearance and improved accessibility
struct LiquidGlassTextField: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    let isSecure: Bool
    @FocusState private var isFocused: Bool
    @State private var isHovered = false
    
    init(
        title: String = "",
        text: Binding<String>,
        placeholder: String = "",
        isSecure: Bool = false
    ) {
        self.title = title
        self._text = text
        self.placeholder = placeholder
        self.isSecure = isSecure
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !title.isEmpty {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
            }
            
            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                        .textFieldStyle(.plain)
                } else {
                    TextField(placeholder, text: $text)
                        .textFieldStyle(.plain)
                }
            }
            .focused($isFocused)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .background {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.background.opacity(isFocused || isHovered ? 0.6 : 0.3))
                            .animation(.liquidGlassFast, value: isFocused || isHovered)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isFocused ? Color.accentColor : .primary.opacity(isHovered ? 0.15 : 0.1), lineWidth: isFocused ? 1.5 : 0.5)
                            .animation(.liquidGlassFast, value: isFocused || isHovered)
                    }
            }
            .onHover { hovering in
                isHovered = hovering
            }
            .accessibilityLabel(title.isEmpty ? placeholder : title)
            .accessibilityValue(text)
        }
    }
}

/// Enhanced navigation bar with liquid glass styling
struct LiquidGlassNavigationBar<Leading: View, Center: View, Trailing: View>: View {
    let leading: Leading
    let center: Center
    let trailing: Trailing
    
    init(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder center: () -> Center,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.leading = leading()
        self.center = center()
        self.trailing = trailing()
    }
    
    var body: some View {
        HStack {
            HStack {
                leading
                Spacer()
            }
            .frame(maxWidth: .infinity)
            
            center
                .frame(maxWidth: .infinity)
            
            HStack {
                Spacer()
                trailing
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .background(.background.opacity(0.3))
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(.primary.opacity(0.08))
                        .frame(height: 0.5)
                }
        }
    }
}

/// Enhanced sidebar with liquid glass styling
struct LiquidGlassSidebar<Content: View>: View {
    let width: CGFloat
    let content: Content
    
    init(width: CGFloat = 280, @ViewBuilder content: () -> Content) {
        self.width = width
        self.content = content()
    }
    
    var body: some View {
        content
            .frame(width: width)
            .background {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .background(.background.opacity(0.2))
                    .overlay(alignment: .trailing) {
                        Rectangle()
                            .fill(.primary.opacity(0.08))
                            .frame(width: 0.5)
                    }
            }
    }
}

// MARK: - Enhanced List Components

/// Liquid glass list row with hover effects and accessibility
struct LiquidGlassListRow<Content: View>: View {
    let content: Content
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false
    
    init(
        isSelected: Bool = false,
        action: @escaping () -> Void = {},
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.isSelected = isSelected
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(backgroundMaterial)
                        .animation(.liquidGlassFast, value: isSelected || isHovered)
                }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private var backgroundMaterial: AnyShapeStyle {
        if isSelected {
            return AnyShapeStyle(Color.accentColor.opacity(0.15))
        } else if isHovered {
            return AnyShapeStyle(.primary.opacity(0.05))
        } else {
            return AnyShapeStyle(.clear)
        }
    }
}

/// Enhanced section header for liquid glass lists
struct LiquidGlassSectionHeader: View {
    let title: String
    let subtitle: String?
    let action: (() -> Void)?
    let actionTitle: String?
    
    init(
        _ title: String,
        subtitle: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.action = action
        self.actionTitle = actionTitle
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            if let action = action, let actionTitle = actionTitle {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .buttonStyle(LiquidGlassButtonStyle(variant: .secondary, size: .small))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Enums and Supporting Types

enum LiquidGlassElevation {
    case none, low, medium, high, floating
    
    var shadowOpacity: Double {
        switch self {
        case .none: return 0.0
        case .low: return 0.03
        case .medium: return 0.06
        case .high: return 0.12
        case .floating: return 0.20
        }
    }
    
    var shadowRadius: CGFloat {
        switch self {
        case .none: return 0
        case .low: return 2
        case .medium: return 6
        case .high: return 12
        case .floating: return 20
        }
    }
    
    var shadowOffset: CGFloat {
        switch self {
        case .none: return 0
        case .low: return 1
        case .medium: return 3
        case .high: return 6
        case .floating: return 10
        }
    }
}

enum LiquidGlassButtonVariant {
    case primary, secondary, tertiary, destructive
    
    func backgroundMaterial(for isPressed: Bool) -> AnyShapeStyle {
        switch self {
        case .primary:
            return AnyShapeStyle(isPressed ? Color.accentColor.opacity(0.8) : Color.accentColor)
        case .secondary:
            if isPressed {
                return AnyShapeStyle(Material.ultraThinMaterial.opacity(0.8))
            } else {
                return AnyShapeStyle(Material.ultraThinMaterial)
            }
        case .tertiary:
            if isPressed {
                return AnyShapeStyle(Color.primary.opacity(0.08))
            } else {
                return AnyShapeStyle(Color.primary.opacity(0.05))
            }
        case .destructive:
            return AnyShapeStyle(isPressed ? Color.red.opacity(0.8) : Color.red)
        }
    }
    
    var foregroundColor: Color {
        switch self {
        case .primary, .destructive:
            return .white
        case .secondary, .tertiary:
            return .primary
        }
    }
    
    var strokeColor: Color {
        switch self {
        case .primary, .destructive:
            return .clear
        case .secondary, .tertiary:
            return .primary.opacity(0.1)
        }
    }
    
    var shadowColor: Color {
        switch self {
        case .primary:
            return Color.accentColor.opacity(0.3)
        case .destructive:
            return .red.opacity(0.3)
        case .secondary, .tertiary:
            return .black.opacity(0.1)
        }
    }
}

enum LiquidGlassButtonSize {
    case small, medium, large
    
    var font: Font {
        switch self {
        case .small: return .caption
        case .medium: return .subheadline
        case .large: return .body
        }
    }
    
    var padding: EdgeInsets {
        switch self {
        case .small: return EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
        case .medium: return EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
        case .large: return EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20)
        }
    }
    
    var cornerRadius: CGFloat {
        switch self {
        case .small: return 6
        case .medium: return 8
        case .large: return 10
        }
    }
}

// MARK: - View Extensions

extension View {
    func liquidGlassCard(
        cornerRadius: CGFloat = 16,
        elevation: LiquidGlassElevation = .medium,
        padding: EdgeInsets = EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16),
        isInteractive: Bool = false
    ) -> some View {
        LiquidGlassCard(
            cornerRadius: cornerRadius,
            elevation: elevation,
            padding: padding,
            isInteractive: isInteractive
        ) {
            self
        }
    }
    
    func liquidGlassBackground(
        cornerRadius: CGFloat = 12,
        elevation: LiquidGlassElevation = .medium,
        isInteractive: Bool = false
    ) -> some View {
        self.modifier(LiquidGlassBackground(cornerRadius: cornerRadius, elevation: elevation, isInteractive: isInteractive))
    }
    
    func liquidGlassButton(
        style: LiquidGlassButtonVariant = .secondary,
        cornerRadius: CGFloat = 8,
        elevation: LiquidGlassElevation = .low,
        padding: EdgeInsets = EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
    ) -> some View {
        Button(action: {}) {
            self
        }
        .modifier(LiquidGlassButtonModifier(style: style, cornerRadius: cornerRadius, elevation: elevation, padding: padding))
    }
    
    func liquidGlassTextField(
        cornerRadius: CGFloat = 12,
        elevation: LiquidGlassElevation = .low,
        padding: EdgeInsets = EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
    ) -> some View {
        self.modifier(LiquidGlassTextFieldModifier(cornerRadius: cornerRadius, elevation: elevation, padding: padding))
    }
    
    func liquidGlassListRow(
        isSelected: Bool = false,
        cornerRadius: CGFloat = 8,
        elevation: LiquidGlassElevation = .low,
        padding: EdgeInsets = EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
    ) -> some View {
        LiquidGlassListRow(isSelected: isSelected) {
            self
        }
    }
    
    func liquidGlassSectionHeader() -> some View {
        self.modifier(LiquidGlassSectionHeaderModifier())
    }
    
    func liquidGlassSidebar() -> some View {
        self.modifier(LiquidGlassSidebarModifier())
    }
}

// MARK: - Animations

extension Animation {
    static let liquidGlass = Animation.easeInOut(duration: 0.3)
    static let liquidGlassFast = Animation.easeInOut(duration: 0.15)
    static let liquidGlassSpring = Animation.spring(response: 0.4, dampingFraction: 0.8)
}

// MARK: - Additional Modifiers

struct LiquidGlassSectionHeaderModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .background {
                        Rectangle()
                            .fill(.background.opacity(0.3))
                    }
            }
    }
}

struct LiquidGlassSidebarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .background {
                        Rectangle()
                            .fill(.background.opacity(0.2))
                    }
            }
    }
}

struct LiquidGlassButtonModifier: ViewModifier {
    let style: LiquidGlassButtonVariant
    let cornerRadius: CGFloat
    let elevation: LiquidGlassElevation
    let padding: EdgeInsets
    
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(style.backgroundMaterial(for: false))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(style.strokeColor, lineWidth: 0.5)
                    }
                    .shadow(
                        color: style.shadowColor,
                        radius: elevation.shadowRadius,
                        x: 0,
                        y: elevation.shadowOffset
                    )
            }
            .foregroundStyle(style.foregroundColor)
    }
}

struct LiquidGlassTextFieldModifier: ViewModifier {
    let cornerRadius: CGFloat
    let elevation: LiquidGlassElevation
    let padding: EdgeInsets
    
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .background {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(.background.opacity(0.3))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(.primary.opacity(0.1), lineWidth: 0.5)
                    }
                    .shadow(
                        color: .black.opacity(elevation.shadowOpacity),
                        radius: elevation.shadowRadius,
                        x: 0,
                        y: elevation.shadowOffset
                    )
            }
    }
}
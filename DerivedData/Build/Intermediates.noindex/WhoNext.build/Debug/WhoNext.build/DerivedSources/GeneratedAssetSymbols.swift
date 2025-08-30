import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif
#if canImport(DeveloperToolsSupport)
import DeveloperToolsSupport
#endif

#if SWIFT_PACKAGE
private let resourceBundle = Foundation.Bundle.module
#else
private class ResourceBundleClass {}
private let resourceBundle = Foundation.Bundle(for: ResourceBundleClass.self)
#endif

// MARK: - Color Symbols -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DeveloperToolsSupport.ColorResource {

}

// MARK: - Image Symbols -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DeveloperToolsSupport.ImageResource {

    /// The "icon_bell" asset catalog image resource.
    static let iconBell = DeveloperToolsSupport.ImageResource(name: "icon_bell", bundle: resourceBundle)

    /// The "icon_calendar" asset catalog image resource.
    static let iconCalendar = DeveloperToolsSupport.ImageResource(name: "icon_calendar", bundle: resourceBundle)

    /// The "icon_fire" asset catalog image resource.
    static let iconFire = DeveloperToolsSupport.ImageResource(name: "icon_fire", bundle: resourceBundle)

    /// The "icon_flag" asset catalog image resource.
    static let iconFlag = DeveloperToolsSupport.ImageResource(name: "icon_flag", bundle: resourceBundle)

    /// The "icon_lightbulb" asset catalog image resource.
    static let iconLightbulb = DeveloperToolsSupport.ImageResource(name: "icon_lightbulb", bundle: resourceBundle)

    /// The "icon_stopwatch" asset catalog image resource.
    static let iconStopwatch = DeveloperToolsSupport.ImageResource(name: "icon_stopwatch", bundle: resourceBundle)

}

// MARK: - Color Symbol Extensions -

#if canImport(AppKit)
@available(macOS 14.0, *)
@available(macCatalyst, unavailable)
extension AppKit.NSColor {

}
#endif

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIColor {

}
#endif

#if canImport(SwiftUI)
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.Color {

}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.ShapeStyle where Self == SwiftUI.Color {

}
#endif

// MARK: - Image Symbol Extensions -

#if canImport(AppKit)
@available(macOS 14.0, *)
@available(macCatalyst, unavailable)
extension AppKit.NSImage {

    /// The "icon_bell" asset catalog image.
    static var iconBell: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .iconBell)
#else
        .init()
#endif
    }

    /// The "icon_calendar" asset catalog image.
    static var iconCalendar: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .iconCalendar)
#else
        .init()
#endif
    }

    /// The "icon_fire" asset catalog image.
    static var iconFire: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .iconFire)
#else
        .init()
#endif
    }

    /// The "icon_flag" asset catalog image.
    static var iconFlag: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .iconFlag)
#else
        .init()
#endif
    }

    /// The "icon_lightbulb" asset catalog image.
    static var iconLightbulb: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .iconLightbulb)
#else
        .init()
#endif
    }

    /// The "icon_stopwatch" asset catalog image.
    static var iconStopwatch: AppKit.NSImage {
#if !targetEnvironment(macCatalyst)
        .init(resource: .iconStopwatch)
#else
        .init()
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIImage {

    /// The "icon_bell" asset catalog image.
    static var iconBell: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .iconBell)
#else
        .init()
#endif
    }

    /// The "icon_calendar" asset catalog image.
    static var iconCalendar: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .iconCalendar)
#else
        .init()
#endif
    }

    /// The "icon_fire" asset catalog image.
    static var iconFire: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .iconFire)
#else
        .init()
#endif
    }

    /// The "icon_flag" asset catalog image.
    static var iconFlag: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .iconFlag)
#else
        .init()
#endif
    }

    /// The "icon_lightbulb" asset catalog image.
    static var iconLightbulb: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .iconLightbulb)
#else
        .init()
#endif
    }

    /// The "icon_stopwatch" asset catalog image.
    static var iconStopwatch: UIKit.UIImage {
#if !os(watchOS)
        .init(resource: .iconStopwatch)
#else
        .init()
#endif
    }

}
#endif

// MARK: - Thinnable Asset Support -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
@available(watchOS, unavailable)
extension DeveloperToolsSupport.ColorResource {

    private init?(thinnableName: Swift.String, bundle: Foundation.Bundle) {
#if canImport(AppKit) && os(macOS)
        if AppKit.NSColor(named: NSColor.Name(thinnableName), bundle: bundle) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#elseif canImport(UIKit) && !os(watchOS)
        if UIKit.UIColor(named: thinnableName, in: bundle, compatibleWith: nil) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIColor {

    private convenience init?(thinnableResource: DeveloperToolsSupport.ColorResource?) {
#if !os(watchOS)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

#if canImport(SwiftUI)
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.Color {

    private init?(thinnableResource: DeveloperToolsSupport.ColorResource?) {
        if let resource = thinnableResource {
            self.init(resource)
        } else {
            return nil
        }
    }

}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.ShapeStyle where Self == SwiftUI.Color {

    private init?(thinnableResource: DeveloperToolsSupport.ColorResource?) {
        if let resource = thinnableResource {
            self.init(resource)
        } else {
            return nil
        }
    }

}
#endif

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
@available(watchOS, unavailable)
extension DeveloperToolsSupport.ImageResource {

    private init?(thinnableName: Swift.String, bundle: Foundation.Bundle) {
#if canImport(AppKit) && os(macOS)
        if bundle.image(forResource: NSImage.Name(thinnableName)) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#elseif canImport(UIKit) && !os(watchOS)
        if UIKit.UIImage(named: thinnableName, in: bundle, compatibleWith: nil) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}

#if canImport(AppKit)
@available(macOS 14.0, *)
@available(macCatalyst, unavailable)
extension AppKit.NSImage {

    private convenience init?(thinnableResource: DeveloperToolsSupport.ImageResource?) {
#if !targetEnvironment(macCatalyst)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIImage {

    private convenience init?(thinnableResource: DeveloperToolsSupport.ImageResource?) {
#if !os(watchOS)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif


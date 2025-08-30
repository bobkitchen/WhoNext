#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The "icon_bell" asset catalog image resource.
static NSString * const ACImageNameIconBell AC_SWIFT_PRIVATE = @"icon_bell";

/// The "icon_calendar" asset catalog image resource.
static NSString * const ACImageNameIconCalendar AC_SWIFT_PRIVATE = @"icon_calendar";

/// The "icon_fire" asset catalog image resource.
static NSString * const ACImageNameIconFire AC_SWIFT_PRIVATE = @"icon_fire";

/// The "icon_flag" asset catalog image resource.
static NSString * const ACImageNameIconFlag AC_SWIFT_PRIVATE = @"icon_flag";

/// The "icon_lightbulb" asset catalog image resource.
static NSString * const ACImageNameIconLightbulb AC_SWIFT_PRIVATE = @"icon_lightbulb";

/// The "icon_stopwatch" asset catalog image resource.
static NSString * const ACImageNameIconStopwatch AC_SWIFT_PRIVATE = @"icon_stopwatch";

#undef AC_SWIFT_PRIVATE

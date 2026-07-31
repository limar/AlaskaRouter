#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The "backdrop" asset catalog image resource.
static NSString * const ACImageNameBackdrop AC_SWIFT_PRIVATE = @"backdrop";

#undef AC_SWIFT_PRIVATE

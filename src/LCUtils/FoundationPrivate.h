#include <Foundation/Foundation.h>

@interface NSBundle (private)
- (id)_cfBundle;
@end

@interface NSUserDefaults (private)
+ (void)setStandardUserDefaults:(id)defaults;
- (NSString*)_identifier;
@end

void* SecTaskCreateFromSelf(CFAllocatorRef allocator);
NSString* SecTaskCopyTeamIdentifier(void* task, NSError** error);
CFTypeRef SecTaskCopyValueForEntitlement(void* task, CFStringRef key, CFErrorRef* error);

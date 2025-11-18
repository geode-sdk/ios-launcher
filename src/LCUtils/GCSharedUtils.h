#import <Foundation/Foundation.h>

@interface GCSharedUtils : NSObject
+ (NSString*)liveContainerBundleID;
+ (NSString*)teamIdentifier;
+ (NSString*)appGroupID;
+ (NSURL*)appGroupPath;
+ (NSString*)certificatePassword;
+ (BOOL)askForJIT;
+ (void)relaunchApp;
+ (BOOL)launchToGuestApp;
+ (void)setWebPageUrlForNextLaunch:(NSString*)urlString;
+ (NSString*)getContainerUsingLCSchemeWithFolderName:(NSString*)folderName;
+ (void)moveSharedAppFolderBack;
+ (NSBundle*)findBundleWithBundleId:(NSString*)bundleId;
+ (void)dumpPreferenceToPath:(NSString*)plistLocationTo dataUUID:(NSString*)dataUUID;
+ (NSString*)findDefaultContainerWithBundleId:(NSString*)bundleId;
+ (void)signApp:(BOOL)force completionHandler:(void (^)(BOOL success, NSString* error))completionHandler;
@end

#import <UIKit/UIKit.h>

typedef void (^ImportCertHandler)(NSData* certData, NSString* password);

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow* window;
@property(copy, nonatomic) void (^openUrlStrFunc)(NSString* urlStr);
@property(copy, nonatomic) void (^launchAppFunc)(NSString* bundleId, NSString* container);
@property(nonatomic, strong) NSString* urlStrToOpen;
@property(nonatomic, strong) NSString* bundleToLaunch;
@property(nonatomic, strong) NSString* containerToLaunch;

+ (void)setOpenUrlStrFunc:(void (^)(NSString* urlStr))handler;
+ (void)setLaunchAppFunc:(void (^)(NSString* bundleId, NSString* container))handler;
+ (void)openWebPage:(NSString*)urlStr;
+ (void)launchApp:(NSString*)bundleId container:(NSString*)container;
+ (void)setImportSideStoreCertFunc:(ImportCertHandler)handler;
+ (void)importSideStoreCert:(NSData*)certData password:(NSString*)password;
@end

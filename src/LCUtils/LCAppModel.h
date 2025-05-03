#import "src/LCUtils/LCAppInfo.h"
#import "src/LCUtils/LCUtils.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@protocol LCAppModelDelegate <NSObject>
- (void)closeNavigationView;
- (void)changeAppVisibility:(id<NSObject>)app;
@end

@interface LCAppModel : NSObject

@property LCAppInfo* appInfo;

@property BOOL isAppRunning;
@property BOOL isSigningInProgress;
@property CGFloat signProgress;
@property BOOL uiIsJITNeeded;
@property NSString* uiDefaultDataFolder;
@property NSArray* uiContainers;
@property NSString* uiTweakFolder;
@property BOOL uiDoSymlinkInbox;
@property BOOL uiBypassAssertBarrierOnQueue;

@property id<LCAppModelDelegate> delegate;

- (instancetype)initWithAppInfo:(LCAppInfo*)appInfo delegate:(id<LCAppModelDelegate>)delegate;

- (BOOL)isEqual:(id<NSObject>)object;

@end

#import "RootViewController.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface GeodeInstaller : NSObject <NSURLSessionDownloadDelegate, NSURLSessionTaskDelegate>
@property(nonatomic, strong) RootViewController* root;
- (void)startInstall:(RootViewController*)root ignoreRoot:(BOOL)ignoreRoot;
- (void)downloadResource:(RootViewController*)root ignoreRoot:(BOOL)ignoreRoot;
- (void)checkUpdates:(RootViewController*)root download:(BOOL)download;
- (void)checkLauncherUpdates:(RootViewController*)root;
- (void)verifyChecksum;
- (void)cancelDownload;
@end

#import "LCUtils.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface LCAppInfo : NSObject {
	NSMutableDictionary* _info;
	NSMutableDictionary* _infoPlist;
	NSString* _bundlePath;
}
@property NSString* relativeBundlePath;
@property bool isShared;
@property bool doSymlinkInbox;
@property NSString* dataUUID;
@property bool autoSaveDisabled;

- (void)setBundlePath:(NSString*)newBundlePath;
- (NSMutableDictionary*)info;
- (NSString*)bundlePath;
- (NSString*)bundleIdentifier;
- (NSString*)version;
- (NSMutableArray*)urlSchemes;
- (instancetype)initWithBundlePath:(NSString*)bundlePath;
- (void)save;
- (void)patchExecAndSignIfNeedWithCompletionHandler:(void (^)(bool success, NSString* errorInfo))completetionHandler
									progressHandler:(void (^)(NSProgress* progress))progressHandler
										  forceSign:(BOOL)forceSign
										  blockMainThread:(BOOL)blockMainThread;
@end

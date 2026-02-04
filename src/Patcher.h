#import <Foundation/Foundation.h>
#import <mach-o/loader.h>

@interface Patcher : NSObject
@property(class, nonatomic, strong) NSMutableArray<NSNumber*>* patchedFuncs;
@property(class, nonatomic, strong) NSMutableDictionary<NSString*, NSData*>* originalBytes;

+ (void)startUnzip:(void (^)(NSString* doForce))completionHandler;
+ (NSString*)getPatchChecksum:(NSURL*)from withSafeMode:(BOOL)safeMode;
+ (void)patchGDBinary:(NSURL*)from
					to:(NSURL*)to
	withHandlerAddress:(uint64_t)handlerAddress
				 force:(BOOL)force
		  withSafeMode:(BOOL)safeMode
	  withEntitlements:(BOOL)entitlements
	 completionHandler:(void (^)(BOOL success, NSString* error))completionHandler;
+ (void)patchGeode:(void (^)(BOOL success, NSString* error))completionHandler;

@end

#import <Foundation/Foundation.h>
#import <mach-o/loader.h>

@interface Patcher : NSObject
@property(class, nonatomic, strong) NSMutableArray<NSNumber*>* patchedFuncs;
@property(class, nonatomic, strong) NSMutableDictionary<NSString*, NSData*>* originalBytes;

+ (void)startUnzip:(void (^)(NSString* doForce))completionHandler;
+ (void)patchGDBinary:(NSURL*)from
					to:(NSURL*)to
	withHandlerAddress:(uint64_t)handlerAddress
				 force:(BOOL)force
	 completionHandler:(void (^)(BOOL success, NSString* error))completionHandler;

@end

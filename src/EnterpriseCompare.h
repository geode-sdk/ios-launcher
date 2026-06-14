#import <Foundation/Foundation.h>
@interface EnterpriseCompare : NSObject
+ (NSString*)getChecksum:(BOOL)helper;
+ (NSInteger)getModCount:(BOOL)helper;
@end

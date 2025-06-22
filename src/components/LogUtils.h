#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, LogLevel) { LogUnk, LogInfo, LogWarn, LogError, LogDebug };

@interface LogUtils : NSObject

+ (void)log:(NSString*)format, ...;
+ (void)logWithLevel:(LogLevel)level log:(NSString*)format, ...;
+ (void)clearLogs:(BOOL)force;

@end
#define AppLogUnknown(x...) [LogUtils log:x];
#define AppLog(x...) [LogUtils logWithLevel:LogInfo log:x];
#define AppLogWarn(x...) [LogUtils logWithLevel:LogWarn log:x];
#define AppLogError(x...) [LogUtils logWithLevel:LogError log:x];
#define AppLogDebug(x...) [LogUtils logWithLevel:LogDebug log:x];

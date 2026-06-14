#import "EnterpriseCompare.h"
#import <CommonCrypto/CommonCrypto.h>

@implementation EnterpriseCompare
+ (NSString*)getChecksum:(BOOL)helper {
	NSFileManager* fm = [NSFileManager defaultManager];
	NSMutableSet<NSString*>* modIDs = [NSMutableSet new];
	NSArray* modsDir = [fm contentsOfDirectoryAtPath:[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"mods"] error:nil];
	if (!helper) {
		NSURL* docPath = [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].lastObject;
		NSURL* bundlePath = [[docPath URLByAppendingPathComponent:@"Applications"] URLByAppendingPathComponent:@"com.robtop.geometryjump.app"];
		modsDir = [fm contentsOfDirectoryAtPath:[bundlePath.path stringByAppendingPathComponent:@"mods"] error:nil];
	}
	for (NSString* file in modsDir) {
		NSString* modID = [[file stringByDeletingPathExtension] stringByDeletingPathExtension];
		[modIDs addObject:modID];
	}
	NSMutableArray* modIDSorted = [[[modIDs allObjects] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)] mutableCopy];
	for (int i = 0; i < modIDSorted.count; i++) {
		NSString* item = modIDSorted[i];
		if (item == nil || [item isEqualToString:@""]) {
			[modIDSorted removeObjectAtIndex:i];
		}
	}
	NSData* data = [[NSString stringWithFormat:@"%@", [modIDSorted componentsJoinedByString:@","]] dataUsingEncoding:NSUTF8StringEncoding];
	unsigned char digest[CC_SHA256_DIGEST_LENGTH];
	CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
	NSMutableString* output = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
	for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
		[output appendFormat:@"%02x", digest[i]];
	}
	return output;
}
+ (NSInteger)getModCount:(BOOL)helper {
	NSFileManager* fm = [NSFileManager defaultManager];
	NSMutableSet<NSString*>* modIDs = [NSMutableSet new];
	NSError* err;
	NSArray* modsDir = [fm contentsOfDirectoryAtPath:[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"mods"] error:&err];
	if (!helper) {
		NSURL* docPath = [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].lastObject;
		NSURL* bundlePath = [[docPath URLByAppendingPathComponent:@"Applications"] URLByAppendingPathComponent:@"com.robtop.geometryjump.app"];
		modsDir = [fm contentsOfDirectoryAtPath:[bundlePath.path stringByAppendingPathComponent:@"mods"] error:nil];
	}
	if (err || modsDir.count == 0) {
		return 0;
	}
	for (NSString* file in modsDir) {
		NSString* modID = [[file stringByDeletingPathExtension] stringByDeletingPathExtension];
		[modIDs addObject:modID];
	}
	NSMutableArray* modIDSorted = [[[modIDs allObjects] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)] mutableCopy];
	for (int i = 0; i < modIDSorted.count; i++) {
		NSString* item = modIDSorted[i];
		if (item == nil || [item isEqualToString:@""]) {
			[modIDSorted removeObjectAtIndex:i];
		}
	}
	return [modIDSorted count];
}
@end

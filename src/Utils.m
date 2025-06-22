#import "LCUtils/GCSharedUtils.h"
#import "LCUtils/Shared.h"
#import "LCUtils/unarchive.h"
#import "Utils.h"
#import "components/LogUtils.h"
#import "src/LCUtils/UIKitPrivate.h"
#import <CommonCrypto/CommonCrypto.h>
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <mach-o/arch.h>

BOOL checkedSandboxed = NO;
BOOL sandboxValue = NO;
NSString* gdBundlePath = nil;
NSString* gdDocPath = nil;
NSString* cachedVersion = nil;

extern NSUserDefaults* gcUserDefaults;

// since iOS for whatever reason doesnt have this API
// https://developer.apple.com/documentation/security/sectaskcopyvalueforentitlement(_:_:_:)
// https://developer.apple.com/documentation/security/sectaskcreatefromself(_:)
typedef struct __SecTask* SecTaskRef;
extern CFTypeRef SecTaskCopyValueForEntitlement(SecTaskRef task, CFStringRef entitlement, CFErrorRef _Nullable* error) __attribute__((weak_import));
extern SecTaskRef SecTaskCreateFromSelf(CFAllocatorRef allocator) __attribute__((weak_import));

@implementation Utils
+ (NSString*)launcherBundleName {
	return @"com.geode.launcher";
}
+ (NSString*)gdBundleName {
	return @"com.robtop.geometryjump.app";
	// return @"GeometryDash";
}
+ (BOOL)isJailbroken {
	return [[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb"] || access("/var/mobile", R_OK) == 0;
}
+ (void)increaseLaunchCount {
	NSInteger currentCount = [[Utils getPrefs] integerForKey:@"LAUNCH_COUNT"];
	if (!currentCount)
		currentCount = 1;
	[[Utils getPrefs] setInteger:(currentCount + 1) forKey:@"LAUNCH_COUNT"];
}

+ (NSData*)getTweakData {
	if (![Utils isSandboxed]) {
		NSString* applicationSupportDirectory = [[Utils getGDDocPath] stringByAppendingString:@"Library/Application Support"];
		if (applicationSupportDirectory != nil) {
			return [NSData dataWithContentsOfFile:[applicationSupportDirectory stringByAppendingString:@"/GeometryDash/game/geode/Geode.ios.dylib"] options:0 error:nil];
		}
	} else {
		return [NSData dataWithContentsOfFile:[[LCPath tweakPath].path stringByAppendingPathComponent:@"Geode.ios.dylib"] options:0 error:nil];
	}
	return nil;
}
+ (NSString*)getTweakDir {
	if (![Utils isSandboxed]) {
		NSString* applicationSupportDirectory = [[Utils getGDDocPath] stringByAppendingString:@"Library/Application Support"];
		if (applicationSupportDirectory != nil) {
			return [applicationSupportDirectory stringByAppendingString:@"/GeometryDash/game/geode/Geode.ios.dylib"];
		}
	} else {
		return [[LCPath tweakPath].path stringByAppendingPathComponent:@"Geode.ios.dylib"];
	}
	return nil;
}

// replicate unix "strings" because
+ (NSArray<NSString*>*)strings:(NSData*)data {
	const uint8_t* bytes = data.bytes;
	NSMutableArray<NSString*>* results = [NSMutableArray array];
	NSMutableData* current = [NSMutableData data];
	for (NSUInteger i = 0; i < data.length; i++) {
		unsigned char byte = bytes[i];
		if (byte >= 32 && byte <= 126) {
			[current appendBytes:&byte length:1];
		} else {
			if (current.length >= 4) {
				NSString* str = [[NSString alloc] initWithData:current encoding:NSASCIIStringEncoding];
				if (str) {
					[results addObject:str];
				}
			}
			[current setLength:0];
		}
	}
	return results;
}

+ (NSString*)getGeodeVersion {
	NSFileManager* fm = NSFileManager.defaultManager;
	if (![Utils isSandboxed]) {
		NSString* applicationSupportDirectory = [[Utils getGDDocPath] stringByAppendingString:@"Library/Application Support"];
		if (applicationSupportDirectory != nil) {
			if (![fm fileExistsAtPath:[applicationSupportDirectory stringByAppendingString:@"/GeometryDash/game/geode/Geode.ios.dylib"]]) {
				return @"Geode is not installed";
			}
		}
	} else {
		if (![fm fileExistsAtPath:[[LCPath tweakPath].path stringByAppendingPathComponent:@"Geode.ios.dylib"]]) {
			return @"Geode is not installed";
		}
	}
	// no need to calculate anything if we're nightly...
	if ([[Utils getPrefs] boolForKey:@"USE_NIGHTLY"]) {
		return @"Nightly";
	} else if (cachedVersion) {
		if ([cachedVersion hasPrefix:@"v"]) {
			return cachedVersion;
		} else {
			return [NSString stringWithFormat:@"v%@", cachedVersion];
		}
	}
	NSString* currentHash = [[Utils getPrefs] stringForKey:@"CURRENT_TWEAK_HASH"];
	NSData* data = [Utils getTweakData];
	NSString* newHash = [Utils sha256sumWithData:data];
	if (data && ![currentHash isEqualToString:newHash]) {
		AppLog(@"Hash mismatch (%@ vs %@)", currentHash, newHash);
		NSError* error;
		NSString* stringData = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
		if (stringData) {
			// https://developer.apple.com/documentation/foundation/nsregularexpression
			// "version":(?: )?"((?:\\.|[^"\\])*)"
			NSRegularExpression* regex = [NSRegularExpression regularExpressionWithPattern:@"\"version\":(?: )?\"((?:\\\\.|[^\"\\\\])*)\""
																				   options:NSRegularExpressionCaseInsensitive
																					 error:&error];
			if (regex && !error) {
				NSTextCheckingResult* match = [regex firstMatchInString:stringData options:0 range:NSMakeRange(0, stringData.length)];
				if (match && match.numberOfRanges > 1) {
					cachedVersion = [stringData substringWithRange:[match rangeAtIndex:1]];
					[[Utils getPrefs] setObject:cachedVersion forKey:@"CURRENT_VERSION_TAG"];
					[[Utils getPrefs] setObject:newHash forKey:@"CURRENT_TWEAK_HASH"];
					AppLog(@"Set new version to %@ and hash to %@", cachedVersion, newHash);
					if ([cachedVersion hasPrefix:@"v"]) {
						return cachedVersion;
					} else {
						return [NSString stringWithFormat:@"v%@", cachedVersion];
					}
				}
			}
		}
	} else {
		cachedVersion = [[Utils getPrefs] stringForKey:@"CURRENT_VERSION_TAG"];
		if ([cachedVersion hasPrefix:@"v"]) {
			return cachedVersion;
		} else {
			return [NSString stringWithFormat:@"v%@", cachedVersion];
		}
	}
	return @"Couldn't fetch version";
}

+ (void)updateGeodeVersion:(NSString*)newVer {
	cachedVersion = newVer;
}

+ (NSString*)getGeodeReleaseURL {
	// return @"http://192.168.200.1:38000";
	if ([[Utils getPrefs] boolForKey:@"USE_NIGHTLY"]) {
		return @"https://api.github.com/repos/geode-sdk/geode/releases/tags/nightly";
	} else {
		return @"https://api.github.com/repos/geode-sdk/geode/releases/latest";
	}
}
+ (NSString*)getGeodeLauncherURL {
	return @"https://api.github.com/repos/geode-sdk/ios-launcher/releases/latest";
}
+ (NSString*)getGeodeLauncherRedirect {
	return @"https://github.com/geode-sdk/ios-launcher/releases/latest";
}

// ai generated because i cant figure this out
+ (UIImageView*)imageViewFromPDF:(NSString*)pdfName {
	NSURL* pdfURL = [[NSBundle mainBundle] URLForResource:pdfName withExtension:@"pdf"];
	if (!pdfURL) {
		return nil;
	}

	CGPDFDocumentRef pdfDocument = CGPDFDocumentCreateWithURL((__bridge CFURLRef)pdfURL);
	if (!pdfDocument) {
		return nil;
	}

	CGPDFPageRef pdfPage = CGPDFDocumentGetPage(pdfDocument, 1); // Get the first page
	if (!pdfPage) {
		CGPDFDocumentRelease(pdfDocument);
		return nil;
	}

	CGRect pageRect = CGPDFPageGetBoxRect(pdfPage, kCGPDFMediaBox);
	UIGraphicsBeginImageContext(pageRect.size);
	CGContextRef context = UIGraphicsGetCurrentContext();

	// Draw the PDF page into the context
	CGContextSaveGState(context);
	CGContextTranslateCTM(context, 0.0, pageRect.size.height);
	CGContextScaleCTM(context, 1.0, -1.0);
	CGContextDrawPDFPage(context, pdfPage);
	CGContextRestoreGState(context);

	// Create the UIImage from the context
	UIImage* pdfImage = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();

	// Release the PDF document
	CGPDFDocumentRelease(pdfDocument);

	// Create and return the UIImageView
	UIImageView* imageView = [[UIImageView alloc] initWithImage:pdfImage];
	return imageView;
}
+ (NSURL*)pathToMostRecentLogInDirectory:(NSString*)directoryPath {
	NSFileManager* fileManager = [NSFileManager defaultManager];
	NSError* error;

	// Get all files in directory
	NSArray<NSURL*>* files = [fileManager contentsOfDirectoryAtURL:[NSURL fileURLWithPath:directoryPath] includingPropertiesForKeys:@[ NSURLCreationDateKey ]
														   options:NSDirectoryEnumerationSkipsHiddenFiles
															 error:&error];

	if (error) {
		AppLogError(@"Couldn't read %@, Error reading directory: %@", directoryPath, error.localizedDescription);
		return nil;
	}

	// Filter and sort log files
	NSArray* logFiles = [files filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"pathExtension == 'log'"]];

	logFiles = [logFiles sortedArrayUsingComparator:^NSComparisonResult(NSURL* file1, NSURL* file2) {
		// Get creation dates
		NSDate *date1, *date2;
		[file1 getResourceValue:&date1 forKey:NSURLCreationDateKey error:nil];
		[file2 getResourceValue:&date2 forKey:NSURLCreationDateKey error:nil];

		// Reverse chronological order
		return [date2 compare:date1];
	}];

	return logFiles.firstObject;
}
+ (BOOL)canAccessDirectory:(NSString*)path {
	NSFileManager* fileManager = [NSFileManager defaultManager];
	return [fileManager fileExistsAtPath:path isDirectory:nil];
}
+ (NSString*)getGDDocPath {
	// me when performance
	if (gdDocPath != nil)
		return gdDocPath;
	NSFileManager* fm = [NSFileManager defaultManager];
	NSError* err;
	NSArray* dirs = [fm contentsOfDirectoryAtPath:@"/var/mobile/Containers/Data/Application" error:&err];
	if (err) {
		// assume we arent on jb or trollstore
		AppLogError(@"Couldn't get doc path %@", err);
		return nil;
	}
	// probably the most inefficient way of getting a bundle id, i need to figure out another way of doing this because this is just bad...
	for (NSString* dir in dirs) {
		NSString* checkPrefsA = [NSString stringWithFormat:@"/var/mobile/Containers/Data/Application/%@/Library/HTTPStorages/com.robtop.geometryjump", dir];
		NSString* checkPrefsB = [NSString stringWithFormat:@"/var/mobile/Containers/Data/Application/%@/tmp/com.robtop.geometryjump-Inbox", dir];
		NSString* checkPrefsC = [NSString stringWithFormat:@"/var/mobile/Containers/Data/Application/%@/.com.apple.mobile_container_manager.metadata.plist", dir];
		if ([fm fileExistsAtPath:checkPrefsA isDirectory:nil] || [fm fileExistsAtPath:checkPrefsB isDirectory:nil]) {
			gdDocPath = [NSString stringWithFormat:@"/var/mobile/Containers/Data/Application/%@/", dir];
			return gdDocPath;
		} else if ([fm fileExistsAtPath:checkPrefsC isDirectory:nil]) {
			NSDictionary* plist = [NSDictionary dictionaryWithContentsOfFile:checkPrefsC];
			if (plist) {
				if (plist[@"MCMMetadataIdentifier"] && [plist[@"MCMMetadataIdentifier"] isEqualToString:@"com.robtop.geometryjump"]) {
					gdDocPath = [NSString stringWithFormat:@"/var/mobile/Containers/Data/Application/%@/", dir];
					return gdDocPath;
				}
			}
		}
	}

	return nil;
}

+ (NSString*)getGDBinaryPath {
	NSFileManager* fm = [NSFileManager defaultManager];
	NSError* err;
	NSArray* dirs = [fm contentsOfDirectoryAtPath:@"/var/containers/Bundle/Application" error:&err];
	if (err) {
		// assume we arent on jb or trollstore
		return nil;
	}
	// probably the most inefficient way of getting a bundle id, i need to figure out another way of doing this because this is just bad...
	for (NSString* dir in dirs) {
		NSString* checkPrefs = [NSString stringWithFormat:@"/var/containers/Bundle/Application/%@/GeometryJump.app", dir];
		if ([fm fileExistsAtPath:checkPrefs isDirectory:nil]) {
			return [NSString stringWithFormat:@"/var/containers/Bundle/Application/%@/GeometryJump.app/GeometryJump", dir];
		}
	}

	return nil;
}
+ (NSString*)getGDBundlePath {
	// me when performance
	if (gdBundlePath != nil)
		return gdBundlePath;
	NSFileManager* fm = [NSFileManager defaultManager];
	NSError* err;
	NSArray* dirs = [fm contentsOfDirectoryAtPath:@"/var/containers/Bundle/Application" error:&err];
	if (err) {
		// assume we arent on jb or trollstore
		return nil;
	}
	// probably the most inefficient way of getting a bundle id, i need to figure out another way of doing this because this is just bad...
	for (NSString* dir in dirs) {
		NSString* checkPrefs = [NSString stringWithFormat:@"/var/containers/Bundle/Application/%@/GeometryJump.app", dir];
		if ([fm fileExistsAtPath:checkPrefs isDirectory:nil]) {
			gdBundlePath = [NSString stringWithFormat:@"/var/containers/Bundle/Application/%@/", dir];
			return gdBundlePath;
		}
	}
	return nil;
}

+ (void)showNotice:(UIViewController*)root title:(NSString*)title {
	UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"common.notice".loc message:title preferredStyle:UIAlertControllerStyleAlert];
	UIAlertAction* okAction = [UIAlertAction actionWithTitle:@"common.ok".loc style:UIAlertActionStyleDefault handler:nil];
	[alert addAction:okAction];
	[root presentViewController:alert animated:YES completion:nil];
}
+ (void)showNoticeGlobal:(NSString*)title {
	UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"common.notice".loc message:title preferredStyle:UIAlertControllerStyleAlert];
	UIAlertAction* okAction = [UIAlertAction actionWithTitle:@"common.ok".loc style:UIAlertActionStyleDefault handler:nil];
	[alert addAction:okAction];

	UIWindowScene* scene = (id)[UIApplication.sharedApplication.connectedScenes allObjects].firstObject;
	UIWindow* window = scene.windows.firstObject;
	if (window != nil) {
		[window.rootViewController presentViewController:alert animated:YES completion:nil];
	}
}
+ (void)showError:(UIViewController*)root title:(NSString*)title error:(NSError*)error {
	UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"common.error".loc
																   message:(error == nil) ? title : [NSString stringWithFormat:@"%@: %@", title, error.localizedDescription]
															preferredStyle:UIAlertControllerStyleAlert];
	UIAlertAction* okAction = [UIAlertAction actionWithTitle:@"common.ok".loc style:UIAlertActionStyleDefault handler:nil];
	[alert addAction:okAction];
	[root presentViewController:alert animated:YES completion:nil];
}

+ (void)showErrorGlobal:(NSString*)title error:(NSError*)error {
	UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"common.error".loc
																   message:(error == nil) ? title : [NSString stringWithFormat:@"%@: %@", title, error.localizedDescription]
															preferredStyle:UIAlertControllerStyleAlert];
	UIAlertAction* okAction = [UIAlertAction actionWithTitle:@"common.ok".loc style:UIAlertActionStyleDefault handler:nil];
	[alert addAction:okAction];

	UIWindowScene* scene = (id)[UIApplication.sharedApplication.connectedScenes allObjects].firstObject;
	UIWindow* window = scene.windows.firstObject;
	if (window != nil) {
		[window.rootViewController presentViewController:alert animated:YES completion:nil];
	}
}

+ (NSString*)archName {
	const NXArchInfo* info = NXGetLocalArchInfo();
	NSString* typeOfCpu = [NSString stringWithUTF8String:info->description];
	return typeOfCpu;
}

+ (void)toggleKey:(NSString*)key {
	[[Utils getPrefs] setBool:![[Utils getPrefs] boolForKey:key] forKey:key];
}

// https://appideas.com/checksum-files-in-ios/
+ (NSString*)sha256sum:(NSString*)path {
	if (!path)
		return nil;
	NSData* data = [NSData dataWithContentsOfFile:path];
	return [Utils sha256sumWithData:data];
}
+ (NSString*)sha256sumWithString:(NSString*)data {
	if (!data)
		return nil;
	return [Utils sha256sumWithData:[data dataUsingEncoding:NSUTF8StringEncoding]];
}
+ (NSString*)sha256sumWithData:(NSData*)data {
	if (!data)
		return nil;
	unsigned char digest[CC_SHA256_DIGEST_LENGTH];
	CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
	NSMutableString* output = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
	for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
		[output appendFormat:@"%02x", digest[i]];
	}
	return output;
}
+ (BOOL)isContainerized {
	return [[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.robtop.geometryjump"];
}
+ (BOOL)isSandboxed {
	if (checkedSandboxed)
		return sandboxValue;
	checkedSandboxed = YES;
	if (SecTaskCreateFromSelf == NULL || SecTaskCopyValueForEntitlement == NULL) {
		AppLog(@"Sandboxed");
		sandboxValue = YES;
		return YES;
	}
	SecTaskRef task = SecTaskCreateFromSelf(nil);
	if (task == nil) {
		AppLog(@"Sandboxed");
		sandboxValue = YES;
		return YES;
	}
	CFTypeRef value = SecTaskCopyValueForEntitlement(task, CFSTR("com.apple.private.security.no-sandbox"), NULL);
	if (value)
		CFRelease(value);
	CFRelease(task);
	if ((value && CFBooleanGetValue(value) == true)) {
		AppLog(@"Not Sandboxed");
		sandboxValue = NO;
		return NO;
	} else {
		AppLog(@"Sandboxed");
		sandboxValue = YES;
		return YES;
	}
	sandboxValue = NO;
	return NO;
}
+ (BOOL)isDevCert {
	SecTaskRef task = SecTaskCreateFromSelf(nil);
	if (task == nil) {
		return NO;
	}
	CFTypeRef value = SecTaskCopyValueForEntitlement(task, CFSTR("get-task-allow"), NULL);
	if (value)
		CFRelease(value);
	CFRelease(task);
	return ((value && CFBooleanGetValue(value) == true));
}

+ (NSUserDefaults*)getPrefs {
	if (![Utils isSandboxed]) {
		// fix for no sandbox because apparently it changes the pref location
		NSURL* libPath = [[NSFileManager defaultManager] URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask].lastObject;
		return [[NSUserDefaults alloc] initWithSuiteName:[libPath URLByAppendingPathComponent:@"Preferences/com.geode.launcher.plist"].path];
	} else {
		return [NSUserDefaults standardUserDefaults];
	}
}
+ (NSUserDefaults*)getPrefsGC {
	if (![Utils isSandboxed]) {
		return [Utils getPrefs];
	} else {
		return gcUserDefaults;
	}
}
+ (const char*)getKillAllPath {
	const char* paths[] = {
		"/usr/bin/killall",
		"/var/jb/usr/bin/killall",
		"/var/libexec/killall",
	};

	for (int i = 0; i < sizeof(paths) / sizeof(paths[0]); i++) {
		if (access(paths[i], X_OK) == 0) {
			return paths[i];
		}
	}
	return paths[0];
}

+ (void)tweakLaunch_withSafeMode:(BOOL)safemode {
	AppLog(@"tweakLaunching GD %@", safemode ? @"in safe mode" : @"normally");
	NSString* launchArgs = [[Utils getPrefs] stringForKey:@"LAUNCH_ARGS"];
	if (safemode) {
		// https://github.com/geode-catgirls/geode-inject-ios/blob/meow/src/geode.m
		NSString* appSupportDirectory = [[Utils getGDDocPath] stringByAppendingString:@"Library/Application Support"];
		NSString* geode_dir = [appSupportDirectory stringByAppendingString:@"/GeometryDash/game/geode"];
		NSString* geode_env = [geode_dir stringByAppendingString:@"/geode.env"];

		NSString* safeModeEnv = @"LAUNCHARGS=--geode:safe-mode";
		NSFileManager* fm = [NSFileManager defaultManager];
		[fm createFileAtPath:geode_env contents:[safeModeEnv dataUsingEncoding:NSUTF8StringEncoding] attributes:@{}];
	} else if (launchArgs && [launchArgs length] > 1) {
		// https://github.com/geode-catgirls/geode-inject-ios/blob/meow/src/geode.m
		NSString* appSupportDirectory = [[Utils getGDDocPath] stringByAppendingString:@"Library/Application Support"];
		NSString* geode_dir = [appSupportDirectory stringByAppendingString:@"/GeometryDash/game/geode"];
		NSString* geode_env = [geode_dir stringByAppendingString:@"/geode.env"];

		NSString* safeModeEnv = [NSString stringWithFormat:@"LAUNCHARGS=%@", launchArgs];
		NSFileManager* fm = [NSFileManager defaultManager];
		[fm createFileAtPath:geode_env contents:[safeModeEnv dataUsingEncoding:NSUTF8StringEncoding] attributes:@{}];
	}

	[[LSApplicationWorkspace defaultWorkspace] openApplicationWithBundleID:@"com.robtop.geometryjump"];
}

+ (NSString*)colorToHex:(UIColor*)color {
	CGFloat red, green, blue, alpha;

	// Get the color components
	if ([color getRed:&red green:&green blue:&blue alpha:&alpha]) {
		// Convert to integer in range [0, 255]
		int redInt = (int)roundf(red * 255);
		int greenInt = (int)roundf(green * 255);
		int blueInt = (int)roundf(blue * 255);

		// Return formatted hex string
		return [NSString stringWithFormat:@"#%02X%02X%02X", redInt, greenInt, blueInt];
	}

	// If the color isn't in RGB-compatible color space, attempt conversion
	CGColorRef colorRef = color.CGColor;
	size_t count = CGColorGetNumberOfComponents(colorRef);
	const CGFloat* components = CGColorGetComponents(colorRef);
	if (count == 2) {
		// Grayscale color space: components are [white, alpha]
		int whiteInt = (int)roundf(components[0] * 255);
		return [NSString stringWithFormat:@"#%02X%02X%02X", whiteInt, whiteInt, whiteInt];
	}

	// If extraction fails, return nil as a fallback
	return nil;
}
+ (NSString*)docPath {
	NSString* path;
	if (![Utils isSandboxed]) {
		path = [[Utils getGDDocPath] stringByAppendingString:@"Documents/"];
	} else {
		path = [[LCPath dataPath] URLByAppendingPathComponent:@"GeometryDash/Documents/"].path;
	}
	if ([path hasSuffix:@"/"]) {
		return path;
	} else {
		return [NSString stringWithFormat:@"%@/", path];
	}
}

// https://clouddevs.com/objective-c/security/
// https://richardwarrender.com/2016/04/encrypt-data-using-aes-and-256-bit-keys/
// https://github.com/coolnameismy/ios-tips/blob/e2b79e6bc648ff8b16b54cbd303132dbdb242602/3_Other/aes128%E5%8A%A0%E5%AF%86%E8%A7%A3%E5%AF%86.md
+ (NSData*)encryptData:(NSData*)data withKey:(NSString*)keyStr {
	if ([keyStr length] != 32)
		return nil;
	NSData* key = [keyStr dataUsingEncoding:NSUTF8StringEncoding];

	size_t bufferSize = [data length] + kCCBlockSizeAES128;
	void* buffer = malloc(bufferSize);

	size_t encryptedSize = 0;
	CCCryptorStatus cryptStatus =
		CCCrypt(kCCEncrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding, [key bytes], kCCKeySizeAES256, NULL, [data bytes], [data length], buffer, bufferSize, &encryptedSize);

	if (cryptStatus == kCCSuccess) {
		return [NSData dataWithBytesNoCopy:buffer length:encryptedSize];
	}

	free(buffer);
	return nil;
}
+ (NSData*)decryptData:(NSData*)data withKey:(NSString*)keyStr {
	if ([keyStr length] != 32)
		return [[[NSString alloc] initWithFormat:@"eW91IGRpZCBpdCB3cm9uZw=="] dataUsingEncoding:NSUTF8StringEncoding];
	NSData* key = [keyStr dataUsingEncoding:NSUTF8StringEncoding];

	size_t bufferSize = [data length] + kCCBlockSizeAES128;
	void* buffer = malloc(bufferSize);

	size_t decryptedSize = 0;
	CCCryptorStatus cryptStatus =
		CCCrypt(kCCDecrypt, kCCAlgorithmAES, kCCOptionPKCS7Padding, [key bytes], kCCKeySizeAES256, NULL, [data bytes], [data length], buffer, bufferSize, &decryptedSize);

	if (cryptStatus == kCCSuccess) {
		return [NSData dataWithBytesNoCopy:buffer length:decryptedSize];
	}

	free(buffer);
	return nil;
}

+ (void)decompress:(NSString*)fileToExtract extractionPath:(NSString*)extractionPath completion:(void (^)(int))completion {
	AppLog(@"Starting decomp of %@ to %@", fileToExtract, extractionPath);
	[[NSFileManager defaultManager] createDirectoryAtPath:extractionPath withIntermediateDirectories:YES attributes:nil error:nil];
	int res = extract(fileToExtract, extractionPath, nil);
	return completion(res);
}
@end

@implementation CompareSemVer

+ (NSString*)normalizedVersionString:(NSString*)versionString {
	if ([versionString hasPrefix:@"v"]) {
		return [versionString substringFromIndex:1];
	}
	return versionString;
}
+ (BOOL)isVersion:(NSString*)versionA greaterThanVersion:(NSString*)versionB {
	if (versionA == nil || [versionA isEqual:@""])
		return YES;
	if (versionB == nil || [versionB isEqual:@""])
		return YES;
	NSString* normalizedA = [self normalizedVersionString:versionA];
	NSString* normalizedB = [self normalizedVersionString:versionB];
	NSArray<NSString*>* componentsA = [normalizedA componentsSeparatedByString:@"."];
	NSArray<NSString*>* componentsB = [normalizedB componentsSeparatedByString:@"."];
	NSUInteger maxCount = MAX(componentsA.count, componentsB.count);
	for (NSUInteger i = 0; i < maxCount; i++) {
		NSInteger valueA = (i < componentsA.count) ? [componentsA[i] integerValue] : 0;
		NSInteger valueB = (i < componentsB.count) ? [componentsB[i] integerValue] : 0;
		if (valueA > valueB) {
			return NO;
		}
	}
	return YES;
}

@end

@import Darwin;
@import MachO;
@import UIKit;

#import "LCUtils.h"
#import "Shared.h"
#import "ZSign/zsigner.h"
#import "src/Utils.h"
#import "src/components/LogUtils.h"
#import <MobileCoreServices/MobileCoreServices.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

extern NSBundle* gcMainBundle;

Class LCSharedUtilsClass = nil;

// make SFSafariView happy and open data: URLs
@implementation NSURL (hack)
- (BOOL)safari_isHTTPFamilyURL {
	// Screw it, Apple
	return YES;
}
@end

@implementation LCUtils

+ (void)load {
	LCSharedUtilsClass = NSClassFromString(@"GCSharedUtils");
}

#pragma mark Certificate & password
+ (NSString*)teamIdentifier {
	return [LCSharedUtilsClass teamIdentifier];
}

+ (NSURL*)appGroupPath {
	return [LCSharedUtilsClass appGroupPath];
}

+ (NSData*)certificateData {
	NSData* ans;
	if ([NSUserDefaults.standardUserDefaults boolForKey:@"LCCertificateImported"]) {
		ans = [NSUserDefaults.standardUserDefaults objectForKey:@"LCCertificateData"];
	} else {
		ans = [[[NSUserDefaults alloc] initWithSuiteName:[self appGroupID]] objectForKey:@"LCCertificateData"];
	}
	return ans;
}

+ (NSString*)certificatePassword {
	return [LCSharedUtilsClass certificatePassword];
}
+ (void)setCertificatePassword:(NSString*)certPassword {
	[NSUserDefaults.standardUserDefaults setObject:certPassword forKey:@"LCCertificatePassword"];
	[[[NSUserDefaults alloc] initWithSuiteName:[self appGroupID]] setObject:certPassword forKey:@"LCCertificatePassword"];
}

+ (NSString*)appGroupID {
	return [LCSharedUtilsClass appGroupID];
}

#pragma mark LCSharedUtils wrappers
+ (BOOL)launchToGuestApp {
	if ([[Utils getPrefs] boolForKey:@"MANUAL_REOPEN"])
		return NO;
	if (NSClassFromString(@"LCSharedUtils"))
		return NO;
	if (![Utils isSandboxed]) {
		NSString* appBundleIdentifier = @"com.robtop.geometryjump";
		[[LSApplicationWorkspace defaultWorkspace] openApplicationWithBundleID:appBundleIdentifier];
		return YES;
	}
	if (![[Utils getPrefs] boolForKey:@"JITLESS"] && ![LCUtils askForJIT])
		return YES;
	return [LCSharedUtilsClass launchToGuestApp];
}

+ (BOOL)askForJIT {
	return [LCSharedUtilsClass askForJIT];
}

#pragma mark Code signing

+ (void)loadStoreFrameworksWithError2:(NSError**)error {
	// too lazy to use dispatch_once
	static BOOL loaded = NO;
	if (loaded)
		return;

	void* handle = dlopen("@executable_path/Frameworks/ZSign.dylib", RTLD_GLOBAL);
	const char* dlerr = dlerror();
	if (!handle || (uint64_t)handle > 0xf00000000000) {
		if (dlerr) {
			AppLog(@"Failed to load ZSign: %s", dlerr);
		} else {
			AppLog(@"Failed to load ZSign: An unknown error occured.");
		}
	}

	loaded = YES;
}

+ (NSURL*)storeBundlePath {
	if ([self store] == SideStore) {
		return [self.appGroupPath URLByAppendingPathComponent:@"Apps/com.SideStore.SideStore/App.app"];
	} else {
		return [self.appGroupPath URLByAppendingPathComponent:@"Apps/com.rileytestut.AltStore/App.app"];
	}
}

+ (NSString*)storeInstallURLScheme {
	if ([self store] == SideStore) {
		return @"sidestore://install?url=%@";
	} else {
		return @"altstore://install?url=%@";
	}
}

+ (NSProgress*)signAppBundleWithZSign:(NSURL*)path completionHandler:(void (^)(BOOL success, NSError* error))completionHandler {
	NSError* error;

	// use zsign as our signer~
	NSURL* profilePath = [gcMainBundle URLForResource:@"embedded" withExtension:@"mobileprovision"];
	NSData* profileData = [NSData dataWithContentsOfURL:profilePath];
	if (profileData == nil) {
		AppLog(@"Couldn't read from mobile provisioning profile! Will assume to use embedded mobile provisioning file in documents.");
		profilePath = [[LCPath docPath] URLByAppendingPathComponent:@"embedded.mobileprovision"];
		profileData = [NSData dataWithContentsOfURL:profilePath];
	}

	if (profileData == nil) {
		completionHandler(NO, error);
		return nil;
	}

	// Load libraries from Documents, yeah
	[self loadStoreFrameworksWithError2:&error];

	if (error) {
		completionHandler(NO, error);
		return nil;
	}

	NSFileManager* fm = [NSFileManager defaultManager];
	NSURL* bundleProvision = [[LCPath bundlePath] URLByAppendingPathComponent:@"com.robtop.geometryjump.app/embedded.mobileprovision"];
	NSURL* provisionURL = [[LCPath docPath] URLByAppendingPathComponent:@"embedded.mobileprovision"];
	if ([[NSFileManager defaultManager] fileExistsAtPath:provisionURL.path]) {
		AppLog(@"Found provision in documents, copying to GD bundle...");
		if ([[NSFileManager defaultManager] fileExistsAtPath:bundleProvision.path]) {
			[[NSFileManager defaultManager] removeItemAtURL:bundleProvision error:&error];
			if (error) {
				completionHandler(NO, error);
				return nil;
			}
		}
		[fm copyItemAtURL:provisionURL toURL:bundleProvision error:&error];
		if (error) {
			completionHandler(NO, error);
			return nil;
		}
		AppLog(@"Copied provision to GD bundle.");
	}

	AppLog(@"starting signing...");

	NSProgress* ans = [NSClassFromString(@"ZSigner") signWithAppPath:[path path] prov:profileData key:self.certificateData pass:self.certificatePassword
												   completionHandler:completionHandler];

	return ans;
}

+ (NSString*)getCertTeamIdWithKeyData:(NSData*)keyData password:(NSString*)password {
	NSError* error;

	NSURL* profilePath = [gcMainBundle URLForResource:@"embedded" withExtension:@"mobileprovision"];
	NSData* profileData = [NSData dataWithContentsOfURL:profilePath];
	if (profileData == nil) {
		AppLog(@"Couldn't read from mobile provisioning profile! Will assume to use embedded mobile provisioning file in documents.");
		profilePath = [[LCPath docPath] URLByAppendingPathComponent:@"embedded.mobileprovision"];
		profileData = [NSData dataWithContentsOfURL:profilePath];
	}

	if (profileData == nil) {
		AppLog(@"Profile still couldn't be read. Assuming we don't have it...");
		return nil;
	}

	AppLog(@"Got Mobile Provisioning Profile data! %lu bytes", [profileData length]);

	[self loadStoreFrameworksWithError2:&error];
	if (error) {
		AppLog(@"Couldn't ZSign load framework: %@", error);
		return nil;
	}
	NSString* ans = [NSClassFromString(@"ZSigner") getTeamIdWithProv:profileData key:keyData pass:password];
	return ans;
}

+ (int)validateCertificate:(void (^)(int status, NSDate* expirationDate, NSString* error))completionHandler {
	NSError* error;
	NSURL* profilePath = [NSBundle.mainBundle URLForResource:@"embedded" withExtension:@"mobileprovision"];
	if (!profilePath) {
		profilePath = [[LCPath docPath] URLByAppendingPathComponent:@"embedded.mobileprovision"];
	}
	if (!profilePath) {
		int ans = 0;
		completionHandler(2, nil, @"Error loading cert or issuer");
		return ans;
	}
	NSData* profileData = [NSData dataWithContentsOfURL:profilePath options:0 error:&error];
	NSData* certData = [LCUtils certificateData];
	if (error) {
		return -6;
	}
	[self loadStoreFrameworksWithError2:&error];
	int ans = [NSClassFromString(@"ZSigner") checkCertWithProv:profileData key:certData pass:[LCUtils certificatePassword] ocsp:![[Utils getPrefs] boolForKey:@"JITLESS_OCSP"]
											 completionHandler:completionHandler];
	return ans;
}

#pragma mark Setup

+ (Store)store {
	static Store ans;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		AppLog(@"Store: %@", [self appGroupID]);
		if ([UTType typeWithIdentifier:[NSString stringWithFormat:@"io.sidestore.Installed.%@", NSBundle.mainBundle.bundleIdentifier]]) {
			ans = SideStore;
		} else if ([UTType typeWithIdentifier:[NSString stringWithFormat:@"io.altstore.Installed.%@", NSBundle.mainBundle.bundleIdentifier]]) {
			ans = AltStore;
		} else {
			ans = Unknown;
		}
		if (ans != Unknown)
			return;
		if ([[self appGroupID] containsString:@"AltStore"] && ![[self appGroupID] isEqualToString:@"group.com.rileytestut.AltStore"]) {
			ans = AltStore;
		} else if ([[self appGroupID] containsString:@"SideStore"] && ![[self appGroupID] isEqualToString:@"group.com.SideStore.SideStore"]) {
			ans = SideStore;
		} else {
			ans = Unknown;
		}
	});
	return ans;
}

+ (NSString*)appUrlScheme {
	return gcMainBundle.infoDictionary[@"CFBundleURLTypes"][0][@"CFBundleURLSchemes"][0];
}

+ (BOOL)isAppGroupAltStoreLike {
	if (NSClassFromString(@"LCSharedUtils"))
		return NO;
	if (self.appGroupID.length == 0)
		return NO;
	return [NSFileManager.defaultManager fileExistsAtPath:self.storeBundlePath.path];
}

+ (void)changeMainExecutableTo:(NSString*)exec error:(NSError**)error {
	NSURL* infoPath = [self.appGroupPath URLByAppendingPathComponent:@"Apps/com.geode.launcher/App.app/Info.plist"];
	NSMutableDictionary* infoDict = [NSMutableDictionary dictionaryWithContentsOfURL:infoPath];
	if (!infoDict)
		return;

	infoDict[@"CFBundleExecutable"] = exec;
	[infoDict writeToURL:infoPath error:error];
}

+ (void)validateJITLessSetup:(void (^)(BOOL success, NSError* error))completionHandler {
	// Verify that the certificate is usable
	// Create a test app bundle
	NSString* path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"CertificateValidation.app"];
	[NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
	NSString* tmpExecPath = [path stringByAppendingPathComponent:@"Geode.tmp"];
	NSString* tmpLibPath = [path stringByAppendingPathComponent:@"TestJITLess.dylib"];
	NSString* tmpInfoPath = [path stringByAppendingPathComponent:@"Info.plist"];
	[NSFileManager.defaultManager copyItemAtPath:NSBundle.mainBundle.executablePath toPath:tmpExecPath error:nil];
	[NSFileManager.defaultManager copyItemAtPath:[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Frameworks/TestJITLess.dylib"] toPath:tmpLibPath error:nil];
	NSMutableDictionary* info = NSBundle.mainBundle.infoDictionary.mutableCopy;
	info[@"CFBundleExecutable"] = @"Geode.tmp";
	[info writeToFile:tmpInfoPath atomically:YES];

	dispatch_semaphore_t sema = dispatch_semaphore_create(0);
	__block bool signSuccess = false;
	__block NSError* signError = nil;

	[LCUtils signAppBundleWithZSign:[NSURL fileURLWithPath:path] completionHandler:^(BOOL success, NSError* _Nullable error) {
		signSuccess = success;
		signError = error;
		dispatch_semaphore_signal(sema);
	}];
	dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
	dispatch_async(dispatch_get_main_queue(), ^{
		if (!signSuccess) {
			completionHandler(NO, signError);
		} else if (checkCodeSignature([tmpLibPath UTF8String])) {
			completionHandler(YES, signError);
		} else {
			completionHandler(NO, [NSError errorWithDomain:NSBundle.mainBundle.bundleIdentifier code:2 userInfo:nil]);
		}
	});
}

+ (NSURL*)archiveTweakedAltStoreWithError:(NSError**)error {
	return nil;
}

#pragma mark - Extensions of LCUtils
// ext
+ (NSUserDefaults*)appGroupUserDefault {
	NSString* suiteName = [self appGroupID];
	NSUserDefaults* userDefaults = [[NSUserDefaults alloc] initWithSuiteName:suiteName];
	return userDefaults ?: [Utils getPrefs];
}

+ (NSString*)getStoreName {
	switch (LCUtils.store) {
	case AltStore:
		return @"AltStore";
	case SideStore:
		return @"SideStore";
	default:
		return @"Unknown Store";
	}
}
+ (NSString*)getAppRunningLCScheme:(NSString*)bundleId {
	NSURL* infoPath = [[LCPath lcGroupDocPath] URLByAppendingPathComponent:@"appLock.plist"];
	NSDictionary* info = [NSDictionary dictionaryWithContentsOfURL:infoPath];
	if (!info) {
		return nil;
	}
	for (NSString* key in info) {
		NSString* value = info[key];
		if ([value isEqualToString:bundleId]) {
			if ([key isEqualToString:[self appUrlScheme]]) {
				return nil;
			}
			return key;
		}
	}
	return nil;
}

+ (void)signFilesInFolder:(NSURL*)url onProgressCreated:(void (^)(NSProgress* progress))onProgressCreated completion:(void (^)(NSString* error))completion {
	NSFileManager* fm = [NSFileManager defaultManager];
	NSURL* codesignPath = [url URLByAppendingPathComponent:@"_CodeSignature"];
	NSURL* provisionPath = [url URLByAppendingPathComponent:@"embedded.mobileprovision"];
	NSURL* tmpExecPath = [url URLByAppendingPathComponent:@"Geode.tmp"];
	NSURL* tmpInfoPath = [url URLByAppendingPathComponent:@"Info.plist"];
	NSMutableDictionary* info = [gcMainBundle.infoDictionary mutableCopy];
	[info setObject:@"Geode.tmp" forKey:@"CFBundleExecutable"];
	[info writeToURL:tmpInfoPath atomically:YES];

	NSError* copyError = nil;
	if (![fm copyItemAtURL:[gcMainBundle executableURL] toURL:tmpExecPath error:&copyError]) {
		completion(copyError.localizedDescription);
		return;
	}
	[self signAppBundleWithZSign:url completionHandler:^(BOOL success, NSError* error) {
		NSString* ans = nil;
		if (error) {
			ans = error.localizedDescription;
		}
		if ([fm fileExistsAtPath:codesignPath.path]) {
			[fm removeItemAtURL:codesignPath error:nil];
		}
		if ([fm fileExistsAtPath:provisionPath.path]) {
			[fm removeItemAtURL:provisionPath error:nil];
		}
		[fm removeItemAtURL:tmpExecPath error:nil];
		[fm removeItemAtURL:tmpInfoPath error:nil];
		completion(ans);
	}];
}
+ (void)signTweaks:(NSURL*)tweakFolderUrl force:(BOOL)force progressHandler:(void (^)(NSProgress* progress))progressHandler completion:(void (^)(NSError* error))completion {
	if (![self certificatePassword]) {
		completion([NSError errorWithDomain:@"CertificatePasswordMissing" code:0 userInfo:nil]);
		return;
	}

	NSFileManager* fm = [NSFileManager defaultManager];
	BOOL isDir = NO;
	if (![fm fileExistsAtPath:tweakFolderUrl.path isDirectory:&isDir] || !isDir) {
		completion([NSError errorWithDomain:@"InvalidTweakFolder" code:0 userInfo:nil]);
		return;
	}

	NSMutableDictionary* tweakSignInfo = [NSMutableDictionary dictionaryWithContentsOfURL:[tweakFolderUrl URLByAppendingPathComponent:@"TweakInfo.plist"]];
	BOOL signNeeded = force;
	if (!force) {
		NSMutableDictionary* tweakFileINodeRecord = [NSMutableDictionary dictionaryWithDictionary:[tweakSignInfo objectForKey:@"files"]];
		NSArray* fileURLs = [fm contentsOfDirectoryAtURL:tweakFolderUrl includingPropertiesForKeys:nil options:0 error:nil];

		for (NSURL* fileURL in fileURLs) {
			NSError* error = nil;
			NSDictionary* attributes = [fm attributesOfItemAtPath:fileURL.path error:&error];
			if (error)
				continue;
			NSString* fileType = attributes[NSFileType];
			if (![fileType isEqualToString:NSFileTypeDirectory] && ![fileType isEqualToString:NSFileTypeRegular])
				continue;
			if ([fileType isEqualToString:NSFileTypeDirectory] && ![[fileURL lastPathComponent] hasSuffix:@".framework"])
				continue;
			if ([fileType isEqualToString:NSFileTypeRegular] && ![[fileURL lastPathComponent] hasSuffix:@".dylib"])
				continue;
			if ([[fileURL lastPathComponent] isEqualToString:@"TweakInfo.plist"])
				continue;

			NSNumber* inodeNumber = [fm attributesOfItemAtPath:fileURL.path error:nil][NSFileSystemNumber];
			if ([tweakFileINodeRecord objectForKey:fileURL.lastPathComponent] != inodeNumber || checkCodeSignature([fileURL.path UTF8String])) {
				signNeeded = YES;
				break;
			}
			AppLog(@"%@", [fileURL lastPathComponent]);
		}
	} else {
		signNeeded = YES;
	}

	if (!signNeeded)
		return completion(nil);
	NSURL* tmpDir = [[fm temporaryDirectory] URLByAppendingPathComponent:@"TweakTmp.app"];
	if ([fm fileExistsAtPath:tmpDir.path]) {
		[fm removeItemAtURL:tmpDir error:nil];
	}
	[fm createDirectoryAtURL:tmpDir withIntermediateDirectories:YES attributes:nil error:nil];
	NSMutableArray* tmpPaths = [NSMutableArray array];
	NSArray* fileURLs = [fm contentsOfDirectoryAtURL:tweakFolderUrl includingPropertiesForKeys:nil options:0 error:nil];
	for (NSURL* fileURL in fileURLs) {
		NSError* error = nil;
		NSDictionary* attributes = [fm attributesOfItemAtPath:fileURL.path error:&error];
		if (error)
			continue;
		NSString* fileType = attributes[NSFileType];

		if (![fileType isEqualToString:NSFileTypeDirectory] && ![fileType isEqualToString:NSFileTypeRegular])
			continue;
		if ([fileType isEqualToString:NSFileTypeDirectory] && ![[fileURL lastPathComponent] hasSuffix:@".framework"])
			continue;
		if ([fileType isEqualToString:NSFileTypeRegular] && ![[fileURL lastPathComponent] hasSuffix:@".dylib"])
			continue;
		if ([[fileURL lastPathComponent] isEqualToString:@"TweakInfo.plist"])
			continue;

		NSURL* tmpPath = [tmpDir URLByAppendingPathComponent:fileURL.lastPathComponent];
		[tmpPaths addObject:tmpPath];
		[fm copyItemAtURL:fileURL toURL:tmpPath error:nil];
	}
	if ([tmpPaths count] == 0) {
		[fm removeItemAtURL:tmpDir error:nil];
		return completion(nil);
	}
	[self signFilesInFolder:tmpDir onProgressCreated:progressHandler completion:^(NSString* error) {
		if (error)
			return completion([NSError errorWithDomain:error code:0 userInfo:nil]);
		NSMutableDictionary* newTweakSignInfo = [NSMutableDictionary dictionary];
		NSMutableArray* fileInodes = [NSMutableArray array];
		for (NSURL* tmpFile in tmpPaths) {
			NSURL* toPath = [tweakFolderUrl URLByAppendingPathComponent:tmpFile.lastPathComponent];
			if ([fm fileExistsAtPath:toPath.path]) {
				[fm removeItemAtURL:toPath error:nil];
			}
			[fm moveItemAtURL:tmpFile toURL:toPath error:nil];

			NSNumber* inodeNumber = [fm attributesOfItemAtPath:toPath.path error:nil][NSFileSystemNumber];
			[fileInodes addObject:inodeNumber];
			[newTweakSignInfo setObject:inodeNumber forKey:tmpFile.lastPathComponent];
		}
		[fm removeItemAtURL:tmpDir error:nil];
		[newTweakSignInfo writeToURL:[tweakFolderUrl URLByAppendingPathComponent:@"TweakInfo.plist"] atomically:YES];
		completion(nil);
	}];
}

+ (BOOL)modifiedAtDifferent:(NSString*)datePath geodePath:(NSString*)geodePath {
	NSFileManager* fm = [NSFileManager defaultManager];
	NSError* error;
	NSString* currentHash = [NSString stringWithContentsOfFile:datePath encoding:NSUTF8StringEncoding error:&error];
	if (!currentHash)
		return NO;
	NSDictionary* attributes = [fm attributesOfItemAtPath:geodePath error:nil];
	NSDate* modifiedDate = [attributes objectForKey:NSFileModificationDate];
	if (!modifiedDate)
		return NO;
	NSTimeInterval interval = [modifiedDate timeIntervalSince1970];
	NSInteger modifiedMilliseconds = (NSInteger)(interval * 1000);
	NSString* modifiedHash = [NSString stringWithFormat:@"%ld", (long)modifiedMilliseconds];
	if ([currentHash isEqualToString:modifiedHash]) {
		return YES;
	}
	AppLog(@"Different hash detected, assuming to need signing: %@ / %@", currentHash, modifiedHash);
	return NO;
}

+ (void)signMods:(NSURL*)tweakFolderUrl force:(BOOL)force progressHandler:(void (^)(NSProgress* progress))progressHandler completion:(void (^)(NSError* error))completion {
	if (![self certificatePassword]) {
		completion([NSError errorWithDomain:@"CertificatePasswordMissing" code:0 userInfo:nil]);
		return;
	}
	NSFileManager* fm = [NSFileManager defaultManager];
	BOOL isDir = NO;
	if (![fm fileExistsAtPath:tweakFolderUrl.path isDirectory:&isDir] || !isDir) {
		completion(nil); // assume we haven't installed geode yet
		// completion([NSError errorWithDomain:@"InvalidModFolder" code:0 userInfo:nil]);
		return;
	}
	if (force) {
		[fm removeItemAtURL:[tweakFolderUrl URLByAppendingPathComponent:@"ModInfo.plist"] error:nil];
	}
	NSMutableDictionary* tweakSignInfo = [NSMutableDictionary dictionaryWithContentsOfURL:[tweakFolderUrl URLByAppendingPathComponent:@"ModInfo.plist"]];
	BOOL signNeeded = force;
	if (!force) {
		NSMutableDictionary* tweakFileINodeRecord = [NSMutableDictionary dictionaryWithDictionary:[tweakSignInfo objectForKey:@"files"]];
		NSArray* fileURLs = [fm contentsOfDirectoryAtURL:[tweakFolderUrl URLByAppendingPathComponent:@"unzipped"] includingPropertiesForKeys:nil options:0 error:nil];
		if (fileURLs) {
			for (NSURL* url in fileURLs) {
				NSError* error = nil;
				NSDictionary* attributes = [fm attributesOfItemAtPath:url.path error:&error];
				if (error)
					continue;
				NSString* fileType = attributes[NSFileType];
				if (![fileType isEqualToString:NSFileTypeDirectory])
					continue;
				NSArray* modContents = [fm contentsOfDirectoryAtURL:url includingPropertiesForKeys:nil options:0 error:nil];
				for (NSURL* fileURL in modContents) {
					NSDictionary* attributes = [fm attributesOfItemAtPath:fileURL.path error:&error];
					if (error)
						continue;
					NSString* fileType = attributes[NSFileType];
					if (![fileType isEqualToString:NSFileTypeDirectory] && ![fileType isEqualToString:NSFileTypeRegular])
						continue;
					if ([fileType isEqualToString:NSFileTypeRegular] && ![[fileURL lastPathComponent] hasSuffix:@".ios.dylib"])
						continue;
					if ([[fileURL lastPathComponent] isEqualToString:@"ModInfo.plist"])
						continue;

					NSNumber* inodeNumber = [fm attributesOfItemAtPath:fileURL.path error:nil][NSFileSystemNumber];
					if ([tweakFileINodeRecord objectForKey:fileURL.lastPathComponent] != inodeNumber || checkCodeSignature([fileURL.path UTF8String])) {
						signNeeded = YES;
						break;
					}
					if (![self modifiedAtDifferent:fileURL.path
										 geodePath:[tweakFolderUrl URLByAppendingPathComponent:[NSString stringWithFormat:@"mods/%@.geode",
																														  [[[url lastPathComponent] stringByDeletingPathExtension]
																															  stringByDeletingPathExtension]]]
													   .path]) {
						signNeeded = YES;
						break;
					}

					AppLog(@"%@", [fileURL lastPathComponent]);
				}
			}
		}
	} else {
		signNeeded = YES;
	}
	if (!signNeeded)
		return completion(nil);
	NSURL* tmpDir = [[fm temporaryDirectory] URLByAppendingPathComponent:@"ModTmp.app"];
	if ([fm fileExistsAtPath:tmpDir.path]) {
		[fm removeItemAtURL:tmpDir error:nil];
	}
	[fm createDirectoryAtURL:tmpDir withIntermediateDirectories:YES attributes:nil error:nil];
	NSMutableArray<NSURL*>* tmpPaths = [NSMutableArray array];
	NSArray* fileURLs = [fm contentsOfDirectoryAtURL:[tweakFolderUrl URLByAppendingPathComponent:@"unzipped"] includingPropertiesForKeys:nil options:0 error:nil];
	for (NSURL* url in fileURLs) {
		NSError* error = nil;
		NSDictionary* attributes = [fm attributesOfItemAtPath:url.path error:&error];
		if (error)
			continue;
		NSString* fileType = attributes[NSFileType];
		if (![fileType isEqualToString:NSFileTypeDirectory])
			continue;
		NSArray* modContents = [fm contentsOfDirectoryAtURL:url includingPropertiesForKeys:nil options:0 error:nil];
		for (NSURL* fileURL in modContents) {
			NSDictionary* attributes = [fm attributesOfItemAtPath:fileURL.path error:&error];
			if (error)
				continue;
			if ([attributes[NSFileType] isEqualToString:NSFileTypeRegular] && [[fileURL lastPathComponent] hasSuffix:@"ios.dylib"]) {
				NSURL* tmpPath = [tmpDir URLByAppendingPathComponent:fileURL.lastPathComponent];
				if (tmpPath) {
					[tmpPaths addObject:tmpPath];
					[fm copyItemAtURL:fileURL toURL:tmpPath error:nil];
				}
			}
		}
	}
	if ([tmpPaths count] == 0) {
		[fm removeItemAtURL:tmpDir error:nil];
		return completion(nil);
	}
	[self signFilesInFolder:tmpDir onProgressCreated:progressHandler completion:^(NSString* error) {
		if (error)
			return completion([NSError errorWithDomain:error code:0 userInfo:nil]);
		NSMutableDictionary* newTweakSignInfo = [NSMutableDictionary dictionary];
		NSMutableArray* fileInodes = [NSMutableArray array];
		for (NSURL* tmpFile in tmpPaths) {
			// NSURL *toPath = [tweakFolderUrl URLByAppendingPathComponent:tmpFile.lastPathComponent];
			NSURL* toPath =
				[tweakFolderUrl URLByAppendingPathComponent:[NSString stringWithFormat:@"unzipped/%@/%@",
																					   [[[tmpFile lastPathComponent] stringByDeletingPathExtension] stringByDeletingPathExtension],
																					   tmpFile.lastPathComponent]];
			AppLog(@"Signing %@", tmpFile.lastPathComponent);
			if ([fm fileExistsAtPath:toPath.path]) {
				[fm removeItemAtURL:toPath error:nil];
			}
			[fm moveItemAtURL:tmpFile toURL:toPath error:nil];
			NSNumber* inodeNumber = [fm attributesOfItemAtPath:toPath.path error:nil][NSFileSystemNumber];
			if (inodeNumber) {
				[fileInodes addObject:inodeNumber];
				[newTweakSignInfo setObject:inodeNumber forKey:tmpFile.lastPathComponent];
			}
		}
		[fm removeItemAtURL:tmpDir error:nil];
		[newTweakSignInfo writeToURL:[tweakFolderUrl URLByAppendingPathComponent:@"ModInfo.plist"] atomically:YES];
		completion(nil);
	}];
}
@end

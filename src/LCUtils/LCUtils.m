@import Darwin;
@import MachO;
@import UIKit;

#import "AltStoreCore/ALTSigner.h"
#import "LCUtils.h"
#import "Shared.h"
#import "ZSign/zsigner.h"
#import "src/Utils.h"
#import "src/components/LogUtils.h"
#import <MobileCoreServices/MobileCoreServices.h>

extern NSBundle* lcMainBundle;

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
	LCSharedUtilsClass = NSClassFromString(@"LCSharedUtils");
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
	if ([[Utils getPrefs] boolForKey:@"USE_TWEAK"] && [Utils isJailbroken]) {
		NSString* appBundleIdentifier = @"com.robtop.geometryjump";
		[[LSApplicationWorkspace defaultWorkspace] openApplicationWithBundleID:appBundleIdentifier];
		return YES;
	}
	if (![[Utils getPrefs] boolForKey:@"JITLESS_REMOVEMEANDTHEUNDERSCORE"] && ![LCUtils askForJIT])
		return YES;
	return [LCSharedUtilsClass launchToGuestApp];
}

+ (BOOL)askForJIT {
	return [LCSharedUtilsClass askForJIT];
}

+ (BOOL)launchToGuestAppWithURL:(NSURL*)url {
	return [LCSharedUtilsClass launchToGuestAppWithURL:url];
}

#pragma mark Code signing

+ (void)loadStoreFrameworksWithError:(NSError**)error {
	// too lazy to use dispatch_once
	static BOOL loaded = NO;
	if (loaded)
		return;

	NSArray* signerFrameworks;

	if ([NSFileManager.defaultManager fileExistsAtPath:[self.storeBundlePath URLByAppendingPathComponent:@"Frameworks/KeychainAccess.framework"].path]) {
		// AltStore requires 1 more framework than sidestore
		signerFrameworks = @[ @"OpenSSL.framework", @"Roxas.framework", @"KeychainAccess.framework", @"AltStoreCore.framework" ];
	} else {
		signerFrameworks = @[ @"OpenSSL.framework", @"Roxas.framework", @"AltStoreCore.framework" ];
	}

	NSURL* storeFrameworksPath = [self.storeBundlePath URLByAppendingPathComponent:@"Frameworks"];
	for (NSString* framework in signerFrameworks) {
		NSBundle* frameworkBundle = [NSBundle bundleWithURL:[storeFrameworksPath URLByAppendingPathComponent:framework]];
		if (!frameworkBundle) {
			// completionHandler(NO, error);
			abort();
		}
		[frameworkBundle loadAndReturnError:error];
		if (error && *error)
			return;
	}
	loaded = YES;
}

+ (void)loadStoreFrameworksWithError2:(NSError**)error {
	// too lazy to use dispatch_once
	static BOOL loaded = NO;
	if (loaded)
		return;

	dlopen("@executable_path/Frameworks/ZSign.dylib", RTLD_GLOBAL);

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

+ (void)removeCodeSignatureFromBundleURL:(NSURL*)appURL {
	int32_t cpusubtype;
	sysctlbyname("hw.cpusubtype", &cpusubtype, NULL, NULL, 0);

	NSDirectoryEnumerator* countEnumerator = [[NSFileManager defaultManager] enumeratorAtURL:appURL includingPropertiesForKeys:@[ NSURLIsRegularFileKey, NSURLFileSizeKey ]
																					 options:0 errorHandler:^BOOL(NSURL* _Nonnull url, NSError* _Nonnull error) {
																						 if (error) {
																							 AppLog(@"Error: %@ (%@)", error, url);
																							 return NO;
																						 }
																						 return YES;
																					 }];

	for (NSURL* fileURL in countEnumerator) {
		NSNumber* isFile = nil;
		if (![fileURL getResourceValue:&isFile forKey:NSURLIsRegularFileKey error:nil] || !isFile.boolValue) {
			continue;
		}

		NSNumber* fileSize = nil;
		[fileURL getResourceValue:&fileSize forKey:NSURLFileSizeKey error:nil];
		if (fileSize.unsignedLongLongValue < 0x4000) {
			continue;
		}

		// Remove LC_CODE_SIGNATURE
		NSString* error = LCParseMachO(fileURL.path.UTF8String, ^(const char* path, struct mach_header_64* header) {
			uint8_t* imageHeaderPtr = (uint8_t*)header + sizeof(struct mach_header_64);
			struct load_command* command = (struct load_command*)imageHeaderPtr;
			for (int i = 0; i < header->ncmds && header->ncmds > 0; i++) {
				if (command->cmd == LC_CODE_SIGNATURE) {
					struct linkedit_data_command* csCommand = (struct linkedit_data_command*)command;
					void* csData = (void*)((uint8_t*)header + csCommand->dataoff);
					// Nuke it.
					AppLog(@"Removing code signature of %@", fileURL);
					bzero(csData, csCommand->datasize);
					break;
				}
				command = (struct load_command*)((void*)command + command->cmdsize);
			}
		});
		if (error) {
			AppLog(@"Error: %@ (%@)", error, fileURL);
		}
	}
}

+ (NSProgress*)signAppBundle:(NSURL*)path completionHandler:(void (^)(BOOL success, NSDate* expirationDate, NSString* teamId, NSError* error))completionHandler {
	NSError* error;

	// I'm too lazy to reimplement signer, so let's borrow everything from SideStore
	// For sure this will break in the future as SideStore team planned to rewrite it
	NSURL* profilePath = [lcMainBundle URLForResource:@"embedded" withExtension:@"mobileprovision"];

	// Load libraries from Documents, yeah
	[self loadStoreFrameworksWithError:&error];
	if (error) {
		completionHandler(NO, nil, nil, error);
		return nil;
	}

	ALTCertificate* cert = [[NSClassFromString(@"ALTCertificate") alloc] initWithP12Data:self.certificateData password:self.certificatePassword];
	if (!cert) {
		error = [NSError errorWithDomain:lcMainBundle.bundleIdentifier code:1 userInfo:@{
			NSLocalizedDescriptionKey : @"Failed to create ALTCertificate. Please try: 1. make sure your store is patched 2. reopen your store 3. refresh all apps"
		}];
		completionHandler(NO, nil, nil, error);
		return nil;
	}
	ALTProvisioningProfile* profile = [[NSClassFromString(@"ALTProvisioningProfile") alloc] initWithURL:profilePath];
	if (!profile) {
		error = [NSError errorWithDomain:lcMainBundle.bundleIdentifier code:2 userInfo:@{
			NSLocalizedDescriptionKey : @"Failed to create ALTProvisioningProfile. Please try: 1. make sure your store is patched 2. reopen your store 3. refresh all apps"
		}];
		completionHandler(NO, nil, nil, error);
		return nil;
	}
	ALTAccount* account = [NSClassFromString(@"ALTAccount") new];
	ALTTeam* team = [[NSClassFromString(@"ALTTeam") alloc] initWithName:@"" identifier:@"" /*profile.teamIdentifier*/ type:ALTTeamTypeUnknown account:account];
	ALTSigner* signer = [[NSClassFromString(@"ALTSigner") alloc] initWithTeam:team certificate:cert];

	void (^signCompletionHandler)(BOOL success, NSError* error) =
		^(BOOL success, NSError* _Nullable error) { completionHandler(success, [profile expirationDate], [profile teamIdentifier], error); };
	return [signer signAppAtURL:path provisioningProfiles:@[ (id)profile ] completionHandler:signCompletionHandler];
}

+ (NSProgress*)signAppBundleWithZSign:(NSURL*)path completionHandler:(void (^)(BOOL success, NSDate* expirationDate, NSString* teamId, NSError* error))completionHandler {
	NSError* error;

	// use zsign as our signer~
	NSURL* profilePath = [lcMainBundle URLForResource:@"embedded" withExtension:@"mobileprovision"];
	NSData* profileData = [NSData dataWithContentsOfURL:profilePath];
	if (profileData == nil) {
		AppLog(@"Couldn't read from mobile provisioning profile! Will assume to use embedded mobile provisioning file in documents.");
		profilePath = [[LCPath docPath] URLByAppendingPathComponent:@"embedded.mobileprovision"];
		profileData = [NSData dataWithContentsOfURL:profilePath];
	}

	if (profileData == nil) {
		completionHandler(NO, nil, nil, error);
		return nil;
	}

	// Load libraries from Documents, yeah
	[self loadStoreFrameworksWithError2:&error];

	if (error) {
		completionHandler(NO, nil, nil, error);
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
				completionHandler(NO, nil, nil, error);
				return nil;
			}
		}
		[fm copyItemAtURL:provisionURL toURL:bundleProvision error:&error];
		if (error) {
			completionHandler(NO, nil, nil, error);
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

	NSURL* profilePath = [lcMainBundle URLForResource:@"embedded" withExtension:@"mobileprovision"];
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

#pragma mark Setup

+ (Store)store {
	static Store ans;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		AppLog(@"Store: %@", [self appGroupID]);
		if ([[self appGroupID] containsString:@"AltStore"]) {
			ans = AltStore;
		} else {
			ans = SideStore;
		}
	});
	return ans;
}

+ (NSString*)appUrlScheme {
	return lcMainBundle.infoDictionary[@"CFBundleURLTypes"][0][@"CFBundleURLSchemes"][0];
}

+ (BOOL)isAppGroupAltStoreLike {
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

+ (void)writeStoreIDToSetupExecutableWithError:(NSError**)error {
	NSURL* execPath = [self.appGroupPath URLByAppendingPathComponent:@"Apps/com.geode.launcher/App.app/JITLessSetup"];
	NSMutableData* data = [NSMutableData dataWithContentsOfURL:execPath options:0 error:error];
	if (!data)
		return;

	// We must get SideStore's exact application-identifier, otherwise JIT-less setup will bug out to hell for using the wrong, expired certificate
	[self loadStoreFrameworksWithError:nil];
	NSURL* profilePath = [self.storeBundlePath URLByAppendingPathComponent:@"embedded.mobileprovision"];
	ALTProvisioningProfile* profile = [[NSClassFromString(@"ALTProvisioningProfile") alloc] initWithURL:profilePath];
	NSString* storeKeychainID = profile.entitlements[@"application-identifier"];
	assert(storeKeychainID);

	NSData* findPattern = [@"KeychainAccessGroupWillBeWrittenByGeodeLauncherAAAAAAAAAAAAAAAAAAAA</string>" dataUsingEncoding:NSUTF8StringEncoding];
	NSRange range = [data rangeOfData:findPattern options:0 range:NSMakeRange(0, data.length)];
	if (range.location == NSNotFound)
		return;

	memset((char*)data.mutableBytes + range.location, ' ', range.length);
	NSString* replacement = [NSString stringWithFormat:@"%@</string>", storeKeychainID];
	assert(replacement.length < range.length);
	memcpy((char*)data.mutableBytes + range.location, replacement.UTF8String, replacement.length);
	[data writeToURL:execPath options:0 error:error];
}

+ (void)validateJITLessSetupWithSigner:(Signer)signer completionHandler:(void (^)(BOOL success, NSError* error))completionHandler {
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

	// Sign the test app bundle
	if (signer == AltSign && ![[Utils getPrefs] boolForKey:@"LCCertificateImported"]) {
		[LCUtils signAppBundle:[NSURL fileURLWithPath:path] completionHandler:^(BOOL success, NSDate* expirationDate, NSString* teamId, NSError* _Nullable error) {
			dispatch_async(dispatch_get_main_queue(), ^{ completionHandler(success, error); });
		}];
	} else {
		[LCUtils signAppBundleWithZSign:[NSURL fileURLWithPath:path] completionHandler:^(BOOL success, NSDate* expirationDate, NSString* teamId, NSError* _Nullable error) {
			dispatch_async(dispatch_get_main_queue(), ^{ completionHandler(success, error); });
		}];
	}
}

+ (NSURL*)archiveIPAWithBundleName:(NSString*)newBundleName error:(NSError**)error {
	if (*error)
		return nil;

	NSFileManager* manager = NSFileManager.defaultManager;
	NSURL* appGroupPath = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:self.appGroupID];
	NSURL* bundlePath = [appGroupPath URLByAppendingPathComponent:@"Apps/com.geode.launcher"];

	NSURL* tmpPath = [appGroupPath URLByAppendingPathComponent:@"tmp"];
	[manager removeItemAtURL:tmpPath error:nil];

	NSURL* tmpPayloadPath = [tmpPath URLByAppendingPathComponent:@"Payload"];
	NSURL* tmpIPAPath = [appGroupPath URLByAppendingPathComponent:@"tmp.ipa"];

	[manager createDirectoryAtURL:tmpPath withIntermediateDirectories:YES attributes:nil error:error];
	if (*error)
		return nil;

	[manager copyItemAtURL:bundlePath toURL:tmpPayloadPath error:error];
	if (*error)
		return nil;

	NSURL* infoPath = [tmpPayloadPath URLByAppendingPathComponent:@"App.app/Info.plist"];
	NSMutableDictionary* infoDict = [NSMutableDictionary dictionaryWithContentsOfURL:infoPath];
	if (!infoDict)
		return nil;

	infoDict[@"CFBundleDisplayName"] = newBundleName;
	infoDict[@"CFBundleName"] = newBundleName;
	infoDict[@"CFBundleIdentifier"] = [NSString stringWithFormat:@"com.kdt.%@", newBundleName];
	infoDict[@"CFBundleURLTypes"][0][@"CFBundleURLSchemes"][0] = [newBundleName lowercaseString];
	infoDict[@"CFBundleIcons~ipad"][@"CFBundlePrimaryIcon"][@"CFBundleIconFiles"][0] = @"AppIcon60x60_2";
	infoDict[@"CFBundleIcons~ipad"][@"CFBundlePrimaryIcon"][@"CFBundleIconFiles"][1] = @"AppIcon76x76_2";
	infoDict[@"CFBundleIcons"][@"CFBundlePrimaryIcon"][@"CFBundleIconFiles"][0] = @"AppIcon60x60_2";
	// reset a executable name so they don't look the same on the log
	NSURL* appBundlePath = [tmpPayloadPath URLByAppendingPathComponent:@"App.app"];

	NSURL* execFromPath = [appBundlePath URLByAppendingPathComponent:infoDict[@"CFBundleExecutable"]];
	infoDict[@"CFBundleExecutable"] = @"GeodeLauncher_PleaseDoNotShortenTheExecutableNameBecauseItIsUsedToReserveSpaceForOverwritingThankYou2";
	NSURL* execToPath = [appBundlePath URLByAppendingPathComponent:infoDict[@"CFBundleExecutable"]];

	[manager moveItemAtURL:execFromPath toURL:execToPath error:error];
	if (*error) {
		AppLog(@"%@", *error);
		return nil;
	}

	// We have to change executable's UUID so iOS won't consider 2 executables the same
	NSString* errorChangeUUID = LCParseMachO([execToPath.path UTF8String], ^(const char* path, struct mach_header_64* header) { LCChangeExecUUID(header); });
	if (errorChangeUUID) {
		NSMutableDictionary* details = [NSMutableDictionary dictionary];
		[details setValue:errorChangeUUID forKey:NSLocalizedDescriptionKey];
		// populate the error object with the details
		*error = [NSError errorWithDomain:@"world" code:200 userInfo:details];
		AppLog(@"%@", errorChangeUUID);
		return nil;
	}

	[infoDict writeToURL:infoPath error:error];

	dlopen("/System/Library/PrivateFrameworks/PassKitCore.framework/PassKitCore", RTLD_GLOBAL);
	NSData* zipData = [[NSClassFromString(@"PKZipArchiver") new] zippedDataForURL:tmpPayloadPath.URLByDeletingLastPathComponent];
	if (!zipData)
		return nil;

	[manager removeItemAtURL:tmpPath error:error];
	if (*error)
		return nil;

	[zipData writeToURL:tmpIPAPath options:0 error:error];
	if (*error)
		return nil;

	return tmpIPAPath;
}

+ (NSURL*)archiveTweakedAltStoreWithError:(NSError**)error {
	if (*error)
		return nil;

	NSFileManager* manager = NSFileManager.defaultManager;
	NSURL* appGroupPath = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:self.appGroupID];
	if (!appGroupPath) {
		NSDictionary* userInfo = @{ NSLocalizedDescriptionKey : @"Unable to access App Group. Please check JITLess diagnose page for more information." };
		*error = [NSError errorWithDomain:@"Unable to Access App Group" code:-1 userInfo:userInfo];
		return nil;
	}

	NSURL* lcBundlePath = [appGroupPath URLByAppendingPathComponent:@"Apps/com.geode.launcher"];
	NSURL* bundlePath;
	if ([self store] == SideStore) {
		bundlePath = [appGroupPath URLByAppendingPathComponent:@"Apps/com.SideStore.SideStore"];
	} else {
		bundlePath = [appGroupPath URLByAppendingPathComponent:@"Apps/com.rileytestut.AltStore"];
	}

	NSURL* tmpPath = [appGroupPath URLByAppendingPathComponent:@"tmp"];
	[manager removeItemAtURL:tmpPath error:nil];

	NSURL* tmpPayloadPath = [tmpPath URLByAppendingPathComponent:@"Payload"];
	NSURL* tmpIPAPath = [appGroupPath URLByAppendingPathComponent:@"tmp.ipa"];

	[manager createDirectoryAtURL:tmpPath withIntermediateDirectories:YES attributes:nil error:error];
	if (*error)
		return nil;

	[manager copyItemAtURL:bundlePath toURL:tmpPayloadPath error:error];
	if (*error)
		return nil;

	// copy altstore tweak
	NSURL* tweakToURL = [tmpPayloadPath URLByAppendingPathComponent:@"App.app/Frameworks/AltStoreTweak.dylib"];
	if ([manager fileExistsAtPath:tweakToURL.path]) {
		[manager removeItemAtURL:tweakToURL error:error];
	}

	[manager copyItemAtURL:[lcBundlePath URLByAppendingPathComponent:@"App.app/Frameworks/AltStoreTweak.dylib"] toURL:tweakToURL error:error];
	NSURL* execToPatch;
	if ([self store] == SideStore) {
		execToPatch = [tmpPayloadPath URLByAppendingPathComponent:@"App.app/SideStore"];
	} else {
		execToPatch = [tmpPayloadPath URLByAppendingPathComponent:@"App.app/AltStore"];
		;
	}

	NSString* errorPatchAltStore =
		LCParseMachO([execToPatch.path UTF8String], ^(const char* path, struct mach_header_64* header) { LCPatchAltStore(execToPatch.path.UTF8String, header); });
	if (errorPatchAltStore) {
		NSMutableDictionary* details = [NSMutableDictionary dictionary];
		[details setValue:errorPatchAltStore forKey:NSLocalizedDescriptionKey];
		// populate the error object with the details
		*error = [NSError errorWithDomain:@"world" code:200 userInfo:details];
		AppLog(@"%@", errorPatchAltStore);
		return nil;
	}

	dlopen("/System/Library/PrivateFrameworks/PassKitCore.framework/PassKitCore", RTLD_GLOBAL);
	NSData* zipData = [[NSClassFromString(@"PKZipArchiver") new] zippedDataForURL:tmpPayloadPath.URLByDeletingLastPathComponent];
	if (!zipData)
		return nil;

	[manager removeItemAtURL:tmpPath error:error];
	if (*error)
		return nil;

	[zipData writeToURL:tmpIPAPath options:0 error:error];
	if (*error)
		return nil;

	return tmpIPAPath;
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

+ (void)signFilesInFolder:(NSURL*)url
				   signer:(Signer)signer
		onProgressCreated:(void (^)(NSProgress* progress))onProgressCreated
			   completion:(void (^)(NSString* error, NSDate* expirationDate))completion {
	NSFileManager* fm = [NSFileManager defaultManager];
	NSURL* codesignPath = [url URLByAppendingPathComponent:@"_CodeSignature"];
	NSURL* provisionPath = [url URLByAppendingPathComponent:@"embedded.mobileprovision"];
	NSURL* tmpExecPath = [url URLByAppendingPathComponent:@"Geode.tmp"];
	NSURL* tmpInfoPath = [url URLByAppendingPathComponent:@"Info.plist"];
	NSMutableDictionary* info = [lcMainBundle.infoDictionary mutableCopy];
	[info setObject:@"Geode.tmp" forKey:@"CFBundleExecutable"];
	[info writeToURL:tmpInfoPath atomically:YES];

	NSError* copyError = nil;
	if (![fm copyItemAtURL:[lcMainBundle executableURL] toURL:tmpExecPath error:&copyError]) {
		completion(copyError.localizedDescription, nil);
		return;
	}
	if (signer == AltSign) {
		[self signAppBundle:url completionHandler:^(BOOL success, NSDate* expirationDate, NSString* teamId, NSError* error) {
			NSString* ans = nil;
			NSDate* ansDate = nil;
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
			ansDate = expirationDate;
			completion(ans, ansDate);
		}];
	} else {
		[self signAppBundleWithZSign:url completionHandler:^(BOOL success, NSDate* expirationDate, NSString* teamId, NSError* error) {
			NSString* ans = nil;
			NSDate* ansDate = nil;
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
			ansDate = expirationDate;
			completion(ans, ansDate);
		}];
	}
}
+ (void)signTweaks:(NSURL*)tweakFolderUrl
			  force:(BOOL)force
			 signer:(Signer)signer
	progressHandler:(void (^)(NSProgress* progress))progressHandler
		 completion:(void (^)(NSError* error))completion {
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
	NSDate* expirationDate = [tweakSignInfo objectForKey:@"expirationDate"];
	BOOL signNeeded = force;
	if (!force && expirationDate && [expirationDate compare:[NSDate date]] == NSOrderedDescending) {
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
			if ([tweakFileINodeRecord objectForKey:fileURL.lastPathComponent] != inodeNumber) {
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
	[self signFilesInFolder:tmpDir signer:signer onProgressCreated:progressHandler completion:^(NSString* error, NSDate* expirationDate2) {
		if (error)
			return completion([NSError errorWithDomain:error code:0 userInfo:nil]);
		NSMutableDictionary* newTweakSignInfo = [NSMutableDictionary dictionary];
		newTweakSignInfo[@"expirationDate"] = expirationDate2;
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

+ (void)signMods:(NSURL*)tweakFolderUrl
			  force:(BOOL)force
			 signer:(Signer)signer
	progressHandler:(void (^)(NSProgress* progress))progressHandler
		 completion:(void (^)(NSError* error))completion {
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

	NSMutableDictionary* tweakSignInfo = [NSMutableDictionary dictionaryWithContentsOfURL:[tweakFolderUrl URLByAppendingPathComponent:@"ModInfo.plist"]];
	NSDate* expirationDate = [tweakSignInfo objectForKey:@"expirationDate"];
	BOOL signNeeded = force;
	if (!force && expirationDate && [expirationDate compare:[NSDate date]] == NSOrderedDescending) {
		NSMutableDictionary* tweakFileINodeRecord = [NSMutableDictionary dictionaryWithDictionary:[tweakSignInfo objectForKey:@"files"]];
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
				if ([tweakFileINodeRecord objectForKey:fileURL.lastPathComponent] != inodeNumber) {
					signNeeded = YES;
					break;
				}
				if (![self modifiedAtDifferent:fileURL.path
									 geodePath:[tweakFolderUrl
												   URLByAppendingPathComponent:[NSString stringWithFormat:@"mods/%@.geode", [[[url lastPathComponent] stringByDeletingPathExtension]
																																stringByDeletingPathExtension]]]
												   .path]) {
					signNeeded = YES;
					break;
				}

				AppLog(@"%@", [fileURL lastPathComponent]);
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
	NSMutableArray* tmpPaths = [NSMutableArray array];
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
	}
	if ([tmpPaths count] == 0) {
		[fm removeItemAtURL:tmpDir error:nil];
		return completion(nil);
	}
	[self signFilesInFolder:tmpDir signer:signer onProgressCreated:progressHandler completion:^(NSString* error, NSDate* expirationDate2) {
		if (error)
			return completion([NSError errorWithDomain:error code:0 userInfo:nil]);
		NSMutableDictionary* newTweakSignInfo = [NSMutableDictionary dictionary];
		newTweakSignInfo[@"expirationDate"] = expirationDate2;
		NSMutableArray* fileInodes = [NSMutableArray array];
		for (NSURL* tmpFile in tmpPaths) {
			// NSURL *toPath = [tweakFolderUrl URLByAppendingPathComponent:tmpFile.lastPathComponent];
			NSURL* toPath =
				[tweakFolderUrl URLByAppendingPathComponent:[NSString stringWithFormat:@"unzipped/%@/%@",
																					   [[[tmpFile lastPathComponent] stringByDeletingPathExtension] stringByDeletingPathExtension],
																					   tmpFile.lastPathComponent]];
			if ([fm fileExistsAtPath:toPath.path]) {
				[fm removeItemAtURL:toPath error:nil];
			}
			[fm moveItemAtURL:tmpFile toURL:toPath error:nil];
			NSNumber* inodeNumber = [fm attributesOfItemAtPath:toPath.path error:nil][NSFileSystemNumber];
			[fileInodes addObject:inodeNumber];
			[newTweakSignInfo setObject:inodeNumber forKey:tmpFile.lastPathComponent];
		}
		[fm removeItemAtURL:tmpDir error:nil];
		[newTweakSignInfo writeToURL:[tweakFolderUrl URLByAppendingPathComponent:@"ModInfo.plist"] atomically:YES];
		completion(nil);
	}];
}
@end

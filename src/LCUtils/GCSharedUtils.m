#import "GCSharedUtils.h"
#import "UIKitPrivate.h"
#import "src/LCUtils/LCAppInfo.h"
#import "src/LCUtils/LCUtils.h"
#import "src/LCUtils/Shared.h"
#import "src/Utils.h"
#import "src/components/LogUtils.h"

extern NSUserDefaults* gcUserDefaults;
extern NSString* gcAppUrlScheme;
extern NSBundle* gcMainBundle;

@implementation GCSharedUtils

+ (NSString*)liveContainerBundleID {
	if (NSClassFromString(@"LCSharedUtils")) {
		NSString* lastID = [NSClassFromString(@"LCSharedUtils") teamIdentifier];
		if (lastID == nil)
			return nil;
		if ([lastID isEqualToString:@"livecontainer"])
			return @"com.kdt.livecontainer";
		return [NSString stringWithFormat:@"com.kdt.livecontainer.%@", lastID];
	} else {
		return nil;
	}
}

+ (NSString*)teamIdentifier {
	static NSString* ans = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{ ans = [[gcMainBundle.bundleIdentifier componentsSeparatedByString:@"."] lastObject]; });
	return ans;
}

+ (NSString*)appGroupID {
	static dispatch_once_t once;
	static NSString* appGroupID = @"Unknown";
	dispatch_once(&once, ^{
		NSArray* possibleAppGroups = @[
			[@"group.com.SideStore.SideStore." stringByAppendingString:[self teamIdentifier]], [@"group.com.rileytestut.AltStore." stringByAppendingString:[self teamIdentifier]],
			@"group.com.SideStore.SideStore", @"group.com.rileytestut.AltStore"
		];

		for (NSString* group in possibleAppGroups) {
			NSURL* path = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:group];
			if (!path)
				continue;
			NSURL* bundlePath = [path URLByAppendingPathComponent:@"Apps/com.geode.launcher/App.app"];
			if ([NSFileManager.defaultManager fileExistsAtPath:bundlePath.path]) {
				// This will fail if LiveContainer is installed in both stores, but it should never be the case
				appGroupID = group;
				return;
			}
		}
		// if no "Apps" is found, we choose a valid group
		for (NSString* group in possibleAppGroups) {
			NSURL* path = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:group];
			if (!path) {
				continue;
			}
			appGroupID = group;
			return;
		}
	});
	return appGroupID;
}

+ (NSURL*)appGroupPath {
	static NSURL* appGroupPath = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{ appGroupPath = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:[GCSharedUtils appGroupID]]; });
	return appGroupPath;
}

+ (NSString*)certificatePassword {
	if ([gcUserDefaults boolForKey:@"LCCertificateImported"]) {
		NSString* ans = [gcUserDefaults objectForKey:@"LCCertificatePassword"];
		return ans;
	} else {
		// password of cert retrieved from the store tweak is always @"". We just keep this function so we can check if certificate presents without changing codes.
		return [[[NSUserDefaults alloc] initWithSuiteName:[self appGroupID]] objectForKey:@"LCCertificatePassword"];
	}
}

+ (BOOL)launchToGuestAppWithURL:(NSURL*)url {
	return NO;
}

+ (void)relaunchApp {
	[gcUserDefaults setValue:[Utils gdBundleName] forKey:@"selected"];
	[gcUserDefaults setValue:@"GeometryDash" forKey:@"selectedContainer"];
	if (NSClassFromString(@"LCSharedUtils")) {
		[gcUserDefaults synchronize];
		NSFileManager* fm = [NSFileManager defaultManager];

		[fm createFileAtPath:[[LCPath docPath].path stringByAppendingPathComponent:@"../../../../jitflag"] contents:[[NSData alloc] init] attributes:@{}];
		UIApplication* application = [NSClassFromString(@"UIApplication") sharedApplication];
		// assume livecontainer
		NSURL* launchURL = [NSURL URLWithString:[NSString stringWithFormat:@"livecontainer://livecontainer-launch?bundle-name=%@.app", gcMainBundle.bundleIdentifier]];
		NSURL* launchURL2 = [NSURL URLWithString:[NSString stringWithFormat:@"livecontainer2://livecontainer-launch?bundle-name=%@.app", gcMainBundle.bundleIdentifier]];
		AppLog(@"Attempting to launch geode with %@", launchURL);

		// since for some reason it doesnt do a JIT check for launchToGuestAppWithURL, otherwise itll error with "jit isn't enabled! wanna enable jitless?". Fix it!
		[NSClassFromString(@"LCSharedUtils") launchToGuestApp];
		return;
		if ([application canOpenURL:launchURL]) {
			[NSClassFromString(@"LCSharedUtils") launchToGuestAppWithURL:launchURL];
			/*dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
				[application openURL:launchURL options:@{} completionHandler:^(BOOL b) {
					exit(0);
					// weird trickery, never mind it causes a crash!
					/\*if (![NSClassFromString(@"LCSharedUtils") askForJIT])
						return;
					[NSClassFromString(@"LCSharedUtils") launchToGuestApp];*\/
				}];
			});*/
		} else if ([application canOpenURL:launchURL2]) {
			[NSClassFromString(@"LCSharedUtils") launchToGuestAppWithURL:launchURL2];
		}
		return;
	}
	if (![Utils isSandboxed]) {
		NSString* appBundleIdentifier = @"com.robtop.geometryjump";
		[[LSApplicationWorkspace defaultWorkspace] openApplicationWithBundleID:appBundleIdentifier];
		exit(0);
		return;
	}
	if ([gcUserDefaults boolForKey:@"JITLESS_REMOVEMEANDTHEUNDERSCORE"]) {
		[LCUtils signMods:[[LCPath docPath] URLByAppendingPathComponent:@"game/geode"] force:NO progressHandler:^(NSProgress* progress) {} completion:^(NSError* error) {
			if (error != nil) {
				AppLog(@"Detailed error for signing mods: %@", error);
			}
			[LCUtils launchToGuestApp];
		}];
	} else {
		if (![GCSharedUtils askForJIT])
			return;
		[GCSharedUtils launchToGuestApp];
	}
}

+ (BOOL)launchToGuestApp {
	UIApplication* application = [NSClassFromString(@"UIApplication") sharedApplication];
	NSString* urlScheme;
	int tries = 1;
	if (NSClassFromString(@"LCSharedUtils")) {
		// urlScheme = @"livecontainer://livecontainer-launch?bundle-name=%@.app";
	} else {
		NSInteger jitEnabler = [gcUserDefaults integerForKey:@"JIT_ENABLER"];
		if (!jitEnabler)
			jitEnabler = 0;
		NSString* tsPath = [NSString stringWithFormat:@"%@/../_TrollStore", gcMainBundle.bundlePath];
		if ((jitEnabler == 0 && !access(tsPath.UTF8String, F_OK)) || jitEnabler == 1) {
			urlScheme = @"apple-magnifier://enable-jit?bundle-id=%@";
		} else if ((jitEnabler == 0 && [application canOpenURL:[NSURL URLWithString:@"stikjit://"]]) || jitEnabler == 2) {
			urlScheme = @"stikjit://enable-jit?bundle-id=%@";
		} else if ((jitEnabler == 0 && [application canOpenURL:[NSURL URLWithString:@"sidestore://"]]) || jitEnabler == 5) {
			urlScheme = @"sidestore://sidejit-enable?bid=%@";
		} else if (self.certificatePassword) {
			tries = 2;
			urlScheme = [NSString stringWithFormat:@"%@://geode-relaunch", gcAppUrlScheme];
		} else {
			tries = 2;
			urlScheme = [NSString stringWithFormat:@"%@://geode-relaunch", gcAppUrlScheme];
		}
	}
	NSURL* launchURL = [NSURL URLWithString:[NSString stringWithFormat:urlScheme, gcMainBundle.bundleIdentifier]];
	AppLog(@"Attempting to launch geode with %@", launchURL);
	if ([application canOpenURL:launchURL]) {
		//[UIApplication.sharedApplication suspend];
		for (int i = 0; i < tries; i++) {
			[application openURL:launchURL options:@{} completionHandler:^(BOOL b) { exit(0); }];
		}
		return YES;
	}
	return NO;
}

+ (BOOL)askForJIT {
	NSInteger jitEnabler = [gcUserDefaults integerForKey:@"JIT_ENABLER"];
	if (!jitEnabler)
		jitEnabler = 0;
	if (jitEnabler != 3 && jitEnabler != 4)
		return YES;
	NSString* sideJITServerAddress = [gcUserDefaults objectForKey:@"SideJITServerAddr"];
	NSString* deviceUDID = [gcUserDefaults objectForKey:@"JITDeviceUDID"];
	if (!sideJITServerAddress || (!deviceUDID && jitEnabler == 4)) {
		[Utils showErrorGlobal:@"Server Address not set." error:nil];
		return NO;
	}
	NSString* launchJITUrlStr = [NSString stringWithFormat:@"%@/launch_app/%@", sideJITServerAddress, gcMainBundle.bundleIdentifier];
	if (jitEnabler == 4) {
		launchJITUrlStr = [NSString stringWithFormat:@"%@/%@/%@", sideJITServerAddress, deviceUDID, gcMainBundle.bundleIdentifier];
	}
	AppLog(@"Launching the app with URL: %@", launchJITUrlStr);
	NSURLSession* session = [NSURLSession sharedSession];
	NSURL* launchJITUrl = [NSURL URLWithString:launchJITUrlStr];
	NSURLRequest* req = [[NSURLRequest alloc] initWithURL:launchJITUrl];
	NSURLSessionDataTask* task = [session dataTaskWithRequest:req completionHandler:^(NSData* _Nullable data, NSURLResponse* _Nullable response, NSError* _Nullable error) {
		if (error) {
			return dispatch_async(dispatch_get_main_queue(), ^{
				[Utils showErrorGlobal:[NSString stringWithFormat:@"(%@) Failed to contact JITStreamer.\nIf you don't have JITStreamer-EB, disable Auto JIT and use \"Manual "
																  @"reopen with JIT\" if launching doesn't work.",
																  launchJITUrlStr]
								 error:error];
				AppLog(@"Tried connecting with %@, failed to contact JITStreamer: %@", launchJITUrlStr, error);
			});
		}
	}];
	[task resume];
	return NO;
}

+ (void)setWebPageUrlForNextLaunch:(NSString*)urlString {
	[gcUserDefaults setObject:urlString forKey:@"webPageToOpen"];
}

+ (NSURL*)containerLockPath {
	static dispatch_once_t once;
	static NSURL* infoPath;

	dispatch_once(&once, ^{ infoPath = [[GCSharedUtils appGroupPath] URLByAppendingPathComponent:@"Geode/containerLock.plist"]; });
	return infoPath;
}

+ (NSString*)getContainerUsingLCSchemeWithFolderName:(NSString*)folderName {
	NSURL* infoPath = [self containerLockPath];
	NSMutableDictionary* info = [NSMutableDictionary dictionaryWithContentsOfFile:infoPath.path];
	if (!info) {
		return nil;
	}
	for (NSString* key in info) {
		if ([folderName isEqualToString:info[key]]) {
			if ([key isEqualToString:gcAppUrlScheme]) {
				return nil;
			}
			return key;
		}
	}
	return nil;
}

// move app data to private folder to prevent 0xdead10cc https://forums.developer.apple.com/forums/thread/126438
+ (void)moveSharedAppFolderBack {
	NSFileManager* fm = NSFileManager.defaultManager;
	NSURL* libraryPathUrl = [fm URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask].lastObject;
	NSURL* docPathUrl = [fm URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].lastObject;
	NSURL* appGroupFolder = [[GCSharedUtils appGroupPath] URLByAppendingPathComponent:@"Geode"];

	NSError* error;
	NSString* sharedAppDataFolderPath = [libraryPathUrl.path stringByAppendingPathComponent:@"SharedDocuments"];
	if (![fm fileExistsAtPath:sharedAppDataFolderPath]) {
		[fm createDirectoryAtPath:sharedAppDataFolderPath withIntermediateDirectories:YES attributes:@{} error:&error];
	}
	// move all apps in shared folder back
	NSArray<NSString*>* sharedDataFoldersToMove = [fm contentsOfDirectoryAtPath:sharedAppDataFolderPath error:&error];
	for (int i = 0; i < [sharedDataFoldersToMove count]; ++i) {
		NSString* destPath = [appGroupFolder.path stringByAppendingPathComponent:[NSString stringWithFormat:@"Data/Application/%@", sharedDataFoldersToMove[i]]];
		if ([fm fileExistsAtPath:destPath]) {
			[fm moveItemAtPath:[sharedAppDataFolderPath stringByAppendingPathComponent:sharedDataFoldersToMove[i]]
						toPath:[docPathUrl.path stringByAppendingPathComponent:[NSString stringWithFormat:@"FOLDER_EXISTS_AT_APP_GROUP_%@", sharedDataFoldersToMove[i]]]
						 error:&error];

		} else {
			[fm moveItemAtPath:[sharedAppDataFolderPath stringByAppendingPathComponent:sharedDataFoldersToMove[i]] toPath:destPath error:&error];
		}
	}
}

+ (NSBundle*)findBundleWithBundleId:(NSString*)bundleId {
	NSString* docPath = [NSString stringWithFormat:@"%s/Documents", getenv("GC_HOME_PATH")];

	NSURL* appGroupFolder = nil;

	NSString* bundlePath = [NSString stringWithFormat:@"%@/Applications/%@", docPath, bundleId];
	NSBundle* appBundle = [[NSBundle alloc] initWithPath:bundlePath];
	// not found locally, let's look for the app in shared folder
	if (!appBundle) {
		appGroupFolder = [[GCSharedUtils appGroupPath] URLByAppendingPathComponent:@"Geode"];

		bundlePath = [NSString stringWithFormat:@"%@/Applications/%@", appGroupFolder.path, bundleId];
		appBundle = [[NSBundle alloc] initWithPath:bundlePath];
	}
	return appBundle;
}

+ (void)dumpPreferenceToPath:(NSString*)plistLocationTo dataUUID:(NSString*)dataUUID {
	NSFileManager* fm = [[NSFileManager alloc] init];
	NSError* error1;

	NSDictionary* preferences = [gcUserDefaults objectForKey:dataUUID];
	if (!preferences) {
		return;
	}

	[fm createDirectoryAtPath:plistLocationTo withIntermediateDirectories:YES attributes:@{} error:&error1];
	for (NSString* identifier in preferences) {
		NSDictionary* preference = preferences[identifier];
		NSString* itemPath = [plistLocationTo stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.plist", identifier]];
		if ([preference count] == 0) {
			// Attempt to delete the file
			[fm removeItemAtPath:itemPath error:&error1];
			continue;
		}
		[preference writeToFile:itemPath atomically:YES];
	}
	[gcUserDefaults removeObjectForKey:dataUUID];
}

+ (NSString*)findDefaultContainerWithBundleId:(NSString*)bundleId {
	// find app's default container
	NSURL* appGroupFolder = [[GCSharedUtils appGroupPath] URLByAppendingPathComponent:@"Geode"];

	NSString* bundleInfoPath = [NSString stringWithFormat:@"%@/Applications/%@/LCAppInfo.plist", appGroupFolder.path, bundleId];
	NSDictionary* infoDict = [NSDictionary dictionaryWithContentsOfFile:bundleInfoPath];
	return infoDict[@"LCDataUUID"];
}

@end

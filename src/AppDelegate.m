#import "AppDelegate.h"
#import "IntroVC.h"
#import "LCUtils/LCUtils.h"
#import "LCUtils/Shared.h"
#import "RootViewController.h"
#import "Theming.h"
#import "Utils.h"
#import "components/LogUtils.h"
#include "src/Patcher.h"
#import <spawn.h>

static ImportCertHandler importCertFunc = nil;
static NSData* certData = nil;
static NSString* certPassword = nil;

// https://www.uicolor.io/
@implementation AppDelegate
- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions {
	self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
	switch ([[Utils getPrefs] integerForKey:@"CURRENT_THEME"]) {
	default: // System
		self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleUnspecified;
		break;
	case 1: // Light
		self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
		break;
	case 2: // Dark
		self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
		break;
	}
	self.window.backgroundColor = [Theming getBackgroundColor];
	if ([[Utils getPrefs] boolForKey:@"CompletedSetup"]) {
		RootViewController* rootViewController = [[RootViewController alloc] init];
		self.window.rootViewController = rootViewController;
	} else {
		IntroVC* introViewController = [[IntroVC alloc] init];
		self.window.rootViewController = introViewController;
	}

	[self.window makeKeyAndVisible];
	return YES;
}

// ext

+ (void)openWebPage:(NSString*)urlStr {
	AppDelegate* delegate = (AppDelegate*)UIApplication.sharedApplication.delegate;
	if (!delegate.openUrlStrFunc) {
		delegate.urlStrToOpen = urlStr;
	} else {
		dispatch_async(dispatch_get_main_queue(), ^{ delegate.openUrlStrFunc(urlStr); });
	}
}

+ (void)setOpenUrlStrFunc:(void (^)(NSString* urlStr))handler {
	AppDelegate* delegate = (AppDelegate*)UIApplication.sharedApplication.delegate;
	delegate.openUrlStrFunc = handler;
	if (delegate.urlStrToOpen) {
		dispatch_async(dispatch_get_main_queue(), ^{
			handler(delegate.urlStrToOpen);
			delegate.urlStrToOpen = nil;
		});
	}
	NSString* storedUrl = [[Utils getPrefs] stringForKey:@"webPageToOpen"];
	if (storedUrl) {
		[[Utils getPrefs] removeObjectForKey:@"webPageToOpen"];
		dispatch_async(dispatch_get_main_queue(), ^{ handler(storedUrl); });
	}
}

+ (void)setLaunchAppFunc:(void (^)(NSString* bundleId, NSString* container))handler {
	AppDelegate* delegate = (AppDelegate*)UIApplication.sharedApplication.delegate;
	delegate.launchAppFunc = handler;
	if (delegate.bundleToLaunch) {
		dispatch_async(dispatch_get_main_queue(), ^{
			handler(delegate.bundleToLaunch, delegate.containerToLaunch);
			delegate.bundleToLaunch = nil;
			delegate.containerToLaunch = nil;
		});
	}
}

+ (void)launchApp:(NSString*)bundleId container:(NSString*)container {
	AppDelegate* delegate = (AppDelegate*)UIApplication.sharedApplication.delegate;
	if (!delegate.launchAppFunc) {
		delegate.bundleToLaunch = bundleId;
		delegate.containerToLaunch = container;
	} else {
		dispatch_async(dispatch_get_main_queue(), ^{ delegate.launchAppFunc(bundleId, container); });
	}
}

- (BOOL)application:(UIApplication*)application openURL:(nonnull NSURL*)url options:(nonnull NSDictionary<UIApplicationOpenURLOptionsKey, id>*)options {
	if (url && [url isFileURL]) {
		NSFileManager* fm = NSFileManager.defaultManager;
		NSString* fileName = [url lastPathComponent];

		NSURL* path;
		NSError* error = nil;
		if ([Utils isContainerized]) {
			path = [NSURL fileURLWithPath:[[LCPath docPath].path stringByAppendingString:@"/game/geode/mods/"]];
		} else {
			path = [NSURL fileURLWithPath:[[Utils docPath] stringByAppendingString:@"game/geode/mods/"]];
		}
		NSURL* destinationURL = [path URLByAppendingPathComponent:fileName];
		if ([fm fileExistsAtPath:destinationURL.path]) {
			[fm removeItemAtURL:destinationURL error:&error];
			if (error) {
				AppLog(@"Couldn't replace file: %@", error);
				return NO;
			}
		}
		BOOL access = [url startAccessingSecurityScopedResource]; // to prevent ios from going "OH YOU HAVE NO PERMISSION!!!"
		if ([fm copyItemAtURL:url toURL:destinationURL error:&error]) {
			AppLog(@"Added new mod %@!", fileName);
			[fm removeItemAtURL:url error:nil];
			if (access)
				[url stopAccessingSecurityScopedResource];
			dispatch_async(dispatch_get_main_queue(), ^{ [Utils showNoticeGlobal:[NSString stringWithFormat:@"launcher.notice.mod-import".loc, fileName]]; });
			return YES;
		} else {
			AppLog(@"Couldn't copy file: %@", error);
			if (access)
				[url stopAccessingSecurityScopedResource];
			dispatch_async(dispatch_get_main_queue(), ^{ [Utils showErrorGlobal:[NSString stringWithFormat:@"launcher.notice.mod-import.fail".loc, fileName] error:error]; });
			return NO;
		}
		return YES;
	}

	if ([url.host isEqualToString:@"launchent"]) {
		AppLog(@"force open helper3");
		[((RootViewController*)self.window.rootViewController) launchHelper2:NO patchCheck:YES];
		return YES;
	}
	if ([[Utils getPrefs] boolForKey:@"ENTERPRISE_MODE"] && ![url.host isEqualToString:@"import"]) {
		[Utils showNoticeGlobal:@"Any app scheme is not supported. This includes restarting Geode. Tap Launch if you recently installed mods to patch the helper."];
		return YES;
	} else if ([[Utils getPrefs] boolForKey:@"ENTERPRISE_MODE"] && [url.host isEqualToString:@"import"]) {
		NSFileManager* fm = [NSFileManager defaultManager];
		// yeah i could optimize it but...
		NSURL* dataPath = [[LCPath docPath] URLByAppendingPathComponent:@"shared"];
		NSError* err;
		[fm removeItemAtURL:dataPath error:&err];
		[fm createDirectoryAtURL:dataPath withIntermediateDirectories:YES attributes:nil error:&err];
		if ([fm fileExistsAtPath:[[fm temporaryDirectory] URLByAppendingPathComponent:@"tmp.zip"].path]) {
			[fm removeItemAtPath:[[fm temporaryDirectory] URLByAppendingPathComponent:@"tmp.zip"].path error:nil];
		}
		NSURLComponents* components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
		__block BOOL hasError = NO;
		__block BOOL safeMode = NO;
		for (NSURLQueryItem* item in components.queryItems) {
			if ([item.name isEqualToString:@"data"]) {
				NSMutableString* encodedUrl = [item.value mutableCopy];
				[encodedUrl replaceOccurrencesOfString:@"-" withString:@"+" options:0 range:NSMakeRange(0, encodedUrl.length)];
				[encodedUrl replaceOccurrencesOfString:@"_" withString:@"/" options:0 range:NSMakeRange(0, encodedUrl.length)];
				// padding go brrr
				while (encodedUrl.length % 4 != 0) {
					[encodedUrl appendString:@"="];
				}
				NSData* zipData = [[NSData alloc] initWithBase64EncodedString:encodedUrl options:0];
				if (zipData) {
					[zipData writeToFile:[[fm temporaryDirectory] URLByAppendingPathComponent:@"tmp.zip"].path atomically:YES];
					[Utils decompress:[[fm temporaryDirectory] URLByAppendingPathComponent:@"tmp.zip"].path extractionPath:[LCPath dataPath].path completion:^(int decompError) {
						dispatch_async(dispatch_get_main_queue(), ^{
							if (decompError != 0) {
								[Utils showErrorGlobal:[NSString stringWithFormat:@"Decompressing ZIP for mods failed.\nStatus Code: %d\nView app logs for more information.",
																				  decompError]
												 error:nil];
								hasError = YES;
								return AppLog(@"Error trying to decompress ZIP for tmp.zip: (Code %@)", decompError);
							}
						});
					}];
				}
			} else if ([item.name isEqualToString:@"dontCallback"]) {
				hasError = YES;
			} else if ([item.name isEqualToString:@"safeMode"]) {
				safeMode = YES;
			}
		}
		NSURL* bundlePath = [[LCPath bundlePath] URLByAppendingPathComponent:[Utils gdBundleName]];
		NSString* checksum = [Patcher getPatchChecksum:[bundlePath URLByAppendingPathComponent:@"GeometryOriginal"] withSafeMode:safeMode];
		[((RootViewController*)self.window.rootViewController) updatePatchStatus];
		if (!hasError) {
			if (checksum != nil && ![checksum isEqualToString:[[Utils getPrefs] stringForKey:@"PATCH_CHECKSUM"]]) {
				[Utils showNoticeGlobal:@"launcher.notice.enterprise.s3".loc];
				[[((RootViewController*)self.window.rootViewController) launchButton] setEnabled:YES];
			} else {
				AppLog(@"force open helper3");
				// this is funny
				[((RootViewController*)self.window.rootViewController) launchHelper2:safeMode patchCheck:YES];
			}
		}
		return YES;
	}
	if ([url.host isEqualToString:@"open-web-page"]) {
		NSURLComponents* components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
		for (NSURLQueryItem* item in components.queryItems) {
			if ([item.name isEqualToString:@"q"]) {
				NSData* decodedData = [[NSData alloc] initWithBase64EncodedString:item.value options:0];
				if (decodedData) {
					NSString* decodedString = [[NSString alloc] initWithData:decodedData encoding:NSUTF8StringEncoding];
					if (decodedString) {
						[AppDelegate openWebPage:decodedString];
					}
				}
			}
		}
		return YES;
	} else if ([url.host isEqualToString:@"geode-launch"] || [url.host isEqualToString:@"launch"] || [url.host isEqualToString:@"relaunch"]) {
		[[Utils getPrefs] setValue:[Utils gdBundleName] forKey:@"selected"];
		[[Utils getPrefs] setValue:@"GeometryDash" forKey:@"selectedContainer"];
		[[Utils getPrefs] setBool:NO forKey:@"safemode"];
		if ([url.host isEqualToString:@"relaunch"] && ![Utils isSandboxed]) {
			pid_t pid;
			int status;
			// sorry, -9 or itll show crash log...
			const char* args[] = { "killall", "-9", "GeometryJump", NULL };
			int spawnError = posix_spawn(&pid, [Utils getKillAllPath], NULL, NULL, (char* const*)args, NULL);
			if (spawnError != 0)
				return NO;
			if (waitpid(pid, &status, 0) != -1) {
				if (WIFEXITED(status) && WEXITSTATUS(status) == 0) {
					dispatch_async(dispatch_get_main_queue(), ^{ [Utils tweakLaunch_withSafeMode:NO]; });
					return NO;
				}
			}
			return NO;
		}
		if (![url.host isEqualToString:@"relaunch"]) {
			AppLog(@"Launching Geometry Dash");
			if (![LCUtils launchToGuestApp]) {
				[Utils showErrorGlobal:[NSString stringWithFormat:@"launcher.error.gd".loc, @"launcher.error.app-uri".loc] error:nil];
			}
		}
		return YES;
	} else if ([url.host isEqualToString:@"safe-mode"]) {
		AppLog(@"Launching in Safe Mode");
		[[Utils getPrefs] setValue:[Utils gdBundleName] forKey:@"selected"];
		[[Utils getPrefs] setValue:@"GeometryDash" forKey:@"selectedContainer"];
		[[Utils getPrefs] setBool:YES forKey:@"safemode"];
		[LCUtils launchToGuestApp];
		return YES;
	} else if ([url.host isEqualToString:@"certificate"]) {
		NSURLComponents* components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
		if (components) {
			NSMutableDictionary<NSString*, NSString*>* queryItems = [[NSMutableDictionary alloc] init];
			for (NSURLQueryItem* item in components.queryItems) {
				if (item.value) {
					// i could also do setObject but...
					queryItems[item.name.lowercaseString] = item.value;
				}
			}
			NSString* encodedCert = queryItems[@"cert"];
			NSString* password = queryItems[@"password"];
			if (encodedCert && password) {
				NSData* certData = [[NSData alloc] initWithBase64EncodedString:[encodedCert stringByRemovingPercentEncoding] options:0];
				if (certData) {
					[AppDelegate importSideStoreCert:certData password:password];
				}
			}
		}
		return YES;
	}
	return NO;
}

+ (void)setImportSideStoreCertFunc:(ImportCertHandler)handler;
{
	importCertFunc = handler;
	if (certData && certPassword) {
		handler(certData, certPassword);
	}
}

+ (void)importSideStoreCert:(NSData*)certDataN password:(NSString*)passwordN {
	if (importCertFunc == nil) {
		certData = certDataN;
		certPassword = passwordN;
	} else {
		importCertFunc(certDataN, passwordN);
	}
}

- (void)applicationWillTerminate:(UIApplication*)application {
	NSUserDefaults* defaults = [Utils getPrefs];
	[defaults removeObjectForKey:@"selected"];
	[defaults removeObjectForKey:@"selectedContainer"];
}

@end

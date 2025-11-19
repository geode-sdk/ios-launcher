#include "../src/LCUtils/unarchive.h"
#import <UIKit/UIKit.h>
#include <dlfcn.h>
#include <objc/runtime.h>
#import "../src/EnterpriseCompare.h"

NSString* exitMsg = nil;
BOOL showNothing = NO;

@interface RootViewController : UIViewController
@end

@implementation RootViewController
- (void)viewDidAppear:(BOOL)animated {
	NSLog(@"[EnterpriseLoader] viewDidAppear");
	[super viewDidAppear:animated];
	if (exitMsg != nil) {
		static dispatch_once_t onceToken;
		dispatch_once(&onceToken, ^{
			UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Notice" message:exitMsg preferredStyle:UIAlertControllerStyleAlert];
			UIAlertAction* ok = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction* _Nonnull action) { exit(0); }];
			[alert addAction:ok];
			[self presentViewController:alert animated:YES completion:nil];
		});
	}
}
@end
@implementation NSObject (modif_AppController)
- (void)overrideToWindow {
	showNothing = YES;
	id anyScene = [UIApplication.sharedApplication.connectedScenes allObjects].firstObject;
	UIWindowScene* scene = [anyScene isKindOfClass:UIWindowScene.class] ? anyScene : nil;
	UIWindow* window;
	if (scene) {
		window = [[UIWindow alloc] initWithWindowScene:scene];
	} else {
		window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
	}
	if (!window) {
		NSLog(@"[EnterpriseLoader] Couldn't find window");
		// something terribly went wrong here
		return;
	}
	window.backgroundColor = [UIColor grayColor];
	window.rootViewController = [[RootViewController alloc] init];
	[window makeKeyAndVisible];
}
- (void)rly_application_didBecomeActive:(UIApplication*)application {
	// robert why do you use deprecated funcs
	NSLog(@"[EnterpriseLoader] AppController:applicationDidBecomeActive swizzled!");
	if (!showNothing) {
		[self rly_application_didBecomeActive:application];
	} else {
		NSLog(@"[EnterpriseLoader] AppController:applicationDidBecomeActive prevented from called!");
	}
}

- (BOOL)rly_application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions {
	NSLog(@"[EnterpriseLoader] application:didFinishLaunchingWithOptions swizzled!");
	NSURL* url = launchOptions[UIApplicationLaunchOptionsURLKey];
	BOOL forceLaunch = NO;
	BOOL useCAHighFPS = NO;
	NSFileManager* fm = [NSFileManager defaultManager];
	NSURL* docDir = [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].lastObject;
	if (url) {
		if ([url.scheme isEqualToString:@"geode-helper"]) {
			NSLog(@"[EnterpriseLoader] Launched with %@", url);
			if ([url.host isEqualToString:@"launch-force"]) {
				forceLaunch = YES;
			} else if ([url.host isEqualToString:@"launch"]) {
				NSURLComponents* components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
				for (NSURLQueryItem* item in components.queryItems) {
					if ([item.name isEqualToString:@"args"]) {
						NSMutableString* encodedUrl = [item.value mutableCopy];
						[encodedUrl replaceOccurrencesOfString:@"-" withString:@"+" options:0 range:NSMakeRange(0, encodedUrl.length)];
						[encodedUrl replaceOccurrencesOfString:@"_" withString:@"/" options:0 range:NSMakeRange(0, encodedUrl.length)];
						while (encodedUrl.length % 4 != 0) {
							[encodedUrl appendString:@"="];
						}
						NSData* decodedData = [[NSData alloc] initWithBase64EncodedString:encodedUrl options:0];
						if (decodedData) {
							NSString* decodedString = [[NSString alloc] initWithData:decodedData encoding:NSUTF8StringEncoding];
							decodedString = [NSString stringWithFormat:@"%@ --geode:binary-dir=\"%@/mods\"", decodedString, [[NSBundle mainBundle] resourcePath]];
							setenv("LAUNCHARGS", decodedString.UTF8String, 1);
						}
					} else if ([item.name isEqualToString:@"checksum"]) {
						NSString* currChecksum = [EnterpriseCompare getChecksum:YES];
						NSString* otherChecksum = [item.value mutableCopy];
						NSLog(@"[EnterpriseLoader] curr-checksum %@ vs other-checksum %@", currChecksum, otherChecksum);
						if (![currChecksum isEqualToString:otherChecksum]) {
							exitMsg = @"You must update the Helper to use any new mods. If you accidentally skipped the step to save the IPA, go back to the launcher, settings, and tap \"Install Helper\".\n\nYou will install that new helper IPA just like you installed it originally. Do not uninstall the Helper, update it like you would with any other app with your signer.";
						}
					} else if ([item.name isEqualToString:@"cahighfps"]) {
						useCAHighFPS = YES;
					}
				}
			} else if ([url.host isEqualToString:@"check"]) {
				if (!docDir)
					return NO;
				BOOL safeMode = NO;
				BOOL dontCallBack = NO;
				NSString* uri = @"geode";
				NSURLComponents* components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
				for (NSURLQueryItem* item in components.queryItems) {
					if ([item.name isEqualToString:@"safe"]) {
						if ([item.value isEqualToString:@"1"]) {
							safeMode = YES;
						}
					} else if ([item.name isEqualToString:@"callback"]) {
						uri = item.value;
					} else if ([item.name isEqualToString:@"dontCallback"]) {
						dontCallBack = YES;
					}
				}
				NSString* zipPath = [[fm temporaryDirectory] URLByAppendingPathComponent:@"data_tmp.zip"].path;
				if ([fm fileExistsAtPath:zipPath]) {
					[fm removeItemAtPath:zipPath error:nil];
				}
				BOOL force = NO;
				int result = compressEnt(docDir.path, zipPath, &force);
				if (result != 0) {
					NSLog(@"[EnterpriseLoader] Couldn't create zip file: %d", result);
					return NO;
				}
				NSLog(@"[EnterpriseLoader] Finish compressing");

				dispatch_async(dispatch_get_main_queue(), ^{
					NSData* zipData = [NSData dataWithContentsOfFile:zipPath];
					NSMutableString* encoded = [[zipData base64EncodedStringWithOptions:0] mutableCopy];
					[encoded replaceOccurrencesOfString:@"+" withString:@"-" options:0 range:NSMakeRange(0, encoded.length)];
					[encoded replaceOccurrencesOfString:@"/" withString:@"_" options:0 range:NSMakeRange(0, encoded.length)];
					while ([encoded hasSuffix:@"="]) {
						[encoded deleteCharactersInRange:NSMakeRange(encoded.length - 1, 1)];
					}
					NSString* encodedParam = [encoded stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
					NSString* urlString = [NSString stringWithFormat:@"%@://import?data=%@%@%@%@", uri, encodedParam, (force) ? @"&force=1" : @"", (safeMode) ? @"safeMode=1" : @"",
																	 (dontCallBack) ? @"dontCallback=1" : @""];
					NSURL* url = [NSURL URLWithString:urlString];
					if ([[UIApplication sharedApplication] canOpenURL:url]) {
						for (int i = 0; i < 2; i++) {
							[application openURL:url options:@{} completionHandler:^(BOOL b) { exit(0); }];
						}
					} else {
						NSLog(@"[EnterpriseLoader] Couldn't open %@. Aborting!", url);
						abort();
					}
				});
				[self overrideToWindow];
				return YES;
			}
		}
	} else {
		// if (docDir) {
		// 	if ([fm fileExistsAtPath:[docDir URLByAppendingPathComponent:@"flags.txt"].path]) {
		// 		NSError* error;
		// 		NSString* decodedString = [NSString stringWithContentsOfFile:[docDir URLByAppendingPathComponent:@"flags.txt"].path encoding:NSUTF8StringEncoding error:&error];
		// 		if (!error) {
		// 			decodedString = [NSString stringWithFormat:@"%@ --geode:binary-dir=\"%@/mods\"", decodedString, [[NSBundle mainBundle] resourcePath]];
		// 			setenv("LAUNCHARGS", decodedString.UTF8String, 1);
		// 		}
		// 	}
		// }
	}
	if (getenv("LAUNCHARGS") || forceLaunch) {
		NSLog(@"[EnterpriseLoader] Geode will load. Launch args: %s", getenv("LAUNCHARGS"));
		NSString* bbUID = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
		NSString* sfBdPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"sf.bd"];
		NSString* sfBd = [NSString stringWithContentsOfURL:[NSURL fileURLWithPath:sfBdPath] encoding:NSUTF8StringEncoding error:nil];
		if (sfBd == nil) {
			exitMsg = @"sf missing. Please reinstall the helper.";
		}
		if (![bbUID isEqualToString:bbUID]) {
			exitMsg = @"Unable to verify. Please ensure both the launcher and helper are signed with the same certificate and installed with the same method.";
		}
	} else {
		NSLog(@"[EnterpriseLoader] Geode won't load");
		exitMsg = @"You must launch the helper with the launcher.";
	}
	if (exitMsg != nil) {
		[self overrideToWindow];
		return YES;
	}
	if (exitMsg == nil) {
		if (useCAHighFPS) {
			NSLog(@"[EnterpriseLoader] dlopen(\"@executable_path/CAHighFPS.dylib\", RTLD_LAZY | RTLD_GLOBAL)");
			void* handle = dlopen("@executable_path/CAHighFPS.dylib", RTLD_LAZY | RTLD_GLOBAL);
			const char* error = dlerror();
			if (handle) {
				NSLog(@"[EnterpriseLoader] Loaded CAHighFPS.dylib");
			} else if (error) {
				NSLog(@"[EnterpriseLoader] Failed to dlopen CAHighFPS.dylib: %s", error);
			} else {
				NSLog(@"[EnterpriseLoader] Failed to dlopen CAHighFPS.dylib: Unknown error because dlerror() returns NULL");
			}
		}
		NSLog(@"[EnterpriseLoader] dlopen(\"@executable_path/Geode.ios.dylib\", RTLD_LAZY | RTLD_GLOBAL)");
		void* handle = dlopen("@executable_path/Geode.ios.dylib", RTLD_LAZY | RTLD_GLOBAL);
		const char* error = dlerror();
		if (handle) {
			NSLog(@"[EnterpriseLoader] Loaded Geode.ios.dylib");
		} else if (error) {
			exitMsg = [NSString stringWithFormat:@"Failed to dlopen Geode.ios.dylib: %s", error];
			NSLog(@"[EnterpriseLoader] Failed to dlopen Geode.ios.dylib: %s", error);
		} else {
			exitMsg = @"Failed to dlopen Geode.ios.dylib: Unknown error because dlerror() returns NULL";
			NSLog(@"[EnterpriseLoader] Failed to dlopen Geode.ios.dylib: Unknown error because dlerror() returns NULL");
		}
	}
	if (exitMsg != nil) {
		[self overrideToWindow];
		return YES;
	}
	return [self rly_application:application didFinishLaunchingWithOptions:nil];
}

- (BOOL)rly_application:(UIApplication*)application openURL:(nonnull NSURL*)url options:(nonnull NSDictionary<UIApplicationOpenURLOptionsKey, id>*)options {
	// just so it doesnt crash because robert didnt add this method
	if ([url.scheme isEqualToString:@"geode-helper"]) {
		return YES;
	}
	return [self rly_application:application openURL:url options:options];
}
@end

__attribute__((constructor)) static void EnterpriseLoaderConstructor() {
	NSLog(@"[EnterpriseLoader] Init");
	// we swizzle because this is too early...
	Class appCtrl = NSClassFromString(@"AppController");
	if (appCtrl) {
		{
			SEL orig = @selector(application:didFinishLaunchingWithOptions:);
			SEL swizzled = @selector(rly_application:didFinishLaunchingWithOptions:);
			Method origMethod = class_getInstanceMethod(appCtrl, orig);
			Method swzMethod = class_getInstanceMethod([NSObject class], swizzled);
			if (origMethod && swzMethod) {
				class_addMethod(appCtrl, swizzled, method_getImplementation(swzMethod), method_getTypeEncoding(swzMethod));
				method_exchangeImplementations(origMethod, class_getInstanceMethod(appCtrl, swizzled));
				NSLog(@"[EnterpriseLoader] Swizzling (AppController) application:didFinishLaunchingWithOptions");
			}
		}
		{
			SEL orig = @selector(applicationDidBecomeActive:);
			SEL swizzled = @selector(rly_application_didBecomeActive:);
			Method origMethod = class_getInstanceMethod(appCtrl, orig);
			Method swzMethod = class_getInstanceMethod([NSObject class], swizzled);
			if (origMethod && swzMethod) {
				class_addMethod(appCtrl, swizzled, method_getImplementation(swzMethod), method_getTypeEncoding(swzMethod));
				method_exchangeImplementations(origMethod, class_getInstanceMethod(appCtrl, swizzled));
				NSLog(@"[EnterpriseLoader] Swizzling (AppController) applicationDidBecomeActive");
			}
		}
		{
			SEL orig = @selector(application:openURL:options:);
			SEL swizzled = @selector(rly_application:openURL:options:);
			Method origMethod = class_getInstanceMethod(appCtrl, orig);
			Method swzMethod = class_getInstanceMethod([NSObject class], swizzled);
			if (!class_getInstanceMethod(appCtrl, orig)) {
				class_addMethod(appCtrl, orig, method_getImplementation(swzMethod), method_getTypeEncoding(swzMethod));
				NSLog(@"[EnterpriseLoader] (addMethod) Swizzling (AppController) application:openURL");
			} else if (origMethod && swzMethod) {
				class_addMethod(appCtrl, swizzled, method_getImplementation(swzMethod), method_getTypeEncoding(swzMethod));
				method_exchangeImplementations(origMethod, class_getInstanceMethod(appCtrl, swizzled));
				NSLog(@"[EnterpriseLoader] Swizzling (AppController) application:openURL");
			} else {
				NSLog(@"[EnterpriseLoader] Couldn't swizzle (AppController) application:openURL");
			}
		}
	}
}

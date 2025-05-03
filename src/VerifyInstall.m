#import "GeodeInstaller.h"
#import "LCUtils/LCAppInfo.h"
#import "LCUtils/LCAppModel.h"
#import "LCUtils/LCUtils.h"
#import "LCUtils/Shared.h"
#import "LCUtils/unarchive.h"
#import "Utils.h"
#import "VerifyInstall.h"
#import "components/LogUtils.h"
#import <UIKit/UIKit.h>
#import <dlfcn.h>

#import <objc/runtime.h>

typedef void (^DecompressCompletion)(int error);

BOOL hasDoneUpdate = NO;

@implementation VerifyInstall
// for actually knowing whether they own the app!
+ (BOOL)verifyGDAuthenticity {
	if (![Utils isSandboxed])
		return YES;
	return [[Utils getPrefs] boolForKey:@"GDVerified"];
}

+ (BOOL)canLaunchAppWithBundleID:(NSString*)bundleID {
	Class LSApplicationWorkspace_class = objc_getClass("LSApplicationWorkspace");
	if (!LSApplicationWorkspace_class)
		return NO;
	id workspace = [LSApplicationWorkspace_class performSelector:@selector(defaultWorkspace)];
	if (!workspace)
		return NO;
	SEL selector = NSSelectorFromString(@"openApplicationWithBundleID:");
	NSInvocation* invocation = [NSInvocation invocationWithMethodSignature:[workspace methodSignatureForSelector:selector]];
	[invocation setTarget:workspace];
	[invocation setSelector:selector];
	[invocation setArgument:&bundleID atIndex:2];

	[invocation invoke];
	// BOOL canLaunch = [workspace performSelector:@selector(openApplicationWithBundleID:) withObject:bundleID];
	[NSThread sleepForTimeInterval:1.0];
	BOOL canLaunch;
	[invocation getReturnValue:&canLaunch];
	return canLaunch;
}

+ (void)startVerifyGDAuth:(RootViewController*)root {
	UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"launcher.verify-gd.title".loc message:@"launcher.verify-gd.msg".loc
															preferredStyle:UIAlertControllerStyleAlert];

	UIAlertAction* launchAction = [UIAlertAction actionWithTitle:@"common.ok".loc style:UIAlertActionStyleDefault handler:^(UIAlertAction* _Nonnull action) {
		BOOL canLaunch = [VerifyInstall canLaunchAppWithBundleID:@"com.robtop.geometryjump"];
		if (!canLaunch) {
			UIAlertController* resultAlert = [UIAlertController alertControllerWithTitle:@"Error" message:@"launcher.verify-gd.error".loc
																		  preferredStyle:UIAlertControllerStyleAlert];
			UIAlertAction* okAction = [UIAlertAction actionWithTitle:@"common.ok".loc style:UIAlertActionStyleDefault handler:nil];
			[resultAlert addAction:okAction];
			[root presentViewController:resultAlert animated:YES completion:nil];
			return;
		}
		NSUserDefaults* prefs = [Utils getPrefs];
		[prefs setBool:YES forKey:@"UPDATE_AUTOMATICALLY"];
		[prefs setBool:YES forKey:@"GDVerified"];
		[prefs synchronize];
		[root updateState];
	}];

	UIAlertAction* cancelAction = [UIAlertAction actionWithTitle:@"common.cancel".loc style:UIAlertActionStyleCancel handler:nil];
	[alert addAction:launchAction];
	[alert addAction:cancelAction];
	[root presentViewController:alert animated:YES completion:nil];
}
// after the user installed the patched ipa
+ (BOOL)verifyGDInstalled {
	BOOL res = NO;
	if (![Utils isSandboxed])
		return YES;
	if ([[NSFileManager defaultManager] fileExistsAtPath:[[LCPath bundlePath] URLByAppendingPathComponent:[Utils gdBundleName] isDirectory:YES].path isDirectory:&res]) {
		if ([[Utils getPrefs] boolForKey:@"GDNeedsUpdate"])
			return NO;
		return res;
	};
	return NO;
}

+ (void)decompress:(NSString*)fileToExtract extractionPath:(NSString*)extractionPath completion:(DecompressCompletion)completion {
	AppLog(@"Starting decomp of %@ to %@", fileToExtract, extractionPath);
	[[NSFileManager defaultManager] createDirectoryAtPath:extractionPath withIntermediateDirectories:YES attributes:nil error:nil];
	int res = extract(fileToExtract, extractionPath, nil);
	return completion(res);
}

// I CANT (return BOOL instead?)
+ (void)startGDInstall:(RootViewController*)root url:(NSURL*)url {
	@autoreleasepool {
		[[Utils getPrefs] setBool:NO forKey:@"GDNeedsUpdate"];
		// https://github.com/khanhduytran0/LiveContainer/blob/d950e0501944282d757bc5c3b60557d8b64e43c9/LiveContainerSwiftUI/LCAppListView.swift#L348
		NSFileManager* fm = [NSFileManager defaultManager];
		[fm removeItemAtURL:[[LCPath bundlePath] URLByAppendingPathComponent:[Utils gdBundleName]] error:nil];
		[fm createDirectoryAtURL:[LCPath bundlePath] withIntermediateDirectories:YES attributes:nil error:nil];
		NSURL* payloadPath = [[fm temporaryDirectory] URLByAppendingPathComponent:@"Payload"];
		NSError* error = nil;
		if ([fm fileExistsAtPath:[payloadPath path]]) {
			[fm removeItemAtURL:payloadPath error:&error];
			if (error) {
				[root updateState];
				// do i .localizedDescription
				return AppLog(@"Error removing item from payload: %@", error);
			}
		}

		// async bad, i cant even update ui without it.. and it sometimes is unstable too!
		dispatch_async(dispatch_get_main_queue(), ^{
			[root barProgress:0];
			[NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer* _Nonnull timer) {
				dispatch_async(dispatch_get_main_queue(), ^{
					if (getProgress() < 100) {
						[root barProgress:getProgress()];
					} else if (getProgress() >= 100) {
						[root progressVisibility:YES];
						[timer invalidate];
					}
				});
			}];
		});

		[VerifyInstall decompress:url.path extractionPath:[[fm temporaryDirectory] path] completion:^(int decompError) {
			if (decompError != 0) {
				return dispatch_async(dispatch_get_main_queue(), ^{
					[root updateState];
					[Utils showError:root
							   title:[NSString stringWithFormat:
												   @"Decompressing IPA failed. (Outdated launcher or incomplete download?)\nStatus Code: %d\nView app logs for more information.",
												   decompError]
							   error:nil];
					return AppLog(@"Error trying to decompress IPA (Code %d)", decompError);
				});
			}
			NSError* error = nil;

			NSArray<NSString*>* payloadContents = [fm contentsOfDirectoryAtPath:payloadPath.path error:&error];
			if (error) {
				return dispatch_async(dispatch_get_main_queue(), ^{
					[Utils showError:root title:@"Retrieving contents failed" error:error];
					[root updateState];
					AppLog(@"Error retrieving contents of directory: %@", error);
				});
			}
			NSString* appBundleName = nil;
			for (NSString* fileName in payloadContents) {
				if ([fileName hasSuffix:@".app"]) {
					appBundleName = fileName;
					break;
				}
			}
			NSURL* appFolderPath = [payloadPath URLByAppendingPathComponent:appBundleName];
			LCAppInfo* newAppInfo = [[LCAppInfo alloc] initWithBundlePath:appFolderPath.path];
			NSString* appRelativePath = [NSString stringWithFormat:@"%@.app", [newAppInfo bundleIdentifier]];
			NSURL* outputFolder = [[LCPath bundlePath] URLByAppendingPathComponent:appRelativePath];
			LCAppModel* appToReplace = nil;
			SharedModel* sharedModel = [[SharedModel alloc] init];

			// sorry i really couldnt figure this out
			NSArray<LCAppModel*>* sameBundleIdApp = [sharedModel.apps filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(LCAppModel* app, NSDictionary* bindings) {
																		  return [app.appInfo.bundleIdentifier isEqualToString:newAppInfo.bundleIdentifier];
																	  }]];

			if (sameBundleIdApp.count == 0) {
				sameBundleIdApp = [sharedModel.hiddenApps filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(LCAppModel* app, NSDictionary* bindings) {
															  return [app.appInfo.bundleIdentifier isEqualToString:newAppInfo.bundleIdentifier];
														  }]];
			}

			if ([fm fileExistsAtPath:outputFolder.path] || sameBundleIdApp.count > 0) {
				// ah yes, c casting
				appRelativePath = [NSString stringWithFormat:@"%@_%ld.app", [newAppInfo bundleIdentifier], (long)CFAbsoluteTimeGetCurrent()];

				outputFolder = [LCPath.bundlePath URLByAppendingPathComponent:appRelativePath];
				if (![fm removeItemAtURL:outputFolder error:&error]) {
					AppLog(@"Error removing item: %@", error);
				}
			}
			// Move it!
			[fm moveItemAtURL:appFolderPath toURL:outputFolder error:&error];
			if (error) {
				return dispatch_async(dispatch_get_main_queue(), ^{
					[Utils showError:root title:@"Moving items failed" error:error];
					[root updateState];
					AppLog(@"Error moving item from url: %@", error);
				});
			}
			LCAppInfo* finalNewApp = [[LCAppInfo alloc] initWithBundlePath:outputFolder.path];
			if (finalNewApp == nil) {
				return dispatch_async(dispatch_get_main_queue(), ^{
					[root updateState];
					AppLog(@"Error getting new app from LCAppInfo");
				});
			}
			finalNewApp.relativeBundlePath = appRelativePath;

			[finalNewApp patchExecAndSignIfNeedWithCompletionHandler:^(BOOL success, NSString* errorInfo) {
				dispatch_async(dispatch_get_main_queue(), ^{
					if (![VerifyInstall verifyGeodeInstalled]) {
						//[root updateState];
						root.optionalTextLabel.text = @"launcher.status.download-geode".loc;
						[[[GeodeInstaller alloc] init] startInstall:root ignoreRoot:NO];
					} else {
						[root progressVisibility:YES];
						[root updateState];
					}
				});
				if (success) {
					LCAppModel* newAppModel = [[LCAppModel alloc] initWithAppInfo:finalNewApp delegate:nil];
					if (appToReplace != nil) {
						finalNewApp.autoSaveDisabled = true;
						finalNewApp.isShared = appToReplace.appInfo.isShared;
						finalNewApp.doSymlinkInbox = appToReplace.appInfo.doSymlinkInbox;
						finalNewApp.containerInfo = appToReplace.appInfo.containerInfo;
						finalNewApp.dataUUID = appToReplace.appInfo.dataUUID;
						finalNewApp.autoSaveDisabled = false;

						[sharedModel.apps removeObject:appToReplace];
						[sharedModel.apps addObject:newAppModel];
					} else {
						[sharedModel.apps addObject:newAppModel];
					}
				} else {
					AppLog(@"error with signing: %@", errorInfo);
				}
			} progressHandler:^(NSProgress* signProgress) {
				//[installProgress addChild:signProgress withPendingUnitCount:20];
			} forceSign:NO];
		}];
	}
}

// after the user installed geode itself
+ (BOOL)verifyGeodeInstalled {
	if (![Utils isSandboxed]) {
		NSString* applicationSupportDirectory = [[Utils getGDDocPath] stringByAppendingString:@"Library/Application Support"];
		if (applicationSupportDirectory != nil) {
			return [[NSFileManager defaultManager] fileExistsAtPath:[applicationSupportDirectory stringByAppendingString:@"/GeometryDash/game/geode/Geode.ios.dylib"]];
		} else {
			return NO;
		}
	} else {
		return [[NSFileManager defaultManager] fileExistsAtPath:[[LCPath tweakPath] URLByAppendingPathComponent:@"Geode.ios.dylib"].path];
	}
}
+ (BOOL)verifyAll {
	if (!hasDoneUpdate && [[Utils getPrefs] boolForKey:@"UPDATE_AUTOMATICALLY"]) {
		hasDoneUpdate = YES;
		return NO;
	}
	return [VerifyInstall verifyGDInstalled] && [VerifyInstall verifyGeodeInstalled];
}
@end

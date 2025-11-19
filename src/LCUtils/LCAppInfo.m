#import "LCAppInfo.h"
#import "LCUtils.h"
#import "Shared.h"
#import "src/Utils.h"
#import "src/components/LogUtils.h"
#import <CommonCrypto/CommonCrypto.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@implementation LCAppInfo
- (instancetype)initWithBundlePath:(NSString*)bundlePath {
	self = [super init];
	self.isShared = false;
	if (self) {
		_bundlePath = bundlePath;
		_infoPlist = [NSMutableDictionary dictionaryWithContentsOfFile:[NSString stringWithFormat:@"%@/Info.plist", bundlePath]];
		_info = [NSMutableDictionary dictionaryWithContentsOfFile:[NSString stringWithFormat:@"%@/LCAppInfo.plist", bundlePath]];
		if (!_info) {
			_info = [[NSMutableDictionary alloc] init];
		}
		if (!_infoPlist) {
			_infoPlist = [[NSMutableDictionary alloc] init];
		}

		// migrate old appInfo
		if (_infoPlist[@"LCPatchRevision"] && [_info count] == 0) {
			NSArray* lcAppInfoKeys = @[
				@"LCPatchRevision", @"LCOrignalBundleIdentifier", @"LCDataUUID", @"LCJITLessSignID", @"LCExpirationDate", @"LCTeamId", @"isJITNeeded", @"isLocked",
				@"doSymlinkInbox", @"bypassAssertBarrierOnQueue", @"signer"
			];
			for (NSString* key in lcAppInfoKeys) {
				_info[key] = _infoPlist[key];
				[_infoPlist removeObjectForKey:key];
			}
			[_infoPlist writeToFile:[NSString stringWithFormat:@"%@/Info.plist", bundlePath] atomically:YES];
			[self save];
		}

		// fix bundle id and execName if crash when signing
		if (_infoPlist[@"LCBundleIdentifier"]) {
			AppLog(@"Fixing Bundle Identifier...");
			_infoPlist[@"CFBundleExecutable"] = _infoPlist[@"LCBundleExecutable"];
			_infoPlist[@"CFBundleIdentifier"] = _infoPlist[@"LCBundleIdentifier"];
			[_infoPlist removeObjectForKey:@"LCBundleExecutable"];
			[_infoPlist removeObjectForKey:@"LCBundleIdentifier"];
			[_infoPlist writeToFile:[NSString stringWithFormat:@"%@/Info.plist", bundlePath] atomically:YES];
		}

		if (![_infoPlist[@"CFBundleExecutable"] isEqualToString:@"GeometryJump"]) {
			AppLog(@"CFBundleExecutable isn't GeometryJump! Changing it back to prevent problems...");
			_infoPlist[@"CFBundleExecutable"] = @"GeometryJump";
			[_infoPlist writeToFile:[NSString stringWithFormat:@"%@/Info.plist", bundlePath] atomically:YES];
		}

		_autoSaveDisabled = false;
	}
	return self;
}

- (void)setBundlePath:(NSString*)newBundlePath {
	_bundlePath = newBundlePath;
}

- (NSMutableArray*)urlSchemes {
	// find all url schemes
	NSMutableArray* urlSchemes = [[NSMutableArray alloc] init];
	int nowSchemeCount = 0;
	if (_infoPlist[@"CFBundleURLTypes"]) {
		NSMutableArray* urlTypes = _infoPlist[@"CFBundleURLTypes"];

		for (int i = 0; i < [urlTypes count]; ++i) {
			NSMutableDictionary* nowUrlType = [urlTypes objectAtIndex:i];
			if (!nowUrlType[@"CFBundleURLSchemes"]) {
				continue;
			}
			NSMutableArray* schemes = nowUrlType[@"CFBundleURLSchemes"];
			for (int j = 0; j < [schemes count]; ++j) {
				[urlSchemes insertObject:[schemes objectAtIndex:j] atIndex:nowSchemeCount];
				++nowSchemeCount;
			}
		}
	}

	return urlSchemes;
}

- (NSString*)version {
	NSString* version = _infoPlist[@"CFBundleShortVersionString"];
	if (!version) {
		version = _infoPlist[@"CFBundleVersion"];
	}
	if (version) {
		return version;
	} else {
		return @"Unknown";
	}
}

- (NSString*)bundleIdentifier {
	NSString* ans = _infoPlist[@"CFBundleIdentifier"];
	if (ans) {
		return ans;
	} else {
		return @"Unknown";
	}
}

- (NSString*)dataUUID {
	return _info[@"LCDataUUID"];
}

- (void)setDataUUID:(NSString*)uuid {
	_info[@"LCDataUUID"] = uuid;
	[self save];
}

- (NSString*)bundlePath {
	return _bundlePath;
}

- (NSMutableDictionary*)info {
	return _info;
}

- (void)save {
	if (!_autoSaveDisabled) {
		[_info writeToFile:[NSString stringWithFormat:@"%@/LCAppInfo.plist", _bundlePath] atomically:YES];
	}
}

- (void)patchExecAndSignIfNeedWithCompletionHandler:(void (^)(bool success, NSString* errorInfo))completetionHandler
									progressHandler:(void (^)(NSProgress* progress))progressHandler
										  forceSign:(BOOL)forceSign blockMainThread:(BOOL)blockMainThread {
	NSString* appPath = self.bundlePath;
	NSString* infoPath = [NSString stringWithFormat:@"%@/Info.plist", appPath];
	NSMutableDictionary* info = _info;
	NSMutableDictionary* infoPlist = _infoPlist;
	if (!info) {
		completetionHandler(NO, @"Info.plist not found");
		return;
	}
	NSFileManager* fm = [NSFileManager defaultManager];
	NSString* execPath = [NSString stringWithFormat:@"%@/%@", appPath, _infoPlist[@"CFBundleExecutable"]];

	// Update patch
	int currentPatchRev = 1;
	bool needPatch = [info[@"LCPatchRevision"] intValue] < currentPatchRev;
	if (needPatch || forceSign) {
		// copy-delete-move to avoid EXC_BAD_ACCESS (SIGKILL - CODESIGNING)
		NSString* backupPath = [NSString stringWithFormat:@"%@/%@_GeodePatchBackUp", appPath, _infoPlist[@"CFBundleExecutable"]];
		NSError* err;
		[fm copyItemAtPath:execPath toPath:backupPath error:&err];
		[fm removeItemAtPath:execPath error:&err];
		[fm moveItemAtPath:backupPath toPath:execPath error:&err];
		if (err) {
			AppLog(@"Interact Error: %@", err);
			// completetionHandler(NO, @"Couldn't interact with execPath or backupPath. Look in logs for more details.");
			// return;
		}
	}

	if (needPatch) {
		NSString* error =
            LCParseMachO(execPath.UTF8String, false, ^(const char* path, struct mach_header_64* header, int fd, void* filePtr) { LCPatchExecSlice(path, header, false, [[Utils getPrefs] boolForKey:@"USE_MAX_FPS"]); });
		if (error) {
			completetionHandler(NO, error);
			return;
		}
		info[@"LCPatchRevision"] = @(currentPatchRev);
		forceSign = true;

		[self save];
	}

	if (forceSign) {
		// remove ZSign cache since hash is changed after upgrading patch
		NSString* cachePath = [appPath stringByAppendingPathComponent:@"zsign_cache.json"];
		if ([fm fileExistsAtPath:cachePath]) {
			NSError* err;
			[fm removeItemAtPath:cachePath error:&err];
			if (err) {
				completetionHandler(NO, @"Couldn't remove cachePath");
				return;
			}
		}
	}
	if (!LCUtils.certificatePassword) {
		completetionHandler(YES, nil);
		return;
	}

	NSString* executablePath = [appPath stringByAppendingPathComponent:infoPlist[@"CFBundleExecutable"]];
	if (!forceSign) {
		bool signatureValid = checkCodeSignature(executablePath.UTF8String);
		if (signatureValid) {
			// not expired, don't sign again
			completetionHandler(YES, nil);
			return;
		}
	}

	if (!LCUtils.certificateData) {
		completetionHandler(NO, @"Failed to find signing certificate. Please refresh your store or import a certificate and try again.");
		return;
	}

	// Sign app if JIT-less is set up
	NSURL* appPathURL = [NSURL fileURLWithPath:appPath];
	// We need to temporarily fake bundle ID and main executable to sign properly
	NSString* tmpExecPath = [appPath stringByAppendingPathComponent:@"Geode.tmp"];
	if (!info[@"LCBundleIdentifier"]) {
		// Don't let main executable get entitlements
		[NSFileManager.defaultManager copyItemAtPath:NSBundle.mainBundle.executablePath toPath:tmpExecPath error:nil];

		infoPlist[@"LCBundleExecutable"] = infoPlist[@"CFBundleExecutable"];
		infoPlist[@"LCBundleIdentifier"] = infoPlist[@"CFBundleIdentifier"];
		infoPlist[@"CFBundleExecutable"] = tmpExecPath.lastPathComponent;
		infoPlist[@"CFBundleIdentifier"] = NSBundle.mainBundle.bundleIdentifier;
		[infoPlist writeToFile:infoPath atomically:YES];
	}
	infoPlist[@"CFBundleExecutable"] = infoPlist[@"LCBundleExecutable"];
	infoPlist[@"CFBundleIdentifier"] = infoPlist[@"LCBundleIdentifier"];
	[infoPlist removeObjectForKey:@"LCBundleExecutable"];
	[infoPlist removeObjectForKey:@"LCBundleIdentifier"];

	void (^signCompletionHandler)(BOOL success, NSError* error) = ^(BOOL success, NSError* _Nullable error) {
		if (blockMainThread) {
			dispatch_async(dispatch_get_main_queue(), ^{
				// Remove fake main executable
				[fm removeItemAtPath:tmpExecPath error:nil];
				// Save sign ID and restore bundle ID
				[self save];
				[infoPlist writeToFile:infoPath atomically:YES];
				if (!success) {
					completetionHandler(NO, error.localizedDescription);
				} else {
					bool signatureValid = checkCodeSignature(executablePath.UTF8String);
					if (signatureValid) {
						completetionHandler(YES, nil);
					} else {
						completetionHandler(NO, @"Invalid signature. Try force resigning. If that doesn't work, try refreshing the certificate, deleting the .app file, reinstalling, "
												@"or use LiveContainer instead.");
					}
				}
			});
		} else {
			dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
				// Remove fake main executable
				[fm removeItemAtPath:tmpExecPath error:nil];
				// Save sign ID and restore bundle ID
				[self save];
				[infoPlist writeToFile:infoPath atomically:YES];
				if (!success) {
					completetionHandler(NO, error.localizedDescription);
				} else {
					bool signatureValid = checkCodeSignature(executablePath.UTF8String);
					if (signatureValid) {
						completetionHandler(YES, nil);
					} else {
						completetionHandler(NO, @"Invalid signature. Try force resigning. If that doesn't work, try refreshing the certificate, deleting the .app file, reinstalling, "
												@"or use LiveContainer instead.");
					}
				}
			});
		}
	};
	__block NSProgress* progress = [LCUtils signAppBundleWithZSign:appPathURL completionHandler:signCompletionHandler];

	if (progress) {
		progressHandler(progress);
	}
}

- (bool)doSymlinkInbox {
	if (_info[@"doSymlinkInbox"] != nil) {
		return [_info[@"doSymlinkInbox"] boolValue];
	} else {
		return NO;
	}
}
- (void)setDoSymlinkInbox:(bool)doSymlinkInbox {
	_info[@"doSymlinkInbox"] = [NSNumber numberWithBool:doSymlinkInbox];
	[self save];
}

@end

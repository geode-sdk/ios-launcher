#import "GeodeInstaller.h"
#import "LCUtils/GCSharedUtils.h"
#import "LCUtils/LCUtils.h"
#import "LCUtils/Shared.h"
#import "RootViewController.h"
#import "SettingsVC.h"
#import "Theming.h"
#import "Utils.h"
#import "VerifyInstall.h"
#import "components/LogUtils.h"
#import "components/ProgressBar.h"
#import "src/LCUtils/LCAppInfo.h"
#import <CommonCrypto/CommonCrypto.h>
#import <Foundation/Foundation.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <Security/SecKey.h>
#import <dlfcn.h>
#include <mach-o/dyld.h>
#import <objc/runtime.h>

@interface RootViewController ()

@property(nonatomic, strong) ProgressBar* progressBar;
@property(nonatomic, strong) NSTimer* launchTimer;
@property(nonatomic, assign) NSInteger countdown;

@end

@implementation RootViewController {
	NSURLSessionDownloadTask* downloadTask;
}

- (BOOL)isLCTweakLoaded {
	NSString* name = @"LiveContainer.app/Frameworks/TweakLoader.dylib";
	int dyld_count = _dyld_image_count();
	for (int i = 0; i < dyld_count; i++) {
		const char* imageName = _dyld_get_image_name(i);
		NSString* res = [NSString stringWithUTF8String:imageName];
		if ([res hasSuffix:name]) {
			return YES;
		}
	}
	return NO;
}

- (void)refreshTheme {
	self.titleLabel.textColor = [Theming getWhiteColor];
	self.settingsButton.backgroundColor = [Theming getDarkColor];
	[self.settingsButton setTintColor:[Theming getWhiteColor]];
	self.optionalTextLabel.textColor = [Theming getFooterColor];
}

- (BOOL)progressVisible {
	return ![self.progressBar isHidden];
}

- (void)progressVisibility:(BOOL)hidden {
	if (self.progressBar != nil) {
		[self.progressBar setHidden:hidden];
		[self.progressBar setCancelHidden:NO];
	}
}

- (void)progressText:(NSString*)text {
	if (self.progressBar != nil) {
		[self.progressBar setProgressText:text];
	}
}

- (void)progressCancelVisibility:(BOOL)hidden {
	if (self.progressBar != nil) {
		[self.progressBar setHidden:hidden];
		[self.progressBar setCancelHidden:YES];
	}
}

- (void)barProgress:(CGFloat)value {
	if (self.progressBar != nil) {
		[self.progressBar setProgress:value];
	}
}

- (void)countdownUpdate {
	self.countdown--;
	if (self.countdown < 0)
		self.countdown = 0;
	self.optionalTextLabel.text = [@"launcher.status.automatic-launch" localizeWithFormat:[NSString stringWithFormat:@"%ld", (long)self.countdown]];

	if (self.countdown <= 0) {
		self.optionalTextLabel.text = @"launcher.status.automatic-launch.end".loc;
		[self.launchTimer invalidate];
		self.launchTimer = nil;
		[self launchGame];
	}
}

- (void)updateState {
	self.logoImageView.frame = CGRectMake(self.view.center.x - 75, self.view.center.y - 130, 150, 150);
	self.titleLabel.frame = CGRectMake(0, CGRectGetMaxY(self.logoImageView.frame) + 15, self.view.bounds.size.width, 35);
	self.optionalTextLabel.frame = CGRectMake(0, CGRectGetMaxY(self.titleLabel.frame) + 10, self.view.bounds.size.width, 40);
	self.launchButton.frame = CGRectMake(self.view.center.x - 95, CGRectGetMaxY(self.titleLabel.frame) + 15, 140, 45);
	self.settingsButton.frame = CGRectMake(self.view.center.x + 50, CGRectGetMaxY(self.titleLabel.frame) + 15, 45, 45);

	NSString* errStr = [[Utils getPrefs] stringForKey:@"error"];
	if (errStr != nil) {
		AppLog(@"Found error: %@", errStr);
		[Utils showError:self title:[@"launcher.error.gd" localizeWithFormat:errStr] error:nil];
		[[Utils getPrefs] setObject:nil forKey:@"error"];
	} else {
		// add logic for checking crash logs, lastCrash
	}

	self.launchButton.backgroundColor = [Theming getAccentColor];
	[self.launchButton setTitleColor:[Theming getTextColor:[Theming getAccentColor]] forState:UIControlStateNormal];
	[self.launchButton setTintColor:[Theming getTextColor:[Theming getAccentColor]]];

	[self.progressBar setProgressText:@"launcher.progress.download.text".loc];

	[self.optionalTextLabel setHidden:YES];
	[self.launchButton setEnabled:YES];
	[self.launchButton removeTarget:nil action:nil forControlEvents:UIControlEventTouchUpInside];
	if ([VerifyInstall verifyAll]) {
		[UIApplication sharedApplication].idleTimerDisabled = NO;
		[self.launchButton setTitle:@"launcher.launch".loc forState:UIControlStateNormal];
		[self.launchButton setImage:[[UIImage systemImageNamed:@"play.fill"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateNormal];
		if ([[Utils getPrefs] boolForKey:@"LOAD_AUTOMATICALLY"]) {
			[self.optionalTextLabel setHidden:NO];
			self.launchButton.frame = CGRectMake(self.view.center.x - 95, CGRectGetMaxY(self.optionalTextLabel.frame) + 15, 140, 45);
			self.settingsButton.frame = CGRectMake(self.view.center.x + 50, CGRectGetMaxY(self.optionalTextLabel.frame) + 15, 45, 45);
			self.countdown = 3;
			[self countdownUpdate];
			self.launchTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(countdownUpdate) userInfo:nil repeats:YES];
		} else {
			[self.launchButton addTarget:self action:@selector(launchGame) forControlEvents:UIControlEventTouchUpInside];
		}
	} else {
		[self.optionalTextLabel setHidden:NO];
		if (![VerifyInstall verifyGDAuthenticity] && ![VerifyInstall verifyGDInstalled]) {
			self.launchButton.frame = CGRectMake(self.view.center.x - 85, CGRectGetMaxY(self.optionalTextLabel.frame) + 15, 110, 45);
			self.settingsButton.frame = CGRectMake(self.view.center.x + 30, CGRectGetMaxY(self.optionalTextLabel.frame) + 15, 45, 45);
			self.optionalTextLabel.text = @"launcher.status.not-verified".loc;
			[self.launchButton setTitle:@"launcher.verify-gd".loc forState:UIControlStateNormal];
			[self.launchButton setImage:[[UIImage systemImageNamed:@"checkmark.circle"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateNormal];
			[self.launchButton addTarget:self action:@selector(verifyGame) forControlEvents:UIControlEventTouchUpInside];
		} else if (![VerifyInstall verifyGDInstalled] || ![VerifyInstall verifyGeodeInstalled]) {
			self.launchButton.frame = CGRectMake(self.launchButton.frame.origin.x, CGRectGetMaxY(self.optionalTextLabel.frame) + 10, 140, 45);
			self.settingsButton.frame = CGRectMake(self.settingsButton.frame.origin.x, CGRectGetMaxY(self.optionalTextLabel.frame) + 10, 45, 45);
			self.optionalTextLabel.text = @"launcher.status.not-installed".loc;
			[self.launchButton setTitle:@"launcher.download".loc forState:UIControlStateNormal];
			[self.launchButton setImage:[[UIImage systemImageNamed:@"tray.and.arrow.down"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
							   forState:UIControlStateNormal];
			[self.launchButton addTarget:self action:@selector(downloadGame) forControlEvents:UIControlEventTouchUpInside];
		} else if ([VerifyInstall verifyAll]) {
			self.launchButton.frame = CGRectMake(self.launchButton.frame.origin.x, CGRectGetMaxY(self.optionalTextLabel.frame) + 10, 140, 45);
			self.settingsButton.frame = CGRectMake(self.settingsButton.frame.origin.x, CGRectGetMaxY(self.optionalTextLabel.frame) + 10, 45, 45);
			[self.launchButton setEnabled:NO];
			self.optionalTextLabel.text = @"launcher.status.check-updates".loc;
			[self.launchButton setTitle:@"launcher.update".loc forState:UIControlStateNormal];
			[self.launchButton setImage:[[UIImage systemImageNamed:@"tray.and.arrow.down"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
							   forState:UIControlStateNormal];
			[self.launchButton addTarget:self action:@selector(updateGeode) forControlEvents:UIControlEventTouchUpInside];
			[[GeodeInstaller alloc] checkUpdates:self download:YES];
		}
	}
}

- (void)viewDidLoad {
	[super viewDidLoad];
	[Utils increaseLaunchCount];
	[LogUtils clearLogs];
	NSError* err;
	[LCPath ensureAppGroupPaths:&err];
	if (err) {
		AppLog(@"error while making app paths: %@", err);
	}
	self.logoImageView = [Utils imageViewFromPDF:@"geode_logo"];
	if (self.logoImageView) {
		self.logoImageView.layer.cornerRadius = 50;
		self.logoImageView.clipsToBounds = YES;
		[self.view addSubview:self.logoImageView];
	} else {
		// self.logoImageView.backgroundColor = [UIColor redColor];
		AppLog(@"Image is null");
	}

	self.titleLabel = [[UILabel alloc] init];
	self.titleLabel.text = @"Geode";
	self.titleLabel.textColor = [Theming getWhiteColor];
	self.titleLabel.textAlignment = NSTextAlignmentCenter;
	self.titleLabel.font = [UIFont systemFontOfSize:35 weight:UIFontWeightRegular];
	[self.view addSubview:self.titleLabel];

	// for things like if it errored or needs installing...
	self.optionalTextLabel = [[UILabel alloc] init];
	self.optionalTextLabel.numberOfLines = 2;
	self.optionalTextLabel.text = @"launcher.status.not-installed".loc;
	self.optionalTextLabel.textColor = [Theming getFooterColor];
	self.optionalTextLabel.textAlignment = NSTextAlignmentCenter;
	self.optionalTextLabel.font = [UIFont systemFontOfSize:16];
	[self.optionalTextLabel setHidden:YES];
	[self.view addSubview:self.optionalTextLabel];

	// Launch or install button
	self.launchButton = [UIButton buttonWithType:UIButtonTypeSystem];

	self.launchButton.layer.cornerRadius = 22.5;
	self.launchButton.titleEdgeInsets = UIEdgeInsetsMake(0, 8, 0, 0);
	self.launchButton.imageEdgeInsets = UIEdgeInsetsMake(0, 0, 0, 8);
	[self.view addSubview:self.launchButton];

	// Settings button for settings!
	self.settingsButton = [UIButton buttonWithType:UIButtonTypeSystem];
	self.settingsButton.backgroundColor = [Theming getDarkColor];
	self.settingsButton.clipsToBounds = YES;
	self.settingsButton.layer.cornerRadius = 22.5;
	[self.settingsButton setImage:[[UIImage systemImageNamed:@"gearshape.fill"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateNormal];
	[self.settingsButton setTintColor:[Theming getWhiteColor]];
	[self.settingsButton addTarget:self action:@selector(showSettings) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:self.settingsButton];

	// progress bar for downloading!
	self.progressBar = [[ProgressBar alloc] initWithFrame:CGRectMake(self.view.center.x - 140, self.view.center.y + 200, 280, 68)
											 progressText:@"launcher.progress.download.text".loc // note for me, nil for no string
										 showCancelButton:YES
													 root:self];
	[self.progressBar setHidden:YES];
	[self.view addSubview:self.progressBar];

	if ([self isLCTweakLoaded]) {
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.75 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			[Utils showNotice:self title:@"In LiveContainer, please enable \"Launch with JIT\", \"Don't Inject TweakLoader\" & \"Don't Load TweakLoader\", otherwise Geode will "
										 @"not launch properly. JIT-Less mode may NOT work on LiveContainer."];
		});
	} else if (![Utils isSandboxed]) {
		if (![Utils getGDDocPath]) {
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.75 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
				[Utils showNotice:self
							title:@"Couldn't find Geometry Dash's documents directory! Please ensure that Geometry Dash is installed, otherwise Geode cannot not install."];
			});
		}
	}

	// making sure it has right attributes
	NSFileManager* fm = NSFileManager.defaultManager;
	NSURL* gdPath = [[LCPath bundlePath] URLByAppendingPathComponent:[Utils gdBundleName]];
	NSURL* emptyFile = [gdPath URLByAppendingPathComponent:@"Geode"];
	if ([fm fileExistsAtPath:emptyFile.path]) {
		// so people can actually deactivate from SideStore
		[fm removeItemAtURL:emptyFile error:nil];
	}

	/*
	// TODO: Change to "App" rather than having .app at the end
	if ([fm fileExistsAtPath:gdPath.path]) {
		NSError *error = nil;
		NSDictionary *currentAttributes = [fm attributesOfItemAtPath:gdPath.path error:&error];
		if (!error) {
			if (![currentAttributes[NSFileType] isEqualToString:NSFileTypeDirectory]) {
				AppLog(@"Attributes aren't a directory! Changing that...");
				NSDictionary *newAttributes = @{NSFileType: NSFileTypeDirectory};
				error = nil;
				BOOL success = [fm setAttributes:newAttributes ofItemAtPath:gdPath.path error:&error];
				if (!success || error) {
					AppLog(@"Error updating directory attributes: %@", error);
				} else {
					AppLog(@"Updated attribute file type!")
				}
			} else {
				NSNumber *perms = currentAttributes[NSFilePosixPermissions];
				NSNumber *newPerms = @(0755); // rwxr-xr-x
				if (![perms isEqualToNumber:newPerms]) {
					NSMutableDictionary *newAttributes = [NSMutableDictionary dictionaryWithDictionary:currentAttributes];
					[newAttributes setObject:newPerms forKey:NSFilePosixPermissions];
					BOOL success = [fm setAttributes:newAttributes ofItemAtPath:gdPath.path error:&error];
					if (!success || error) {
						AppLog(@"Error updating directory permissions: %@", error);
					} else {
						AppLog(@"Updated attribute permissions!")
					}
				}
				if ([currentAttributes[NSFileExtensionHidden] isEqualToNumber:@(1)]) {
					AppLog(@"Setting NSFileExtensionHidden to 0");
					NSMutableDictionary *newAttributes = [NSMutableDictionary dictionaryWithDictionary:currentAttributes];
					[newAttributes setObject:@(0) forKey:NSFileExtensionHidden];
					BOOL success = [fm setAttributes:newAttributes ofItemAtPath:gdPath.path error:&error];
					if (!success || error) {
						AppLog(@"Error updating directory permissions: %@", error);
					} else {
						AppLog(@"Updated attribute hidden extension!")
					}
				}
			}
		} else {
			AppLog(@"Error getting attributes: %@", error);
		}
	}
	*/
}

- (void)startWeb {
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	[self startWeb];
	[self updateState];
}

- (void)verifyGame {
	[VerifyInstall startVerifyGDAuth:self];
}

- (void)showSettings {
	if (self.launchTimer != nil) {
		[self.launchTimer invalidate];
		self.launchTimer = nil;
		[self.launchButton addTarget:self action:@selector(launchGame) forControlEvents:UIControlEventTouchUpInside];
		[self.optionalTextLabel setHidden:YES];
		self.launchButton.frame = CGRectMake(self.view.center.x - 95, CGRectGetMaxY(self.titleLabel.frame) + 15, 140, 45);
		self.settingsButton.frame = CGRectMake(self.view.center.x + 50, CGRectGetMaxY(self.titleLabel.frame) + 15, 45, 45);
	}
	SettingsVC* settings = [[SettingsVC alloc] initWithNibName:nil bundle:nil];
	settings.root = self;
	UINavigationController* navController = [[UINavigationController alloc] initWithRootViewController:settings];
	[self presentViewController:navController animated:YES completion:nil];
}
- (void)updateGeode {
	[[GeodeInstaller alloc] checkUpdates:self download:YES];
}
- (void)downloadGame {
	if (![Utils isSandboxed]) { // since jit doesnt work anyways... why would we install it twice??
		if (![VerifyInstall verifyGeodeInstalled]) {
			self.optionalTextLabel.text = @"launcher.status.download-geode".loc;
			[[[GeodeInstaller alloc] init] startInstall:self ignoreRoot:NO];
		} else {
			[Utils showNotice:self title:@"launcher.notice.ts.install".loc];
		}
		return;
	}
	if (![VerifyInstall verifyGDAuthenticity]) {
		[Utils showError:self title:@"launcher.status.not-verified".loc error:nil];
		return;
	}
	[self.launchButton setEnabled:NO];
	[UIApplication sharedApplication].idleTimerDisabled = YES;
	if ([VerifyInstall verifyGDInstalled] && ![VerifyInstall verifyGeodeInstalled]) {
		[[[GeodeInstaller alloc] init] startInstall:self ignoreRoot:NO];
	} else {
		if (![VerifyInstall verifyGDAuthenticity])
			return AppLog(@"GD not verified! Not installing!");
		// this is all so unnecessary, just use import IPA if you're that desperate
		NSData* b64Data = [[NSData alloc] initWithBase64EncodedString:@"__KEY_PART2__" options:0];
		if (!b64Data) {
			[Utils showError:self title:@"launcher.error.non".loc error:nil];
			[self updateState];
			return;
		}
		NSString* b64 = [[NSString alloc] initWithData:b64Data encoding:NSUTF8StringEncoding];
		[self.progressBar setHidden:NO];
		NSURLRequest* request2 = [NSURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@", b64]]];
		NSURLSession* session2 = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
		NSURLSessionDataTask* dataTask = [session2 dataTaskWithRequest:request2 completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
			if (error) {
				return dispatch_async(dispatch_get_main_queue(), ^{
					[Utils showError:self title:@"launcher.error.req-failed".loc error:error];
					[self updateState];
					AppLog(@"Error during request: %@", error);
				});
			}
			if (data) {
				NSString* keyData = [[NSString stringWithFormat:@"%@__KEY_PART1__", [[NSString alloc] initWithData:data
																										  encoding:NSUTF8StringEncoding]] stringByReplacingOccurrencesOfString:@"\n"
																																									withString:@""];
				NSString* eStr = @"__DOWNLOAD_LINK__";
				NSData* dataToDecrypt = [[NSData alloc] initWithBase64EncodedString:eStr options:0];
				NSString* decoded = [[NSString alloc] initWithData:[Utils decryptData:dataToDecrypt withKey:keyData] encoding:NSUTF8StringEncoding];

				NSData* decodedb64Data = [[NSData alloc] initWithBase64EncodedString:decoded options:0];
				if (!decodedb64Data) {
					dispatch_async(dispatch_get_main_queue(), ^{
						[Utils showError:self title:@"launcher.error.req-failed".loc error:nil];
						[self updateState];
						AppLog(@"Error during decoding, data is invalid.");
					});
					return;
				}
				NSString* decb64 = [[NSString alloc] initWithData:decodedb64Data encoding:NSUTF8StringEncoding];
				dispatch_async(dispatch_get_main_queue(), ^{
					NSURLSession* session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration] delegate:self delegateQueue:nil];
					downloadTask = [session downloadTaskWithURL:[NSURL URLWithString:decb64]];
					[downloadTask resume];
				});
			} else {
				dispatch_async(dispatch_get_main_queue(), ^{
					[Utils showError:self title:@"launcher.error.req-failed".loc error:nil];
					[self updateState];
					AppLog(@"Error during request, data is invalid.");
				});
			}
		}];
		[dataTask resume];
	}
}

- (void)signApp:(BOOL)force completionHandler:(void (^)(BOOL success, NSString* error))completionHandler {
	if (![[Utils getPrefs] boolForKey:@"JITLESS"])
		return completionHandler(YES, nil);
	LCAppInfo* app = [[LCAppInfo alloc] initWithBundlePath:[[LCPath bundlePath] URLByAppendingPathComponent:@"com.robtop.geometryjump.app"].path];
	[app patchExecAndSignIfNeedWithCompletionHandler:^(BOOL signSuccess, NSString* signError) {
		if (signError)
			return completionHandler(NO, signError);
		[LCUtils signTweaks:[LCPath tweakPath] force:force progressHandler:^(NSProgress* progress) {} completion:^(NSError* error) {
			if (error != nil) {
				AppLog(@"Detailed error for signing tweaks: %@", error);
				return completionHandler(
					NO, [NSString stringWithFormat:@"Couldn't sign tweaks. Please make sure that you have either patched %@, or imported a certificate in settings.",
												   [LCUtils getStoreName]]);
			}
			[LCUtils signMods:[[LCPath dataPath] URLByAppendingPathComponent:@"GeometryDash/Documents/game/geode"] force:force progressHandler:^(NSProgress* progress) {}
				completion:^(NSError* error) {
					if (error != nil) {
						AppLog(@"Detailed error for signing mods: %@", error);
						return completionHandler(
							NO, [NSString stringWithFormat:@"Couldn't sign mods. Please make sure that you have either patched %@, or imported a certificate in settings.",
														   [LCUtils getStoreName]]);
					}
					completionHandler(YES, nil);
				}];
		}];
	} progressHandler:^(NSProgress* signProgress) {} forceSign:force];
}

- (void)launchGame {
	[self.launchButton setEnabled:NO];
	if (([[Utils getPrefs] boolForKey:@"MANUAL_REOPEN"] && [Utils isSandboxed]) || NSClassFromString(@"LCSharedUtils")) {
		[[Utils getPrefs] setValue:[Utils gdBundleName] forKey:@"selected"];
		[[Utils getPrefs] setValue:@"GeometryDash" forKey:@"selectedContainer"];
		[[Utils getPrefs] setBool:NO forKey:@"safemode"];
		NSFileManager* fm = [NSFileManager defaultManager];
		[fm createFileAtPath:[[LCPath docPath] URLByAppendingPathComponent:@"jitflag"].path contents:[[NSData alloc] init] attributes:@{}];
		// get around NSUserDefaults because sometimes it works and doesnt work when relaunching...
		if (NSClassFromString(@"LCSharedUtils")) {
			[Utils showNotice:self title:@"launcher.relaunch-notice.lc".loc];
		} else {
			[Utils showNotice:self title:@"launcher.relaunch-notice".loc];
		}
		return;
	}
	if (![Utils isSandboxed]) {
		[Utils tweakLaunch_withSafeMode:false];
		return;
	}
	NSString* openURL = [NSString stringWithFormat:@"geode://launch"];
	NSURL* url = [NSURL URLWithString:openURL];
	if ([[NSClassFromString(@"UIApplication") sharedApplication] canOpenURL:url]) {
		[[NSClassFromString(@"UIApplication") sharedApplication] openURL:url options:@{} completionHandler:nil];
		return;
	}
	/*
		[[Utils getPrefs] setValue:[Utils gdBundleName] forKey:@"selected"];
		[[Utils getPrefs] setValue:@"GeometryDash" forKey:@"selectedContainer"];
		[[Utils getPrefs] setBool:NO forKey:@"safemode"];
		[self signApp:NO completionHandler:^(BOOL success, NSString *error){
			if (!success) {
				dispatch_async(dispatch_get_main_queue(), ^{
					[Utils showError:self title:error error:nil];
					[self updateState];
				});
				return;
			}
			if (![LCUtils launchToGuestApp]) {
				dispatch_async(dispatch_get_main_queue(), ^{
					NSFileManager *fm = [NSFileManager defaultManager];
					[fm createFileAtPath:
						[[LCPath docPath] URLByAppendingPathComponent:@"jitflag"].path
						contents:[[NSData alloc] init]
						attributes:@{}
					];
					 // get around NSUserDefaults because sometimes it works and doesnt work when relaunching...
					[Utils showNotice:self title:@"Relaunch the app with JIT to start Geode!"];
				});
			}
		}];
		*/
}

// download part because im too lazy to impl delegates in the other class
// updating
- (void)URLSession:(NSURLSession*)session
				 downloadTask:(NSURLSessionDownloadTask*)downloadTask
				 didWriteData:(int64_t)bytesWritten
			totalBytesWritten:(int64_t)totalBytesWritten
	totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
	dispatch_async(dispatch_get_main_queue(), ^{
		CGFloat progress = (CGFloat)totalBytesWritten / (CGFloat)totalBytesExpectedToWrite * 100.0;
		[self.progressBar setProgress:progress];
	});
}

// finish
- (void)URLSession:(NSURLSession*)session downloadTask:(NSURLSessionDownloadTask*)downloadTask didFinishDownloadingToURL:(NSURL*)location {
	dispatch_async(dispatch_get_main_queue(), ^{
		// so apparently i have to run this asynchronously or else it wont work... WHY
		AppLog(@"start installing ipa!");
		self.optionalTextLabel.text = @"launcher.status.extracting".loc;
		[self.progressBar setProgressText:@"launcher.progress.extract.text".loc];
		[self.progressBar setHidden:NO];
		[self.progressBar setCancelHidden:YES];
	});
	// and i cant run this asynchronously!? this is... WHY
	[VerifyInstall startGDInstall:self url:location];
}

// error
- (void)URLSession:(NSURLSession*)session task:(NSURLSessionTask*)task didCompleteWithError:(NSError*)error {
	dispatch_async(dispatch_get_main_queue(), ^{
		if (error) {
			[Utils showError:self title:@"launcher.error.download-fail".loc error:error];
			[self.progressBar setHidden:YES];
		}
	});
}

- (void)cancelDownload {
	if (downloadTask != nil) {
		[downloadTask cancel];
	}
	[self.progressBar setHidden:YES];
}

@end

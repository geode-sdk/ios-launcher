#import "EnterpriseCompare.h"
#import "GeodeInstaller.h"
#import "LCUtils/GCSharedUtils.h"
#import "LCUtils/LCUtils.h"
#import "LCUtils/Shared.h"
#include "LCUtils/unarchive.h"
#import "LCUtils/utils.h"
#import "Patcher.h"
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
#include <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <objc/runtime.h>

#define LOCAL_BUILD 0
#define LOCAL_URL "http://192.168.1.22:3000/Geometry-2.207.ipa"

@interface RootViewController ()

@property(nonatomic, strong) ProgressBar* progressBar;
@property(nonatomic, strong) NSTimer* launchTimer;
@property(nonatomic, assign) NSInteger countdown;
@property(nonatomic, strong) NSArray* icons;

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
		[self launchGame];
	}
}

- (void)updateState {
	[self updatePatchStatus];
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
		if ([[Utils getPrefs] boolForKey:@"LOAD_AUTOMATICALLY"] && self.countdown != -5) {
			[self.optionalTextLabel setHidden:NO];
			self.launchButton.frame = CGRectMake(self.view.center.x - 95, CGRectGetMaxY(self.optionalTextLabel.frame) + 15, 140, 45);
			self.settingsButton.frame = CGRectMake(self.view.center.x + 50, CGRectGetMaxY(self.optionalTextLabel.frame) + 15, 45, 45);
			self.countdown = 3;
			[self countdownUpdate];
			self.launchTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(countdownUpdate) userInfo:nil repeats:YES];
			[self.launchButton addTarget:self action:@selector(launchGame) forControlEvents:UIControlEventTouchUpInside];
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

// TODO: Add another "patching" function which will patch but not write, that way it knows ahead of time whether it will need patching
- (void)updatePatchStatus {
	self.patchStatus.backgroundColor = [UIColor systemGreenColor];
	[self.patchStatus setHidden:![[Utils getPrefs] boolForKey:@"ENTERPRISE_MODE"]];
	NSString* patchChecksum = [[Utils getPrefs] stringForKey:@"PATCH_CHECKSUM"];

	NSURL* bundlePath = [[LCPath bundlePath] URLByAppendingPathComponent:[Utils gdBundleName]];
	NSString* checksum = [Patcher getPatchChecksum:[bundlePath URLByAppendingPathComponent:@"GeometryOriginal"] withSafeMode:NO];
	if ((checksum != nil && ![checksum isEqualToString:patchChecksum])) {
		AppLog(@"Patch diff: %@ vs %@", checksum, patchChecksum);
		self.patchStatus.backgroundColor = [UIColor systemYellowColor];
	}
	if ([patchChecksum isEqualToString:@"NO"]) {
		self.patchStatus.backgroundColor = [UIColor systemRedColor];
	}
	if ([[Utils getPrefs] boolForKey:@"IS_COMPRESSING_IPA"]) {
		self.patchStatus.backgroundColor = [UIColor systemOrangeColor];
	}
}
- (void)showPatchStatusMsg:(UITapGestureRecognizer*)gestureRecognizer {
	if (gestureRecognizer.state == UIGestureRecognizerStateEnded) {
		[self updatePatchStatus];
		[Utils showNotice:self title:@"launcher.notice.enterprise.status".loc];
	}
}

- (void)updateLogoImage:(NSInteger)index {
	if (self.icons[index]) {
		[self.logoImageView setImage:[Utils imageViewFromPDF:self.icons[index][@"Logo"]].image];
	}
}

- (void)viewDidLoad {
	[super viewDidLoad];
	[Utils increaseLaunchCount];

	_icons = @[
		@{ @"name" : @"Default", @"Logo" : @"geode_logo", @"iconName" : @"AppIcon" },
		@{ @"name" : @"Geode", @"Logo" : @"new_geode_logo", @"iconName" : @"Geode" },
		@{ @"name" : @"Pride", @"Logo" : @"pride_logo", @"iconName" : @"Pride" },
		@{ @"name" : @"Lesbian", @"Logo" : @"lesbian_logo", @"iconName" : @"Lesbian" },
		@{ @"name" : @"Gay", @"Logo" : @"gay_logo", @"iconName" : @"Gay" },
		@{ @"name" : @"Bi", @"Logo" : @"bi_logo", @"iconName" : @"Bi" },
		@{ @"name" : @"Trans", @"Logo" : @"trans_logo", @"iconName" : @"Trans" },
		@{ @"name" : @"Pan", @"Logo" : @"pan_logo", @"iconName" : @"Pan" },
		@{ @"name" : @"Nonbinary", @"Logo" : @"nonbinary_logo", @"iconName" : @"Nonbinary" },
		@{ @"name" : @"Asexual", @"Logo" : @"asexual_logo", @"iconName" : @"Asexual" },
		@{ @"name" : @"Genderfluid", @"Logo" : @"genderfluid_logo", @"iconName" : @"Genderfluid" },
		@{ @"name" : @"Perfection.", @"Logo" : @"pride_logo", @"iconName" : @"Perfection" }
	];

	self.impactFeedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy];
	[self.impactFeedback prepare];
	[LogUtils clearLogs:NO];
	NSError* err;
	[LCPath ensureAppGroupPaths:&err];
	if (err) {
		AppLog(@"error while making app paths: %@", err);
	}
	NSString* iconKey = [[Utils getPrefs] stringForKey:@"CURRENT_ICON"];
	NSString* currentIcon = [UIApplication sharedApplication].alternateIconName;
	if (currentIcon == nil) {
		if (iconKey == nil) {
			[[Utils getPrefs] setValue:@"Default" forKey:@"CURRENT_ICON"];
		}
	} else {
		if (iconKey == nil) {
			NSString *foundName = nil;
			for (NSDictionary *dict in _icons) {
				if ([dict[@"iconName"] isEqualToString:currentIcon]) {
					foundName = dict[@"name"];
					break;
				}
			}
			if (foundName) {
				[[Utils getPrefs] setValue:foundName forKey:@"CURRENT_ICON"];
				iconKey = foundName;
			}
		}
	}
	NSString *logoFile = nil;
	if (iconKey) {
		for (NSDictionary *dict in _icons) {
			if ([dict[@"name"] isEqualToString:iconKey]) {
				logoFile = dict[@"Logo"];
				break;
			}
		}
	}
	if (logoFile) {
		self.logoImageView = [Utils imageViewFromPDF:logoFile];
	} else {
		self.logoImageView = [Utils imageViewFromPDF:@"geode_logo"];
	}
	//self.logoImageView = [Utils imageViewFromPDF:@"geode_logo"];
	if (self.logoImageView) {
		self.logoImageView.layer.cornerRadius = 50;
		self.logoImageView.clipsToBounds = YES;
		[self.view addSubview:self.logoImageView];
	} else {
		// self.logoImageView.backgroundColor = [UIColor redColor];
		AppLog(@"Image is null");
	}

	self.logoImageView.userInteractionEnabled = YES;
	UILongPressGestureRecognizer* longPressGR = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(fish:)];
	[self.logoImageView addGestureRecognizer:longPressGR];

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

	CGFloat dotSize = 20.0;
	self.patchStatus = [[UIView alloc] initWithFrame:CGRectMake(CGRectGetWidth(self.view.frame) - dotSize - 20.0, 60.0, dotSize, dotSize)];
	self.patchStatus.backgroundColor = [UIColor systemGreenColor];
	self.patchStatus.layer.cornerRadius = dotSize / 2;
	self.patchStatus.layer.masksToBounds = YES;
	[self.view addSubview:self.patchStatus];
	self.patchStatus.userInteractionEnabled = YES;
	UITapGestureRecognizer* pressGR = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(showPatchStatusMsg:)];
	[self.patchStatus addGestureRecognizer:pressGR];
	[self updatePatchStatus];

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

	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.75 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		if ([self isLCTweakLoaded]) {
			[Utils showNotice:self title:@"In LiveContainer, please enable \"Launch with JIT\", \"Don't Inject TweakLoader\" & \"Don't Load TweakLoader\", otherwise Geode will "
										 @"not launch properly. JIT-Less mode may NOT work on LiveContainer."];
		} else if (![Utils isSandboxed]) {
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
				if (![Utils getGDDocPath]) {
					[Utils showNotice:self
								title:@"Couldn't find Geometry Dash's documents directory! Please ensure that Geometry Dash is installed, otherwise Geode cannot not install."];
				}
			});
		} else if (!NSClassFromString(@"LCSharedUtils") && [Utils isSandboxed]) {
			// i still am unsure what compels users to open with jit when its not needed *unless* you want to launch gd, so ill just warn them that they dont need to waste their
			// time doing that!
			int flags;
			csops(getpid(), 0, &flags, sizeof(flags)); // im not sure if dopamine just changes PPL or runs every app as debugged but it doesn't for me so this works
			if ((flags & CS_DEBUGGED) != 0) {
				// mission failed successfully
				AppLog(@"User tried running launcher with JIT but didn't know they had to press the launch button... Let's warn them about that.");
				if (![[Utils getPrefs] boolForKey:@"DONT_WARN_JIT"]) {
					[Utils showNotice:self title:@"jit.warning".loc];
				}
			}
		}
	});

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

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	[self updateState];
}

- (void)verifyGame {
	[VerifyInstall startVerifyGDAuth:self];
}

- (void)showSettings {
	[self updatePatchStatus];
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

- (void)fish:(UILongPressGestureRecognizer*)gestureRecognizer {
	if (gestureRecognizer.state != UIGestureRecognizerStateCancelled && !self.hasTappedFish) {
		self.processOfTappedFish = NO;
	}
	if (gestureRecognizer.state == UIGestureRecognizerStateBegan && !self.hasTappedFish) {
		self.processOfTappedFish = YES;
		[self loadFishAnimation];
		[self.impactFeedback impactOccurredWithIntensity:0.25];
		[self.impactFeedback prepare];
		[UIView animateWithDuration:0.5 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{ self.logoImageView.transform = CGAffineTransformMakeRotation(M_PI); }
			completion:^(BOOL finished) {
				if (finished && self.processOfTappedFish) {
					[self.impactFeedback impactOccurredWithIntensity:0.5];
					[self.impactFeedback prepare];
					[UIView animateWithDuration:0.5 delay:0 options:UIViewAnimationOptionCurveEaseOut
						animations:^{ self.logoImageView.transform = CGAffineTransformMakeRotation(M_PI_2); } completion:^(BOOL finished2) {
							if (finished2 && self.processOfTappedFish) {
								self.hasTappedFish = YES;
								self.processOfTappedFish = NO;
								[self.impactFeedback impactOccurredWithIntensity:1.0];
								[self.impactFeedback prepare];

								UIImageView* fishImageView = [[UIImageView alloc] init];
								fishImageView.image = self.cachedFishAnimation;
								fishImageView.contentMode = UIViewContentModeCenter;
								fishImageView.clipsToBounds = YES;
								fishImageView.alpha = 0.f;
								fishImageView.frame = self.logoImageView.frame;
								fishImageView.contentScaleFactor /= 3; // yes we divide instead of multiplying, that definitely makes sense apple

								/* i wanted to do rainbow but i cant figure it out
								CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"tintColor"];
								animation.fromValue = [NSNumber numberWithFloat:1.0];
								animation.toValue = [NSNumber numberWithFloat:0.0];
								animation.duration = 1.0;
								animation.repeatCount = HUGE_VALF;*/

								[self.view addSubview:fishImageView];

								[UIView animateWithDuration:0.5 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
									self.logoImageView.alpha = 0.f;
									fishImageView.alpha = 1.f;
									self.titleLabel.text = @"fish";
								} completion:^(BOOL finished3) {
									if (finished3) {
										self.fishes = [[NSMutableArray alloc] init];
										[self startFishRain];
									}
								}];
							}
						}];
				}
			}];
	}
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
		if (LOCAL_BUILD == 1) {
			AppLog(@"Downloading locally");
			NSURLSession* session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration] delegate:self delegateQueue:nil];
			downloadTask = [session downloadTaskWithURL:[NSURL URLWithString:@LOCAL_URL]];
			[downloadTask resume];
			return;
		}
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

- (void)signAppWithSafeMode:(void (^)(BOOL success, NSString* error))completionHandler {
	NSURL* bundlePath = [[LCPath bundlePath] URLByAppendingPathComponent:[Utils gdBundleName]];
	if ([[Utils getPrefs] boolForKey:@"JITLESS"]) {
		[Patcher patchGDBinary:[bundlePath URLByAppendingPathComponent:@"GeometryOriginal"] to:[bundlePath URLByAppendingPathComponent:@"GeometryJump"] withHandlerAddress:0x8b8000
						 force:NO
				  withSafeMode:YES
			  withEntitlements:NO completionHandler:^(BOOL success, NSString* error) {
				  dispatch_async(dispatch_get_main_queue(), ^{
					  if (success) {
						  if (![[Utils getPrefs] boolForKey:@"JITLESS"])
							  return completionHandler(YES, nil);
						  BOOL force = NO;
						  if ([error isEqualToString:@"force"]) {
							  AppLog(@"Signing is forced!");
							  force = YES;
						  }
						  self.optionalTextLabel.text = @"launcher.status.signing".loc;
						  if ([LCUtils certificateData]) {
							  [LCUtils validateCertificate:^(int status, NSDate* expirationDate, NSString* errorC) {
								  if (errorC) {
									  return completionHandler(NO, [NSString stringWithFormat:@"launcher.error.sign.invalidcert".loc, errorC]);
								  }
								  if (status != 0) {
									  return completionHandler(NO, @"launcher.error.sign.invalidcert2".loc);
								  }
								  LCAppInfo* app = [[LCAppInfo alloc] initWithBundlePath:[[LCPath bundlePath] URLByAppendingPathComponent:@"com.robtop.geometryjump.app"].path];
								  [app patchExecAndSignIfNeedWithCompletionHandler:^(BOOL signSuccess, NSString* signError) {
									  if (signError)
										  return completionHandler(NO, signError);
									  [LCUtils signTweaks:[LCPath tweakPath] force:force progressHandler:^(NSProgress* progress) {} completion:^(NSError* error) {
										  if (error != nil) {
											  AppLog(@"Detailed error for signing tweaks: %@", error);
											  return completionHandler(NO, @"Couldn't sign tweaks. Please make sure that you imported a certificate in settings.");
										  }
										  if (error != nil) {
											  AppLog(@"Detailed error for signing mods: %@", error);
											  return completionHandler(NO, @"Couldn't sign mods. Please make sure that you imported a certificate in settings.");
										  }
										  completionHandler(YES, nil);
									  }];
								  } progressHandler:^(NSProgress* signProgress) {} forceSign:force blockMainThread:YES];
							  }];
						  } else {
							  return completionHandler(NO, @"No certificate found. Please go to settings to import a certificate.");
						  }
					  } else {
						  completionHandler(NO, error);
					  }
				  });
			  }];
	} else if ([[Utils getPrefs] integerForKey:@"FORCE_CERT_JIT"]) {
		// probably should move this... or idk
		[Utils copyOrigBinary:^(BOOL success, NSString *error) {
			dispatch_async(dispatch_get_main_queue(), ^{
				if (success) {
					self.optionalTextLabel.text = @"launcher.status.signing".loc;
					if ([LCUtils certificateData]) {
						[LCUtils validateCertificate:^(int status, NSDate* expirationDate, NSString* errorC) {
							if (errorC) {
								return completionHandler(NO, [NSString stringWithFormat:@"launcher.error.sign.invalidcert".loc, errorC]);
							}
							if (status != 0) {
								return completionHandler(NO, @"launcher.error.sign.invalidcert2".loc);
							}
							LCAppInfo* app = [[LCAppInfo alloc] initWithBundlePath:[[LCPath bundlePath] URLByAppendingPathComponent:@"com.robtop.geometryjump.app"].path];
							[app patchExecAndSignIfNeedWithCompletionHandler:^(BOOL signSuccess, NSString* signError) {
								if (signError)
									return completionHandler(NO, signError);
								[LCUtils signTweaks:[LCPath tweakPath] force:NO progressHandler:^(NSProgress* progress) {} completion:^(NSError* error) {
									if (error != nil) {
										AppLog(@"Detailed error for signing tweaks: %@", error);
										return completionHandler(
											NO,
											@"Couldn't sign tweaks. Please make sure that you imported a certificate in settings.");
									}
									if (error != nil) {
										AppLog(@"Detailed error for signing mods: %@", error);
										return completionHandler(NO, @"Couldn't sign mods. Please make sure that you imported a certificate in settings.");
									}
									completionHandler(YES, nil);
								}];
							} progressHandler:^(NSProgress* signProgress) {} forceSign:NO blockMainThread:YES];
						  }];
					  } else {
						  return completionHandler(NO, @"No certificate found. Please go to settings to import a certificate.");
					  }
				} else {
					completionHandler(NO, error);
				}
			});
		}];
	} else {
		return completionHandler(YES, nil);
	}
}

- (void)signApp:(BOOL)forceSign completionHandler:(void (^)(BOOL success, NSString* error))completionHandler {
	if (![[Utils getPrefs] boolForKey:@"JITLESS"] && ![[Utils getPrefs] boolForKey:@"FORCE_PATCHING"] && ![[Utils getPrefs] integerForKey:@"FORCE_CERT_JIT"])
		return completionHandler(YES, nil);

	NSURL* bundlePath = [[LCPath bundlePath] URLByAppendingPathComponent:[Utils gdBundleName]];
	if ([[Utils getPrefs] boolForKey:@"JITLESS"]) {
		[Patcher patchGDBinary:[bundlePath URLByAppendingPathComponent:@"GeometryOriginal"] to:[bundlePath URLByAppendingPathComponent:@"GeometryJump"] withHandlerAddress:0x8b8000
						 force:NO
				  withSafeMode:NO
			  withEntitlements:NO completionHandler:^(BOOL success, NSString* error) {
				  dispatch_async(dispatch_get_main_queue(), ^{
					  if (success) {
						  if (![[Utils getPrefs] boolForKey:@"JITLESS"])
							  return completionHandler(YES, nil);
						  BOOL force = forceSign;
						  if ([error isEqualToString:@"force"]) {
							  AppLog(@"Signing is forced!");
							  force = YES;
						  }
						  self.optionalTextLabel.text = @"launcher.status.signing".loc;
						  if ([LCUtils certificateData]) {
							  [LCUtils validateCertificate:^(int status, NSDate* expirationDate, NSString* errorC) {
								  if (errorC) {
									  return completionHandler(NO, [NSString stringWithFormat:@"launcher.error.sign.invalidcert".loc, errorC]);
								  }
								  if (status != 0) {
									  return completionHandler(NO, @"launcher.error.sign.invalidcert2".loc);
								  }
								  LCAppInfo* app = [[LCAppInfo alloc] initWithBundlePath:[[LCPath bundlePath] URLByAppendingPathComponent:@"com.robtop.geometryjump.app"].path];
								  [app patchExecAndSignIfNeedWithCompletionHandler:^(BOOL signSuccess, NSString* signError) {
									  if (signError)
										  return completionHandler(NO, signError);
									  [LCUtils signTweaks:[LCPath tweakPath] force:force progressHandler:^(NSProgress* progress) {} completion:^(NSError* error) {
										  if (error != nil) {
											  AppLog(@"Detailed error for signing tweaks: %@", error);
											  return completionHandler(NO, @"Couldn't sign tweaks. Please make sure that you imported a certificate in settings.");
										  }

										  [LCUtils signModsNew:[[LCPath dataPath] URLByAppendingPathComponent:@"game/geode"] force:force progressHandler:^(NSProgress* progress) {}
											  completion:^(NSError* error) {
												  [LCUtils signMods:[[LCPath dataPath] URLByAppendingPathComponent:@"game/geode"] force:force
													  progressHandler:^(NSProgress* progress) {} completion:^(NSError* error) {
														  if (error != nil) {
															  AppLog(@"Detailed error for signing mods: %@", error);
															  return completionHandler(NO, @"Couldn't sign mods. Please make sure that you imported a certificate in settings.");
														  }
														  [[Utils getPrefs] setValue:[Utils gdBundleName] forKey:@"selected"];
														  [[Utils getPrefs] setValue:@"GeometryDash" forKey:@"selectedContainer"];
														  completionHandler(YES, nil);
													  }];
											  }];
									  }];
								  } progressHandler:^(NSProgress* signProgress) {} forceSign:force blockMainThread:YES];
							  }];
						  } else {
							  return completionHandler(NO, @"No certificate found. Please go to settings to import a certificate.");
						  }
					  } else {
						  completionHandler(NO, error);
					  }
			});
		}];
	} else if ([[Utils getPrefs] integerForKey:@"FORCE_CERT_JIT"]) {
		[Utils copyOrigBinary:^(BOOL success, NSString *error) {
			dispatch_async(dispatch_get_main_queue(), ^{
				if (success) {
					BOOL force = forceSign;
					self.optionalTextLabel.text = @"launcher.status.signing".loc;
					if ([LCUtils certificateData]) {
						[LCUtils validateCertificate:^(int status, NSDate* expirationDate, NSString* errorC) {
							if (errorC) {
								return completionHandler(NO, [NSString stringWithFormat:@"launcher.error.sign.invalidcert".loc, errorC]);
							}
							if (status != 0) {
								return completionHandler(NO, @"launcher.error.sign.invalidcert2".loc);
							}
							LCAppInfo* app = [[LCAppInfo alloc] initWithBundlePath:[[LCPath bundlePath] URLByAppendingPathComponent:@"com.robtop.geometryjump.app"].path];
								[app patchExecAndSignIfNeedWithCompletionHandler:^(BOOL signSuccess, NSString* signError) {
								if (signError)
									return completionHandler(NO, signError);
								[LCUtils signTweaks:[LCPath tweakPath] force:force progressHandler:^(NSProgress* progress) {} completion:^(NSError* error) {
									if (error != nil) {
										AppLog(@"Detailed error for signing tweaks: %@", error);
										return completionHandler(NO, @"Couldn't sign tweaks. Please make sure that you imported a certificate in settings.");
									}

									[LCUtils signModsNew:[[LCPath dataPath] URLByAppendingPathComponent:@"game/geode"] force:force progressHandler:^(NSProgress* progress) {} completion:^(NSError* error) {
										[LCUtils signMods:[[LCPath dataPath] URLByAppendingPathComponent:@"game/geode"] force:force progressHandler:^(NSProgress* progress) {} completion:^(NSError* error) {
										if (error != nil) {
											AppLog(@"Detailed error for signing mods: %@", error);
											return completionHandler(NO, @"Couldn't sign mods. Please make sure that you imported a certificate in settings.");
										}
										[[Utils getPrefs] setValue:[Utils gdBundleName] forKey:@"selected"];
										[[Utils getPrefs] setValue:@"GeometryDash" forKey:@"selectedContainer"];
									completionHandler(YES, nil);
										}];
									}];
								}];
							} progressHandler:^(NSProgress* signProgress) {} forceSign:force blockMainThread:YES];
						}];
					} else {
						return completionHandler(NO, @"No certificate found. Please go to settings to import a certificate.");
					}
				} else {
					completionHandler(NO, error);
				}
			});
		}];
	} else {
		[Patcher patchGDBinary:[bundlePath URLByAppendingPathComponent:@"GeometryOriginal"] to:[bundlePath URLByAppendingPathComponent:@"GeometryJump"] withHandlerAddress:0x8b8000
						 force:NO
				  withSafeMode:NO
			  withEntitlements:NO completionHandler:^(BOOL success, NSString* error) { completionHandler(success, error); }];
	}
}
- (void)launchHelper2:(BOOL)safeMode patchCheck:(BOOL)patchCheck {
	NSString* env;
	NSString* launchArgs = [[Utils getPrefs] stringForKey:@"LAUNCH_ARGS"];
	if (launchArgs && [launchArgs length] > 2) {
		env = launchArgs;
	} else {
		if (safeMode) {
			env = @"--geode:use-common-handler-offset=8b8000 --geode:safe-mode";
		} else {
			env = @"--geode:use-common-handler-offset=8b8000";
		}
	}
	NSString* b64 = [[env dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
	NSMutableString* encodedUrl = [b64 mutableCopy];
	[encodedUrl replaceOccurrencesOfString:@"+" withString:@"-" options:0 range:NSMakeRange(0, encodedUrl.length)];
	[encodedUrl replaceOccurrencesOfString:@"/" withString:@"_" options:0 range:NSMakeRange(0, encodedUrl.length)];
	while ([encodedUrl hasSuffix:@"="]) {
		[encodedUrl deleteCharactersInRange:NSMakeRange(encodedUrl.length - 1, 1)];
	}
	NSString* openURL = [NSString stringWithFormat:@"geode-helper://launch?args=%@%@", encodedUrl, [[Utils getPrefs] boolForKey:@"USE_MAX_FPS"] ? @"&cahighfps=1" : @""];
	if (patchCheck) {
		NSString* checksum = [EnterpriseCompare getChecksum:NO];
		openURL = [NSString stringWithFormat:@"geode-helper://launch?checksum=%@&args=%@%@", checksum, encodedUrl, [[Utils getPrefs] boolForKey:@"USE_MAX_FPS"] ? @"&cahighfps=1" : @""];
	}
	NSURL* url = [NSURL URLWithString:openURL];
	if ([[UIApplication sharedApplication] canOpenURL:url]) {
		[[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
	} else {
		UIAlertController* resultAlert = [UIAlertController alertControllerWithTitle:@"Error" message:@"launcher.error.enterprise-launch".loc
																	  preferredStyle:UIAlertControllerStyleAlert];
		UIAlertAction* okAction = [UIAlertAction actionWithTitle:@"common.ok".loc style:UIAlertActionStyleDefault handler:nil];
		[resultAlert addAction:okAction];
		[self presentViewController:resultAlert animated:YES completion:nil];
	}
}
- (void)launchHelper:(BOOL)safeMode {
	NSString* env;
	NSString* launchArgs = [[Utils getPrefs] stringForKey:@"LAUNCH_ARGS"];
	if (launchArgs && [launchArgs length] > 2) {
		env = launchArgs;
	} else {
		if (safeMode) {
			env = @"--geode:use-common-handler-offset=8b8000 --geode:safe-mode";
		} else {
			env = @"--geode:use-common-handler-offset=8b8000";
		}
	}
	NSString* b64 = [[env dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
	NSMutableString* encodedUrl = [b64 mutableCopy];
	[encodedUrl replaceOccurrencesOfString:@"+" withString:@"-" options:0 range:NSMakeRange(0, encodedUrl.length)];
	[encodedUrl replaceOccurrencesOfString:@"/" withString:@"_" options:0 range:NSMakeRange(0, encodedUrl.length)];
	while ([encodedUrl hasSuffix:@"="]) {
		[encodedUrl deleteCharactersInRange:NSMakeRange(encodedUrl.length - 1, 1)];
	}
	NSString* openURL = [NSString stringWithFormat:@"geode-helper://check?safe=%d&callback=%@&args=%@", safeMode,
												   NSBundle.mainBundle.infoDictionary[@"CFBundleURLTypes"][0][@"CFBundleURLSchemes"][0], encodedUrl];
	NSURL* url = [NSURL URLWithString:openURL];
	if ([[UIApplication sharedApplication] canOpenURL:url]) {
		[[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
	} else {
		UIAlertController* resultAlert = [UIAlertController alertControllerWithTitle:@"Error" message:@"launcher.error.enterprise-launch".loc
																	  preferredStyle:UIAlertControllerStyleAlert];
		UIAlertAction* okAction = [UIAlertAction actionWithTitle:@"common.ok".loc style:UIAlertActionStyleDefault handler:nil];
		[resultAlert addAction:okAction];
		[self presentViewController:resultAlert animated:YES completion:nil];
	}
}
- (BOOL)bundleIPAWithPatch:(BOOL)safeMode withLaunch:(BOOL)launch {
	[UIApplication sharedApplication].idleTimerDisabled = YES;
	NSURL* bundlePath = [[LCPath bundlePath] URLByAppendingPathComponent:[Utils gdBundleName]];
	NSFileManager* fm = [NSFileManager defaultManager];
	NSString* infoPath = [bundlePath URLByAppendingPathComponent:@"Info.plist"].path;
	NSString* infoBackupPath = [bundlePath URLByAppendingPathComponent:@"InfoBackup.plist"].path;
	NSError* err;
	if (![fm fileExistsAtPath:infoBackupPath]) {
		[fm copyItemAtPath:infoPath toPath:infoBackupPath error:&err];
		if (err) {
			[Utils showError:self title:@"Failed to copy Info.plist" error:err];
			return NO;
		}
	}
	if ([fm fileExistsAtPath:infoBackupPath]) {
		NSMutableDictionary* infoDict = [NSMutableDictionary dictionaryWithContentsOfFile:infoBackupPath];
		if (!infoDict) {
			[Utils showError:self title:@"Couldn't read InfoBackup.plist" error:nil];
			return NO;
		}
		infoDict[@"CFBundleDisplayName"] = @"Geode Helper";
		infoDict[@"CFBundleIdentifier"] = @"com.geode.helper";
		infoDict[@"GCSupportsControllerUserInteraction"] = @YES;
		infoDict[@"GCSupportsGameMode"] = @YES;
		infoDict[@"LSApplicationCategoryType"] = @"public.app-category.games";
		infoDict[@"CADisableMinimumFrameDurationOnPhone"] = @YES;
		infoDict[@"UISupportsDocumentBrowser"] = @YES; // is this necessary? dunno
		infoDict[@"UIFileSharingEnabled"] = @YES;
		infoDict[@"LSSupportsOpeningDocumentsInPlace"] = @YES;
		infoDict[@"MinimumOSVersion"] = @"13.0";
		// infoDict[@"CFBundleExecutable"] = @"GeodeHelper";
		// infoDict[@"CFBundleName"] = @"GeodeHelper";

		// permissions
		infoDict[@"NSMicrophoneUsageDescription"] = @"A mod you are using is requesting this permission.";
		infoDict[@"NSCameraUsageDescription"] = @"A mod you are using is requesting this permission.";

		// icon
		NSMutableDictionary* iphoneIconsDict = infoDict[@"CFBundleIcons"];
		NSMutableDictionary* ipadIconsDict = infoDict[@"CFBundleIcons~ipad"];
		NSMutableDictionary* iphonePrimaryIconDict = iphoneIconsDict[@"CFBundlePrimaryIcon"];
		NSMutableDictionary* ipadPrimaryIconDict = ipadIconsDict[@"CFBundlePrimaryIcon"];
		iphonePrimaryIconDict[@"CFBundleIconName"] = @"HelperIcon";
		ipadPrimaryIconDict[@"CFBundleIconName"] = @"HelperIcon";
		NSMutableArray* iconFiles = [iphonePrimaryIconDict[@"CFBundleIconFiles"] mutableCopy];
		for (NSUInteger i = 0; i < iconFiles.count; i++) {
			NSString* oldName = iconFiles[i];
			if ([oldName hasPrefix:@"AppIcon"]) {
				NSString* newName = [oldName stringByReplacingOccurrencesOfString:@"AppIcon" withString:@"HelperIcon"];
				iconFiles[i] = newName;
			}
		}
		iphonePrimaryIconDict[@"CFBundleIconFiles"] = iconFiles;
		NSMutableArray* iconFiles2 = [ipadPrimaryIconDict[@"CFBundleIconFiles"] mutableCopy];
		for (NSUInteger i = 0; i < iconFiles2.count; i++) {
			NSString* oldName = iconFiles2[i];
			if ([oldName hasPrefix:@"AppIcon"]) {
				NSString* newName = [oldName stringByReplacingOccurrencesOfString:@"AppIcon" withString:@"HelperIcon"];
				iconFiles2[i] = newName;
			}
		}
		ipadPrimaryIconDict[@"CFBundleIconFiles"] = iconFiles2;

		// uri scheme
		infoDict[@"LSApplicationQueriesSchemes"] = @[ @"geode", @"geode-helper" ];
		NSDictionary* urlTypeDict = @{ @"CFBundleURLName" : @"com.geode.helper.urlscheme", @"CFBundleURLSchemes" : @[ @"geode-helper" ] };
		infoDict[@"CFBundleURLTypes"] = @[ urlTypeDict ];

		[infoDict writeToFile:infoPath atomically:YES];

		if (![fm fileExistsAtPath:[bundlePath URLByAppendingPathComponent:@"HelperIcon60x60@2x.png"].path]) {
			[fm copyItemAtPath:[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"GD/AppIcon76x76@2x~ipad.png"]
						toPath:[bundlePath URLByAppendingPathComponent:@"HelperIcon76x76@2x~ipad.png"].path
						 error:nil];
			[fm copyItemAtPath:[[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"GD/AppIcon60x60@2x.png"]
						toPath:[bundlePath URLByAppendingPathComponent:@"HelperIcon60x60@2x.png"].path
						 error:nil];
		}
	}
	NSString* docPath = [fm URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].lastObject.path;
	NSString* tweakPath = [NSString stringWithFormat:@"%@/Tweaks/Geode.ios.dylib", docPath];
	NSString* tweakBundlePath = [bundlePath URLByAppendingPathComponent:@"Geode.ios.dylib"].path;
	if ([fm fileExistsAtPath:tweakBundlePath]) {
		NSError* removeError;
		[fm removeItemAtPath:tweakBundlePath error:&removeError];
		if (removeError) {
			[Utils showError:self title:@"Failed to delete old Geode library" error:removeError];
			return NO;
		}
	}
	NSString* tweakLoaderPath = [bundlePath URLByAppendingPathComponent:@"EnterpriseLoader.dylib"].path;
	NSString* target = [NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:@"EnterpriseLoader.dylib"];
	if ([fm fileExistsAtPath:tweakLoaderPath]) {
		[fm removeItemAtPath:tweakLoaderPath error:nil];
	}

	[fm copyItemAtPath:target toPath:tweakLoaderPath error:nil];
	[fm copyItemAtPath:tweakPath toPath:tweakBundlePath error:&err];

	NSData* tdata = [NSData dataWithContentsOfFile:tweakPath options:0 error:nil];
	NSData* bdata = [NSData dataWithContentsOfFile:tweakBundlePath options:0 error:nil];
	if (!tdata || !bdata) {
		[Utils showError:self title:@"Failed to read Geode.ios.dylib" error:nil];
		return NO;
	}
	if (![[Utils sha256sumWithData:bdata] isEqualToString:[Utils sha256sumWithData:tdata]]) {
		[Utils showError:self title:[NSString stringWithFormat:@"Checksum mismatch (%@ & %@)", [Utils sha256sumWithData:bdata], [Utils sha256sumWithData:tdata]] error:nil];
		return NO;
	}

	if (err) {
		[Utils showError:self title:@"Failed to copy Geode library" error:err];
		return NO;
	}
	NSString* uniqId = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
	[fm createFileAtPath:[bundlePath URLByAppendingPathComponent:@"sf.bd"].path contents:[uniqId dataUsingEncoding:NSUTF8StringEncoding] attributes:@{}];

	[Patcher patchGDBinary:[bundlePath URLByAppendingPathComponent:@"GeometryOriginal"] to:[bundlePath URLByAppendingPathComponent:@"GeometryJump"] withHandlerAddress:0x8b8000
					 force:[[Utils getPrefs] boolForKey:@"IS_COMPRESSING_IPA"]
			  withSafeMode:safeMode
		  withEntitlements:YES completionHandler:^(BOOL success, NSString* error) {
			  dispatch_async(dispatch_get_main_queue(), ^{
				  if (success) {
					  if ([error isEqualToString:@"force"]) {
						  AppLog(@"Starting compression of IPA due to force...");
						  /*if ([fm fileExistsAtPath:[bundlePath URLByAppendingPathComponent:@"GeodeHelper"].path]) {
							  [fm removeItemAtURL:[bundlePath URLByAppendingPathComponent:@"GeodeHelper"] error:nil];
						  }
						  [fm copyItemAtURL:[bundlePath URLByAppendingPathComponent:@"GeometryJump"] toURL:[bundlePath URLByAppendingPathComponent:@"GeodeHelper"] error:nil];*/
						  [self.progressBar setProgressText:@"launcher.progress.patch.text".loc];
						  [self.progressBar setHidden:NO];
						  [self.progressBar setCancelHidden:YES];
						  [self barProgress:0];
						  dispatch_async(dispatch_get_main_queue(), ^{
							  [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer* _Nonnull timer) {
								  dispatch_async(dispatch_get_main_queue(), ^{
									  if (getProgressCompress() < 100) {
										  [self barProgress:getProgressCompress()];
									  } else if (getProgressCompress() >= 100) {
										  [self progressVisibility:YES];
										  [UIApplication sharedApplication].idleTimerDisabled = NO;
										  [timer invalidate];
									  }
								  });
							  }];
						  });
						  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{ [Utils bundleIPA:self]; });
					  } else if (launch) {
						  [UIApplication sharedApplication].idleTimerDisabled = NO;
						  [self launchHelper:safeMode];
					  } else {
						  [UIApplication sharedApplication].idleTimerDisabled = NO;
						  [Utils showNotice:self title:@"launcher.notice.enterprise.s3".loc];
					  }
				  } else {
					  [UIApplication sharedApplication].idleTimerDisabled = NO;
					  [Utils showError:self title:error error:nil];
				  }
			  });
		  }];
	return YES;
}

- (void)launchGame {
	[self.launchTimer invalidate];
	self.launchTimer = nil;
	[self.launchButton setEnabled:NO];
	if (([[Utils getPrefs] boolForKey:@"MANUAL_REOPEN"] && [Utils isSandboxed])) {
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
	NSFileManager* fm = [NSFileManager defaultManager];
	if ([[Utils getPrefs] boolForKey:@"ENTERPRISE_MODE"]) {
		if (![fm fileExistsAtPath:[[fm temporaryDirectory] URLByAppendingPathComponent:@"Helper.ipa"].path]) {
			UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"common.notice".loc message:@"launcher.notice.enterprise.s1".loc
																	preferredStyle:UIAlertControllerStyleAlert];
			UIAlertAction* okAction = [UIAlertAction actionWithTitle:@"common.yes".loc style:UIAlertActionStyleDefault
															 handler:^(UIAlertAction* _Nonnull action) { [self bundleIPAWithPatch:NO withLaunch:NO]; }];
			UIAlertAction* cancelAction = [UIAlertAction actionWithTitle:@"common.no".loc style:UIAlertActionStyleCancel
																 handler:^(UIAlertAction* _Nonnull action) { [self.launchButton setEnabled:YES]; }];
			[alert addAction:okAction];
			[alert addAction:cancelAction];
			[self presentViewController:alert animated:YES completion:nil];
		} else {
			[self bundleIPAWithPatch:NO withLaunch:YES];
		}
		return;
	} else if (![Utils isDevCert]) {
		[Utils showNotice:self title:@"Geode was signed without entitlements! Please follow the guide on Enterprise Mode, or sign Geode with entitlements (recommended)."];
		return;
	}
	if (![Utils isSandboxed]) {
		[self.optionalTextLabel setHidden:YES];
		[self.launchButton setEnabled:YES];
		self.countdown = -5;
		[self updateState];
		[Utils tweakLaunch_withSafeMode:false];
		return;
	}
	if ([[Utils getPrefs] boolForKey:@"JITLESS"] || [[Utils getPrefs] boolForKey:@"FORCE_PATCHING"] || [[Utils getPrefs] integerForKey:@"FORCE_CERT_JIT"]) {
		[self.optionalTextLabel setHidden:NO];
		self.launchButton.frame = CGRectMake(self.view.center.x - 95, CGRectGetMaxY(self.optionalTextLabel.frame) + 15, 140, 45);
		self.settingsButton.frame = CGRectMake(self.view.center.x + 50, CGRectGetMaxY(self.optionalTextLabel.frame) + 15, 45, 45);
	}
	[self signApp:NO completionHandler:^(BOOL success, NSString* error) {
		dispatch_async(dispatch_get_main_queue(), ^{
			if (!success) {
				[self.optionalTextLabel setHidden:YES];
				[Utils showError:self title:error error:nil];
				[self updateState];
				return;
			}
			if (NSClassFromString(@"LCSharedUtils")) {
				// since we told the user you cant use TweakLoader
				[[Utils getPrefs] setValue:[Utils gdBundleName] forKey:@"selected"];
				[[Utils getPrefs] setValue:@"GeometryDash" forKey:@"selectedContainer"];
				[[Utils getPrefs] setBool:NO forKey:@"safemode"];
				AppLog(@"Launching Geometry Dash");
				if (![LCUtils launchToGuestApp]) {
					[Utils showErrorGlobal:[NSString stringWithFormat:@"launcher.error.gd".loc, @"launcher.error.app-uri".loc] error:nil];
				}
			} else {
				NSString* openURL = [NSString stringWithFormat:@"%@://launch", NSBundle.mainBundle.infoDictionary[@"CFBundleURLTypes"][0][@"CFBundleURLSchemes"][0]];
				NSURL* url = [NSURL URLWithString:openURL];
				if ([[NSClassFromString(@"UIApplication") sharedApplication] canOpenURL:url]) {
					[self.optionalTextLabel setHidden:YES];
					[[NSClassFromString(@"UIApplication") sharedApplication] openURL:url options:@{} completionHandler:nil];
					return;
				}
			}
		});
	}];
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

- (void)loadFishAnimation {
	NSMutableArray* fishFrames = [[NSMutableArray alloc] init];
	UIImage* spriteSheet = [UIImage imageNamed:@"fish_spritesheet"];
	if (!spriteSheet) {
		AppLog(@"Failed to load spritesheet");
		return;
	}
	int columns = 11;
	int rows = 13;
	CGFloat frameWidth = spriteSheet.size.width / columns;
	CGFloat frameHeight = spriteSheet.size.height / rows;
	for (int frameIndex = 0; frameIndex <= 142; frameIndex++) {
		int col = frameIndex % columns;
		int row = frameIndex / columns;
		CGRect frameRect = CGRectMake(col * frameWidth, row * frameHeight, frameWidth, frameHeight);
		CGImageRef frameImageRef = CGImageCreateWithImageInRect(spriteSheet.CGImage, frameRect);
		UIImage* frameImage = [UIImage imageWithCGImage:frameImageRef];
		CGImageRelease(frameImageRef);

		if (frameImage) {
			[fishFrames addObject:frameImage];
		}
	}
	self.cachedFishAnimation = [UIImage animatedImageWithImages:fishFrames duration:5.0];
}

- (void)startFishRain {
	[self createFishBurst];
	[NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(createFishBurst) userInfo:nil repeats:YES];
	[NSTimer scheduledTimerWithTimeInterval:10.0 target:self selector:@selector(cleanupOffscreenFish) userInfo:nil repeats:YES];
}

- (void)createFishBurst {
	int fishCount = 3 + arc4random_uniform(10);
	for (int i = 0; i < fishCount; i++) {
		UIImageView* fishImageView = [[UIImageView alloc] init];
		fishImageView.image = self.cachedFishAnimation;
		fishImageView.contentMode = UIViewContentModeCenter;
		fishImageView.clipsToBounds = YES;
		CGFloat fishSize = 48.0;

		CGFloat start = arc4random_uniform((int)(self.view.bounds.size.width - fishSize));
		fishImageView.frame = CGRectMake(start, -fishSize, fishSize, fishSize);
		[self.view insertSubview:fishImageView atIndex:0];
		[self.fishes addObject:fishImageView];

		CGFloat delay = (arc4random_uniform(10)) / 100.0;
		CGFloat duration = 3.0 + (arc4random_uniform(200)) / 100.0;

		[UIView animateWithDuration:duration delay:delay options:UIViewAnimationOptionCurveLinear animations:^{
			fishImageView.frame = CGRectMake(start, self.view.bounds.size.height + fishSize, fishSize, fishSize);
			fishImageView.transform = CGAffineTransformMakeRotation(M_PI * 0.5 * (arc4random_uniform(100) / 100.0));
		} completion:^(BOOL finished) {
			[fishImageView removeFromSuperview];
			[self.fishes removeObject:fishImageView];
		}];
	}
}

- (void)cleanupOffscreenFish {
	NSMutableArray* fishToRemove = [[NSMutableArray alloc] init];
	CGFloat screenHeight = self.view.bounds.size.height;
	for (UIImageView* fishImageView in self.fishes) {
		if (fishImageView.frame.origin.y > screenHeight + 100) {
			[fishToRemove addObject:fishImageView];
		}
	}
	for (UIImageView* fishImageView in fishToRemove) {
		[fishImageView removeFromSuperview];
		[self.fishes removeObject:fishImageView];
	}
}

- (void)documentPicker:(UIDocumentPickerViewController*)controller didPickDocumentsAtURLs:(nonnull NSArray<NSURL*>*)urls {
	NSURL* folderURL = urls.firstObject;
	// mini "hack" to get around this
	if ([folderURL startAccessingSecurityScopedResource]) {
		NSFileManager* fm = [NSFileManager defaultManager];
		NSError* error;
		NSArray<NSString*>* entries = [fm contentsOfDirectoryAtPath:folderURL.path error:&error];
		if (error) {
			[Utils showError:self title:@"Couldn't read folder" error:error];
			return;
		}
		if (![entries containsObject:@"game"] || ![entries containsObject:@"save"]) {
			[Utils showError:self title:@"Incorrect Geode Helper directory. Please select the correct directory." error:nil];
			return;
		}
		NSData* bookmark = [folderURL bookmarkDataWithOptions:0 includingResourceValuesForKeys:nil relativeToURL:nil error:NULL];
		[[Utils getPrefs] setBool:YES forKey:@"HAS_IMPORTED_BOOKMARK"];
		[[Utils getPrefs] setObject:bookmark forKey:@"GEODE_HELPER_BOOKMARK"];
		[folderURL stopAccessingSecurityScopedResource];
		[Utils showNotice:self title:@"launcher.notice.enterprise.s3".loc];
	}
}

@end

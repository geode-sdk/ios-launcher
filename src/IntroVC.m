// TODO: add a check for embedded.mobileprovision BEFORE the user imports the cert. Also have that check in settings too

#import "IntroVC.h"
#include "src/AppDelegate.h"
#include "src/components/LogUtils.h"
#include "src/LCUtils/LCUtils.h"
#include "src/LCUtils/GCSharedUtils.h"
#include "src/LCUtils/utils.h"
#import "RootViewController.h"
#import "Theming.h"
#import "Utils.h"
#import "src/LCUtils/Shared.h"
#include <stdlib.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <objc/runtime.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <mach-o/dyld.h>
#include <mach-o/dyld_images.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/syscall.h>

#include <mach/vm_map.h> /* vm_allocate()        */
#include <mach/mach_init.h> /* mach_task_self()     */

#include "LCUtils/utils.h"

bool passJITTest = false;

@implementation IntroVC

- (void)viewDidLoad {
	[super viewDidLoad];
	[self showWelcomeStep];
}
#pragma mark - UI

- (void)goToNextStep {
	switch (_currentStep) {
	case InstallStepWelcome:
		_currentStep = InstallStepAccentColor;
		[self showAccentColorStep];
		break;
	case InstallStepAccentColor:
		if (_skipColor == NO) {
			[Theming saveAccentColor:_accentColor];
		}
		if (![Utils isSandboxed]) {
			_currentStep = InstallStepJailbreakStore;
			[self showJailbreakStoreStep];
		} else {
			// do we have get-task-allow?
			if ([Utils isDevCert]) {
				int flags;
				csops(getpid(), 0, &flags, sizeof(flags));
				bool runningJIT = (flags & CS_DEBUGGED) != 0;
				// is LiveContainer?
				if (NSClassFromString(@"LCSharedUtils")) {
					// Did the user change the app settings?
					if ([RootViewController isLCTweakLoaded]) {
						[self showSoftLock:0];
						break;
					}
					// Running JIT?
					if (runningJIT) {
						if (@available(iOS 26.0, *)) {
							NSURL* profilePath = [[NSBundle mainBundle] URLForResource:@"embedded" withExtension:@"mobileprovision"];
							if (!profilePath) {
								if (NSClassFromString(@"LCSharedUtils")) {
									profilePath = [[LCPath realLCDocPath] URLByAppendingPathComponent:@"embedded.mobileprovision"];
								}
							}
							if (!profilePath) {
								return [self showSoftLock:2];
							}
							_currentStep = InstallStepWarning;
							[self jitTest];
						} else {
							// iOS 18 or lower?
							_currentStep = InstallStepComplete;
							[self completeSetup];
						}
					} else {
						NSURL* profilePath = [[NSBundle mainBundle] URLForResource:@"embedded" withExtension:@"mobileprovision"];
						if (!profilePath) {
							if (NSClassFromString(@"LCSharedUtils")) {
								profilePath = [[LCPath realLCDocPath] URLByAppendingPathComponent:@"embedded.mobileprovision"];
							}
						}
						if (!profilePath) {
							return [self showSoftLock:2];
						}
						_currentStep = InstallStepComplete;
						[self completeSetup];
					}
					break;
				} else {
					// is TrollStore?
					NSString* tsPath = [NSString stringWithFormat:@"%@/../_TrollStore", [NSBundle mainBundle].bundlePath];
					if (!access(tsPath.UTF8String, F_OK)) {
						_currentStep = InstallStepWarning;
						[self showWarningStep];
						break;
					} else {
						// is NOT sideloaded from AltStore/SideStore?
						if ([[GCSharedUtils appGroupID] isEqualToString:@"Unknown"]) {
							if (@available(iOS 26.0, *)) {
								[self showQuestionaireStep:0];
							} else {
								// we have stikdebug? well if we do then we can just skip and go to the warning thing
								if ([[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"stikjit://"]] || runningJIT) {
									_currentStep = InstallStepWarning;
									[self showWarningStep];
								} else {
									[self showQuestionaireStep:0];
								}
							}
							// we have to secretly hope the user doesnt disable the team ID extension for sideloadly
							/*NSString* teamID = [LCUtils teamIdentifier];

							if (teamID != nil && ![teamID hasSuffix:@"launcher"]) {
								if (@available(iOS 26.0, *)) {
									[self showSoftLock:0];
								} else {
									// we have stikdebug? well if we do then we can just skip and go to the warning thing
									if ([[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"stikjit://"]]) {
										_currentStep = InstallStepWarning;
										[self showWarningStep];
									} else {
										// otherwise we will just prompt if they have a cert...
									}

								}

							} else {
							}*/
						} else {
                            if (@available(iOS 26.0, *)) {
                                [self promptCert];
							} else {
								// we have stikdebug? well if we do then we can just skip and go to the warning thing
								if ([[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"stikjit://"]] || runningJIT) {
									_currentStep = InstallStepWarning;
									[self showWarningStep];
								} else {
									[self promptCert];
								}
							}
						}
					}
				}
			} else {
				[self showQuestionaireStep:0];
				return;
			}
			_currentStep = InstallStepWarning;
			[self showWarningStep];
		}
		break;
	case InstallStepInstallMethod:
		if ([_installMethod isEqualToString:@"Tweak"]) {
			_currentStep = InstallStepJailbreakStore;
			[self showJailbreakStoreStep];
		} else {
			if (![Utils isSandboxed]) {
				[Utils showNotice:self title:@"intro.s3.option1.warning".loc];
			}
			_currentStep = InstallStepComplete;
			[self completeSetup];
		}
		break;
	case InstallStepWarning:
	case InstallStepLaunchMethod:
		_currentStep = InstallStepComplete;
		[self completeSetup];
		break;
	case InstallStepJailbreakStore:
		_currentStep = InstallStepComplete;
		[self completeSetup];
		break;
	default:
		break;
	}
}

- (UIButton*)addNextButton {
	UIButton* nextButton = [UIButton buttonWithType:UIButtonTypeSystem];
	nextButton.backgroundColor = [Theming getAccentColor];
	nextButton.clipsToBounds = YES;
	nextButton.layer.cornerRadius = 22.5;
	[nextButton setTitle:@"intro.next".loc forState:UIControlStateNormal];
	nextButton.titleEdgeInsets = UIEdgeInsetsMake(0, 8, 0, 0);
	nextButton.imageEdgeInsets = UIEdgeInsetsMake(0, 0, 0, 8);
	[nextButton setImage:[[UIImage systemImageNamed:@"play.fill"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateNormal];
	[nextButton setTitleColor:[Theming getTextColor:[Theming getAccentColor]] forState:UIControlStateNormal];
	[nextButton setTintColor:[Theming getTextColor:[Theming getAccentColor]]];
	[nextButton addTarget:self action:@selector(goToNextStep) forControlEvents:UIControlEventTouchUpInside];
	return nextButton;
}

#pragma mark - View Transition

- (void)transitionToView:(UIView*)newView {
	[UIView animateWithDuration:0.3 animations:^{
		for (UIView* subview in self.view.subviews) {
			subview.alpha = 0.0;
		}
	} completion:^(BOOL finished) {
		[self.view.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
		newView.alpha = 0.0;
		newView.frame = self.view.bounds;
		newView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		[self.view addSubview:newView];
		[UIView animateWithDuration:0.3 animations:^{ newView.alpha = 1.0; }];
	}];
}

#pragma mark - Update checker
- (void)checkLauncherUpdates {
	NSLog(@"[Geode/IntroVC] Checking for Launcher updates...");
	NSURLRequest* request = [NSURLRequest requestWithURL:[NSURL URLWithString:[Utils getGeodeLauncherURL]]];
	NSURLSession* session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
	NSURLSessionDataTask* dataTask = [session dataTaskWithRequest:request completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
		if (error)
			return;
		if (data) {
			NSError* jsonError;
			NSArray* jsonObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
			if (!jsonError) {
				if ([jsonObject isKindOfClass:[NSArray class]]) {
					NSDictionary* jsonDict = jsonObject[0];
					NSString* tagName = jsonDict[@"tag_name"];
					if (tagName && [tagName isKindOfClass:[NSString class]]) {
						NSString* launcherVer = [NSString stringWithFormat:@"v%@", [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"]];
						BOOL greaterThanVer = [CompareSemVer isVersion:tagName greaterThanVersion:launcherVer];
						NSLog(@"[Geode/IntroVC] Latest Launcher version is %@ (Currently on %@)", tagName, launcherVer);
						if (!greaterThanVer) {
							// assume out of date
							dispatch_async(dispatch_get_main_queue(), ^{
								UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"intro.update.title".loc message:@"intro.update.subtitle".loc
																						preferredStyle:UIAlertControllerStyleAlert];
								UIAlertAction* okAction = [UIAlertAction actionWithTitle:@"common.yes".loc style:UIAlertActionStyleDefault
																				 handler:^(UIAlertAction* _Nonnull action) {
																					 NSURL* url = [NSURL URLWithString:[Utils getGeodeLauncherRedirect]];
																					 if ([[UIApplication sharedApplication] canOpenURL:url]) {
																						 [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
																					 }
																				 }];
								UIAlertAction* cancelAction = [UIAlertAction actionWithTitle:@"common.no".loc style:UIAlertActionStyleCancel handler:nil];
								[alert addAction:okAction];
								[alert addAction:cancelAction];

								UIWindowScene* scene = (id)[UIApplication.sharedApplication.connectedScenes allObjects].firstObject;
								UIWindow* window = scene.windows.firstObject;
								if (window != nil) {
									[window.rootViewController presentViewController:alert animated:YES completion:nil];
								}
							});
						} else if ([Utils isSandboxed]) {
							dispatch_async(dispatch_get_main_queue(), ^{
								NSString* tsPath = [NSString stringWithFormat:@"%@/../_TrollStore", NSBundle.mainBundle.bundlePath];
								if (!access(tsPath.UTF8String, F_OK)) {
									// assume TrollStore
									[Utils showNotice:self title:@"launcher.notice.ts-app-uri".loc];
								}
							});
						}
					}
				}
			}
		}
	}];
	[dataTask resume];
}

#pragma mark - Step Views

- (void)showWarningStep {
	UIView* view = [[UIView alloc] initWithFrame:self.view.bounds];

	UIImageView* logoImageView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"exclamationmark.triangle"]];
	logoImageView.clipsToBounds = YES;
	[logoImageView setTintColor:[Theming getAccentColor]];
	//[41, 36].map(x => x * 6);
	float sizeMult = 5.F;
	logoImageView.frame = CGRectMake(view.center.x - ((41 * sizeMult) / 2), (view.bounds.size.height / 8) - 20, 41 * sizeMult, 36 * sizeMult);
	[view addSubview:logoImageView];

	UILabel* titleLabel = [[UILabel alloc] init];
	titleLabel.text = @"intro.warning.title".loc;
	titleLabel.textColor = [Theming getWhiteColor];
	titleLabel.textAlignment = NSTextAlignmentCenter;
	titleLabel.font = [UIFont boldSystemFontOfSize:48];
	titleLabel.frame = CGRectMake(0, CGRectGetMaxY(logoImageView.frame) + 40, view.bounds.size.width, 60);
	[view addSubview:titleLabel];

	UILabel* subtitleLabel = [[UILabel alloc] init];
	NSString* tsPath = [NSString stringWithFormat:@"%@/../_TrollStore", [NSBundle mainBundle].bundlePath];
	if (!access(tsPath.UTF8String, F_OK)) {
		subtitleLabel.text = @"intro.warning.subtitle4".loc;
	} else {
		if ([Utils isDevCert]) {
			if (@available(iOS 26.0, *)) {
				subtitleLabel.text = @"intro.warning.subtitle3".loc;
			} else {
				subtitleLabel.text = @"intro.warning.subtitle1".loc;
			}
		} else {
			subtitleLabel.text = @"intro.warning.subtitle2".loc;
		}
	}
	subtitleLabel.numberOfLines = 10;
	subtitleLabel.textColor = [Theming getFooterColor];
	subtitleLabel.textAlignment = NSTextAlignmentCenter;
	subtitleLabel.font = [UIFont systemFontOfSize:14];
	subtitleLabel.frame = CGRectMake(30, CGRectGetMaxY(titleLabel.frame) + 5, view.bounds.size.width - 60, 170);
	[view addSubview:subtitleLabel];

	UIButton* nextButton = [UIButton buttonWithType:UIButtonTypeSystem];
	nextButton.backgroundColor = [Theming getAccentColor];
	nextButton.clipsToBounds = YES;
	nextButton.layer.cornerRadius = 22.5;
	[nextButton setTitle:@"intro.warning.understood".loc forState:UIControlStateNormal];
	nextButton.titleEdgeInsets = UIEdgeInsetsMake(0, 8, 0, 0);
	nextButton.imageEdgeInsets = UIEdgeInsetsMake(0, 0, 0, 8);
	[nextButton setImage:[[UIImage systemImageNamed:@"checkmark.circle.fill"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateNormal];
	[nextButton setTitleColor:[Theming getTextColor:[Theming getAccentColor]] forState:UIControlStateNormal];
	[nextButton setTintColor:[Theming getTextColor:[Theming getAccentColor]]];
	[nextButton addTarget:self action:@selector(goToNextStep) forControlEvents:UIControlEventTouchUpInside];

	nextButton.frame = CGRectMake(view.center.x - 70, (view.bounds.size.height / 1.5), 140, 45);
	[view addSubview:nextButton];

	[self transitionToView:view];
}

- (void)showWelcomeStep {
	[self.view.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];

	UIView* view = [[UIView alloc] initWithFrame:self.view.bounds];

	UIImageView* logoImageView = [Utils imageViewFromPDF:@"geode_logo"];
	if (logoImageView) {
		logoImageView.layer.cornerRadius = 50;
		logoImageView.clipsToBounds = YES;
		logoImageView.frame = CGRectMake(view.center.x - 75, view.center.y - 130, 150, 150);
		[view addSubview:logoImageView];
	}

	UILabel* titleLabel = [[UILabel alloc] init];
	titleLabel.text = @"intro.s1.title".loc;
	titleLabel.textColor = [Theming getWhiteColor];
	titleLabel.textAlignment = NSTextAlignmentCenter;
	titleLabel.font = [UIFont boldSystemFontOfSize:32];
	titleLabel.frame = CGRectMake(0, CGRectGetMaxY(logoImageView.frame) + 20, view.bounds.size.width, 44);
	[view addSubview:titleLabel];

	UILabel* subtitleLabel = [[UILabel alloc] init];
	subtitleLabel.text = @"intro.s1.subtitle".loc;
	subtitleLabel.textColor = [Theming getFooterColor];
	subtitleLabel.textAlignment = NSTextAlignmentCenter;
	subtitleLabel.font = [UIFont systemFontOfSize:16];
	subtitleLabel.frame = CGRectMake(0, CGRectGetMaxY(titleLabel.frame) + 10, view.bounds.size.width, 30);
	[view addSubview:subtitleLabel];

	UIButton* nextButton = [self addNextButton];
	nextButton.frame = CGRectMake(view.center.x - 70, CGRectGetMaxY(subtitleLabel.frame) + 20, 140, 45);
	[view addSubview:nextButton];

	[self checkLauncherUpdates];

	[self transitionToView:view];
}

- (void)showAccentColorStep {
	UIView* view = [[UIView alloc] initWithFrame:self.view.bounds];

	UILabel* titleLabel = [[UILabel alloc] init];
	titleLabel.text = @"intro.s2.title".loc;
	titleLabel.textColor = [Theming getWhiteColor];
	titleLabel.textAlignment = NSTextAlignmentCenter;
	titleLabel.font = [UIFont boldSystemFontOfSize:24];
	titleLabel.frame = CGRectMake(0, 80, view.bounds.size.width, 45);
	[view addSubview:titleLabel];

	UILabel* subtitleLabel = [[UILabel alloc] init];
	subtitleLabel.text = @"intro.subtitle".loc;
	subtitleLabel.textColor = [Theming getFooterColor];
	subtitleLabel.textAlignment = NSTextAlignmentCenter;
	subtitleLabel.font = [UIFont systemFontOfSize:16];
	subtitleLabel.frame = CGRectMake(0, CGRectGetMaxY(titleLabel.frame) + 10, view.bounds.size.width, 30);
	[view addSubview:subtitleLabel];

	UIButton* colorButton = [UIButton buttonWithType:UIButtonTypeSystem];
	colorButton.backgroundColor = [Theming getDarkColor];
	colorButton.clipsToBounds = YES;
	colorButton.layer.cornerRadius = 22.5;
	[colorButton setTitle:@"intro.s2.color.button".loc forState:UIControlStateNormal];
	colorButton.titleEdgeInsets = UIEdgeInsetsMake(0, 8, 0, 0);
	colorButton.imageEdgeInsets = UIEdgeInsetsMake(0, 0, 0, 8);
	[colorButton setImage:[[UIImage systemImageNamed:@"circle.lefthalf.fill"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateNormal];
	[colorButton setTitleColor:[Theming getWhiteColor] forState:UIControlStateNormal];
	[colorButton setTintColor:[Theming getWhiteColor]];
	[colorButton addTarget:self action:@selector(onColorClickButton) forControlEvents:UIControlEventTouchUpInside];
	colorButton.frame = CGRectMake(view.center.x - 80, view.center.y + 40, 150, 45);
	[view addSubview:colorButton];

	self.colorPreviewLabel = [[UILabel alloc] init];
	self.colorPreviewLabel.text = @"intro.s2.color.preview".loc;
	self.colorPreviewLabel.textColor = [Theming getAccentColor];
	self.colorPreviewLabel.textAlignment = NSTextAlignmentCenter;
	self.colorPreviewLabel.font = [UIFont systemFontOfSize:32];
	self.colorPreviewLabel.frame = CGRectMake(0, view.center.y - 40, view.bounds.size.width, 30);
	[view addSubview:self.colorPreviewLabel];

	self.colorNextButton = [self addNextButton];
	self.colorNextButton.frame = CGRectMake(view.center.x - 130, view.bounds.size.height - 150, 140, 45);
	[view addSubview:self.colorNextButton];

	UIButton* skipButton = [UIButton buttonWithType:UIButtonTypeSystem];
	[skipButton setTitle:@"intro.skip".loc forState:UIControlStateNormal];
	[skipButton setTitleColor:[Theming getFooterColor] forState:UIControlStateNormal];
	skipButton.titleLabel.font = [UIFont systemFontOfSize:18];
	[skipButton addTarget:self action:@selector(colorSkipPressed) forControlEvents:UIControlEventTouchUpInside];
	skipButton.frame = CGRectMake(CGRectGetMaxX(self.colorNextButton.frame) + 30, view.bounds.size.height - 150, 70, 45);
	[view addSubview:skipButton];
	[self transitionToView:view];
}

- (void)showInstallMethodStep {
	UIView* view = [[UIView alloc] initWithFrame:self.view.bounds];

	UILabel* titleLabel = [[UILabel alloc] init];
	titleLabel.text = @"intro.s3.title".loc;
	titleLabel.textColor = [Theming getWhiteColor];
	titleLabel.textAlignment = NSTextAlignmentCenter;
	titleLabel.font = [UIFont boldSystemFontOfSize:24];
	titleLabel.frame = CGRectMake(0, 80, view.bounds.size.width, 45);
	[view addSubview:titleLabel];

	int maximumImageSize = view.bounds.size.width / 4;

	UILabel* subtitleLabel = [[UILabel alloc] init];
	subtitleLabel.text = @"intro.subtitle".loc;
	subtitleLabel.textColor = [Theming getFooterColor];
	subtitleLabel.textAlignment = NSTextAlignmentCenter;
	subtitleLabel.font = [UIFont systemFontOfSize:16];
	subtitleLabel.frame = CGRectMake(0, CGRectGetMaxY(titleLabel.frame) + 10, view.bounds.size.width, 30);
	[view addSubview:subtitleLabel];

	UIView* normalOptionContainer = [[UIView alloc] initWithFrame:CGRectMake(25, view.bounds.size.height / 4, view.bounds.size.width, view.bounds.size.height / 5)];

	UIImageView* normalIcon = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, maximumImageSize, maximumImageSize)];
	normalIcon.contentMode = UIViewContentModeScaleAspectFit;
	normalIcon.tintColor = [Theming getAccentColor];
	UIImage* shieldImage = [UIImage systemImageNamed:@"shield.lefthalf.filled" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:60]];
	normalIcon.image = shieldImage;
	[normalOptionContainer addSubview:normalIcon];

	UIButton* normalRadioButton = [UIButton buttonWithType:UIButtonTypeCustom];
	normalRadioButton.frame = CGRectMake(CGRectGetMaxX(normalIcon.frame) + 10, 10, 30, 30);
	normalRadioButton.layer.cornerRadius = 15;
	normalRadioButton.layer.borderWidth = 2;
	normalRadioButton.layer.borderColor = [Theming getFooterColor].CGColor;
	normalRadioButton.tag = 1;
	[normalRadioButton addTarget:self action:@selector(radioButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
	[normalOptionContainer addSubview:normalRadioButton];

	UILabel* normalLabel = [[UILabel alloc] initWithFrame:CGRectMake(CGRectGetMaxX(normalRadioButton.frame) + 10, 10, view.bounds.size.width - 160, 30)];
	normalLabel.text = @"intro.s3.option1.title".loc;
	normalLabel.textColor = [Theming getWhiteColor];
	normalLabel.font = [UIFont boldSystemFontOfSize:16];
	[normalOptionContainer addSubview:normalLabel];

	UILabel* normalDescription = [[UILabel alloc]
		initWithFrame:CGRectMake(CGRectGetMaxX(normalIcon.frame) + 10, CGRectGetMaxY(normalLabel.frame) + 10, view.bounds.size.width - 150, view.bounds.size.height / 8)];
	normalDescription.text = @"intro.s3.option1.subtitle".loc;
	normalDescription.textColor = [Theming getFooterColor];
	normalDescription.font = [UIFont systemFontOfSize:13];
	normalDescription.numberOfLines = 5;
	[normalOptionContainer addSubview:normalDescription];

	[view addSubview:normalOptionContainer];

	// =============
	UIView* separator = [[UIView alloc] initWithFrame:CGRectMake(40, CGRectGetMaxY(normalOptionContainer.frame) + 10, view.bounds.size.width - 80, 1)];
	separator.backgroundColor = [UIColor darkGrayColor];
	[view addSubview:separator];
	// =============

	UIView* tweakOptionContainer = [[UIView alloc] initWithFrame:CGRectMake(25, CGRectGetMaxY(separator.frame) + 20, view.bounds.size.width, view.bounds.size.height / 4)];
	UIImageView* tweakIcon = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, maximumImageSize, maximumImageSize)];
	tweakIcon.contentMode = UIViewContentModeScaleAspectFit;
	tweakIcon.tintColor = [Theming getAccentColor];
	UIImage* tweakImage = [UIImage systemImageNamed:@"cube.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:60]];
	tweakIcon.image = tweakImage;
	[tweakOptionContainer addSubview:tweakIcon];

	UIButton* tweakRadioButton = [UIButton buttonWithType:UIButtonTypeCustom];
	tweakRadioButton.frame = CGRectMake(CGRectGetMaxX(tweakIcon.frame) + 10, 10, 30, 30);
	tweakRadioButton.layer.cornerRadius = 15;
	tweakRadioButton.layer.borderWidth = 2;
	tweakRadioButton.layer.borderColor = [Theming getFooterColor].CGColor;
	tweakRadioButton.tag = 2;
	[tweakRadioButton addTarget:self action:@selector(radioButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
	[tweakOptionContainer addSubview:tweakRadioButton];

	UILabel* tweakLabel = [[UILabel alloc] initWithFrame:CGRectMake(CGRectGetMaxX(tweakRadioButton.frame) + 10, 10, view.bounds.size.width - 160, 30)];
	tweakLabel.text = @"intro.s3.option2.title".loc;
	tweakLabel.textColor = [Theming getWhiteColor];
	tweakLabel.font = [UIFont boldSystemFontOfSize:16];
	[tweakOptionContainer addSubview:tweakLabel];

	UILabel* tweakDescription = [[UILabel alloc]
		initWithFrame:CGRectMake(CGRectGetMaxX(tweakIcon.frame) + 10, CGRectGetMaxY(tweakLabel.frame) + 10, view.bounds.size.width - 150, view.bounds.size.height / 6)];
	tweakDescription.text = @"intro.s3.option2.subtitle".loc;
	tweakDescription.textColor = [Theming getFooterColor];
	tweakDescription.font = [UIFont systemFontOfSize:13];
	tweakDescription.numberOfLines = 7;
	[tweakOptionContainer addSubview:tweakDescription];

	[view addSubview:tweakOptionContainer];
	[self radioButtonTapped:normalRadioButton];

	UIButton* nextButton = [self addNextButton];
	nextButton.frame = CGRectMake(view.center.x - 70, view.bounds.size.height - 120, 140, 45);
	[view addSubview:nextButton];

	[self transitionToView:view];
}

- (void)showLaunchMethodStep {
	UIView* view = [[UIView alloc] initWithFrame:self.view.bounds];

	UILabel* titleLabel = [[UILabel alloc] init];
	titleLabel.text = @"intro.s4.title".loc;
	titleLabel.textColor = [Theming getWhiteColor];
	titleLabel.textAlignment = NSTextAlignmentCenter;
	titleLabel.font = [UIFont boldSystemFontOfSize:24];
	titleLabel.frame = CGRectMake(0, 80, view.bounds.size.width, 45);
	[view addSubview:titleLabel];

	int maximumImageSize = view.bounds.size.width / 4;

	UILabel* subtitleLabel = [[UILabel alloc] init];
	subtitleLabel.text = @"intro.subtitle".loc;
	subtitleLabel.textColor = [Theming getFooterColor];
	subtitleLabel.textAlignment = NSTextAlignmentCenter;
	subtitleLabel.font = [UIFont systemFontOfSize:16];
	subtitleLabel.frame = CGRectMake(0, CGRectGetMaxY(titleLabel.frame) + 10, view.bounds.size.width, 30);
	[view addSubview:subtitleLabel];

	UIView* normalOptionContainer = [[UIView alloc] initWithFrame:CGRectMake(25, view.bounds.size.height / 4, view.bounds.size.width, view.bounds.size.height / 5)];

	UIImageView* normalIcon = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, maximumImageSize, maximumImageSize)];
	normalIcon.contentMode = UIViewContentModeScaleAspectFit;
	normalIcon.tintColor = [Theming getAccentColor];
	UIImage* shieldImage = [UIImage systemImageNamed:@"bolt.slash.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:60]];
	normalIcon.image = shieldImage;
	[normalOptionContainer addSubview:normalIcon];

	UIButton* normalRadioButton = [UIButton buttonWithType:UIButtonTypeCustom];
	normalRadioButton.frame = CGRectMake(CGRectGetMaxX(normalIcon.frame) + 10, 10, 30, 30);
	normalRadioButton.layer.cornerRadius = 15;
	normalRadioButton.layer.borderWidth = 2;
	normalRadioButton.layer.borderColor = [Theming getFooterColor].CGColor;
	normalRadioButton.tag = 3;
	[normalRadioButton addTarget:self action:@selector(radioButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
	[normalOptionContainer addSubview:normalRadioButton];

	UILabel* normalLabel = [[UILabel alloc] initWithFrame:CGRectMake(CGRectGetMaxX(normalRadioButton.frame) + 10, 10, view.bounds.size.width - 160, 30)];
	normalLabel.text = @"intro.s4.option1.title".loc;
	normalLabel.textColor = [Theming getWhiteColor];
	normalLabel.font = [UIFont boldSystemFontOfSize:16];
	[normalOptionContainer addSubview:normalLabel];

	UILabel* normalDescription = [[UILabel alloc]
		initWithFrame:CGRectMake(CGRectGetMaxX(normalIcon.frame) + 7, CGRectGetMaxY(normalLabel.frame) + 10, view.bounds.size.width - 150, view.bounds.size.height / 8)];
	normalDescription.text = @"intro.s4.option1.subtitle".loc;
	normalDescription.textColor = [Theming getFooterColor];
	normalDescription.font = [UIFont systemFontOfSize:13];
	normalDescription.numberOfLines = 5;
	[normalOptionContainer addSubview:normalDescription];

	[view addSubview:normalOptionContainer];

	// =============
	UIView* separator = [[UIView alloc] initWithFrame:CGRectMake(40, CGRectGetMaxY(normalOptionContainer.frame) + 10, view.bounds.size.width - 80, 1)];
	separator.backgroundColor = [UIColor darkGrayColor];
	[view addSubview:separator];
	// =============

	UIView* tweakOptionContainer = [[UIView alloc] initWithFrame:CGRectMake(25, CGRectGetMaxY(separator.frame) + 20, view.bounds.size.width, view.bounds.size.height / 4)];
	UIImageView* tweakIcon = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, maximumImageSize, maximumImageSize)];
	tweakIcon.contentMode = UIViewContentModeScaleAspectFit;
	tweakIcon.tintColor = [Theming getAccentColor];
	UIImage* tweakImage = [UIImage systemImageNamed:@"bolt.fill" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:60]];
	tweakIcon.image = tweakImage;
	[tweakOptionContainer addSubview:tweakIcon];

	UIButton* tweakRadioButton = [UIButton buttonWithType:UIButtonTypeCustom];
	tweakRadioButton.frame = CGRectMake(CGRectGetMaxX(tweakIcon.frame) + 10, 10, 30, 30);
	tweakRadioButton.layer.cornerRadius = 15;
	tweakRadioButton.layer.borderWidth = 2;
	tweakRadioButton.layer.borderColor = [Theming getFooterColor].CGColor;
	tweakRadioButton.tag = 4;
	[tweakRadioButton addTarget:self action:@selector(radioButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
	[tweakOptionContainer addSubview:tweakRadioButton];

	UILabel* tweakLabel = [[UILabel alloc] initWithFrame:CGRectMake(CGRectGetMaxX(tweakRadioButton.frame) + 10, 10, view.bounds.size.width - 160, 30)];
	tweakLabel.text = @"intro.s4.option2.title".loc;
	tweakLabel.textColor = [Theming getWhiteColor];
	tweakLabel.font = [UIFont boldSystemFontOfSize:16];
	[tweakOptionContainer addSubview:tweakLabel];

	UILabel* tweakDescription = [[UILabel alloc]
		initWithFrame:CGRectMake(CGRectGetMaxX(tweakIcon.frame) + 7, CGRectGetMaxY(tweakLabel.frame) + 10, view.bounds.size.width - 150, view.bounds.size.height / 6)];
	tweakDescription.text = @"intro.s4.option2.subtitle".loc;
	tweakDescription.textColor = [Theming getFooterColor];
	tweakDescription.font = [UIFont systemFontOfSize:13];
	tweakDescription.numberOfLines = 7;
	[tweakOptionContainer addSubview:tweakDescription];

	[view addSubview:tweakOptionContainer];
	[self radioButtonTapped:normalRadioButton];

	UIButton* nextButton = [self addNextButton];
	nextButton.frame = CGRectMake(view.center.x - 70, view.bounds.size.height - 120, 140, 45);
	[view addSubview:nextButton];

	[self transitionToView:view];
}

- (void)radioButtonTapped:(UIButton*)sender {
	for (UIView* subview in sender.superview.superview.subviews) {
		for (UIView* containerView in subview.subviews) {
			if ([containerView isKindOfClass:[UIButton class]] && containerView != sender) {
				[(UIButton*)containerView setBackgroundColor:[UIColor clearColor]];
				[(UIButton*)containerView layer].borderWidth = 2;
			}
		}
	}
	sender.backgroundColor = [Theming getAccentColor];
	sender.layer.borderWidth = 0;
	if (sender.tag == 1) {
		self.installMethod = @"Normal";
	} else if (sender.tag == 2) {
		self.installMethod = @"Tweak";
	} else if (sender.tag == 3) {
		self.useJITLess = YES;
	} else if (sender.tag == 4) {
		self.useJITLess = NO;
	}
}

- (void)jitTest {
	UIView* view = [[UIView alloc] initWithFrame:self.view.bounds];
	UIImageView* logoImageView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"exclamationmark.triangle"]];
	logoImageView.clipsToBounds = YES;
	[logoImageView setTintColor:[Theming getAccentColor]];
	//[41, 36].map(x => x * 6);
	float sizeMult = 5.F;
	logoImageView.frame = CGRectMake(view.center.x - ((41 * sizeMult) / 2), (view.bounds.size.height / 8) - 20, 41 * sizeMult, 36 * sizeMult);
	[view addSubview:logoImageView];

	UILabel* titleLabel = [[UILabel alloc] init];
	titleLabel.text = @"JIT Test".loc;
	titleLabel.textColor = [Theming getWhiteColor];
	titleLabel.textAlignment = NSTextAlignmentCenter;
	titleLabel.font = [UIFont boldSystemFontOfSize:48];
	titleLabel.frame = CGRectMake(0, CGRectGetMaxY(logoImageView.frame) + 40, view.bounds.size.width, 60);
	[view addSubview:titleLabel];

	UILabel* subtitleLabel = [[UILabel alloc] init];
	subtitleLabel.text = @"You will press the Test button to test if you applied the JIT script correctly, then tap Next.\nIf the app crashes, freezes, or the Next button doesn't bring you to the right menu, then you didn't apply the correct script. This assumes you followed the guide for instructions.".loc;
	subtitleLabel.numberOfLines = 10;
	subtitleLabel.textColor = [Theming getFooterColor];
	subtitleLabel.textAlignment = NSTextAlignmentCenter;
	subtitleLabel.font = [UIFont systemFontOfSize:14];
	subtitleLabel.frame = CGRectMake(30, CGRectGetMaxY(titleLabel.frame) + 5, view.bounds.size.width - 60, 170);
	[view addSubview:subtitleLabel];

	UIButton* nextButton = [UIButton buttonWithType:UIButtonTypeSystem];
	nextButton.backgroundColor = [Theming getAccentColor];
	nextButton.clipsToBounds = YES;
	nextButton.layer.cornerRadius = 22.5;
	[nextButton setTitle:@"Test".loc forState:UIControlStateNormal];
	nextButton.titleEdgeInsets = UIEdgeInsetsMake(0, 8, 0, 0);
	nextButton.imageEdgeInsets = UIEdgeInsetsMake(0, 0, 0, 8);
	[nextButton setImage:[[UIImage systemImageNamed:@"bolt.circle.fill"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateNormal];
	[nextButton setTitleColor:[Theming getTextColor:[Theming getAccentColor]] forState:UIControlStateNormal];
	[nextButton setTintColor:[Theming getTextColor:[Theming getAccentColor]]];

	UIAction *action = [UIAction actionWithHandler:^(__kindof UIAction * _Nonnull action) {
		// credits: https://gist.github.com/JJTech0130/142aee0f7bda9c61a421140d17afbdeb
		[Utils showNoticeGlobal:@"If the app freezes or crashes, you do not have the correct script.".loc];
		void* page = mmap(0, 0x4000, PROT_READ | PROT_EXEC, MAP_ANON | MAP_PRIVATE, -1, 0);
		vm_address_t buf_rw = (vm_address_t)page;
		vm_address_t buf_rx = 0;
		vm_prot_t cur_prot, max_prot;
		kern_return_t ret = vm_remap(mach_task_self(), &buf_rx, 0x4000, 0, VM_FLAGS_ANYWHERE, mach_task_self(), buf_rw, false, &cur_prot, &max_prot, VM_INHERIT_NONE);
		assert(ret == KERN_SUCCESS);
		BreakMarkJITMapping((void*)buf_rx, 0x4000);
		ret = vm_protect(mach_task_self(), buf_rw, 0x4000, FALSE, VM_PROT_READ | VM_PROT_WRITE);
		assert(ret == KERN_SUCCESS);
		uint32_t instructions[] = {
			0x52800540, // mov w0, #42
			0xD65F03C0 // ret
		};
		BreakJITWrite((void*)buf_rx, instructions, sizeof(instructions));
		int (*func)(void) = (int (*)(void))buf_rx;
		passJITTest = func() == 42;
		AppLog(@"Function called! Result: %@", (passJITTest) ? @"PASS" : @"FAIL");
		[Utils showNoticeGlobal:@"Tap the Next button."];
	}];
	[nextButton addAction:action forControlEvents:UIControlEventTouchUpInside];

	nextButton.frame = CGRectMake(view.center.x - 70, (view.bounds.size.height / 1.25) - 75, 140, 45);
	[view addSubview:nextButton];

	UIButton* nextButton2 = [self addNextButton];
	nextButton2.frame = CGRectMake(view.center.x - 70, (view.bounds.size.height / 1.25), 140, 45);
	[nextButton2 removeTarget:nil action:nil forControlEvents:UIControlEventTouchUpInside];
	[nextButton2 addTarget:self action:@selector(jitLCError) forControlEvents:UIControlEventTouchUpInside];
	[view addSubview:nextButton2];

	[self transitionToView:view];
}
- (void)jitLCError {
	if (passJITTest) {
		[self goToNextStep];
	} else {
		[self showSoftLock:1];
	}
}

- (UIView *)makeOptionWithIcon:(UIImage *)icon title:(NSString *)title action:(void(^)(void))action {
	UIControl *card = [[UIControl alloc] init];
	card.backgroundColor = [UIColor systemBackgroundColor];
	card.layer.cornerRadius = 14;
	card.layer.borderWidth = 1;
	card.layer.borderColor = [UIColor separatorColor].CGColor;
	card.translatesAutoresizingMaskIntoConstraints = NO;

	UIView *iconBg = [[UIView alloc] init];
	iconBg.backgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.15];
	iconBg.layer.cornerRadius = 10;
	iconBg.translatesAutoresizingMaskIntoConstraints = NO;

	UIImageView *iconView = [[UIImageView alloc] initWithImage:icon];
	iconView.tintColor = [UIColor systemBlueColor];
	iconView.translatesAutoresizingMaskIntoConstraints = NO;

	[iconBg addSubview:iconView];
	[card addSubview:iconBg];

	UILabel *label = [[UILabel alloc] init];
	label.text = title;
	label.font = [UIFont systemFontOfSize:16];
	label.textColor = [UIColor labelColor];
	label.translatesAutoresizingMaskIntoConstraints = NO;

	[card addSubview:label];

	// i couldnt be bothered
	[NSLayoutConstraint activateConstraints:@[
		[card.heightAnchor constraintEqualToConstant:64],

		[iconBg.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
		[iconBg.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
		[iconBg.widthAnchor constraintEqualToConstant:40],
		[iconBg.heightAnchor constraintEqualToConstant:40],

		[iconView.centerXAnchor constraintEqualToAnchor:iconBg.centerXAnchor],
		[iconView.centerYAnchor constraintEqualToAnchor:iconBg.centerYAnchor],

		[label.leadingAnchor constraintEqualToAnchor:iconBg.trailingAnchor constant:14],
		[label.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
		[label.centerYAnchor constraintEqualToAnchor:card.centerYAnchor]
	]];
	UIAction *uiAction = [UIAction actionWithHandler:^(__kindof UIAction * _Nonnull act) {
		if (action) action();
	}];
	[card addAction:uiAction forControlEvents:UIControlEventTouchUpInside];
	return card;
}

- (void)showQuestionaireStep:(NSInteger)state {
	UIView* view = [[UIView alloc] initWithFrame:self.view.bounds];

	UILabel* titleLabel = [[UILabel alloc] init];
	titleLabel.textColor = [Theming getWhiteColor];
	titleLabel.textAlignment = NSTextAlignmentCenter;
	titleLabel.font = [UIFont boldSystemFontOfSize:24];
	titleLabel.frame = CGRectMake(0, 80, view.bounds.size.width, 45);
	[view addSubview:titleLabel];

	//int maximumImageSize = view.bounds.size.width / 4;

	UILabel* subtitleLabel = [[UILabel alloc] init];
	subtitleLabel.textColor = [Theming getFooterColor];
	subtitleLabel.textAlignment = NSTextAlignmentCenter;
	subtitleLabel.font = [UIFont systemFontOfSize:16];
	subtitleLabel.frame = CGRectMake(0, CGRectGetMaxY(titleLabel.frame) + 10, view.bounds.size.width, 30);
	[view addSubview:subtitleLabel];

	UIStackView *optionsStack = [[UIStackView alloc] init];
	optionsStack.axis = UILayoutConstraintAxisVertical;
	optionsStack.spacing = 14;
	optionsStack.translatesAutoresizingMaskIntoConstraints = NO;

	[view addSubview:optionsStack];

	[NSLayoutConstraint activateConstraints:@[
		[optionsStack.topAnchor constraintEqualToAnchor:subtitleLabel.bottomAnchor constant:32],
		[optionsStack.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:20],
		[optionsStack.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-20]
	]];

	switch (state) {
		case 0:
			if (![Utils isDevCert]) {
				titleLabel.text = @"intro.s1.subtitle".loc;
				subtitleLabel.text = @"Do you have any of the following?".loc;
				[optionsStack addArrangedSubview:[self makeOptionWithIcon:[UIImage systemImageNamed:@"desktopcomputer"] title:@"PC / Laptop" action:^(void){
					[self showSoftLock:0];
				}]];
				[optionsStack addArrangedSubview:[self makeOptionWithIcon:[UIImage systemImageNamed:@"applelogo"] title:@"Mac" action:^(void){
					[self showSoftLock:0];
				}]];
				[optionsStack addArrangedSubview:[self makeOptionWithIcon:[UIImage systemImageNamed:@"laptopcomputer"] title:@"Chromebook" action:^(void){
					[self showSoftLock:0];
				}]];
				[optionsStack addArrangedSubview:[self makeOptionWithIcon:[UIImage systemImageNamed:@"desktopcomputer"] title:@"A friend's PC / Laptop" action:^(void){
					[self showSoftLock:0];
				}]];
				[optionsStack addArrangedSubview:[self makeOptionWithIcon:[UIImage systemImageNamed:@"questionmark.circle"] title:@"I don’t have any of these" action:^(void){
					[self showQuestionaireStep:1];
				}]];
			} else {
				titleLabel.text = @"How did you sideload Geode?";
				subtitleLabel.text = @"";
				[optionsStack addArrangedSubview:[self makeOptionWithIcon:[UIImage systemImageNamed:@"arrow.down.circle"] title:@"Sideloadly" action:^(void){
					[self showSoftLock:0];
				}]];
				[optionsStack addArrangedSubview:[self makeOptionWithIcon:[UIImage systemImageNamed:@"square.split.2x2"] title:@"PlumeImpactor" action:^(void){
					[self showSoftLock:0];
				}]];
				[optionsStack addArrangedSubview:[self makeOptionWithIcon:[UIImage systemImageNamed:@"signature"] title:@"KSign" action:^(void){
					[self promptCert];
				}]];
				[optionsStack addArrangedSubview:[self makeOptionWithIcon:[UIImage systemImageNamed:@"pencil.tip.crop.circle"] title:@"Feather" action:^(void){
					[self promptCert];
				}]];
				[optionsStack addArrangedSubview:[self makeOptionWithIcon:[UIImage systemImageNamed:@"questionmark.circle"] title:@"Other" action:^(void){
					[self promptCert];
				}]];
			}
			break;
		case 1:
			if (![Utils isDevCert]) {
				titleLabel.text = @"intro.s1.subtitle".loc;
				subtitleLabel.text = @"Where did you get your certificate from?".loc;
				[optionsStack addArrangedSubview:[self makeOptionWithIcon:[UIImage systemImageNamed:@"pencil"] title:@"KravaSign" action:^(void){
					[self showDevCertLock];
				}]];
				[optionsStack addArrangedSubview:[self makeOptionWithIcon:[UIImage systemImageNamed:@"signature"] title:@"Signulous" action:^(void){
					[self showDevCertLock];
				}]];
                [optionsStack addArrangedSubview:[self makeOptionWithIcon:[UIImage systemImageNamed:@"dollarsign.circle"] title:@"Paid Certificate Provider" action:^(void){
					[self showDevCertLock];
				}]];
				[optionsStack addArrangedSubview:[self makeOptionWithIcon:[UIImage systemImageNamed:@"questionmark.circle"] title:@"Other" action:^(void){
					_currentStep = InstallStepWarning;
                    [self showWarningStep];
				}]];
			}
			break;
	}
	[self transitionToView:view];
}

- (void)documentPicker:(UIDocumentPickerViewController*)controller didPickDocumentsAtURLs:(nonnull NSArray<NSURL*>*)urls {
	if (urls.count != 1)
		return [Utils showError:self title:@"You must select a p12 certificate!" error:nil];
	AppLog(@"Selected URLs: %@", urls);
	UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Input the password of the Certificate." message:@"This will be used for signing."
															preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField* _Nonnull textField) {
		textField.placeholder = @"Certificate Password";
		textField.secureTextEntry = YES;
	}];
	UIAlertAction* okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction* _Nonnull action) {
		UITextField* field = alert.textFields.firstObject;
		[self certPass:field.text url:urls.firstObject];
	}];
	UIAlertAction* cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
	[alert addAction:okAction];
	[alert addAction:cancelAction];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)certPass:(NSString*)certPass url:(NSURL*)url {
	NSError* err;
	NSData* certData = [NSData dataWithContentsOfURL:url options:0 error:&err];
	if (err) {
		[Utils showError:self title:@"jitless.cert.readerror".loc error:err];
		return;
	}
	NSString* teamId = [LCUtils getCertTeamIdWithKeyData:certData password:certPass];
	if (!teamId) {
		[Utils showError:self title:@"jitless.cert.invalidcert".loc error:nil];
		return;
	}
	AppLog(@"Import complete!");
	NSUserDefaults* NSUD = [Utils getPrefs];
	[NSUD setObject:certPass forKey:@"LCCertificatePassword"];
	[NSUD setObject:certData forKey:@"LCCertificateData"];
	[NSUD setBool:YES forKey:@"LCCertificateImported"];
	if (![Utils isDevCert]) {
		[Utils showNotice:self title:@"jitless.cert.dev-cert".loc];
	} else {
		[Utils showNotice:self title:@"jitless.cert.success".loc];
	}
	[self afterPromptCert];
}

- (void)promptCert {
	NSURL* profilePath = [[NSBundle mainBundle] URLForResource:@"embedded" withExtension:@"mobileprovision"];
	if (!profilePath) {
		if (NSClassFromString(@"LCSharedUtils")) {
			profilePath = [[LCPath realLCDocPath] URLByAppendingPathComponent:@"embedded.mobileprovision"];
		} else {
			profilePath = [[LCPath docPath] URLByAppendingPathComponent:@"embedded.mobileprovision"];
		}
	}
	if (!profilePath) {
		return [self showSoftLock:1];
	}
	if ([LCUtils certificateData] != nil) {
		return [self afterPromptCert];
	}
	
	UIView* view = [[UIView alloc] initWithFrame:self.view.bounds];

	UIImageView* logoImageView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"lock.circle"]];
	logoImageView.clipsToBounds = YES;
	[logoImageView setTintColor:[Theming getAccentColor]];
	float sizeMult = 4.5F;
	logoImageView.frame = CGRectMake(view.center.x - ((41 * sizeMult) / 2), (view.bounds.size.height / 8) - 20, 41 * sizeMult, 36 * sizeMult);
	[view addSubview:logoImageView];

	UILabel* titleLabel = [[UILabel alloc] init];
	titleLabel.textColor = [Theming getWhiteColor];
	titleLabel.textAlignment = NSTextAlignmentCenter;
	titleLabel.font = [UIFont boldSystemFontOfSize:40];
	titleLabel.frame = CGRectMake(0, CGRectGetMaxY(logoImageView.frame) + 40, view.bounds.size.width, 45);
	titleLabel.text = @"Import Certificate".loc;
	[view addSubview:titleLabel];

	UILabel* subtitleLabel = [[UILabel alloc] init];
	subtitleLabel.textColor = [Theming getFooterColor];
	subtitleLabel.textAlignment = NSTextAlignmentCenter;
	subtitleLabel.font = [UIFont systemFontOfSize:14];
	subtitleLabel.numberOfLines = 8;
	subtitleLabel.frame = CGRectMake(0, CGRectGetMaxY(titleLabel.frame) + 20, view.bounds.size.width, 200);
	if ([[GCSharedUtils appGroupID] isEqualToString:@"Unknown"]) {
		subtitleLabel.text = @"To continue, you'll need to import your .p12 signing certificate you used to sign the app.\n\nThis will be used to sign mods and get around the code signing requirement. You will also need the certificate password as well.\nIf you do not have a .p12 signing certificate, and you haven't paid for a certificate, please use SideStore instead.";
	} else {
		subtitleLabel.text = @"To continue, you'll need to import your signing certificate from AltStore/SideStore.\n\nYou can obtain the certificate by opening the app -> tapping settings -> scrolling down -> tap \"Export Signing Certificate\", entering any password of choice! (123456 as as an example) -> then the p12 file will be exported!\nMake sure to remember the password.";
	}
	[view addSubview:subtitleLabel];

	UIButton* nextButton = [UIButton buttonWithType:UIButtonTypeSystem];
	nextButton.backgroundColor = [Theming getAccentColor];
	nextButton.clipsToBounds = YES;
	nextButton.layer.cornerRadius = 10.5;
	[nextButton setTitle:@"Import Certificate" forState:UIControlStateNormal];
	[nextButton setTitleColor:[Theming getTextColor:[Theming getAccentColor]] forState:UIControlStateNormal];

	UIAction *action = [UIAction actionWithHandler:^(__kindof UIAction * _Nonnull action) {
		if ([[Utils getPrefs] boolForKey:@"LCCertificateImported"]) {
			// unsure how this would happen but sure.
			[self afterPromptCert];
			return;
		}
		// https://developer.apple.com/documentation/uniformtypeidentifiers/uttype-swift.struct/pkcs12
		// public.x509-certificate
		UTType* type = [UTType typeWithIdentifier:@"com.rsa.pkcs-12"];
		if (!type) {
			type = [UTType typeWithFilenameExtension:@"p12"];
		}
		if (!type) {
			type = [UTType typeWithIdentifier:@"public.data"];
		}
		if (!type) {
			// what is going on apple
			NSLog(@"Couldn't find any valid UTType. Not opening to prevent crashing.");
			return;
		}
		UIDocumentPickerViewController* picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[ type ] asCopy:YES];
		picker.delegate = self;
		picker.allowsMultipleSelection = NO;
		[self presentViewController:picker animated:YES completion:nil];
	}];
	[nextButton addAction:action forControlEvents:UIControlEventTouchUpInside];

	nextButton.frame = CGRectMake((view.bounds.size.width / 2) / 2, CGRectGetMaxY(subtitleLabel.frame) + 80, view.bounds.size.width / 2, 45);
	[view addSubview:nextButton];

	[self transitionToView:view];
}

- (void)afterPromptCert {
	self.useJITLess = YES;
	if (@available(iOS 26.0, *)) {
		int flags;
		csops(getpid(), 0, &flags, sizeof(flags));
		bool runningJIT = (flags & CS_DEBUGGED) != 0;
		if ([[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"stikjit://"]] || runningJIT) {
			self.useJITLess = NO;
			_currentStep = InstallStepWarning;
			[self showWarningStep];
			return;
		}
	}
	_currentStep = InstallStepComplete;
	[self completeSetup];
}

- (void)showDevCertLock {
	UIView* view = [[UIView alloc] initWithFrame:self.view.bounds];
	UILabel* titleLabel = [[UILabel alloc] init];
	titleLabel.text = @"common.notice".loc;
	titleLabel.textColor = [Theming getWhiteColor];
	titleLabel.textAlignment = NSTextAlignmentCenter;
	titleLabel.font = [UIFont boldSystemFontOfSize:28];
	titleLabel.frame = CGRectMake(0, 80, view.bounds.size.width, 30);
	[view addSubview:titleLabel];

	UILabel* subtitleLabel = [[UILabel alloc] init];
	subtitleLabel.text = @"Please contact your certificate provider to receive a Development Certificate.\n\nAfter receiving the certificate, please resign Geode with the certificate. It may require uninstalling and installing.\n\nYou will know if Geode is signed with a Development Certificate if the question after accent colors is not asking if you have a PC.".loc;
	subtitleLabel.numberOfLines = 3;
	subtitleLabel.textColor = [Theming getFooterColor];
	subtitleLabel.textAlignment = NSTextAlignmentCenter;
	subtitleLabel.font = [UIFont systemFontOfSize:12];
	subtitleLabel.frame = CGRectMake(0, CGRectGetMaxY(titleLabel.frame) + 15, view.bounds.size.width, 90);
	[view addSubview:subtitleLabel];

	UIButton* nextButton = [UIButton buttonWithType:UIButtonTypeSystem];
	nextButton.backgroundColor = [Theming getAccentColor];
	nextButton.clipsToBounds = YES;
	nextButton.layer.cornerRadius = 22.5;
	[nextButton setTitle:@"common.ok".loc forState:UIControlStateNormal];
	[nextButton setTitleColor:[Theming getTextColor:[Theming getAccentColor]] forState:UIControlStateNormal];
	UIAction *action = [UIAction actionWithHandler:^(__kindof UIAction * _Nonnull action) {
		exit(0);
	}];
	nextButton.frame = CGRectMake(view.center.x - 130, view.bounds.size.height - 150, 140, 45);
	[nextButton addAction:action forControlEvents:UIControlEventTouchUpInside];

	UIButton* dontHaveCert = [UIButton buttonWithType:UIButtonTypeRoundedRect];
	[dontHaveCert setTitleColor:[Theming getFooterColor] forState:UIControlStateNormal];
	dontHaveCert.clipsToBounds = YES;
	dontHaveCert.layer.cornerRadius = 22.5;
	[dontHaveCert setTitle:@"I cannot" forState:UIControlStateNormal];
	dontHaveCert.titleLabel.font = [UIFont systemFontOfSize:18];
	[dontHaveCert setTitleColor:[Theming getAccentColor] forState:UIControlStateNormal];
	UIAction *action2 = [UIAction actionWithHandler:^(__kindof UIAction * _Nonnull action) {
	}];
	[dontHaveCert addAction:action2 forControlEvents:UIControlEventTouchUpInside];
	dontHaveCert.frame = CGRectMake(CGRectGetMaxX(self.colorNextButton.frame) + 30, view.bounds.size.height - 150, 70, 45);
	[view addSubview:nextButton];
	[view addSubview:dontHaveCert];
	[self transitionToView:view];
}

- (void)showSoftLock:(NSInteger)state {
	UIView* view = [[UIView alloc] initWithFrame:self.view.bounds];
	NSString* title = @"common.error".loc;
	NSString* message = @"Please report this. Something went wrong.";
	NSString* linkToGuide = nil;

	if (NSClassFromString(@"LCSharedUtils")) {
		linkToGuide = @"https://github.com/geode-sdk/ios-launcher/blob/main/LIVECONTAINER-INSTALL-GUIDE.md";
	}
	switch (state) {
		case 0:
			if (NSClassFromString(@"LCSharedUtils")) {
				message = @"Please follow the Geode guide for LiveContainer on what app settings to enable for Geode, enabling the following: Fix File Picker, Fix Local Notification, Use LiveContainer's Bundle ID, Don't Inject TweakLoader, Don't Load TweakLoader.";
			} else {
				if ([Utils isDevCert]) {
					if (@available(iOS 26.0, *)) {
						message = @"You must use SideStore to use Geode. Sideloadly will not work because your iDevice is using iOS 26 or higher.";
					} else {
						title = @"common.notice".loc;
						message = @"Please sideload StikDebug or use SideStore for Geode.";
						linkToGuide = @"https://github.com/geode-sdk/ios-launcher/blob/main/MODERN-IOS-INSTALL.md";
					}
				} else {
					title = @"common.notice".loc;
					if (@available(iOS 26.0, *)) {
						linkToGuide = @"https://github.com/geode-sdk/ios-launcher/blob/main/JITLESS-INSTALL-GUIDE.md";
					} else {
						linkToGuide = @"https://github.com/geode-sdk/ios-launcher/blob/main/INSTALL.md";
					}
					message = @"Follow the guide by tapping the \"OK\" button.";
				}
			}
			break;
		case 1:
			if (NSClassFromString(@"LCSharedUtils")) {
				message = @"Please restart the app, as you skipped the Test button, Geode failed to patch memory, or you aren't running the correct script.";
			} else if ([Utils isDevCert]) {
				message = @"Please sign and install Geode again with the mobile provision file, or place the mobile provision file (embedded.mobileprovision) in the Geode folder, then restart the app.";
				linkToGuide = nil;
			}
			break;
		case 2:
			if (NSClassFromString(@"LCSharedUtils")) {
				message = @"The certificate files could not be found, or they are invalid. If you have exported the certificate from LiveContainer but it still shows this error, tap \"Import Certificate\" instead, and import the certificate you used for LiveContainer with the password. You may also need to copy the embedded.mobileprovision file over.";
			}
			break;
    }

	UIImageView* logoImageView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"xmark.circle"]];
	logoImageView.clipsToBounds = YES;
	[logoImageView setTintColor:[Theming getAccentColor]];
	float sizeMult = 4.5F;
	logoImageView.frame = CGRectMake(view.center.x - ((41 * sizeMult) / 2), (view.bounds.size.height / 8) - 20, 41 * sizeMult, 36 * sizeMult);
	[view addSubview:logoImageView];

	UILabel* titleLabel = [[UILabel alloc] init];
	titleLabel.text = title;
	titleLabel.textColor = [Theming getWhiteColor];
	titleLabel.textAlignment = NSTextAlignmentCenter;
	titleLabel.font = [UIFont boldSystemFontOfSize:48];
	titleLabel.frame = CGRectMake(0, CGRectGetMaxY(logoImageView.frame) + 40, view.bounds.size.width, 60);
	[view addSubview:titleLabel];

	UILabel* subtitleLabel = [[UILabel alloc] init];
	if (linkToGuide != nil) {
		subtitleLabel.text = [NSString stringWithFormat:@"%@\n\nYou can also tap the link icon on the top right to view the guide. Tapping Exit will force exit this app.", message];
	} else {
		subtitleLabel.text = message;
	}
	subtitleLabel.numberOfLines = 10;
	subtitleLabel.textColor = [Theming getFooterColor];
	subtitleLabel.textAlignment = NSTextAlignmentCenter;
	subtitleLabel.font = [UIFont systemFontOfSize:14];
	subtitleLabel.frame = CGRectMake(30, CGRectGetMaxY(titleLabel.frame) + 5, view.bounds.size.width - 60, 170);
	[view addSubview:subtitleLabel];

	UIButton* nextButton = [UIButton buttonWithType:UIButtonTypeSystem];
	nextButton.backgroundColor = [Theming getAccentColor];
	nextButton.clipsToBounds = YES;
	nextButton.layer.cornerRadius = 22.5;
	[nextButton setTitle:([Utils isDevCert] ? @"common.exit".loc : @"common.ok".loc) forState:UIControlStateNormal];
	[nextButton setTitleColor:[Theming getTextColor:[Theming getAccentColor]] forState:UIControlStateNormal];
	UIAction *action = [UIAction actionWithHandler:^(__kindof UIAction * _Nonnull action) {
		if ([Utils isDevCert]) {
			exit(0);
		} else {
            [[UIApplication sharedApplication] openURL:[NSURL URLWithString:linkToGuide] options:@{} completionHandler:nil];
		}
	}];
	[nextButton addAction:action forControlEvents:UIControlEventTouchUpInside];

	nextButton.frame = CGRectMake(view.center.x - 70, (view.bounds.size.height / 1.5), 140, 45);
	[view addSubview:nextButton];

	[self transitionToView:view];
}

- (void)showJailbreakStoreStep {
	UIView* view = [[UIView alloc] initWithFrame:self.view.bounds];

	UILabel* titleLabel = [[UILabel alloc] init];
	titleLabel.text = @"intro.s5.title".loc;
	titleLabel.textColor = [Theming getWhiteColor];
	titleLabel.textAlignment = NSTextAlignmentCenter;
	titleLabel.font = [UIFont boldSystemFontOfSize:28];
	titleLabel.frame = CGRectMake(0, 80, view.bounds.size.width, 30);
	[view addSubview:titleLabel];

	UILabel* subtitleLabel = [[UILabel alloc] init];
	subtitleLabel.text = @"intro.s5.subtitle".loc;
	subtitleLabel.numberOfLines = 2;
	subtitleLabel.textColor = [Theming getFooterColor];
	subtitleLabel.textAlignment = NSTextAlignmentCenter;
	subtitleLabel.font = [UIFont systemFontOfSize:12];
	subtitleLabel.frame = CGRectMake(0, CGRectGetMaxY(titleLabel.frame) + 15, view.bounds.size.width, 30);
	[view addSubview:subtitleLabel];

	[[Utils getPrefs] setBool:YES forKey:@"USE_TWEAK"];
	NSArray* stores = @[ @"Sileo", @"Zebra", @"Cydia" ];

	for (NSInteger i = 0; i < stores.count; i++) { //
		int center = view.center.x - 45;
		switch (i) {
		case 0:
			center = center - 110;
			break;
		case 2:
			center = center + 110;
			break;
		}
		UIView* storeOptionContainer = [[UIView alloc] initWithFrame:CGRectMake(center, view.center.y - 100, 90, 200)];

		UIButton* storeButton = [UIButton buttonWithType:UIButtonTypeSystem];
		storeButton.frame = CGRectMake(0, 0, 90, 90);
		storeButton.tag = i;
		[storeButton setBackgroundImage:[UIImage imageNamed:stores[i]] forState:UIControlStateNormal];
		[storeButton addTarget:self action:@selector(storeSelected:) forControlEvents:UIControlEventTouchUpInside];

		UILabel* storeLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 80, 90, 90)];

		storeLabel.text = [@"intro.s5.openin" localizeWithFormat:stores[i]];
		storeLabel.textColor = [Theming getWhiteColor];
		storeLabel.textAlignment = NSTextAlignmentCenter;
		storeLabel.numberOfLines = 2;
		storeLabel.font = [UIFont systemFontOfSize:16];

		[storeOptionContainer addSubview:storeButton];
		[storeOptionContainer addSubview:storeLabel];

		UITapGestureRecognizer* tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(storeSelected:)];
		storeOptionContainer.tag = i;
		storeOptionContainer.userInteractionEnabled = YES;
		[storeOptionContainer addGestureRecognizer:tapGesture];

		[view addSubview:storeOptionContainer];
	}

	UIButton* nextButton = [self addNextButton];
	nextButton.frame = CGRectMake(view.center.x - 110, view.bounds.size.height - 150, 140, 45);
	[view addSubview:nextButton];

	UIButton* shareButton = [UIButton buttonWithType:UIButtonTypeSystem];
	shareButton.frame = CGRectMake(CGRectGetMaxX(nextButton.frame) + 30, view.bounds.size.height - 150, 40, 40);
	UIImage* shareImage = [UIImage systemImageNamed:@"square.and.arrow.up" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:20]];
	[shareButton setImage:shareImage forState:UIControlStateNormal];
	shareButton.tintColor = [UIColor systemBlueColor];
	[shareButton addTarget:self action:@selector(otherStoreOption) forControlEvents:UIControlEventTouchUpInside];
	[view addSubview:shareButton];

	[self transitionToView:view];
}

- (void)storeSelected:(UIButton*)button {
	switch (button.tag) {
	case 0: { // Sileo
		if (![[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"sileo://"]])
			return [Utils showError:self title:@"You do not have Sileo installed!" error:nil];
		[[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"sileo://source/https://ios-repo.geode-sdk.org"] options:@{} completionHandler:nil];
		break;
	}
	case 1: { // Zebra
		if (![[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"zbra://"]])
			return [Utils showError:self title:@"You do not have Zebra installed!" error:nil];
		[[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"zbra://sources/add/https://ios-repo.geode-sdk.org"] options:@{} completionHandler:nil];
		break;
	}
	case 2: { // Cydia
		if (![[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"cydia://"]])
			return [Utils showError:self title:@"You do not have Cydia installed!" error:nil];
		[[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"cydia://url/https://cydia.saurik.com/api/share#?source=https://ios-repo.geode-sdk.org"] options:@{}
								 completionHandler:nil];
		break;
	}
	}
}

- (void)otherStoreOption {
	/*NSURL *zipFileURL = [NSURL URLWithString:@"https://ios-repo.geode-sdk.org/debs/gay.rooot.geodeinject_0.0.2_iphoneos-arm.deb"];
	UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:@[zipFileURL] applicationActivities:nil];
	activityVC.excludedActivityTypes = @[UIActivityTypeAssignToContact, UIActivityTypePrint];
	[self presentViewController:activityVC animated:YES completion:nil];*/
	NSURL* url = [NSURL URLWithString:@"https://ios-repo.geode-sdk.org/repo"];
	if ([[NSClassFromString(@"UIApplication") sharedApplication] canOpenURL:url]) {
		[[NSClassFromString(@"UIApplication") sharedApplication] openURL:url options:@{} completionHandler:nil];
	}
}

- (void)completeSetup {
	UIView* view = [[UIView alloc] initWithFrame:self.view.bounds];
	if (self.useJITLess) {
		[[Utils getPrefs] setBool:YES forKey:@"JITLESS"];
	}
	UILabel* titleLabel = [[UILabel alloc] init];
	titleLabel.text = @"intro.final.title".loc;
	titleLabel.textColor = [Theming getWhiteColor];
	titleLabel.textAlignment = NSTextAlignmentCenter;
	titleLabel.font = [UIFont boldSystemFontOfSize:32];
	titleLabel.frame = CGRectMake(0, view.center.y - 40, view.bounds.size.width, 45);
	[view addSubview:titleLabel];

	UILabel* subtitleLabel = [[UILabel alloc] init];
	subtitleLabel.text = @"intro.final.subtitle".loc;
	subtitleLabel.textColor = [Theming getFooterColor];
	subtitleLabel.textAlignment = NSTextAlignmentCenter;
	subtitleLabel.font = [UIFont systemFontOfSize:16];
	subtitleLabel.frame = CGRectMake(0, CGRectGetMaxY(titleLabel.frame) + 10, view.bounds.size.width, 30);
	[view addSubview:subtitleLabel];

	UIButton* nextButton = [self addNextButton];
	[nextButton removeTarget:nil action:nil forControlEvents:UIControlEventTouchUpInside];
	[nextButton addTarget:self action:@selector(completeSetup2) forControlEvents:UIControlEventTouchUpInside];
	nextButton.frame = CGRectMake(view.center.x - 70, CGRectGetMaxY(subtitleLabel.frame) + 20, 140, 45);
	[view addSubview:nextButton];

	[self transitionToView:view];

	[[Utils getPrefs] setValue:@"http://[fd00::]:9172" forKey:@"SideJITServerAddr"];
	[[Utils getPrefs] setBool:YES forKey:@"CompletedSetup"];
	[[Utils getPrefs] synchronize];
}

- (void)completeSetup2 {
	RootViewController* rootViewController = [[RootViewController alloc] init];
	UIWindowScene* scene = (id)[UIApplication.sharedApplication.connectedScenes allObjects].firstObject;
	UIWindow* window = scene.windows.firstObject;
	[UIView transitionWithView:window duration:0.5 options:UIViewAnimationOptionTransitionFlipFromRight animations:^{ window.rootViewController = rootViewController; }
					completion:nil];
}

#pragma mark - Color stuff

- (void)colorSkipPressed {
	_skipColor = YES;
	[self goToNextStep];
}

- (void)onColorClickButton {
	self.colorSelectionController = [[MSColorSelectionViewController alloc] init];
	UINavigationController* navCtrl = [[UINavigationController alloc] initWithRootViewController:self.colorSelectionController];

	navCtrl.popoverPresentationController.delegate = self;
	navCtrl.modalInPresentation = YES;
	navCtrl.preferredContentSize = [self.colorSelectionController.view systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
	navCtrl.modalPresentationStyle = UIModalPresentationOverFullScreen;

	self.colorSelectionController.delegate = self;
	self.colorSelectionController.color = [Theming getAccentColor];

	if (self.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact) {
		UIBarButtonItem* doneBtn = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(ms_dismissViewController:)];
		self.colorSelectionController.navigationItem.rightBarButtonItem = doneBtn;
	}
	[self presentViewController:navCtrl animated:YES completion:nil];
}

- (void)ms_dismissViewController:(id)sender {
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)colorViewController:(MSColorSelectionViewController*)colorViewCntroller didChangeColor:(UIColor*)color {
	_accentColor = color;
	if (self.colorNextButton != nil && self.colorPreviewLabel != nil) {
		self.colorSelectionController.color = color;
		[self.colorNextButton setBackgroundColor:color];
		[self.colorNextButton setTitleColor:[Theming getTextColor:color] forState:UIControlStateNormal];
		[self.colorNextButton setTintColor:[Theming getTextColor:color]];
		self.colorPreviewLabel.textColor = color;
	}
}
@end

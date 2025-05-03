#import "GeodeInstaller.h"
// #import "src/components/DropdownView.h"
#import "LogsView.h"
#import "SettingsVC.h"
#import "VerifyInstall.h"
#import "components/LogUtils.h"
#import "src/LCUtils/LCUtils.h"
#import "src/LCUtils/Shared.h"
#import "src/Theming.h"
#import "src/Utils.h"
#import <MobileCoreServices/MobileCoreServices.h>
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <dlfcn.h>
#include <spawn.h>

@interface SettingsVC () <UIDocumentPickerDelegate>
@property(nonatomic, strong) NSArray* creditsArray;
@property(nonatomic, assign) BOOL isImportCert;
@property(nonatomic, assign) BOOL isImportIPA;
@end

#define JITLESS 0

@implementation SettingsVC
- (void)viewDidLoad {
	[super viewDidLoad];
	[self setTitle:@"Settings"];
	self.creditsArray = @[
		@{ @"name" : @"rooot", @"url" : @"https://github.com/RoootTheFox" },
		@{ @"name" : @"dankmeme01", @"url" : @"https://github.com/dankmeme01" },
		@{ @"name" : @"Firee", @"url" : @"https://github.com/FireMario211" },
		@{ @"name" : @"ninXout", @"url" : @"https://github.com/ninXout" },
		@{ @"name" : @"Duy Tran Khanh", @"url" : @"https://github.com/khanhduytran0" },
		@{ @"name" : @"camila314", @"url" : @"https://github.com/camila314" },
		@{ @"name" : @"TheSillyDoggo", @"url" : @"https://github.com/TheSillyDoggo" },
		@{ @"name" : @"Nathan", @"url" : @"https://github.com/verygenericname" },
		@{ @"name" : @"LimeGradient", @"url" : @"https://github.com/LimeGradient" },
		@{ @"name" : @"km7dev", @"url" : @"https://github.com/Kingminer7" },
		@{ @"name" : @"Anh", @"url" : @"https://github.com/AnhNguyenlost13" },
		@{ @"name" : @"pengubow", @"url" : @"https://github.com/pengubow" },
	];

	self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
	[[self tableView] setTranslatesAutoresizingMaskIntoConstraints:NO];
	[[self tableView] setDelegate:self];
	[[self tableView] setDataSource:self];
	[[self view] addSubview:self.tableView];
	// https://github.com/reactwg/react-native-new-architecture/blob/76d8426c27c1bf30c235f653e425ef872554a33b/docs/fabric-native-components.md
	[NSLayoutConstraint activateConstraints:@[
		[self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
	]];

	[[self view] setBackgroundColor:[Theming getBackgroundColor]];
	[[[self navigationController] navigationBar] setPrefersLargeTitles:YES];
}
- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView {
	return [[Utils getPrefs] boolForKey:@"DEVELOPER_MODE"] ? 8 : 7;
}

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
	switch (section) {
	case 0: // General
		return 6;
	case 1: // Gameplay
		return 4;
	case 2: // JIT
		if ([Utils isSandboxed]) {
			if ([[Utils getPrefs] integerForKey:@"JIT_ENABLER"] == 4) {
				return 3;
			} else if ([[Utils getPrefs] integerForKey:@"JIT_ENABLER"] == 3) {
				return 2;
			}
		} else {
			return 0;
		}
		return 1;
	case 3: // JIT-Less
		if ([Utils isSandboxed]) {
			if (JITLESS == 1) {
				return 5;
			} else {
				return 0; // 5;
			}
		} else {
			return 0;
		}
	case 4: // Advanced
		return 5;
	case 5: // About
		return 4;
	case 6: // Credits
		return [self.creditsArray count];
	case 7: // Developer
		return 6;
	default:
		return 0;
	}
}

- (UISwitch*)createSwitch:(BOOL)enabled tag:(NSInteger)tag disable:(BOOL)disable {
	UISwitch* uiSwitch = [[UISwitch alloc] init];
	[uiSwitch setOn:enabled];
	[uiSwitch setTag:tag];
	[uiSwitch setEnabled:!disable];
	[uiSwitch addTarget:self action:@selector(switchValueChanged:) forControlEvents:UIControlEventValueChanged];
	return uiSwitch;
}

- (void)showDevMode:(UILongPressGestureRecognizer*)gestureRecognizer {
	if (gestureRecognizer.state == UIGestureRecognizerStateBegan && ![[Utils getPrefs] boolForKey:@"DEVELOPER_MODE"]) {
		UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"developer.warning.title".loc message:@"developer.warning.msg".loc
																preferredStyle:UIAlertControllerStyleAlert];
		UIAlertAction* yesAction = [UIAlertAction actionWithTitle:@"common.yes".loc style:UIAlertActionStyleDefault handler:^(UIAlertAction* _Nonnull action) {
			[[Utils getPrefs] setBool:YES forKey:@"DEVELOPER_MODE"];
			[self.tableView reloadData];
		}];
		UIAlertAction* noAction = [UIAlertAction actionWithTitle:@"common.no".loc style:UIAlertActionStyleCancel handler:nil];
		[alert addAction:yesAction];
		[alert addAction:noAction];
		[self presentViewController:alert animated:YES completion:nil];
	}
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath {
	UITableViewCell* cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	UITableViewCell* cellval1 = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
	// i wish i could case(0,0) :(
	switch (indexPath.section) {
	case 0:
		if (indexPath.row == 0) {
			cell.textLabel.text = @"general.accent-color".loc;
			UIView* colView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 16, 16)];
			colView.backgroundColor = [Theming getAccentColor];
			colView.layer.cornerRadius = colView.frame.size.width / 2;
			cell.accessoryView = colView;
		} else if (indexPath.row == 1) {
			cell.textLabel.text = @"general.reset-accent-color".loc;
			cell.textLabel.textColor = [Theming getAccentColor];
			cell.accessoryType = UITableViewCellAccessoryNone;
		} else if (indexPath.row == 2) {
			cellval1.selectionStyle = UITableViewCellSelectionStyleNone;
			UISegmentedControl* control = [[UISegmentedControl alloc] initWithItems:@[ @"general.theme.system".loc, @"general.theme.light".loc, @"general.theme.dark".loc ]];
			cellval1.accessoryView = control;
			// cellval1.separatorInset = UIEdgeInsetsMake(0.0f, 0.0f, 0.0f, CGFLOAT_MAX);
			control.autoresizingMask =
				UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
			control.center = CGPointMake(cell.contentView.bounds.size.width / 1.5, cell.contentView.bounds.size.height / 2);
			control.selectedSegmentIndex = [[Utils getPrefs] integerForKey:@"CURRENT_THEME"];
			[control addTarget:self action:@selector(themeSelected:) forControlEvents:UIControlEventValueChanged];
			cellval1.textLabel.text = @"general.theme".loc;
			return cellval1;
		} else if (indexPath.row == 3) {
			cell.textLabel.text = @"general.open-fm".loc;
			cell.textLabel.textColor = [Theming getAccentColor];
			cell.accessoryType = UITableViewCellAccessoryNone;
		} else if (indexPath.row == 4) {
			cellval1.selectionStyle = UITableViewCellSelectionStyleNone;
			cellval1.textLabel.text = @"general.enable-updates".loc;
			cellval1.accessoryView = [self createSwitch:[[Utils getPrefs] boolForKey:@"UPDATE_AUTOMATICALLY"] tag:0 disable:NO];
			return cellval1;
		} else if (indexPath.row == 5) {
			cell.textLabel.text = @"general.check-updates".loc;
			cell.textLabel.textColor = [Theming getAccentColor];
			cell.accessoryType = UITableViewCellAccessoryNone;
		}
		break;
	case 1:
		if (indexPath.row == 0) {
			cell.textLabel.text = @"gameplay.safe-mode".loc;
			cell.textLabel.textColor = [Theming getAccentColor];
			cell.accessoryType = UITableViewCellAccessoryNone;
		} else if (indexPath.row == 1) {
			cellval1.selectionStyle = UITableViewCellSelectionStyleNone;
			cellval1.textLabel.text = @"gameplay.auto-launch".loc;
			cellval1.accessoryView = [self createSwitch:[[Utils getPrefs] boolForKey:@"LOAD_AUTOMATICALLY"] tag:1 disable:NO];
			return cellval1;
		} else if (indexPath.row == 2) {
			cellval1.selectionStyle = UITableViewCellSelectionStyleNone;
			cellval1.textLabel.text = @"gameplay.fix-rotation".loc;
			if (![Utils isSandboxed]) {
				cellval1.textLabel.textColor = [UIColor systemGrayColor];
			}
			cellval1.accessoryView = [self createSwitch:[[Utils getPrefs] boolForKey:@"FIX_ROTATION"] tag:5 disable:![Utils isSandboxed]];
			return cellval1;
		}
		if (indexPath.row == 3) {
			cellval1.selectionStyle = UITableViewCellSelectionStyleNone;
			cellval1.textLabel.text = @"gameplay.fix-black-screen".loc;
			if (![Utils isSandboxed]) {
				cellval1.textLabel.textColor = [UIColor systemGrayColor];
			}
			cellval1.accessoryView = [self createSwitch:[[Utils getPrefs] boolForKey:@"FIX_BLACKSCREEN"] tag:8 disable:![Utils isSandboxed]];
			return cellval1;
		}
		break;
	case 2: {
		if (indexPath.row == 0) {
			cellval1.textLabel.text = @"jit.jit-enabler".loc;
			if (NSClassFromString(@"LCSharedUtils")) {
				cellval1.detailTextLabel.text = @"jit.jit-enabler.livecontainer".loc;
				cellval1.selectionStyle = UITableViewCellSelectionStyleNone;
				cellval1.textLabel.textColor = [UIColor systemGrayColor];
			} else {
				cellval1.detailTextLabel.text = [self getJITEnablerOptions][[[Utils getPrefs] integerForKey:@"JIT_ENABLER"]];
			}
			cellval1.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
			return cellval1;
		} else if (indexPath.row == 1) {
			UITextField* textField = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 200, 30)];
			textField.textAlignment = NSTextAlignmentRight;
			textField.delegate = self;
			textField.returnKeyType = UIReturnKeyDone;
			textField.autocorrectionType = UITextAutocorrectionTypeNo;
			textField.keyboardType = UIKeyboardTypeURL;
			textField.tag = 0;
			cell.accessoryView = textField;
			cell.textLabel.text = @"jit.jit-server".loc;
			if ([[Utils getPrefs] integerForKey:@"JIT_ENABLER"] == 4) {
				textField.placeholder = @"http://x.x.x.x:8080";
			} else {
				textField.placeholder = @"http://[fd00::]:9172";
			}
			textField.text = [[Utils getPrefs] stringForKey:@"SideJITServerAddr"];
		} else if (indexPath.row == 2) {
			UITextField* textField = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 200, 30)];
			textField.textAlignment = NSTextAlignmentRight;
			textField.delegate = self;
			textField.returnKeyType = UIReturnKeyDone;
			textField.autocorrectionType = UITextAutocorrectionTypeNo;
			textField.keyboardType = UIKeyboardTypeURL;
			textField.tag = 1;
			cell.accessoryView = textField;
			cell.textLabel.text = @"jit.jit-udid".loc;
			textField.placeholder = @"00008020-008D4548007B4F26";
			textField.text = [[Utils getPrefs] stringForKey:@"JITDeviceUDID"];
		}
		break;
	}
	case 3: {
		if (indexPath.row == 0) {
			cellval1.selectionStyle = UITableViewCellSelectionStyleNone;
			cellval1.textLabel.text = @"Enable JIT-Less";
			if (![Utils isSandboxed] || NSClassFromString(@"LCSharedUtils")) {
				cellval1.textLabel.textColor = [UIColor systemGrayColor];
			}
			cellval1.accessoryView = [self createSwitch:[[Utils getPrefs] boolForKey:@"JITLESS"] tag:9 disable:![Utils isSandboxed]];
			return cellval1;
		} else if (indexPath.row == 1) {
			cell.textLabel.text = [NSString stringWithFormat:@"Patch %@", [LCUtils getStoreName]];
			if (![LCUtils isAppGroupAltStoreLike]) {
				cell.selectionStyle = UITableViewCellSelectionStyleNone;
				cell.textLabel.textColor = [UIColor systemGrayColor];
			} else {
				cell.textLabel.textColor = [Theming getAccentColor];
			}
			cell.accessoryType = UITableViewCellAccessoryNone;
		} else if (indexPath.row == 2) {
			if ([[Utils getPrefs] boolForKey:@"LCCertificateImported"]) {
				cell.textLabel.text = @"Remove Certificate";
			} else {
				cell.textLabel.text = @"Import Certificate";
			}
			cell.textLabel.textColor = [Theming getAccentColor];
			cell.accessoryType = UITableViewCellAccessoryNone;
			if ([LCUtils isAppGroupAltStoreLike]) {
				cell.selectionStyle = UITableViewCellSelectionStyleNone;
				cellval1.textLabel.textColor = [UIColor systemGrayColor];
			}
		} else if (indexPath.row == 3) {
			cell.textLabel.text = @"Test JIT-Less Mode";
			cell.textLabel.textColor = [Theming getAccentColor];
			cell.accessoryType = UITableViewCellAccessoryNone;
		} else if (indexPath.row == 4) {
			cell.textLabel.text = @"Force Resign";
			if (![[Utils getPrefs] boolForKey:@"JITLESS"]) {
				cell.selectionStyle = UITableViewCellSelectionStyleNone;
				cell.textLabel.textColor = [UIColor systemGrayColor];
			} else {
				cell.textLabel.textColor = [Theming getAccentColor];
			}
			cell.accessoryType = UITableViewCellAccessoryNone;
		}
		break;
	}
	case 4:
		/*if (indexPath.row == 0) {
			cellval1.selectionStyle = UITableViewCellSelectionStyleNone;
			cellval1.textLabel.text = @"advanced.dev-mode".loc;
			if (![[Utils getPrefs] boolForKey:@"NOT_AN_NPC"]) {
				cellval1.textLabel.textColor = [UIColor systemGrayColor];
			}
			cellval1.accessoryView = [self createSwitch:[[Utils getPrefs] boolForKey:@"DEVELOPER_MODE"] tag:2 disable:![[Utils getPrefs] boolForKey:@"NOT_AN_NPC"]];
			return cellval1;
		} else*/
		if (indexPath.row == 0) {
			cellval1.selectionStyle = UITableViewCellSelectionStyleNone;
			cellval1.accessoryView = [self createSwitch:[[Utils getPrefs] boolForKey:@"MANUAL_REOPEN"] tag:7 disable:![Utils isSandboxed] || NSClassFromString(@"LCSharedUtils")];
			cellval1.textLabel.text = @"advanced.manual-reopen-jit".loc;
			if (![Utils isSandboxed] || NSClassFromString(@"LCSharedUtils")) {
				cellval1.textLabel.textColor = [UIColor systemGrayColor];
			}
			return cellval1;
		} else if (indexPath.row == 1) {
			cellval1.selectionStyle = UITableViewCellSelectionStyleNone;
			cellval1.accessoryView = [self createSwitch:[[Utils getPrefs] boolForKey:@"USE_NIGHTLY"] tag:11 disable:NO];
			cellval1.textLabel.text = @"advanced.use-nightly".loc;
			return cellval1;
		} else if (indexPath.row == 2) {
			cell.textLabel.text = @"advanced.view-app-logs".loc;
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		} else if (indexPath.row == 3) {
			cell.textLabel.text = @"advanced.view-recent-logs".loc;
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		} else if (indexPath.row == 4) {
			cell.textLabel.text = @"advanced.view-recent-crash".loc;
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		}
		break;
	case 5: {
		cellval1.selectionStyle = UITableViewCellSelectionStyleNone;
		if (indexPath.row == 0) {
			cellval1.textLabel.text = @"about.launcher".loc;
			cellval1.detailTextLabel.text = [NSString stringWithFormat:@"v%@", [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"]];
			cellval1.textLabel.userInteractionEnabled = YES;
			UILongPressGestureRecognizer* longPressGR = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(showDevMode:)];
			[cellval1.textLabel addGestureRecognizer:longPressGR];
		} else if (indexPath.row == 1) {
			cellval1.textLabel.text = @"about.geode".loc;
			cellval1.detailTextLabel.text = [Utils getGeodeVersion];
		} else if (indexPath.row == 2) {
			NSString* infoPlistPath;
			if (![Utils isSandboxed]) {
				infoPlistPath = [[Utils getGDBundlePath] stringByAppendingPathComponent:@"GeometryJump.app/Info.plist"];
			} else {
				infoPlistPath = [[[LCPath bundlePath] URLByAppendingPathComponent:[Utils gdBundleName]] URLByAppendingPathComponent:@"Info.plist"].path;
			}
			NSDictionary* infoDictionary = [NSDictionary dictionaryWithContentsOfFile:infoPlistPath];
			cellval1.textLabel.text = @"about.geometry-dash".loc;
			cellval1.detailTextLabel.text = [NSString stringWithFormat:@"v%@", [infoDictionary objectForKey:@"CFBundleShortVersionString"]];
		} else if (indexPath.row == 3) {
			cellval1.textLabel.text = @"about.device".loc;
			NSString* model = [[UIDevice currentDevice] localizedModel];
			NSString* systemName = [[UIDevice currentDevice] systemName];
			NSString* systemVersion = [[UIDevice currentDevice] systemVersion];
			cellval1.detailTextLabel.text = [NSString stringWithFormat:@"%@ %@ (%@,%@)", systemName, systemVersion, model, [Utils archName]];
		}
		return cellval1;
	}
	case 6: {
		cell.textLabel.text = self.creditsArray[indexPath.row][@"name"];
		cell.textLabel.textColor = [Theming getAccentColor];
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		return cell;
	}
	case 7: {
		if (indexPath.row == 0) {
			UITextField* textField = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 200, 30)];
			textField.textAlignment = NSTextAlignmentRight;
			textField.delegate = self;
			textField.returnKeyType = UIReturnKeyDone;
			textField.autocorrectionType = UITextAutocorrectionTypeNo;
			textField.keyboardType = UIKeyboardTypeURL;
			textField.tag = 3;
			cell.accessoryView = textField;
			cell.textLabel.text = @"developer.launchargs".loc;
			textField.placeholder = @"--geode:safe-mode";
			textField.text = [[Utils getPrefs] stringForKey:@"LAUNCH_ARGS"];
		} else if (indexPath.row == 1) {
			cellval1.selectionStyle = UITableViewCellSelectionStyleNone;
			cellval1.textLabel.text = @"advanced.dev-mode".loc;
			cellval1.accessoryView = [self createSwitch:[[Utils getPrefs] boolForKey:@"DEVELOPER_MODE"] tag:2 disable:NO];
			return cellval1;
		} else if (indexPath.row == 2) {
			cellval1.selectionStyle = UITableViewCellSelectionStyleNone;
			cellval1.textLabel.text = @"developer.completedsetup".loc;
			cellval1.accessoryView = [self createSwitch:[[Utils getPrefs] boolForKey:@"CompletedSetup"] tag:6 disable:NO];
			return cellval1;
		} else if (indexPath.row == 3) {
			cellval1.selectionStyle = UITableViewCellSelectionStyleNone;
			cellval1.textLabel.text = @"developer.webserver".loc;
			cellval1.accessoryView = [self createSwitch:[[Utils getPrefs] boolForKey:@"WEB_SERVER"] tag:12 disable:NO];
			return cellval1;
		} else if (indexPath.row == 4) {
			cell.textLabel.text = @"developer.testbundleaccess".loc;
			cell.textLabel.textColor = [Theming getAccentColor];
			cell.accessoryType = UITableViewCellAccessoryNone;
		} else if (indexPath.row == 5) {
			cell.textLabel.text = @"developer.importipa".loc;
			cell.textLabel.textColor = [Theming getAccentColor];
			cell.accessoryType = UITableViewCellAccessoryNone;
		}
		break;
	}
	}

	return cell;
}

- (BOOL)tableView:(UITableView*)tableView canEditRowAtIndexPath:(NSIndexPath*)indexPath {
	return NO;
}

- (void)tableView:(UITableView*)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath*)indexPath {
	[tableView deleteRowsAtIndexPaths:@[ indexPath ] withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (NSString*)tableView:(UITableView*)tableView titleForHeaderInSection:(NSInteger)section {
	switch (section) {
	case 0:
		return @"general".loc;
	case 1:
		return @"gameplay".loc;
	case 2:
		if ([Utils isSandboxed]) {
			return @"jit".loc;
		} else {
			return @"";
		}
	case 3:
		if ([Utils isSandboxed] && JITLESS == 1) {
			return @"jitless".loc;
		} else {
			return @"";
		}
	case 4:
		return @"advanced".loc;
	case 5:
		return @"about".loc;
	case 6:
		return @"credits".loc;
	case 7:
		return @"developer".loc;
	default:
		return @"Unknown";
	}
}

// TODO: Replace Manual Reopen with JIT to be in the JIT Enabler
- (NSArray*)getJITEnablerOptions {
	NSString* tsPath = [NSString stringWithFormat:@"%@/../_TrollStore", [NSBundle mainBundle].bundlePath];
	if (NSClassFromString(@"LCSharedUtils")) {
		return @[ @"", @"", @"", @"", @"", @"", @"jit.jit-enabler.livecontainer".loc ];
	}
	if (!access(tsPath.UTF8String, F_OK)) {
		return @[
			@"jit.jit-enabler.default".loc, @"jit.jit-enabler.trollstore".loc, @"jit.jit-enabler.stikjit".loc, @"jit.jit-enabler.jitstreamereb".loc, @"jit.jit-enabler.sidejit".loc,
			@"jit.jit-enabler.sidestore".loc, @""
		];
	} else {
		return @[
			@"jit.jit-enabler.default".loc, @"", @"jit.jit-enabler.stikjit".loc, @"jit.jit-enabler.jitstreamereb".loc, @"jit.jit-enabler.sidejit".loc,
			@"jit.jit-enabler.sidestore".loc, @""
		];
	}
}

- (NSString*)getJITEnablerFooter {
	switch ([[Utils getPrefs] integerForKey:@"JIT_ENABLER"]) {
	default:
	case 0: // Default
		return @"jit.footer.default".loc;
	case 1: // TrollStore
		return @"jit.footer.trollstore".loc;
	case 2: // StikJIT
		return @"jit.footer.stikjit".loc;
	case 3: // JITStreamer-EB
		return @"jit.footer.jitstreamereb".loc;
	case 4: // SideJITServer
		return @"jit.footer.sidejit".loc;
	case 5: // SideStore
		return @"jit.footer.sidestore".loc;
	case 6: // LiveContainer
		return @"jit.footer.livecontainer".loc;
	}
}

- (NSString*)tableView:(UITableView*)tableView titleForFooterInSection:(NSInteger)section {
	switch (section) {
	case 0:
		return [@"general.footer" localizeWithFormat:[Utils getGeodeVersion]];
	case 1:
		return @"gameplay.footer".loc;
	case 2:
		// return @"jit.footer".loc;
		if (NSClassFromString(@"LCSharedUtils"))
			return @"jit.footer.livecontainer".loc;
		return [self getJITEnablerFooter];
	case 3:
		if (JITLESS == 0)
			return @"";
		return @"jitless.footer".loc;
	case 6:
		return @"credits.footer".loc;
	default:
		return nil;
	}
}

- (void)patchAltstore:(BOOL)archive {
	NSError* err;
	NSURL* altStoreIpa = [LCUtils archiveTweakedAltStoreWithError:&err];
	if (altStoreIpa == nil || err)
		return [Utils showError:self title:@"Failed to retrieve tweaked store" error:err];
	NSURL* storeInstallUrl = [NSURL URLWithString:[NSString stringWithFormat:[LCUtils storeInstallURLScheme], altStoreIpa]];
	if (archive) {
		[[NSFileManager defaultManager] moveItemAtURL:altStoreIpa
												toURL:[[LCPath docPath] URLByAppendingPathComponent:[NSString stringWithFormat:@"Patched%@.ipa", [LCUtils getStoreName]]]
												error:&err];
		if (err)
			return [Utils showError:self title:@"Failed to move patched store" error:err];
		[Utils showNotice:self title:[NSString stringWithFormat:@"Patched %@ has been saved to Geode's document folder. Please sideload it.", [LCUtils getStoreName]]];
	} else {
		[[UIApplication sharedApplication] openURL:storeInstallUrl options:@{} completionHandler:nil];
	}
}

#pragma mark - Table View Delegate

- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath {
	if (indexPath.section == 0) {
		switch (indexPath.row) {
		case 0: { // Change accent color
			MSColorSelectionViewController* colorSelectionController = [[MSColorSelectionViewController alloc] init];
			UINavigationController* navCtrl = [[UINavigationController alloc] initWithRootViewController:colorSelectionController];

			navCtrl.popoverPresentationController.delegate = self;
			navCtrl.modalInPresentation = YES;
			navCtrl.preferredContentSize = [colorSelectionController.view systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
			navCtrl.modalPresentationStyle = UIModalPresentationOverFullScreen;

			colorSelectionController.delegate = self;
			colorSelectionController.color = [Theming getAccentColor];

			if (self.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact) {
				UIBarButtonItem* doneBtn = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"color.done".loc, ) style:UIBarButtonItemStyleDone target:self
																		   action:@selector(ms_dismissViewController:)];
				colorSelectionController.navigationItem.rightBarButtonItem = doneBtn;
			}
			//[[self navigationController] pushViewController:colorSelectionController animated:YES];
			[self presentViewController:navCtrl animated:YES completion:nil];
			break;
		}
			// TODO: Replace Manual Reopen with JIT to be in the JIT Enabler
		case 1: {
			[[Utils getPrefs] removeObjectForKey:@"accentColor"];
			[self.root updateState];
			[self.tableView reloadData];
			break;
		}
		case 3: { // Open file manager
			NSString* openURL;
			if (![Utils isSandboxed]) {
				openURL = [NSString stringWithFormat:@"filza://%@", [[Utils getGDDocPath] stringByAppendingPathComponent:@"Documents"]];
			} else {
				openURL = [NSString stringWithFormat:@"shareddocuments://%@", [[LCPath dataPath] URLByAppendingPathComponent:@"GeometryDash/Documents"].path];
			}
			NSURL* url = [NSURL URLWithString:openURL];
			if ([[UIApplication sharedApplication] canOpenURL:url]) {
				[[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
			}
			break;
		}
		case 5: { // Check for updates
			if ([VerifyInstall verifyGeodeInstalled]) {
				[[GeodeInstaller alloc] checkUpdates:_root download:YES];
				[self dismissViewControllerAnimated:YES completion:nil];
			} else {
				[Utils showError:_root title:@"general.check-updates.error".loc error:nil];
			}
			break;
		}
		default:
			break;
		}
	} else if (indexPath.section == 1) {
		switch (indexPath.row) {
		case 0: { // Safe Mode
			if (![Utils isSandboxed]) {
				[Utils tweakLaunch_withSafeMode:true];
				break;
			}
			if ([[Utils getPrefs] boolForKey:@"MANUAL_REOPEN"] || NSClassFromString(@"LCSharedUtils")) {
				[[Utils getPrefs] setValue:[Utils gdBundleName] forKey:@"selected"];
				[[Utils getPrefs] setValue:@"GeometryDash" forKey:@"selectedContainer"];
				[[Utils getPrefs] setBool:YES forKey:@"safemode"];
				NSFileManager* fm = [NSFileManager defaultManager];
				[fm createFileAtPath:[[LCPath docPath] URLByAppendingPathComponent:@"jitflag"].path contents:[[NSData alloc] init] attributes:@{}];
				if (NSClassFromString(@"LCSharedUtils")) {
					[Utils showNotice:self title:@"launcher.relaunch-notice.lc".loc];
				} else {
					[Utils showNotice:self title:@"launcher.relaunch-notice".loc];
				}
			} else {
				NSString* openURL = @"geode://safe-mode";
				NSURL* url = [NSURL URLWithString:openURL];
				if ([[UIApplication sharedApplication] canOpenURL:url]) {
					[_root.launchButton setEnabled:NO];
					[[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
					[self dismissViewControllerAnimated:YES completion:nil];
				}
			}
			break;
		}
		}
	} else if (indexPath.section == 2) {
		switch (indexPath.row) {
		case 0: {
			if (NSClassFromString(@"LCSharedUtils"))
				break;
			UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"jit.jit-enabler".loc message:nil preferredStyle:UIAlertControllerStyleActionSheet];
			for (NSInteger i = 0; i < [self getJITEnablerOptions].count; i++) {
				NSString* value = [self getJITEnablerOptions][i];
				if (![value isEqualToString:@""]) {
					[alert addAction:[UIAlertAction actionWithTitle:[self getJITEnablerOptions][i] style:UIAlertActionStyleDefault handler:^(UIAlertAction* _Nonnull action) {
							   [[Utils getPrefs] setInteger:i forKey:@"JIT_ENABLER"];
							   [self.tableView reloadData];
						   }]];
				}
			}

			[alert addAction:[UIAlertAction actionWithTitle:@"common.cancel".loc style:UIAlertActionStyleCancel handler:nil]];

			[self presentViewController:alert animated:YES completion:nil];
			/*UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];

			NSArray *options = @[@"Option 1", @"Option 2", @"Option 3", @"Option 4"];

			CGPoint anchorPoint = CGPointMake(CGRectGetMidX(cell.frame), CGRectGetMaxY(cell.frame));

			anchorPoint = [tableView convertPoint:anchorPoint toView:self.view];

			DropdownView *dropdown = [[DropdownView alloc] initWithItems:options anchorPoint:anchorPoint width:200.0];
			dropdown.delegate = self;
			[dropdown show];

			[tableView deselectRowAtIndexPath:indexPath animated:YES];*/
			break;
		}
		}
	} else if (indexPath.section == 3) {
		NSFileManager* fm = [NSFileManager defaultManager];
		switch (indexPath.row) {
		case 1: { // Patch
			if (![LCUtils isAppGroupAltStoreLike])
				break;
			NSString* storeName = [LCUtils getStoreName];
			BOOL isSideStore = [LCUtils store] == SideStore;
			NSString* message;
			if (isSideStore) {
				message = [NSString stringWithFormat:@"To use JIT-Less mode with %@, you must patch %@ in order to retrieve certificate. %@'s functions will not be affected. "
													 @"Please confirm that you can refresh %@ before applying the patch. Continue? (You will need to wait)\n\nIf you have multiple "
													 @"of %@ installed, please select \"Archive Only\" and install the tweaked IPA manually.",
													 storeName, storeName, storeName, storeName, storeName];
			} else {
				message = [NSString stringWithFormat:@"To use JIT-Less mode with %@, you must patch %@ in order to retrieve certificate. %@'s functions will not be affected. "
													 @"Please confirm that you can refresh %@ before applying the patch. Continue? (You will need to wait)",
													 storeName, storeName, storeName, storeName];
			}
			UIAlertController* alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Patch %@", storeName] message:message
																	preferredStyle:UIAlertControllerStyleAlert];

			UIAlertAction* continueAction = [UIAlertAction actionWithTitle:@"Continue" style:UIAlertActionStyleDestructive
																   handler:^(UIAlertAction* _Nonnull action) { [self patchAltstore:NO]; }];
			UIAlertAction* archiveAction = [UIAlertAction actionWithTitle:@"Archive Only" style:UIAlertActionStyleDefault
																  handler:^(UIAlertAction* _Nonnull action) { [self patchAltstore:YES]; }];
			UIAlertAction* cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
			[alert addAction:continueAction];
			if (isSideStore) {
				[alert addAction:archiveAction];
			}
			[alert addAction:cancelAction];
			[self presentViewController:alert animated:YES completion:nil];
			break;
		}
		case 2: { // Import Cert
			// if ([LCUtils isAppGroupAltStoreLike]) break;
			if ([[Utils getPrefs] boolForKey:@"LCCertificateImported"]) {
				UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Warning" message:@"Are you sure you want to remove your certificate?"
																		preferredStyle:UIAlertControllerStyleAlert];
				UIAlertAction* okAction = [UIAlertAction actionWithTitle:@"Yes" style:UIAlertActionStyleDestructive handler:^(UIAlertAction* _Nonnull action) {
					NSUserDefaults* NSUD = [Utils getPrefs];
					[NSUD setObject:nil forKey:@"LCCertificatePassword"];
					[NSUD setObject:nil forKey:@"LCCertificateData"];
					[NSUD setObject:nil forKey:@"LCCertificateTeamId"];
					[NSUD setBool:NO forKey:@"LCCertificateImported"];
					[fm removeItemAtURL:[[LCPath docPath] URLByAppendingPathComponent:@"embedded.mobileprovision"] error:nil];
					[self.tableView reloadData];
					[Utils showNotice:self title:@"Certificate removed."];
				}];
				UIAlertAction* cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
				[alert addAction:okAction];
				[alert addAction:cancelAction];
				[self presentViewController:alert animated:YES completion:nil];
				break;
			}
			_isImportCert = true;
			// https://developer.apple.com/documentation/uniformtypeidentifiers/uttype-swift.struct/pkcs12
			// public.x509-certificate
			UTType* type = [UTType typeWithIdentifier:@"com.rsa.pkcs-12"];
			UTType* type2 = [UTType typeWithIdentifier:@"com.apple.mobileprovision"];
			UIDocumentPickerViewController* picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[ type, type2 ] asCopy:YES];
			picker.delegate = self;
			picker.allowsMultipleSelection = YES;
			[self presentViewController:picker animated:YES completion:nil];
			break;
		}
		case 3: { // Test JIT-Less
			if (![LCUtils isAppGroupAltStoreLike] && ![[Utils getPrefs] boolForKey:@"LCCertificateImported"]) {
				[Utils showError:self title:@"You did not sideload this app with AltStore or SideStore! Or you didn't import a certificate." error:nil];
				break;
			}
			NSURL* appGroupURL = [LCUtils appGroupPath];
			if (!appGroupURL)
				break;
			if ([LCUtils certificateData]) {
				[LCUtils validateCertificate:^(int status, NSDate* expirationDate, NSString* errorC) {
					if (errorC) {
						return [Utils showError:self title:[NSString stringWithFormat:@"Couldn't validate certificate: %@", errorC] error:nil];
					}
					if (status != 0) {
						return [Utils showError:self title:@"Certificate Status Invalid" error:nil];
					}
					[LCUtils validateJITLessSetup:^(BOOL success, NSError* error) {
						if (success) {
							return [Utils
								showNotice:self
									 title:[NSString stringWithFormat:@"JIT-Less Mode Test Passed!\nApp Group ID: %@\nStore: %@", [LCUtils appGroupID], [LCUtils getStoreName]]];
						} else {
							AppLog(@"JIT-Less test failed: %@", error);
							return [Utils
								showError:self
									title:[NSString stringWithFormat:@"The test library has failed to load. This means your certificate may be having issue. Please try to: 1. "
																	 @"Reopen %@; 2. Refresh all apps in %@; 3. Re-patch %@ and try again.\n\nIf you imported certificate, "
																	 @"please ensure the certificate is valid, and it is NOT an enterprise certificate.",
																	 [LCUtils getStoreName], [LCUtils getStoreName], [LCUtils getStoreName]]
									error:nil];
						}
					}];
				}];
			} else {
				[Utils showError:self title:@"Invalid Certificate Data" error:nil];
				break;
			}
			break;
		}
		case 4: { // Force Resign
			if (![[Utils getPrefs] boolForKey:@"JITLESS"])
				break;
			return [_root signApp:YES completionHandler:^(BOOL success, NSString* error) {
				dispatch_async(dispatch_get_main_queue(), ^{
					if (!success) {
						[Utils showError:self title:error error:nil];
					} else {
						[Utils showNotice:self title:@"Resign successful!"];
					}
					[tableView deselectRowAtIndexPath:indexPath animated:YES];
				});
			}];
		}
		}
	} else if (indexPath.section == 4) {
		switch (indexPath.row) {
		case 2: { // View app logs
			[[self navigationController] pushViewController:[[LogsViewController alloc] initWithFile:[[LCPath docPath] URLByAppendingPathComponent:@"app.log"]] animated:YES];
			break;
		}
		case 3: { // View geode logs
			NSURL* file = [Utils pathToMostRecentLogInDirectory:[[Utils docPath] stringByAppendingString:@"game/geode/logs/"]];
			[[self navigationController] pushViewController:[[LogsViewController alloc] initWithFile:file] animated:YES];
			break;
		}
		case 4: { // View recent crash
			NSURL* file = [Utils pathToMostRecentLogInDirectory:[[Utils docPath] stringByAppendingString:@"game/geode/crashlogs/"]];
			[[self navigationController] pushViewController:[[LogsViewController alloc] initWithFile:file] animated:YES];
			break;
		}
		}
	} else if (indexPath.section == 6) {
		NSURL* url = [NSURL URLWithString:self.creditsArray[indexPath.row][@"url"]];
		if ([[NSClassFromString(@"UIApplication") sharedApplication] canOpenURL:url]) {
			[[NSClassFromString(@"UIApplication") sharedApplication] openURL:url options:@{} completionHandler:nil];
		}
	} else if (indexPath.section == 7) {
		switch (indexPath.row) {
		case 4: { // Test GD Bundle Access
			[Utils showNotice:self title:[Utils getGDDocPath]];
			break;
		}
		case 5: { // Import IPA
			_isImportIPA = true;
			UTType* type = [UTType typeWithIdentifier:@"com.apple.itunes.ipa"];
			UIDocumentPickerViewController* picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[ type ] asCopy:YES];
			picker.delegate = self;
			picker.allowsMultipleSelection = NO;
			[self presentViewController:picker animated:YES completion:nil];
			break;
		}
		}
	}

	[tableView deselectRowAtIndexPath:indexPath animated:YES];
}

// ios 13 bad!
- (void)switchValueChanged:(UISwitch*)sender {
	switch (sender.tag) {
	case 0: // Enable Automatic Updates
		[Utils toggleKey:@"UPDATE_AUTOMATICALLY"];
		break;
	case 1: // Automatically Launch
		[Utils toggleKey:@"LOAD_AUTOMATICALLY"];
		break;
	case 2: // Dev Mode
		[Utils toggleKey:@"DEVELOPER_MODE"];
		[self.tableView reloadData];
		break;
	case 3: // Use Tweak instead of JIT
		if ([sender isOn]) {
			[Utils showNotice:self title:@"advanced.use-tweak.warning".loc];
		}
		[Utils toggleKey:@"USE_TWEAK"];
		[self.tableView reloadData];
		break;
	case 4: // Auto JIT
		if ([sender isOn]) {
			UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"jit.enable-auto-jit.warning.title".loc message:@"jit.enable-auto-jit.warning".loc
																	preferredStyle:UIAlertControllerStyleAlert];
			UIAlertAction* yesAction = [UIAlertAction actionWithTitle:@"common.yes".loc style:UIAlertActionStyleDefault
															  handler:^(UIAlertAction* _Nonnull action) { [[Utils getPrefs] setBool:YES forKey:@"AUTO_JIT"]; }];
			UIAlertAction* noAction = [UIAlertAction actionWithTitle:@"common.no".loc style:UIAlertActionStyleDefault
															 handler:^(UIAlertAction* _Nonnull action) { [sender setOn:NO]; }];
			[alert addAction:yesAction];
			[alert addAction:noAction];
			[self presentViewController:alert animated:YES completion:nil];
		} else {
			[[Utils getPrefs] setBool:NO forKey:@"AUTO_JIT"];
		}
		break;
	case 5: // Rotate Fix
		[Utils toggleKey:@"FIX_ROTATION"];
		break;
	case 6: // Completed Setup
		[Utils toggleKey:@"CompletedSetup"];
		break;
	case 7:
		[Utils toggleKey:@"MANUAL_REOPEN"];
		break;
	case 8:
		[Utils toggleKey:@"FIX_BLACKSCREEN"];
		break;
	case 9:
		[Utils toggleKey:@"JITLESS"];
		[self.tableView reloadData];
		break;
	case 10:
		break;
	case 11:
		[Utils toggleKey:@"USE_NIGHTLY"];
		[[Utils getPrefs] setBool:NO forKey:@"UPDATE_AUTOMATICALLY"];
		[self.tableView reloadData];
		break;
	case 12:
		if ([sender isOn]) {
			[Utils showNotice:self title:@"developer.webserver.msg".loc];
		}
		[Utils toggleKey:@"WEB_SERVER"];
		break;
	}
}

- (void)themeSelected:(UISegmentedControl*)sender {
	NSInteger style = sender.selectedSegmentIndex;
	[[Utils getPrefs] setInteger:style forKey:@"CURRENT_THEME"];

	UIWindow* keyWindow = nil;
	for (UIWindow* window in [UIApplication sharedApplication].windows) {
		if (window.isKeyWindow) {
			keyWindow = window;
			break;
		}
	}
	if (!keyWindow) {
		keyWindow = [UIApplication sharedApplication].windows.firstObject;
	}
	if (keyWindow) {
		switch (style) {
		case 0: // System
			keyWindow.overrideUserInterfaceStyle = UIUserInterfaceStyleUnspecified;
			break;
		case 1: // Light
			keyWindow.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
			break;
		case 2: // Dark
			keyWindow.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
			break;
		}
		keyWindow.backgroundColor = [Theming getBackgroundColor];
		[self.root refreshTheme];
		[self.tableView reloadData];
	}
}

#pragma mark - Text Field Delegate
- (void)textFieldDidEndEditing:(UITextField*)textField {
	switch (textField.tag) {
	case 0: // address
		[[Utils getPrefs] setValue:textField.text forKey:@"SideJITServerAddr"];
		break;
	case 1: // udid
		[[Utils getPrefs] setValue:textField.text forKey:@"JITDeviceUDID"];
		break;
	case 2: // reinstall addr
		[[Utils getPrefs] setValue:textField.text forKey:@"DEV_REINSTALL_ADDR"];
		break;
	case 3: // launch args
		[[Utils getPrefs] setValue:textField.text forKey:@"LAUNCH_ARGS"];
		break;
	}
}

- (BOOL)textFieldShouldReturn:(UITextField*)textField {
	[textField resignFirstResponder];
	return YES;
}

- (void)ms_dismissViewController:(id)sender {
	[self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - MSColorViewDelegate

- (void)colorViewController:(MSColorSelectionViewController*)colorViewCntroller didChangeColor:(UIColor*)color {
	[Theming saveAccentColor:color];
	[self.root updateState];
	[self.tableView reloadData];
	//[self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationFade];
}

#pragma mark - Document Delegate Funcs (for importing cert mainly)
- (void)documentPicker:(UIDocumentPickerViewController*)controller didPickDocumentAtURL:(NSURL*)url {
}

- (void)documentPicker:(UIDocumentPickerViewController*)controller didPickDocumentsAtURLs:(nonnull NSArray<NSURL*>*)urls {
	if (_isImportCert) {
		_isImportCert = NO;
		if (urls.count != 2)
			return [Utils showError:self title:@"2 files must be selected! (p12 & mobileprovision)" error:nil];
		NSString* extension1 = urls.firstObject.pathExtension;
		NSString* extension2 = urls.lastObject.pathExtension;
		if ([extension1 isEqualToString:extension2])
			return [Utils showError:self title:@"You must only select 2 different files! Both the certificate (.p12) and the mobile provision profile! (.mobileprovision)"
							  error:nil];
		AppLog(@"Selected URLs: %@", urls);
		UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Input the password of the Certificate." message:@"This will be used for signing."
																preferredStyle:UIAlertControllerStyleAlert];
		[alert addTextFieldWithConfigurationHandler:^(UITextField* _Nonnull textField) {
			textField.placeholder = @"Certificate Password";
			textField.secureTextEntry = YES;
		}];
		UIAlertAction* okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction* _Nonnull action) {
			NSError* err;
			NSURL* provisionURL;
			if (![extension1 isEqualToString:@"p12"]) {
				provisionURL = urls.firstObject;
			} else {
				provisionURL = urls.lastObject;
			}
			NSURL* newURL = [[LCPath docPath] URLByAppendingPathComponent:@"embedded.mobileprovision"];
			if ([[NSFileManager defaultManager] fileExistsAtPath:newURL.path]) {
				[[NSFileManager defaultManager] removeItemAtURL:newURL error:&err];
				if (err)
					return [Utils showError:self title:@"Couldn't remove mobile provision from documents" error:err];
			}
			[[NSFileManager defaultManager] moveItemAtURL:provisionURL toURL:newURL error:&err];
			if (err)
				return [Utils showError:self title:@"Couldn't move mobile provision to documents" error:err]; // when would this error realistically happen
			UITextField* field = alert.textFields.firstObject;
			if ([extension1 isEqualToString:@"p12"]) {
				[self certPass:field.text url:urls.firstObject];
			} else {
				[self certPass:field.text url:urls.lastObject];
			}
		}];

		UIAlertAction* cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
		[alert addAction:okAction];
		[alert addAction:cancelAction];
		[self presentViewController:alert animated:YES completion:nil];
	} else if (_isImportIPA) {
		_isImportIPA = NO;
		NSURL* url = urls.firstObject;
		if (url) {
			[self dismissViewControllerAnimated:YES completion:nil];
			dispatch_async(dispatch_get_main_queue(), ^{
				AppLog(@"start installing ipa!");
				_root.optionalTextLabel.text = @"launcher.status.extracting".loc;
				[_root progressCancelVisibility:NO];
			});
			[VerifyInstall startGDInstall:_root url:url];
		}
	}
}

- (void)certPass:(NSString*)certPass url:(NSURL*)url {
	NSError* err;
	NSData* certData = [NSData dataWithContentsOfURL:url options:0 error:&err];
	if (err) {
		[Utils showError:self title:@"Couldn't read certificate" error:err];
		return;
	}
	NSString* teamId = [LCUtils getCertTeamIdWithKeyData:certData password:certPass];
	if (!teamId) {
		[Utils showError:self title:@"Couldn't get Team ID from certificate." error:nil];
		return;
	}
	AppLog(@"Import complete!");
	NSUserDefaults* NSUD = [Utils getPrefs];
	[NSUD setObject:certPass forKey:@"LCCertificatePassword"];
	[NSUD setObject:certData forKey:@"LCCertificateData"];
	[NSUD setObject:teamId forKey:@"LCCertificateTeamId"];
	[NSUD setBool:YES forKey:@"LCCertificateImported"];
	[NSUD setBool:YES forKey:@"USE_ZSIGN"];
	[Utils showNotice:self title:@"Certificate Imported!"];
	[self.tableView reloadData];
}
@end

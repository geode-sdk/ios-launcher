#import "IconView.h"
#import "Utils.h"
#import "components/LogUtils.h"
#import "src/Theming.h"
#import <UIKit/UIKit.h>

@interface IconViewController ()
@property(nonatomic, strong) NSArray* icons;
@end

@implementation IconViewController
- (void)viewDidLoad {
	[super viewDidLoad];
	//[self setTitle:@"general.change-icon".loc];
	[[self tableView] setRowHeight:75];
	self.icons = @[
		@{ @"name" : @"Default", @"iconName" : @"AppIcon", @"iconImg" : @"AppIcon60x60" },
		@{ @"name" : @"Geode", @"iconName" : @"Geode", @"iconImg" : @"GeodeIcon60x60" },
		@{ @"name" : @"Perfection.", @"iconName" : @"Perfection", @"iconImg" : @"PerfectionIcon60x60" },
	];
	// https://github.com/reactwg/react-native-new-architecture/blob/76d8426c27c1bf30c235f653e425ef872554a33b/docs/fabric-native-components.md
	[NSLayoutConstraint activateConstraints:@[
		[self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
	]];
	[[self view] setBackgroundColor:[Theming getBackgroundColor]];
}
- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView {
	return 1;
}

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {
	return self.icons.count;
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath {
	UITableViewCell* cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];

	cell.backgroundColor = nil;

	UIImageView* iconView = [[UIImageView alloc] init];
	iconView.image = [UIImage imageNamed:self.icons[indexPath.row][@"iconImg"]];
	iconView.translatesAutoresizingMaskIntoConstraints = NO;
	iconView.layer.masksToBounds = YES;
	iconView.layer.cornerRadius = 15;
	[cell.contentView addSubview:iconView];

	UILabel* name = [[UILabel alloc] init];
	name.translatesAutoresizingMaskIntoConstraints = NO;
	name.font = [UIFont boldSystemFontOfSize:20];
	name.text = self.icons[indexPath.row][@"name"];
	[cell.contentView addSubview:name];

	[NSLayoutConstraint activateConstraints:@[
		[iconView.widthAnchor constraintEqualToConstant:60],
		[iconView.heightAnchor constraintEqualToConstant:60], // or itll be squished
		[iconView.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:20],
		[iconView.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],

		[name.leadingAnchor constraintEqualToAnchor:iconView.trailingAnchor constant:16],
		[name.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
	]];

	NSString* iconKey = [[Utils getPrefs] stringForKey:@"CURRENT_ICON"];
	NSString* currentIcon = [UIApplication sharedApplication].alternateIconName;
	BOOL isSelected = ([iconKey isEqualToString:self.icons[indexPath.row][@"name"]]) || ([currentIcon isEqualToString:self.icons[indexPath.row][@"iconName"]]);
	if (currentIcon == nil) {
		isSelected = ([self.icons[indexPath.row][@"iconName"] isEqualToString:@"AppIcon"]);
		if (iconKey == nil) {
			[[Utils getPrefs] setValue:@"Default" forKey:@"CURRENT_ICON"];
		}
	} else {
		if (iconKey == nil && isSelected) {
			[[Utils getPrefs] setValue:self.icons[indexPath.row][@"name"] forKey:@"CURRENT_ICON"];
		}
	}
	cell.accessoryType = isSelected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
	return cell;
}

- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	NSString* iconKey = nil;
	if (![self.icons[indexPath.row][@"iconName"] isEqualToString:@"AppIcon"]) {
		iconKey = self.icons[indexPath.row][@"iconName"];
	}
	[[UIApplication sharedApplication] setAlternateIconName:iconKey completionHandler:^(NSError* _Nullable error) {
		if (error) {
			AppLog(@"Failed to set alternate icon: %@, assuming doesn't have entitlements", error);
		} else {
			AppLog(@"Icon set successfully.");
		}
	}];
	[[Utils getPrefs] setValue:self.icons[indexPath.row][@"name"] forKey:@"CURRENT_ICON"];
	[_root updateLogoImage:indexPath.row];
	[self.tableView reloadData];
}

@end

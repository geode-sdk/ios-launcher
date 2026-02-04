#import "MSColorPicker/MSColorPicker/MSColorSelectionViewController.h"
#import "RootViewController.h"
#include <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, SettingType) {
    SettingTypeToggle,
    SettingTypeButton,
    SettingTypeButtonWithIcon,
    SettingTypeCustom,
    SettingTypeCustomVal1
};
@interface Setting : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) SettingType type;
@property (nonatomic, copy) BOOL (^disabled)(void);
@property (nonatomic, copy) BOOL (^visible)(void);
@property (nonatomic, copy) void (^action)(void);
@property (nonatomic, copy) void (^custom)(UITableViewCell *cell);
@property (nonatomic, copy) NSString *prefsKey;
@property (nonatomic, assign) NSInteger switchTag;
@end

@interface SettingsVC
	: UIViewController <UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate, UIPopoverPresentationControllerDelegate, MSColorSelectionViewControllerDelegate>
@property(nonatomic, strong) UITableView* tableView;
@property(nonatomic, strong) RootViewController* root;
@end

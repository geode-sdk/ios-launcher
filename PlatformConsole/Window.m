#import <UIKit/UIKit.h>
#include <dlfcn.h>
#include <objc/runtime.h>
#import "Window.h"
#import "fishhook/fishhook.h"
#import <mach/mach.h>
#import <os/proc.h>

@interface LogWindow () <UITextViewDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIView *titleBar;
@property (nonatomic, strong) UIButton *scrollLockButton;
@property (nonatomic, strong) UITextView *textView;

@property (nonatomic, strong) UIView *resizeHandleRight;
@property (nonatomic, strong) UIView *resizeHandleLeft;
@property (nonatomic, strong) NSMutableAttributedString *logContent;

@property (nonatomic, assign) BOOL scrollLocked;

@property (nonatomic, strong) NSTimer *memoryTimer;

@end

@implementation LogWindow
- (UIButton *)makeButton:(NSString *)title {
	UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
	[btn setTitle:title forState:UIControlStateNormal];
	[btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
	btn.titleLabel.font = [UIFont systemFontOfSize:14];
	btn.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.2];
	btn.layer.cornerRadius = 4;
	btn.clipsToBounds = YES;
	return btn;
}
- (void)addTriangleToHandle:(UIView *)handle corner:(UIRectCorner)corner {
	CAShapeLayer *triangle = [CAShapeLayer layer];
	UIBezierPath *path = [UIBezierPath bezierPath];

	if (corner == UIRectCornerBottomRight) {
		[path moveToPoint:CGPointMake(handle.bounds.size.width, handle.bounds.size.height)];
		[path addLineToPoint:CGPointMake(handle.bounds.size.width, 0)];
		[path addLineToPoint:CGPointMake(0, handle.bounds.size.height)];
	} else if (corner == UIRectCornerBottomLeft) {
		[path moveToPoint:CGPointMake(0, handle.bounds.size.height)];
		[path addLineToPoint:CGPointMake(0, 0)];
		[path addLineToPoint:CGPointMake(handle.bounds.size.width, handle.bounds.size.height)];
	}
	[path closePath];

	triangle.path = path.CGPath;
	triangle.fillColor = [UIColor colorWithWhite:1.0 alpha:0.4].CGColor;

	[handle.layer addSublayer:triangle];
}

- (instancetype)init {
	CGRect frame = CGRectMake(100, 100, 400, 200);
	BOOL rotate = getenv("ROTATE_PLATFORM_CONSOLE");
	if (rotate) {
		frame = CGRectMake(-100, 100, 400, 200);
		self = [super initWithFrame:CGRectMake(100, 100, 200, 400)];
	} else {
		self = [super initWithFrame:frame];
	}
	if (self) {
		self.windowLevel = UIWindowLevelAlert + 1;
		self.backgroundColor = [UIColor clearColor];

		// Container
		UIView *contentView;
		if (rotate) {
			contentView = [[UIView alloc] initWithFrame:frame];
			contentView.transform = CGAffineTransformMakeRotation(M_PI_2);
		} else {
			contentView = [[UIView alloc] initWithFrame:self.bounds];
		}
		contentView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.9];
		contentView.layer.cornerRadius = 8;
		contentView.layer.masksToBounds = YES;
		contentView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		[self addSubview:contentView];

		// Title Bar
		self.titleBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, frame.size.width, 28)];
		self.titleBar.backgroundColor = [[UIColor clearColor] colorWithAlphaComponent:0.4];
		self.titleBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		[contentView addSubview:self.titleBar];

		self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(8, 0, 400, 28)];
		self.titleLabel.text = [NSString stringWithFormat:@"Platform Console"];
		self.titleLabel.textColor = [UIColor whiteColor];
		self.titleLabel.font = [UIFont boldSystemFontOfSize:14];
		[self.titleBar addSubview:self.titleLabel];

		// Buttons
		UIButton *closeButton = [self makeButton:@"✕"];
		[closeButton addTarget:self action:@selector(onClose) forControlEvents:UIControlEventTouchUpInside];
		closeButton.frame = CGRectMake(frame.size.width - 26, 2, 24, 24);
		closeButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
		[self.titleBar addSubview:closeButton];

		UIButton *clearButton = [self makeButton:@"⌫"];
		[clearButton addTarget:self action:@selector(clearTapped) forControlEvents:UIControlEventTouchUpInside];
		clearButton.frame = CGRectMake(frame.size.width - 52, 2, 24, 24);
		clearButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
		[self.titleBar addSubview:clearButton];

		_scrollLockButton = [self makeButton:@"⇩"];
		[_scrollLockButton addTarget:self action:@selector(toggleScrollLock) forControlEvents:UIControlEventTouchUpInside];
		_scrollLockButton.frame = CGRectMake(frame.size.width - 78, 2, 24, 24);
		_scrollLockButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
		[self.titleBar addSubview:_scrollLockButton];
		[self toggleScrollLock];

		// Text View
		self.textView = [[UITextView alloc] initWithFrame:CGRectMake(0, 28, frame.size.width, frame.size.height-28)];
		self.textView.font = [UIFont fontWithName:@"Courier" size:12];
		self.textView.editable = NO;
		self.textView.selectable = NO;

		self.textView.backgroundColor = [UIColor clearColor];
		self.textView.textColor = [UIColor whiteColor];
		self.textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		[contentView addSubview:self.textView];

		_logContent = [[NSMutableAttributedString alloc] init];

		// bottom right
		self.resizeHandleRight = [[UIView alloc] initWithFrame:CGRectMake(frame.size.width-20, frame.size.height-20, 20, 20)];
		self.resizeHandleRight.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin;
		[contentView addSubview:self.resizeHandleRight];
		[self addTriangleToHandle:self.resizeHandleRight corner:UIRectCornerBottomRight];

		UIPanGestureRecognizer *resizePanRight = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleResizeRight:)];
		[self.resizeHandleRight addGestureRecognizer:resizePanRight];

		// bottom left
		self.resizeHandleLeft = [[UIView alloc] initWithFrame:CGRectMake(0, frame.size.height-20, 20, 20)];
		self.resizeHandleLeft.autoresizingMask = UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin;
		[contentView addSubview:self.resizeHandleLeft];
		[self addTriangleToHandle:self.resizeHandleLeft corner:UIRectCornerBottomLeft];

		UIPanGestureRecognizer *resizePanLeft = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleResizeLeft:)];
		[self.resizeHandleLeft addGestureRecognizer:resizePanLeft];
		
		// only drag on titlebar
		UIPanGestureRecognizer *movePan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
		[self.titleBar addGestureRecognizer:movePan];
		
		self.alpha = 0.8;

		[self makeKeyAndVisible];

		self.memoryTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(updateTitle) userInfo:nil repeats:YES];
	}
	return self;
}

- (void)updateTitle {
	// https://stackoverflow.com/questions/53854873/tracking-ios-memory-usage
	uint64_t usedMemory;
	task_vm_info_data_t vmInfo;
	mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
	kern_return_t result = task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&vmInfo, &count);
	if (result != KERN_SUCCESS) {
		usedMemory = 0;
	} else {
		usedMemory = vmInfo.phys_footprint;
	}
	//uint64_t maxMemory = [NSProcessInfo processInfo].physicalMemory;
	uint64_t maxMemory = usedMemory + (uint64_t)os_proc_available_memory();

	double usedMemoryMB = usedMemory / (1024.0 * 1024.0);
	double maxMemoryMB = maxMemory / (1024.0 * 1024.0);

	self.titleLabel.text = [NSString stringWithFormat:@"Platform Console - (%.2fMB/%.2fMB)", usedMemoryMB, maxMemoryMB];
}

- (void)scrollToBottom {
	if (!self.scrollLocked) return;

	CGFloat contentHeight = self.textView.contentSize.height;
	CGFloat boundsHeight = self.textView.bounds.size.height;
	if (contentHeight > boundsHeight) {
		CGPoint bottomOffset = CGPointMake(0, contentHeight - boundsHeight);
		[self.textView setContentOffset:bottomOffset animated:NO];
	}
}

- (void)log:(NSString *)message {
	dispatch_async(dispatch_get_main_queue(), ^{
		NSAttributedString *line = [[NSAttributedString alloc] initWithString:[message stringByAppendingString:@"\n"] attributes:@{NSForegroundColorAttributeName:[UIColor whiteColor]}];
		[_logContent appendAttributedString:line];
		self.textView.attributedText = _logContent;
		if (self.scrollLocked) {
			[self scrollToBottom];
		}
	});
}

- (void)onClose {
	self.hidden = YES;
}

- (void)clearTapped {
	[_logContent setAttributedString:[[NSAttributedString alloc] initWithString:@""]];
	self.textView.attributedText = _logContent;
}

- (void)toggleScrollLock {
	self.scrollLocked = !self.scrollLocked;
	_scrollLockButton.backgroundColor = self.scrollLocked ? [[UIColor greenColor] colorWithAlphaComponent:0.5] : [[UIColor whiteColor] colorWithAlphaComponent:0.2];
}

#pragma mark - Dragging
- (void)handlePan:(UIPanGestureRecognizer *)pan {
	CGPoint translation = [pan translationInView:self];
	self.center = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
	[pan setTranslation:CGPointZero inView:self];
	if (pan.state == UIGestureRecognizerStateEnded) {
		self.alpha = 0.8;
	} else if (pan.state == UIGestureRecognizerStateBegan) {
		self.alpha = 1.0;
	}
}

#pragma mark - Resizing
- (void)handleResize:(UIPanGestureRecognizer *)pan {
	CGPoint translation = [pan translationInView:self];
	CGRect newFrame = self.frame;
	if (getenv("ROTATE_PLATFORM_CONSOLE")) {
		newFrame.size.width -= translation.x;
		newFrame.origin.x += translation.x;
		newFrame.size.height = MAX(150, newFrame.size.height + translation.y);
		if (newFrame.size.width >= 100) {
			self.frame = newFrame;
		}
	} else {
		newFrame.size.width = MAX(150, newFrame.size.width + translation.x);
		newFrame.size.height = MAX(100, newFrame.size.height + translation.y);
		self.frame = newFrame;
	}
	[pan setTranslation:CGPointZero inView:self];
	[self scrollToBottom];
}

- (void)handleResizeRight:(UIPanGestureRecognizer *)pan {
	CGPoint translation = [pan translationInView:self];
	CGRect newFrame = self.frame;
	if (getenv("ROTATE_PLATFORM_CONSOLE")) {
		newFrame.size.width -= translation.x;
		newFrame.origin.x += translation.x;
		newFrame.size.height = MAX(150, newFrame.size.height + translation.y);
		if (newFrame.size.width >= 100) {
			self.frame = newFrame;
		}
	} else {
		newFrame.size.width = MAX(150, newFrame.size.width + translation.x);
		newFrame.size.height = MAX(100, newFrame.size.height + translation.y);
		self.frame = newFrame;
	}
	[pan setTranslation:CGPointZero inView:self];
	[self scrollToBottom];
}

- (void)handleResizeLeft:(UIPanGestureRecognizer *)pan {
	CGPoint translation = [pan translationInView:self];
	CGRect newFrame = self.frame;
	newFrame.origin.x += translation.x;
	newFrame.size.width -= translation.x;
	if (getenv("ROTATE_PLATFORM_CONSOLE")) {
		newFrame.origin.y += translation.y;
		newFrame.size.height -= translation.y;

		if (newFrame.size.height >= 150 && newFrame.size.width >= 100) {
			self.frame = newFrame;
		}
	} else {
		newFrame.size.height = MAX(100, newFrame.size.height + translation.y);

		if (newFrame.size.width >= 150) {
			self.frame = newFrame;
		}
	}
	[pan setTranslation:CGPointZero inView:self];
	[self scrollToBottom];
}

@end

// this is so hacky
static void (*orig_NSLog)(NSString *format, ...);
BOOL s_windowSpawned;
static LogWindow* window;

// surely isnt bad lol
void new_NSLog(NSString *format, ...) {
	va_list args;
	va_start(args, format);
	NSString *str = [[NSString alloc] initWithFormat:format arguments:args];
	va_end(args);

	if (s_windowSpawned) {
		[window log:str];
	}

	orig_NSLog(@"%@", str);
}

@implementation NSObject (modif_AppController)
- (BOOL)pc_application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions {
	BOOL ret = [self pc_application:application didFinishLaunchingWithOptions:nil];
	dispatch_async(dispatch_get_main_queue(), ^{
		window = [[LogWindow alloc] init];
		[window makeKeyAndVisible];
		s_windowSpawned = YES;
	});
	return ret;
}
@end

__attribute__((constructor))
static void PlatformConsoleConstructor() {
	// maybe have an NSUserDefault which is enabled or disabled in main.m depending on the read of saved.json before idk
	if (getenv("SHOW_PLATFORM_CONSOLE")) {
		Class appCtrl = NSClassFromString(@"AppController");
		if (appCtrl) {
			SEL orig = @selector(application:didFinishLaunchingWithOptions:);
			SEL swizzled = @selector(pc_application:didFinishLaunchingWithOptions:);
			Method origMethod = class_getInstanceMethod(appCtrl, orig);
			Method swzMethod = class_getInstanceMethod([NSObject class], swizzled);
			if (origMethod && swzMethod) {
				class_addMethod(appCtrl, swizzled, method_getImplementation(swzMethod), method_getTypeEncoding(swzMethod));
				method_exchangeImplementations(origMethod, class_getInstanceMethod(appCtrl, swizzled));
			}
		}
		rebind_symbols((struct rebinding[1]){ { "NSLog", (void*)new_NSLog, (void**)&orig_NSLog } }, 1);
	}
}

#import "LCUtils/FoundationPrivate.h"
#import "LCUtils/GCSharedUtils.h"
#import "LCUtils/Shared.h"
#import "LCUtils/UIKitPrivate.h"
#import "LCUtils/utils.h"
#import "Utils.h"
#import "components/LogUtils.h"
#import <Foundation/Foundation.h>

#include <mach-o/dyld.h>
#include <mach-o/dyld_images.h>
#include <mach/mach.h>
#include <objc/runtime.h>

#import "AppDelegate.h"
#include "LCUtils/TPRO.h"
#include "fishhook/fishhook.h"
#import <UIKit/UIKit.h>
#include <dlfcn.h>
#include <execinfo.h>
#include <mach-o/ldsyms.h>
#include <signal.h>
#include <stdlib.h>
#include <sys/mman.h>

static int (*appMain)(int, char**);
static const char* dyldImageName;
NSUserDefaults* gcUserDefaults;
NSUserDefaults* gcSharedDefaults;
NSString* gcAppGroupPath;
NSString* gcAppUrlScheme;
NSBundle* gcMainBundle;
NSDictionary* guestAppInfo;

BOOL usingLiveContainer;

void NUDGuestHooksInit();

void UIAGuestHooksInit();

@implementation NSUserDefaults (Geode)
+ (instancetype)gcUserDefaults {
	return gcUserDefaults;
}
+ (instancetype)gcSharedDefaults {
	return gcSharedDefaults;
}
+ (NSString*)gcAppGroupPath {
	return gcAppGroupPath;
}
+ (NSString*)gcAppUrlScheme {
	return gcAppUrlScheme;
}
+ (NSBundle*)gcMainBundle {
	return gcMainBundle;
}
+ (NSDictionary*)guestAppInfo {
	return guestAppInfo;
}
@end

static BOOL checkJITEnabled() {
	if (access("/Users", R_OK) == 0)
		return YES;
	if ([gcUserDefaults boolForKey:@"JITLESS"])
		return NO;
	// check if jailbroken
	if (access("/var/mobile", R_OK) == 0) {
		return YES;
	}

	// check csflags
	int flags;
	csops(getpid(), 0, &flags, sizeof(flags));
	return (flags & CS_DEBUGGED) != 0;
}

static uint64_t rnd64(uint64_t v, uint64_t r) {
	r--;
	return (v + r) & ~r;
}

static void overwriteMainCFBundle() {
	// Overwrite CFBundleGetMainBundle
	uint32_t* pc = (uint32_t*)CFBundleGetMainBundle;
	void** mainBundleAddr = 0;
	while (true) {
		uint64_t addr = aarch64_get_tbnz_jump_address(*pc, (uint64_t)pc);
		if (addr) {
			// adrp <- pc-1
			// tbnz <- pc
			// ...
			// ldr  <- addr
			mainBundleAddr = (void**)aarch64_emulate_adrp_ldr(*(pc - 1), *(uint32_t*)addr, (uint64_t)(pc - 1));
			break;
		}
		++pc;
	}
	assert(mainBundleAddr != NULL);
	*mainBundleAddr = (__bridge void*)NSBundle.mainBundle._cfBundle;
}

static void overwriteMainNSBundle(NSBundle* newBundle) {
	// Overwrite NSBundle.mainBundle
	// iOS 16: x19 is _MergedGlobals
	// iOS 17: x19 is _MergedGlobals+4

	NSString* oldPath = NSBundle.mainBundle.executablePath;
	uint32_t* mainBundleImpl = (uint32_t*)method_getImplementation(class_getClassMethod(NSBundle.class, @selector(mainBundle)));
	for (int i = 0; i < 20; i++) {
		void** _MergedGlobals = (void**)aarch64_emulate_adrp_add(mainBundleImpl[i], mainBundleImpl[i + 1], (uint64_t)&mainBundleImpl[i]);
		if (!_MergedGlobals)
			continue;

		// In iOS 17, adrp+add gives _MergedGlobals+4, so it uses ldur instruction instead of ldr
		if ((mainBundleImpl[i + 4] & 0xFF000000) == 0xF8000000) {
			uint64_t ptr = (uint64_t)_MergedGlobals - 4;
			_MergedGlobals = (void**)ptr;
		}

		for (int mgIdx = 0; mgIdx < 20; mgIdx++) {
			if (_MergedGlobals[mgIdx] == (__bridge void*)NSBundle.mainBundle) {
				_MergedGlobals[mgIdx] = (__bridge void*)newBundle;
				break;
			}
		}
	}

	assert(![NSBundle.mainBundle.executablePath isEqualToString:oldPath]);
}

static void overwriteExecPath_handler(int signum, siginfo_t* siginfo, void* context) {
	struct __darwin_ucontext* ucontext = (struct __darwin_ucontext*)context;

	// x19: size pointer
	// x20: output buffer
	// x21: executable_path

	// Ensure we're not getting SIGSEGV twice
	static uint32_t fakeSize = 0;
	assert(ucontext->uc_mcontext->__ss.__x[19] == 0);
	ucontext->uc_mcontext->__ss.__x[19] = (uint64_t)&fakeSize;

	char* path = (char*)ucontext->uc_mcontext->__ss.__x[21];
	char* newPath = (char*)dyldImageName;
	size_t maxLen = rnd64(strlen(path), 8);
	size_t newLen = strlen(newPath);
	// Check if it's long enough...
	assert(maxLen >= newLen);

	// if we don't have TPRO, we will use the old way
	if (!os_thread_self_restrict_tpro_to_rw()) {
		// Make it RW and overwrite now
		kern_return_t ret = builtin_vm_protect(mach_task_self(), (mach_vm_address_t)path, maxLen, false, PROT_READ | PROT_WRITE);
		if (ret != KERN_SUCCESS) {
			ret = builtin_vm_protect(mach_task_self(), (mach_vm_address_t)path, maxLen, false, PROT_READ | PROT_WRITE | VM_PROT_COPY);
		}
		assert(ret == KERN_SUCCESS);
	}

	bzero(path, maxLen);
	strncpy(path, newPath, newLen);
}
static void overwriteExecPath(NSString* bundlePath) {
	// Silly workaround: we have set our executable name 100 characters long, now just overwrite its path with our fake executable file
	char* path = (char*)dyldImageName;
	const char* newPath = [bundlePath stringByAppendingPathComponent:@"Geode"].UTF8String;
	size_t maxLen = rnd64(strlen(path), 8);
	size_t newLen = strlen(newPath);

	// Check if it's long enough...
	assert(maxLen >= newLen);
	// Create an empty file so dyld could resolve its path properly
	close(open(newPath, O_CREAT | S_IRUSR | S_IWUSR));

	// Make it RW and overwrite now
	// | VM_PROT_COPY
	kern_return_t ret = builtin_vm_protect(mach_task_self(), (mach_vm_address_t)path, maxLen, false, PROT_READ | PROT_WRITE);
	if (ret != KERN_SUCCESS) {
		// thanks apple for introducing this ios 18.2 specific problem!
		BOOL tpro_ret = os_thread_self_restrict_tpro_to_rw();
		assert(tpro_ret);
	}
	bzero(path, maxLen);
	strncpy(path, newPath, newLen);

	// dyld4 stores executable path in a different place
	// https://github.com/apple-oss-distributions/dyld/blob/ce1cc2088ef390df1c48a1648075bbd51c5bbc6a/dyld/DyldAPIs.cpp#L802
	char currPath[PATH_MAX];
	uint32_t len = PATH_MAX;
	_NSGetExecutablePath(currPath, &len);
	if (strncmp(currPath, newPath, newLen)) {
		struct sigaction sa, saOld;
		sa.sa_sigaction = overwriteExecPath_handler;
		sa.sa_flags = SA_SIGINFO;
		sigaction(SIGSEGV, &sa, &saOld);
		// Jump to overwriteExecPath_handler()
		_NSGetExecutablePath((char*)0x41414141, NULL);
		sigaction(SIGSEGV, &saOld, NULL);
	}
}

static void* getAppEntryPoint(void* handle, uint32_t imageIndex) {
	uint32_t entryoff = 0;
	const struct mach_header_64* header = (struct mach_header_64*)_dyld_get_image_header(imageIndex);
	uint8_t* imageHeaderPtr = (uint8_t*)header + sizeof(struct mach_header_64);
	struct load_command* command = (struct load_command*)imageHeaderPtr;
	for (int i = 0; i < header->ncmds > 0; ++i) {
		if (command->cmd == LC_MAIN) {
			struct entry_point_command ucmd = *(struct entry_point_command*)imageHeaderPtr;
			entryoff = ucmd.entryoff;
			break;
		}
		imageHeaderPtr += command->cmdsize;
		command = (struct load_command*)imageHeaderPtr;
	}
	assert(entryoff > 0);
	return (void*)header + entryoff;
}

uint32_t appMainImageIndex = 0;
void* appExecutableHandle = 0;
void* (*orig_dlsym)(void* __handle, const char* __symbol);
void* new_dlsym(void* __handle, const char* __symbol) {
	if (__handle == (void*)RTLD_MAIN_ONLY) {
		if (strcmp(__symbol, MH_EXECUTE_SYM) == 0) {
			return (void*)_dyld_get_image_header(appMainImageIndex);
		}
		return orig_dlsym(appExecutableHandle, __symbol);
	}

	return orig_dlsym(__handle, __symbol);
}

static NSString* invokeAppMain(NSString* selectedApp, NSString* selectedContainer, BOOL safeMode, int argc, char* argv[]) {
	NSString* appError = nil;
	if (![gcUserDefaults boolForKey:@"JITLESS"]) {
		// First of all, let's check if we have JIT
		for (int i = 0; i < 10 && !checkJITEnabled(); i++) {
			usleep(1000 * 100);
		}
		if (!checkJITEnabled()) {
			appError = @"JIT was not enabled. Please ensure that you launched the Geode launcher with JIT. You can enable \"Manual reopen with JIT\" for manually enabling JIT "
					   @"(Pressing launch, closing app, open with JIT).";
			// appError = @"JIT was not enabled. If you want to use Geode without JIT, setup JITLess mode in settings.";
			return appError;
		}
	}

	NSFileManager* fm = NSFileManager.defaultManager;
	NSString* docPath = [fm URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].lastObject.path;

	NSURL* appGroupFolder = nil;

	NSString* bundlePath = [NSString stringWithFormat:@"%@/Applications/%@", docPath, selectedApp];
	NSBundle* appBundle = [[NSBundle alloc] initWithPath:bundlePath];
	NSString* tweakFolder = nil;
	if (docPath != nil) {
		tweakFolder = [docPath stringByAppendingPathComponent:@"Tweaks"];
	}

	bool isSharedBundle = false;
	// not found locally, let's look for the app in shared folder
	if (!appBundle) {
		AppLog(@"[invokeAppMain] Couldn't find appBundle, finding locally...");
		NSURL* appGroupPath = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:[GCSharedUtils appGroupID]];
		appGroupFolder = [appGroupPath URLByAppendingPathComponent:@"Geode"];

		bundlePath = [NSString stringWithFormat:@"%@/Applications/%@", appGroupFolder.path, selectedApp];
		appBundle = [[NSBundle alloc] initWithPath:bundlePath];
		isSharedBundle = true;
	}
	guestAppInfo = [NSDictionary dictionaryWithContentsOfURL:[appBundle URLForResource:@"LCAppInfo" withExtension:@"plist"]];

	if (!appBundle) {
		return @"App not found";
	}

	// find container in Info.plist
	NSString* dataUUID = selectedContainer;
	if (dataUUID == nil) {
		return @"Container not found!";
	}

	NSError* error;
	if (tweakFolder != nil) {
		setenv("GC_GLOBAL_TWEAKS_FOLDER", tweakFolder.UTF8String, 1);

		// Update TweakLoader symlink
		NSString* tweakLoaderPath = [tweakFolder stringByAppendingPathComponent:@"TweakLoader.dylib"];
		if (![fm fileExistsAtPath:tweakLoaderPath]) {
			AppLog(@"invokeAppMain - Creating TweakLoader.dylib symlink");
			remove(tweakLoaderPath.UTF8String);
			NSString* target = [NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:@"TweakLoader.dylib"];
			symlink(target.UTF8String, tweakLoaderPath.UTF8String);
		}

		if ([gcUserDefaults boolForKey:@"WEB_SERVER"]) {
			NSString* webServerPath = [tweakFolder stringByAppendingPathComponent:@"WebServer.dylib"];
			if (![fm fileExistsAtPath:webServerPath]) {
				AppLog(@"[invokeAppMain] Creating WebServer.dylib symlink");
				remove(webServerPath.UTF8String);
				NSString* target = [NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:@"WebServer.dylib"];
				symlink(target.UTF8String, webServerPath.UTF8String);
			}
		}
	} else {
		AppLog(@"[invokeAppMain] Couldn't find tweak folder!");
	}
	// If JIT is enabled, bypass library validation so we can load arbitrary binaries
	if (!usingLiveContainer) {
		if (checkJITEnabled()) { // lc already hooks it so it's unnecessary to do it again...
			init_bypassDyldLibValidation();
		}
		AppLog(@"[invokeAppMain] JIT pass (2/2) & Bypassed Dyld-lib validation!");
	} else {
		AppLog(@"[invokeAppMain] Ignoring bypass dyld lib validation hook since LC should already do that.");
	}

	// Locate dyld image name address
	const char** path = _CFGetProcessPath();
	const char* oldPath = *path;
	for (uint32_t i = 0; i < _dyld_image_count(); i++) {
		const char* name = _dyld_get_image_name(i);
		if (!strcmp(name, oldPath)) {
			dyldImageName = name;
			break;
		}
	}

	// Overwrite @executable_path
	const char* appExecPath = appBundle.executablePath.UTF8String;
	*path = appExecPath;

	if (!usingLiveContainer) {
		AppLog(@"[invokeAppMain] Overwriting exec path...");
		// the dumbest solution that caused me a headache, simply dont call the function!
		// i accidentally figured that out
		overwriteExecPath(appBundle.bundlePath);
	} else {
		AppLog(@"[invokeAppMain] Skip overwriteExecPath (LC)");
	}
	// Overwrite NSUserDefaults
	if ([guestAppInfo[@"doUseLCBundleId"] boolValue]) {
		NSUserDefaults.standardUserDefaults = [[NSUserDefaults alloc] initWithSuiteName:guestAppInfo[@"LCOrignalBundleIdentifier"]];
	} else {
		NSUserDefaults.standardUserDefaults = [[NSUserDefaults alloc] initWithSuiteName:appBundle.bundleIdentifier];
	}

	// Overwrite home and tmp path
	NSString* newHomePath = nil;
	if (isSharedBundle) {
		newHomePath = [NSString stringWithFormat:@"%@/Data/Application/%@", appGroupFolder.path, dataUUID];
		// move data folder to private library
		NSURL* libraryPathUrl = [fm URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask].lastObject;
		NSString* sharedAppDataFolderPath = [libraryPathUrl.path stringByAppendingPathComponent:@"SharedDocuments"];
		NSString* dataFolderPath = [appGroupFolder.path stringByAppendingPathComponent:[NSString stringWithFormat:@"Data/Application/%@", dataUUID]];
		newHomePath = [sharedAppDataFolderPath stringByAppendingPathComponent:dataUUID];
		[fm moveItemAtPath:dataFolderPath toPath:newHomePath error:&error];
	} else {
		newHomePath = [NSString stringWithFormat:@"%@/Data/Application/%@", docPath, dataUUID];
	}

	NSString* newTmpPath = [newHomePath stringByAppendingPathComponent:@"tmp"];
	remove(newTmpPath.UTF8String);
	symlink(getenv("TMPDIR"), newTmpPath.UTF8String);

	if ([guestAppInfo[@"doSymlinkInbox"] boolValue]) {
		NSString* inboxSymlinkPath = [NSString stringWithFormat:@"%s/%@-Inbox", getenv("TMPDIR"), [appBundle bundleIdentifier]];
		NSString* inboxPath = [newHomePath stringByAppendingPathComponent:@"Inbox"];

		if (![fm fileExistsAtPath:inboxPath]) {
			[fm createDirectoryAtPath:inboxPath withIntermediateDirectories:YES attributes:nil error:&error];
		}
		if ([fm fileExistsAtPath:inboxSymlinkPath]) {
			NSString* fileType = [fm attributesOfItemAtPath:inboxSymlinkPath error:&error][NSFileType];
			if (fileType == NSFileTypeDirectory) {
				NSArray* contents = [fm contentsOfDirectoryAtPath:inboxSymlinkPath error:&error];
				for (NSString* content in contents) {
					[fm moveItemAtPath:[inboxSymlinkPath stringByAppendingPathComponent:content] toPath:[inboxPath stringByAppendingPathComponent:content] error:&error];
				}
				[fm removeItemAtPath:inboxSymlinkPath error:&error];
			}
		}

		symlink(inboxPath.UTF8String, inboxSymlinkPath.UTF8String);
	} else {
		NSString* inboxSymlinkPath = [NSString stringWithFormat:@"%s/%@-Inbox", getenv("TMPDIR"), [appBundle bundleIdentifier]];
		NSDictionary* targetAttribute = [fm attributesOfItemAtPath:inboxSymlinkPath error:&error];
		if (targetAttribute) {
			if (targetAttribute[NSFileType] == NSFileTypeSymbolicLink) {
				[fm removeItemAtPath:inboxSymlinkPath error:&error];
			}
		}
	}

	BOOL fixBlackscreen2 = [gcUserDefaults boolForKey:@"FIX_BLACKSCREEN"];
	if (fixBlackscreen2) {
		dlopen("/System/Library/Frameworks/UIKit.framework/UIKit", RTLD_GLOBAL);
		NSLog(@"[LC] Fix BlackScreen2 %@", [NSClassFromString(@"UIScreen") mainScreen]);
	}

	setenv("CFFIXED_USER_HOME", newHomePath.UTF8String, 1);
	setenv("HOME", newHomePath.UTF8String, 1);
	setenv("TMPDIR", newTmpPath.UTF8String, 1);
	NSString* launchArgs = [gcUserDefaults stringForKey:@"LAUNCH_ARGS"];
	if (launchArgs && [launchArgs length] > 1) {
		setenv("LAUNCHARGS", launchArgs.UTF8String, 1);
	}
	// safe mode
	if ([gcUserDefaults boolForKey:@"JITLESS"] || [gcUserDefaults boolForKey:@"FORCE_PATCHING"]) {
		if (safeMode) {
			setenv("LAUNCHARGS", "--geode:use-common-handler-offset=88d000 --geode:safe-mode", 1);
		} else {
			setenv("LAUNCHARGS", "--geode:use-common-handler-offset=88d000", 1);
		}
	} else {
		if (safeMode) {
			setenv("LAUNCHARGS", "--geode:safe-mode", 1);
		}
	}

	// Setup directories
	NSArray* dirList = @[ @"Library/Caches", @"Documents", @"SystemData" ];
	for (NSString* dir in dirList) {
		NSLog(@"creating %@", dir);
		NSString* dirPath = [newHomePath stringByAppendingPathComponent:dir];
		NSDictionary* attributes = @{ NSFileProtectionKey : NSFileTypeDirectory };
		[fm createDirectoryAtPath:dirPath withIntermediateDirectories:YES attributes:attributes error:nil];
	}

	[gcUserDefaults setObject:dataUUID forKey:@"lastLaunchDataUUID"];
	if (!usingLiveContainer) {
		if (isSharedBundle) {
			[gcUserDefaults setObject:@"Shared" forKey:@"lastLaunchType"];
		} else {
			[gcUserDefaults setObject:@"Private" forKey:@"lastLaunchType"];
		}
	}

	AppLog(@"[invokeAppMain] Overwriting NSBundle...");
	// Overwrite NSBundle
	overwriteMainNSBundle(appBundle);
	AppLog(@"[invokeAppMain] Overwriting CFBundle...");
	// Overwrite CFBundle
	overwriteMainCFBundle();

	// Overwrite executable info
	NSMutableArray<NSString*>* objcArgv = NSProcessInfo.processInfo.arguments.mutableCopy;
	objcArgv[0] = appBundle.executablePath;
	[NSProcessInfo.processInfo performSelector:@selector(setArguments:) withObject:objcArgv];
	NSProcessInfo.processInfo.processName = appBundle.infoDictionary[@"CFBundleExecutable"];
	*_CFGetProgname() = NSProcessInfo.processInfo.processName.UTF8String;

	AppLog(@"[invokeAppMain] Init guest hooks...");
	// hook NSUserDefault before running libraries' initializers
	NUDGuestHooksInit();

	// UIAGuestHooksInit();

	if ([gcUserDefaults boolForKey:@"LCCertificateImported"]) {
		// SecItemGuestHooksInit();
	}

	// Preload executable to bypass RT_NOLOAD
	uint32_t appIndex = _dyld_image_count();
	appMainImageIndex = appIndex;
	void* appHandle = dlopen(*path, RTLD_LAZY | RTLD_GLOBAL | RTLD_FIRST);
	appExecutableHandle = appHandle;
	const char* dlerr = dlerror();

	if (!appHandle || (uint64_t)appHandle > 0xf00000000000 || dlerr) {
		if (dlerr) {
			appError = @(dlerr);
		} else {
			appError = @"dlopen: an unknown error occurred";
		}
		AppLog(@"[GeodeBootstrap] Error: %@", appError);
		*path = oldPath;
		return appError;
	}

	// hook dlsym to solve RTLD_MAIN_ONLY
	rebind_symbols((struct rebinding[1]){ { "dlsym", (void*)new_dlsym, (void**)&orig_dlsym } }, 1);

	// Fix dynamic properties of some apps
	[NSUserDefaults performSelector:@selector(initialize)];

	if (![appBundle loadAndReturnError:&error]) {
		appError = error.localizedDescription;
		AppLog(@"[GeodeBootstrap] loading bundle failed: %@", error);
		*path = oldPath;
		return appError;
	}
	AppLog(@"[GeodeBootstrap] loaded bundle");

	// Find main()
	appMain = getAppEntryPoint(appHandle, appIndex);
	if (!appMain) {
		appError = @"Could not find the main entry point";
		AppLog(@"[GeodeBootstrap] Error: %@", appError);
		*path = oldPath;
		return appError;
	}

	// Go!
	AppLog(@"[GeodeBootstrap] jumping to main %p", appMain);
	argv[0] = (char*)appExecPath;
	int ret = appMain(argc, argv);

	return [NSString stringWithFormat:@"App returned from its main function with code %d.", ret];
}

static void exceptionHandler(NSException* exception) {
	NSString* error = [NSString stringWithFormat:@"%@\nCall stack: %@", exception.reason, exception.callStackSymbols];
	[gcUserDefaults setObject:error forKey:@"error"];
}

int GeodeMain(int argc, char* argv[]) {
	// This strangely fixes some apps getting stuck on black screen
	NSLog(@"ignore: %@", dispatch_get_main_queue());
	gcMainBundle = [NSBundle mainBundle];
	gcUserDefaults = [Utils getPrefs];
	gcSharedDefaults = [[NSUserDefaults alloc] initWithSuiteName:[GCSharedUtils appGroupID]];
	gcAppUrlScheme = NSBundle.mainBundle.infoDictionary[@"CFBundleURLTypes"][0][@"CFBundleURLSchemes"][0];

	// see if we are in livecontainer...
	if (NSClassFromString(@"LCSharedUtils")) {
		// why do you like nesting
		AppLog(@"LiveContainer Detected!");
		usingLiveContainer = YES;
	} else {
		gcAppGroupPath = [[NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:[NSClassFromString(@"GCSharedUtils") appGroupID]] path];
	}
	// AppLog(@"Current Launch Count is %@, %@ launches until app logs clear...", launchCount, (5 - (launchCount % 5)));

	NSString* lastLaunchDataUUID = [gcUserDefaults objectForKey:@"lastLaunchDataUUID"];
	if (lastLaunchDataUUID) {
		NSString* lastLaunchType = [gcUserDefaults objectForKey:@"lastLaunchType"];
		NSString* preferencesTo;
		NSURL* libraryPathUrl = [NSFileManager.defaultManager URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask].lastObject;
		NSURL* docPathUrl = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].lastObject;
		if ([lastLaunchType isEqualToString:@"Shared"]) {
			preferencesTo = [libraryPathUrl.path stringByAppendingPathComponent:[NSString stringWithFormat:@"SharedDocuments/%@/Library/Preferences", lastLaunchDataUUID]];
		} else {
			preferencesTo = [docPathUrl.path stringByAppendingPathComponent:[NSString stringWithFormat:@"Data/Application/%@/Library/Preferences", lastLaunchDataUUID]];
		}
		// recover preferences
		[GCSharedUtils dumpPreferenceToPath:preferencesTo dataUUID:lastLaunchDataUUID];
		[gcUserDefaults removeObjectForKey:@"lastLaunchDataUUID"];
		[gcUserDefaults removeObjectForKey:@"lastLaunchType"];
	}
	// ok but WHY DOES IT CRASH!? LIKE STOP, ALL IM DOING IS MOVING THE DIRECTORY, I DONT CARE THAT TYOUSTSUPID NIL SEGFAULT ITS NOT NIL SHUT UP
	if (!usingLiveContainer) {
		[GCSharedUtils moveSharedAppFolderBack];
	}

	NSString* selectedApp = [gcUserDefaults stringForKey:@"selected"];
	NSFileManager* fm = [NSFileManager defaultManager];
	NSString* docPath = [fm URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].lastObject.path;
	if ([fm fileExistsAtPath:[docPath stringByAppendingPathComponent:@"jitflag"]]) {
		selectedApp = [Utils gdBundleName];
		[fm removeItemAtPath:[docPath stringByAppendingPathComponent:@"jitflag"] error:nil];
	}
	BOOL safeMode = [gcUserDefaults boolForKey:@"safemode"];

	// is this even needed
	if (!usingLiveContainer) {
		NSString* selectedContainer = [gcUserDefaults stringForKey:@"selectedContainer"];
		if (selectedApp && !selectedContainer) {
			selectedContainer = [GCSharedUtils findDefaultContainerWithBundleId:selectedApp];
		}
		NSString* runningLC = [GCSharedUtils getContainerUsingLCSchemeWithFolderName:selectedContainer];
		if (selectedApp && runningLC) {
			[gcUserDefaults removeObjectForKey:@"selected"];
			[gcUserDefaults removeObjectForKey:@"selectedContainer"];
			[gcUserDefaults removeObjectForKey:@"safemode"];
			NSString* selectedAppBackUp = selectedApp;
			selectedApp = nil;
			dispatch_time_t delay = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC));
			dispatch_after(delay, dispatch_get_main_queue(), ^{
				// Base64 encode the data
				NSString* urlStr;
				if (selectedContainer) {
					urlStr = [NSString stringWithFormat:@"%@://geode-launch?bundle-name=%@&container-folder-name=%@", runningLC, selectedAppBackUp, selectedContainer];
				} else {
					urlStr = [NSString stringWithFormat:@"%@://geode-launch?bundle-name=%@", runningLC, selectedAppBackUp];
				}

				NSURL* url = [NSURL URLWithString:urlStr];
				if ([[NSClassFromString(@"UIApplication") sharedApplication] canOpenURL:url]) {
					[[NSClassFromString(@"UIApplication") sharedApplication] openURL:url options:@{} completionHandler:nil];

					NSString* launchUrl = [gcUserDefaults stringForKey:@"launchAppUrlScheme"];
					// also pass url scheme to another lc
					if (launchUrl) {
						[gcUserDefaults removeObjectForKey:@"launchAppUrlScheme"];

						// Base64 encode the data
						NSData* data = [launchUrl dataUsingEncoding:NSUTF8StringEncoding];
						NSString* encodedUrl = [data base64EncodedStringWithOptions:0];

						NSString* finalUrl = [NSString stringWithFormat:@"%@://open-url?url=%@", runningLC, encodedUrl];
						NSURL* url = [NSURL URLWithString:finalUrl];

						[[NSClassFromString(@"UIApplication") sharedApplication] openURL:url options:@{} completionHandler:nil];
					}
				}
			});
		}
	}
	if (selectedApp && [Utils isSandboxed]) {
		NSString* launchUrl = [gcUserDefaults stringForKey:@"launchAppUrlScheme"];
		[gcUserDefaults removeObjectForKey:@"selected"];
		[gcUserDefaults removeObjectForKey:@"safemode"];
		// wait for app to launch so that it can receive the url
		if (launchUrl) {
			[gcUserDefaults removeObjectForKey:@"launchAppUrlScheme"];
			dispatch_time_t delay = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC));
			dispatch_after(delay, dispatch_get_main_queue(), ^{
				// Base64 encode the data
				NSData* data = [launchUrl dataUsingEncoding:NSUTF8StringEncoding];
				NSString* encodedUrl = [data base64EncodedStringWithOptions:0];

				NSString* finalUrl = [NSString stringWithFormat:@"%@://open-url?url=%@", gcAppUrlScheme, encodedUrl];
				NSURL* url = [NSURL URLWithString:finalUrl];

				[[NSClassFromString(@"UIApplication") sharedApplication] openURL:url options:@{} completionHandler:nil];
			});
		}
		NSSetUncaughtExceptionHandler(&exceptionHandler);
		setenv("GC_HOME_PATH", getenv("HOME"), 1);
		NSString* appError = invokeAppMain(selectedApp, @"GeometryDash", safeMode, argc, argv);
		if (appError) {
			[gcUserDefaults setObject:appError forKey:@"error"];
			// potentially unrecovable state, exit now
			return 1;
		}
	}
	@autoreleasepool {
		dlopen("@executable_path/Frameworks/WebServer.dylib", RTLD_LAZY);
		void* uikitHandle = dlopen("/System/Library/Frameworks/UIKit.framework/UIKit", RTLD_GLOBAL);
		int (*UIApplicationMain)(int, char**, NSString*, NSString*) = dlsym(uikitHandle, "UIApplicationMain");
		return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
	}
}

int main(int argc, char* argv[]) {
	assert(appMain != NULL);
	return appMain(argc, argv);
}

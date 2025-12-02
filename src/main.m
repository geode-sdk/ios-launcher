#import "LCUtils/FoundationPrivate.h"
#include "src/Patcher.h"
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

// since theos sdk apparently doesnt have this
// thanks to https://github.com/theos/theos/issues/493
int __isOSVersionAtLeast(int major, int minor, int patch) {
	NSOperatingSystemVersion version;
	version.majorVersion = major;
	version.minorVersion = minor;
	version.patchVersion = patch;
	return [[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:version];
}

static int (*appMain)(int, char**);
NSUserDefaults* gcUserDefaults;
NSUserDefaults* gcSharedDefaults;
NSString* gcAppGroupPath;
NSString* gcAppUrlScheme;
NSBundle* gcMainBundle;
NSDictionary* guestAppInfo;

BOOL usingLiveContainer;

void NUDGuestHooksInit();
bool performHookDyldApi(const char* functionName, uint32_t adrpOffset, void** origFunction, void* hookFunction) {
	uint32_t* baseAddr = dlsym(RTLD_DEFAULT, functionName);
	assert(baseAddr != 0);
	/*
	 arm64e
	 1ad450b90  e10300aa   mov     x1, x0
	 1ad450b94  487b2090   adrp    x8, dyld4::gAPIs
	 1ad450b98  000140f9   ldr     x0, [x8]  {dyld4::gAPIs} may contain offset
	 1ad450b9c  100040f9   ldr     x16, [x0]
	 1ad450ba0  f10300aa   mov     x17, x0
	 1ad450ba4  517fecf2   movk    x17, #0x63fa, lsl #0x30
	 1ad450ba8  301ac1da   autda   x16, x17
	 1ad450bac  114780d2   mov     x17, #0x238
	 1ad450bb0  1002118b   add     x16, x16, x17
	 1ad450bb4  020240f9   ldr     x2, [x16]
	 1ad450bb8  e30310aa   mov     x3, x16
	 1ad450bbc  f00303aa   mov     x16, x3
	 1ad450bc0  7085f3f2   movk    x16, #0x9c2b, lsl #0x30
	 1ad450bc4  50081fd7   braa    x2, x16

	 arm64
	 00000001ac934c80         mov        x1, x0
	 00000001ac934c84         adrp       x8, #0x1f462d000
	 00000001ac934c88         ldr        x0, [x8, #0xf88]                            ; __ZN5dyld45gDyldE
	 00000001ac934c8c         ldr        x8, [x0]
	 00000001ac934c90         ldr        x2, [x8, #0x258]
	 00000001ac934c94         br         x2
	 */
	uint32_t* adrpInstPtr = baseAddr + adrpOffset;
	assert((*adrpInstPtr & 0x9f000000) == 0x90000000);
	uint32_t immlo = (*adrpInstPtr & 0x60000000) >> 29;
	uint32_t immhi = (*adrpInstPtr & 0xFFFFE0) >> 5;
	int64_t imm = (((int64_t)((immhi << 2) | immlo)) << 43) >> 31;

	void* gdyldPtr = (void*)(((uint64_t)baseAddr & 0xfffffffffffff000) + imm);

	uint32_t* ldrInstPtr1 = baseAddr + adrpOffset + 1;
	// check if the instruction is ldr Unsigned offset
	assert((*ldrInstPtr1 & 0xBFC00000) == 0xB9400000);
	uint32_t size = (*ldrInstPtr1 & 0xC0000000) >> 30;
	uint32_t imm12 = (*ldrInstPtr1 & 0x3FFC00) >> 10;
	gdyldPtr += (imm12 << size);

	assert(gdyldPtr != 0);
	assert(*(void**)gdyldPtr != 0);
	void* vtablePtr = **(void***)gdyldPtr;

	void* vtableFunctionPtr = 0;
	uint32_t* movInstPtr = baseAddr + adrpOffset + 6;

	if ((*movInstPtr & 0x7F800000) == 0x52800000) {
		// arm64e, mov imm + add + ldr
		uint32_t imm16 = (*movInstPtr & 0x1FFFE0) >> 5;
		vtableFunctionPtr = vtablePtr + imm16;
	} else if ((*movInstPtr & 0xFFE00C00) == 0xF8400C00) {
		// arm64e, ldr immediate Pre-index 64bit
		uint32_t imm9 = (*movInstPtr & 0x1FF000) >> 12;
		vtableFunctionPtr = vtablePtr + imm9;
	} else {
		// arm64
		uint32_t* ldrInstPtr2 = baseAddr + adrpOffset + 3;
		assert((*ldrInstPtr2 & 0xBFC00000) == 0xB9400000);
		uint32_t size2 = (*ldrInstPtr2 & 0xC0000000) >> 30;
		uint32_t imm12_2 = (*ldrInstPtr2 & 0x3FFC00) >> 10;
		vtableFunctionPtr = vtablePtr + (imm12_2 << size2);
	}

	kern_return_t ret = builtin_vm_protect(mach_task_self(), (mach_vm_address_t)vtableFunctionPtr, sizeof(uintptr_t), false, PROT_READ | PROT_WRITE | VM_PROT_COPY);
	assert(ret == KERN_SUCCESS);
	*origFunction = (void*)*(void**)vtableFunctionPtr;
	*(uint64_t*)vtableFunctionPtr = (uint64_t)hookFunction;
	builtin_vm_protect(mach_task_self(), (mach_vm_address_t)vtableFunctionPtr, sizeof(uintptr_t), false, PROT_READ);
	return true;
}

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
#if TARGET_OS_MACCATALYST || TARGET_OS_SIMULATOR
	return YES;
#else
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
#endif
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

int hook__NSGetExecutablePath_overwriteExecPath(char*** dyldApiInstancePtr, char* newPath, uint32_t* bufsize) {
	assert(dyldApiInstancePtr != 0);
	char** dyldConfig = dyldApiInstancePtr[1];
	assert(dyldConfig != 0);

	char** mainExecutablePathPtr = 0;
	// mainExecutablePath is at 0x10 for iOS 15~18.3.2, 0x20 for iOS 18.4+
	if (dyldConfig[2] != 0 && dyldConfig[2][0] == '/') {
		mainExecutablePathPtr = dyldConfig + 2;
	} else if (dyldConfig[4] != 0 && dyldConfig[4][0] == '/') {
		mainExecutablePathPtr = dyldConfig + 4;
	} else {
		assert(mainExecutablePathPtr != 0);
	}

	kern_return_t ret = builtin_vm_protect(mach_task_self(), (mach_vm_address_t)mainExecutablePathPtr, sizeof(mainExecutablePathPtr), false, PROT_READ | PROT_WRITE);
	if (ret != KERN_SUCCESS) {
		BOOL tpro_ret = os_thread_self_restrict_tpro_to_rw();
		assert(tpro_ret);
	}
	*mainExecutablePathPtr = newPath;
	if (ret != KERN_SUCCESS) {
		os_thread_self_restrict_tpro_to_ro();
	}

	return 0;
}

static void overwriteExecPath(const char* newExecPath) {
	// dyld4 stores executable path in a different place (iOS 15.0 +)
	// https://github.com/apple-oss-distributions/dyld/blob/ce1cc2088ef390df1c48a1648075bbd51c5bbc6a/dyld/DyldAPIs.cpp#L802
	int (*orig__NSGetExecutablePath)(void* dyldPtr, char* buf, uint32_t* bufsize);
	performHookDyldApi("_NSGetExecutablePath", 2, (void**)&orig__NSGetExecutablePath, hook__NSGetExecutablePath_overwriteExecPath);
	_NSGetExecutablePath((char*)newExecPath, NULL);
	// put the original function back
	performHookDyldApi("_NSGetExecutablePath", 2, (void**)&orig__NSGetExecutablePath, orig__NSGetExecutablePath);
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

// static void loadFramework(NSString* name) {
// 	const char* path = [NSString stringWithFormat:@"@executable_path/Frameworks/%@.framework/%@", name, name].UTF8String;
// 	void* handle = dlopen(path, RTLD_GLOBAL);
// 	const char* dlerr = dlerror();
// 	if (!handle || (uint64_t)handle > 0xf00000000000) {
// 		if (dlerr) {
// 			AppLog(@"Failed to load %@: %s", name, dlerr);
// 		} else {
// 			AppLog(@"Failed to load %@: An unknown error occured.", name);
// 		}
// 	}
// }

static NSString* invokeAppMain(NSString* selectedApp, NSString* selectedContainer, BOOL safeMode, int argc, char* argv[]) {
	NSString* appError = nil;
	if (![gcUserDefaults boolForKey:@"JITLESS"]) {
		// First of all, let's check if we have JIT
		for (int i = 0; i < 10 && !checkJITEnabled(); i++) {
			usleep(1000 * 100);
		}
		if (!checkJITEnabled()) {
			if (![Utils isDevCert]) {
				appError = @"JIT was not enabled. Please follow the installation guide for enabling Enterprise Mode, or sign this app with a Developer Certificate.";
			} else {
				appError =
					@"JIT was not enabled. Please ensure that you launched the Geode launcher with JIT. If you want to use Geode without JIT, setup JIT-Less mode in settings.";
			}
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

		BOOL isDir = NO;
		NSString *frameworksPath = [bundlePath stringByAppendingPathComponent:@"Frameworks"];
		if (![fm fileExistsAtPath:frameworksPath isDirectory:&isDir]) {
			[fm createDirectoryAtPath:frameworksPath withIntermediateDirectories:YES attributes:nil error:nil];
		}
		NSString* zSignPath = [frameworksPath stringByAppendingPathComponent:@"ZSign.dylib"];
		if (![fm fileExistsAtPath:zSignPath]) {
			AppLog(@"invokeAppMain - Creating ZSign.dylib symlink");
			remove(zSignPath.UTF8String);
			NSString* target = [NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:@"ZSign.dylib"];
			symlink(target.UTF8String, zSignPath.UTF8String);
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
		//show-platform-console
		if ([gcUserDefaults boolForKey:@"PLATFORM_CONSOLE"]) {
			NSString* platformPath = [tweakFolder stringByAppendingPathComponent:@"PlatformConsole.dylib"];
			if (![fm fileExistsAtPath:platformPath]) {
				AppLog(@"[invokeAppMain] Creating PlatformConsole.dylib symlink");
				remove(platformPath.UTF8String);
				NSString* target = [NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:@"PlatformConsole.dylib"];
				symlink(target.UTF8String, platformPath.UTF8String);
			}
		    setenv("SHOW_PLATFORM_CONSOLE", "1", 1);
		}

		NSString* caHighFPSPath = [tweakFolder stringByAppendingPathComponent:@"CAHighFPS.dylib"];
		if ([gcUserDefaults boolForKey:@"USE_MAX_FPS"]) {
			//loadFramework(@"ANGLEGLKit");
			//loadFramework(@"libEGL");
			//loadFramework(@"libGLESv2");
			if (![fm fileExistsAtPath:caHighFPSPath]) {
				AppLog(@"[invokeAppMain] Creating CAHighFPS.dylib symlink");
				remove(caHighFPSPath.UTF8String);
				NSString* target = [NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:@"CAHighFPS.dylib"];
				symlink(target.UTF8String, caHighFPSPath.UTF8String);
			}
			setenv("ANGLEGLKit", "1", 1);
		}
	} else {
		AppLog(@"[invokeAppMain] Couldn't find tweak folder!");
	}
	// If JIT is enabled, bypass library validation so we can load arbitrary binaries
	if (has_txm()) {
		setenv("TXM_JIT", "1", 1);
	}
	if (!usingLiveContainer || has_txm()) {
		if (checkJITEnabled() && ![gcUserDefaults boolForKey:@"FORCE_CERT_JIT"]) {
			init_bypassDyldLibValidation();
			AppLog(@"[invokeAppMain] JIT pass (2/2) & Bypassed Dyld-lib validation!");
		} else {
			AppLog(@"[invokeAppMain] JIT pass (2/2) [Bypassed because JIT-Less]");
		}
	} else {
		// lc already hooks it so it's unnecessary to do it again...
		AppLog(@"[invokeAppMain] Ignoring bypass dyld lib validation hook since LC should already do that.");
	}

	// Locate dyld image name address
	const char** path = _CFGetProcessPath();
	const char* oldPath = *path;

	// Overwrite @executable_path
	const char* appExecPath = appBundle.executablePath.fileSystemRepresentation;
	*path = appExecPath;

	if (!usingLiveContainer) {
		AppLog(@"[invokeAppMain] Overwriting exec path...");
		// the dumbest solution that caused me a headache, simply dont call the function!
		// i accidentally figured that out
		overwriteExecPath(appExecPath);
	} else {
		AppLog(@"[invokeAppMain] Skip overwriteExecPath (LC)");
	}
	// Overwrite NSUserDefaults
	NSUserDefaults.standardUserDefaults = [[NSUserDefaults alloc] initWithSuiteName:appBundle.bundleIdentifier];

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
			setenv("LAUNCHARGS", "--geode:use-common-handler-offset=8b8000 --geode:safe-mode", 1);
		} else {
			setenv("LAUNCHARGS", "--geode:use-common-handler-offset=8b8000", 1);
		}
	} else {
		if (safeMode) {
			setenv("LAUNCHARGS", "--geode:safe-mode", 1);
		}
	}
	setenv("GAME", "1", 1);

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

	if (!appBundle.executablePath) {
		return @"Couldn't find app executable path. Try force resign in settings or delete the .app file in the Applications directory.";
	}

	if ([gcUserDefaults boolForKey:@"FIX_BLACKSCREEN"]) {
		dlopen("/System/Library/Frameworks/UIKit.framework/UIKit", RTLD_GLOBAL);
		NSLog(@"[LC] Fix BlackScreen2 %@", [NSClassFromString(@"UIScreen") mainScreen]);
	}

	// Overwrite executable info
	NSMutableArray<NSString*>* objcArgv = NSProcessInfo.processInfo.arguments.mutableCopy;
	objcArgv[0] = appBundle.executablePath;
	[NSProcessInfo.processInfo performSelector:@selector(setArguments:) withObject:objcArgv];
	NSProcessInfo.processInfo.processName = appBundle.infoDictionary[@"CFBundleExecutable"];
	*_CFGetProgname() = NSProcessInfo.processInfo.processName.UTF8String;

	AppLog(@"[invokeAppMain] Init guest hooks...");
	// hook NSUserDefault before running libraries' initializers
	NUDGuestHooksInit();
	// SecItemGuestHooksInit();
	// NSFMGuestHooksInit();
	// initDead10ccFix();
	//  UIAGuestHooksInit();

	// Preload executable to bypass RT_NOLOAD
	uint32_t appIndex = _dyld_image_count();
	appMainImageIndex = appIndex;

	void* appHandle = dlopen(appExecPath, RTLD_LAZY | RTLD_GLOBAL | RTLD_FIRST);
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
		appError = @"Could not find the main entry point (Corrupted binary?)";
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
		if ([gcUserDefaults boolForKey:@"RestartFlag"]) {
			[gcUserDefaults removeObjectForKey:@"RestartFlag"];
			// a hacky workaround since we cant just copy & sign the binary while its running...
			if ([gcUserDefaults boolForKey:@"JITLESS"] && !usingLiveContainer) {
				__block BOOL successPatch = YES;
				dispatch_group_t group = dispatch_group_create();
				dispatch_group_enter(group);
				NSURL* bundlePath = [[LCPath bundlePath] URLByAppendingPathComponent:[Utils gdBundleName]];
				AppLog(@"Checking if GD needs to be patched & signed...");
				dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
					[Patcher patchGDBinary:[bundlePath URLByAppendingPathComponent:@"GeometryOriginal"] to:[bundlePath URLByAppendingPathComponent:@"GeometryJump"] withHandlerAddress:0x8b8000 force:NO withSafeMode:safeMode withEntitlements:NO completionHandler:^(BOOL success, NSString* error) {
						AppLog(@"Seeing conditions");
						if (success) {
							BOOL force = NO;
							if ([error isEqualToString:@"force"]) {
								AppLog(@"Patching was required! Now signing...");
								force = YES;
							} else {
								AppLog(@"No patching needed! Skipping...");
								dispatch_group_leave(group);
								return;
							}
							AppLog(@"Sign (1/3)");
							if ([LCUtils certificateData]) {
								[LCUtils validateCertificate:^(int status, NSDate* expirationDate, NSString* errorC) {
									if (errorC) {
										[gcUserDefaults setObject:[NSString stringWithFormat:@"launcher.error.sign.invalidcert".loc, errorC] forKey:@"error"];
										successPatch = NO;
										dispatch_group_leave(group);
										return;
									}
									if (status != 0) {
										[gcUserDefaults setObject:@"launcher.error.sign.invalidcert2".loc forKey:@"error"];
										successPatch = NO;
										dispatch_group_leave(group);
										return;
									}
									AppLog(@"Sign (2/3)");
									LCAppInfo* app = [[LCAppInfo alloc] initWithBundlePath:[[LCPath bundlePath] URLByAppendingPathComponent:@"com.robtop.geometryjump.app"].path];
									[app patchExecAndSignIfNeedWithCompletionHandler:^(BOOL signSuccess, NSString* signError) {
										AppLog(@"Sign (3/3)");
										if (signError) {
											[gcUserDefaults setObject:signError forKey:@"error"];
											successPatch = NO;
										}
										dispatch_group_leave(group);
									} progressHandler:^(NSProgress* signProgress) {} forceSign:force blockMainThread:NO];
								}];
							} else {
								[gcUserDefaults setObject:@"No certificate found. Please go to settings to import a certificate." forKey:@"error"];
								successPatch = NO;
								dispatch_group_leave(group);
							}
						  } else {
							[gcUserDefaults setObject:error forKey:@"error"];
							successPatch = NO;
							dispatch_group_leave(group);
						}
					}];
				});
				dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
				AppLog(@"Out of wait.");
				if (!successPatch) {
					//return @"Couldn't patch successfully.";
					return 1;
				}
				AppLog(@"Success patch! Now invoking main...");
			}
			// since zsign is being so weird
			if ([gcUserDefaults boolForKey:@"JITLESS"] && usingLiveContainer) {
				goto passafter;
			}
		}
		NSString* appError = invokeAppMain(selectedApp, @"GeometryDash", safeMode, argc, argv);
		if (appError) {
			[gcUserDefaults setObject:appError forKey:@"error"];
			// potentially unrecovable state, exit now
			return 1;
		}
	}
passafter:
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

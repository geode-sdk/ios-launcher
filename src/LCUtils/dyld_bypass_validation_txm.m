// Based on: https://blog.xpnsec.com/restoring-dyld-memory-loading
// https://github.com/xpn/DyldDeNeuralyzer/blob/main/DyldDeNeuralyzer/DyldPatch/dyldpatch.m

#import "src/components/LogUtils.h"
#import <Foundation/Foundation.h>

#include <dlfcn.h>
#include <fcntl.h>
#include <mach-o/dyld.h>
#include <mach-o/dyld_images.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <libkern/OSCacheControl.h>

#include "utils.h"

#include <dirent.h>

int cache_txm = 0;
int cache_txm2 = 0;

BOOL has_txm() {
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"FORCE_TXM"]) return YES;
	if (@available(iOS 26.0, *)) return YES;
	if (cache_txm > 0) return cache_txm == 2;
	if (@available(iOS 26.0, *)) {
		if (access("/System/Volumes/Preboot/boot/usr/standalone/firmware/FUD/Ap,TrustedExecutionMonitor.img4", F_OK) == 0) {
			cache_txm = 2;
			return YES;
		}
		DIR *d = opendir("/private/preboot");
		if(!d) {
			cache_txm = 1;
			return NO;
		}
		struct dirent *dir;
		char txmPath[PATH_MAX];
		while ((dir = readdir(d)) != NULL) {
			if(strlen(dir->d_name) == 96) {
				snprintf(txmPath, sizeof(txmPath), "/private/preboot/%s/usr/standalone/firmware/FUD/Ap,TrustedExecutionMonitor.img4", dir->d_name);
				break;
			}
		}
		closedir(d);
		BOOL ret = access(txmPath, F_OK) == 0;
		cache_txm = (ret) ? 2 : 1;
		return ret;
	}
	return NO;
}

// have someone test non-txm so i can determine whether to use this
BOOL has_txm_no_force() {
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"FORCE_TXM"]) return YES;
	if (cache_txm2 > 0) return cache_txm2 == 2;
	if (@available(iOS 26.0, *)) {
		if (access("/System/Volumes/Preboot/boot/usr/standalone/firmware/FUD/Ap,TrustedExecutionMonitor.img4", F_OK) == 0) {
			cache_txm2 = 2;
			return YES;
		}
		DIR *d = opendir("/private/preboot");
		if(!d) {
			cache_txm2 = 1;
			return NO;
		}
		struct dirent *dir;
		char txmPath[PATH_MAX];
		while ((dir = readdir(d)) != NULL) {
			if(strlen(dir->d_name) == 96) {
				snprintf(txmPath, sizeof(txmPath), "/private/preboot/%s/usr/standalone/firmware/FUD/Ap,TrustedExecutionMonitor.img4", dir->d_name);
				break;
			}
		}
		closedir(d);
		BOOL ret = access(txmPath, F_OK) == 0;
		cache_txm2 = (ret) ? 2 : 1;
		return ret;
	}
	return NO;
}


#define ASM(...) __asm__(#__VA_ARGS__)
static char patch[] = { 0x88, 0x00, 0x00, 0x58, 0x00, 0x01, 0x1f, 0xd6, 0x1f, 0x20, 0x03, 0xd5, 0x1f, 0x20, 0x03, 0xd5, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41 };

// Signatures to search for
static char mmapSig[] = { 0xB0, 0x18, 0x80, 0xD2, 0x01, 0x10, 0x00, 0xD4 };
static char fcntlSig[] = { 0x90, 0x0B, 0x80, 0xD2, 0x01, 0x10, 0x00, 0xD4 };

static int (*orig_fcntl)(int fildes, int cmd, void* param) = 0;

extern void* __mmap(void* addr, size_t len, int prot, int flags, int fd, off_t offset);
extern int __fcntl(int fildes, int cmd, void* param);

static void builtin_memcpy(char *target, char *source, size_t size) {
    for (int i = 0; i < size; i++) {
        target[i] = source[i];
    }
}

// x0 (addr), x1 (bytes)
__attribute__((noinline,optnone,naked))
void BreakMarkJITMapping(void* addr, size_t bytes) {
    asm("brk #0x69 \n"
        "ret");
}

// x0 (dest), x1 (src), x2 (bytes)
__attribute__((noinline,optnone,naked))
void BreakJITWrite(void* dest, void* src, size_t bytes) {
    asm("brk #0x70 \n"
        "ret");
}

static bool redirectFunction(char* name, void* patchAddr, void* target) {
	if (has_txm()) {
		BreakJITWrite(patchAddr, patch, sizeof(patch));
	}
	// mirror `addr` (rx, JIT applied) to `mirrored` (rw)
	vm_address_t mirrored = 0;
	vm_prot_t cur_prot, max_prot;
	kern_return_t ret = vm_remap(mach_task_self(), &mirrored, sizeof(patch), 0, VM_FLAGS_ANYWHERE, mach_task_self(), (vm_address_t)patchAddr, false, &cur_prot, &max_prot, VM_INHERIT_SHARE);
	if (ret != KERN_SUCCESS) {
		AppLog(@"[TXM] vm_remap() fails at line %d", __LINE__);
		return FALSE;
	}

	mirrored += (vm_address_t)patchAddr & PAGE_MASK;
	vm_protect(mach_task_self(), mirrored, sizeof(patch), NO,
			   VM_PROT_READ | VM_PROT_WRITE);
	builtin_memcpy((char *)mirrored, patch, sizeof(patch));
	*(void **)((char*)mirrored + 16) = target;
	sys_icache_invalidate((void*)patchAddr, sizeof(patch));
	AppLog(@"[TXM] hook %s succeed!", name);

	vm_deallocate(mach_task_self(), mirrored, sizeof(patch));
	return TRUE;
}


static bool searchAndPatch(char* name, char* base, char* signature, int length, void* target) {
	char* patchAddr = NULL;

	AppLog(@"[TXM] searching for %s...", name, patchAddr);
	for (int i = 0; i < 0x80000; i++) {
		if (base[i] == signature[0] && memcmp(base + i, signature, length) == 0) {
			patchAddr = base + i;
			break;
		}
	}

	if (patchAddr == NULL) {
		AppLog(@"[TXM] hook %s fails line %d", name, __LINE__);
		return FALSE;
	}

	AppLog(@"[TXM] found %s at %p", name, patchAddr);
	return redirectFunction(name, patchAddr, target);
}

static struct dyld_all_image_infos* _alt_dyld_get_all_image_infos() {
	static struct dyld_all_image_infos* result;
	if (result) {
		return result;
	}
	struct task_dyld_info dyld_info;
	mach_vm_address_t image_infos;
	mach_msg_type_number_t count = TASK_DYLD_INFO_COUNT;
	kern_return_t ret;
	ret = task_info(mach_task_self_, TASK_DYLD_INFO, (task_info_t)&dyld_info, &count);
	if (ret != KERN_SUCCESS) {
		return NULL;
	}
	image_infos = dyld_info.all_image_info_addr;
	result = (struct dyld_all_image_infos*)image_infos;
	return result;
}

static void* getDyldBase(void) { return (void*)_alt_dyld_get_all_image_infos()->dyldImageLoadAddress; }

static void* hooked_mmap(void* addr, size_t len, int prot, int flags, int fd, off_t offset) {
	void* map = __mmap(addr, len, prot, flags, fd, offset);
	if (map == MAP_FAILED && fd && (prot & PROT_EXEC)) {
		map = __mmap(addr, len, prot, flags | MAP_PRIVATE | MAP_ANON, 0, 0);
		if (has_txm()) {
			BreakMarkJITMapping(map, len);
		}
		void* memoryLoadedFile = __mmap(NULL, len, PROT_READ, MAP_PRIVATE, fd, offset);
		// mirror `addr` (rx, JIT applied) to `mirrored` (rw)
		vm_address_t mirrored = 0;
		vm_prot_t cur_prot, max_prot;
		kern_return_t ret = vm_remap(mach_task_self(), &mirrored, len, 0, VM_FLAGS_ANYWHERE, mach_task_self(), (vm_address_t)map, false, &cur_prot, &max_prot, VM_INHERIT_SHARE);
		if(ret == KERN_SUCCESS) {
			vm_protect(mach_task_self(), mirrored, len, NO,
					   VM_PROT_READ | VM_PROT_WRITE);
			memcpy((void*)mirrored, memoryLoadedFile, len);
			vm_deallocate(mach_task_self(), mirrored, len);
		}
		munmap(memoryLoadedFile, len);
	}
	return map;
}

static int hooked___fcntl(int fildes, int cmd, void* param) {
	if (cmd == F_ADDFILESIGS_RETURN) {
		if (access("/Users", F_OK) != 0) {
			// attempt to attach code signature on iOS only as the binaries may have been signed
			// on macOS, attaching on unsigned binaries without CS_DEBUGGED will crash
			orig_fcntl(fildes, cmd, param);
		}
		fsignatures_t* fsig = (fsignatures_t*)param;
		// called to check that cert covers file.. so we'll make it cover everything ;)
		fsig->fs_file_start = 0xFFFFFFFF;
		return 0;
	}
	// Signature sanity check by dyld
	else if (cmd == F_CHECK_LV) {
		orig_fcntl(fildes, cmd, param);
		// Just say everything is fine
		return 0;
	}
	return orig_fcntl(fildes, cmd, param);
}

void init_bypassDyldLibValidation() {
	static BOOL bypassed;
	if (bypassed)
		return;
	bypassed = YES;

	if (!has_txm_no_force()) { //_no_force()
		init_bypassDyldLibValidationNonTXM();
		return;
	}
	signal(SIGBUS, SIG_IGN);
	AppLog(@"init (TXM)");

	// ty https://github.com/LiveContainer/LiveContainer/tree/jitless
	// https://github.com/AngelAuraMC/Amethyst-iOS/commit/3690cb368d1e4a347f1b6f7700f95c1ef52cb1c7
	orig_fcntl = __fcntl;
	char* dyldBase = getDyldBase();
	searchAndPatch("dyld_mmap", dyldBase, mmapSig, sizeof(mmapSig), hooked_mmap);
	searchAndPatch("dyld_fcntl", dyldBase, fcntlSig, sizeof(fcntlSig), hooked___fcntl);
}

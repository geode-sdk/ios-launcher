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

#include "utils.h"

#define ASM(...) __asm__(#__VA_ARGS__)
// ldr x8, value; br x8; value: .ascii "\x41\x42\x43\x44\x45\x46\x47\x48"
static char patch[] = { 0x88, 0x00, 0x00, 0x58, 0x00, 0x01, 0x1f, 0xd6, 0x1f, 0x20, 0x03, 0xd5, 0x1f, 0x20, 0x03, 0xd5, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41 };

// Signatures to search for
static char mmapSig[] = { 0xB0, 0x18, 0x80, 0xD2, 0x01, 0x10, 0x00, 0xD4 };
static char fcntlSig[] = { 0x90, 0x0B, 0x80, 0xD2, 0x01, 0x10, 0x00, 0xD4 };
static char syscallSig[] = { 0x01, 0x10, 0x00, 0xD4 };

static int (*dopamineFcntlHookAddr)(int fildes, int cmd, void* param) = 0;

extern void* __mmap(void* addr, size_t len, int prot, int flags, int fd, off_t offset);
extern int __fcntl(int fildes, int cmd, void* param);

// Since we're patching libsystem_kernel, we must avoid calling to its functions
static void builtin_memcpy(char* target, char* source, size_t size) {
	for (int i = 0; i < size; i++) {
		target[i] = source[i];
	}
}

// Originated from _kernelrpc_mach_vm_protect_trap
ASM(.global _builtin_vm_protect \n _builtin_vm_protect :     \n mov x16, # - 0xe       \n svc #0x80            \n ret);

static bool redirectFunction(char* name, void* patchAddr, void* target) {
	kern_return_t kret = builtin_vm_protect(mach_task_self(), (vm_address_t)patchAddr, sizeof(patch), false, PROT_READ | PROT_WRITE | VM_PROT_COPY);
	if (kret != KERN_SUCCESS) {
		AppLog(@"vm_protect(RW) fails at line %d", __LINE__);
		return FALSE;
	}

	builtin_memcpy((char*)patchAddr, patch, sizeof(patch));
	*(void**)((char*)patchAddr + 16) = target;

	kret = builtin_vm_protect(mach_task_self(), (vm_address_t)patchAddr, sizeof(patch), false, PROT_READ | PROT_EXEC);
	if (kret != KERN_SUCCESS) {
		AppLog(@"vm_protect(RX) fails at line %d", __LINE__);
		return FALSE;
	}

	AppLog(@"hook %s succeed!", name);
	return TRUE;
}

static bool searchAndPatch(char* name, char* base, char* signature, int length, void* target) {
	char* patchAddr = NULL;

	AppLog(@"searching for %s...", name, patchAddr);
	// TODO: maybe add a condition for if the user really has dopamine, considering that I may need to look further into the address space
	// but it crashes if I have it too big!? wacky
	// for(int i=0; i < 0x100000; i++) {
	for (int i = 0; i < 0x80000; i++) { // i+=4
		if (base[i] == signature[0] && memcmp(base + i, signature, length) == 0) {
			patchAddr = base + i;
			break;
		}
	}

	if (patchAddr == NULL) {
		AppLog(@"hook %s fails line %d", name, __LINE__);
		return FALSE;
	}

	AppLog(@"found %s at %p", name, patchAddr);
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
		map = __mmap(addr, len, PROT_READ | PROT_WRITE, flags | MAP_PRIVATE | MAP_ANON, 0, 0);
		void* memoryLoadedFile = __mmap(NULL, len, PROT_READ, MAP_PRIVATE, fd, offset);
		memcpy(map, memoryLoadedFile, len);
		munmap(memoryLoadedFile, len);
		mprotect(map, len, prot);
	}
	return map;
}

static int hooked___fcntl(int fildes, int cmd, void* param) {
	if (cmd == F_ADDFILESIGS_RETURN) {
		char filePath[PATH_MAX];
		bzero(filePath, PATH_MAX);

		// Check if the file is our "in-memory" file
		if (__fcntl(fildes, F_GETPATH, filePath) != -1) {
			const char* homeDir = getenv("GC_HOME_PATH");
			if (!strncmp(filePath, homeDir, strlen(homeDir))) {
				fsignatures_t* fsig = (fsignatures_t*)param;
				// called to check that cert covers file.. so we'll make it cover everything ;)
				fsig->fs_file_start = 0xFFFFFFFF;
				return 0;
			}
		}
	}

	// Signature sanity check by dyld
	else if (cmd == F_CHECK_LV) {
		// Just say everything is fine
		return 0;
	}

	// If for another command or file, we pass through
	// return __fcntl(fildes, cmd, param);

	// dopamine already hooks fcntl?? so i guess we will call their func instead...
	if (dopamineFcntlHookAddr) {
		return dopamineFcntlHookAddr(fildes, cmd, param);
	} else {
		return __fcntl(fildes, cmd, param);
	}
}

void init_bypassDyldLibValidation() {
	static BOOL bypassed;
	if (bypassed)
		return;
	bypassed = YES;

	AppLog(@"init");

	// Modifying exec page during execution may cause SIGBUS, so ignore it now
	// Only comment this out if only one thread (main) is running
	// signal(SIGBUS, SIG_IGN);
	char* dyldBase = getDyldBase();
	// redirectFunction("mmap", mmap, hooked_mmap);
	// redirectFunction("fcntl", fcntl, hooked_fcntl);
	searchAndPatch("dyld_mmap", dyldBase, mmapSig, sizeof(mmapSig), hooked_mmap);
	bool ret = searchAndPatch("dyld_fcntl", dyldBase, fcntlSig, sizeof(fcntlSig), hooked___fcntl);

	// fix for dopamine giving that "oh this code isnt signed!", or specifically "not valid for use in process" issue
	if (!ret) {
		// this should ONLY RUN if the hook failed
		char* fcntlAddr = 0;
		for (int i = 0; i < 0x80000; i += 4) {
			if (dyldBase[i] == syscallSig[0] && memcmp(dyldBase + i, syscallSig, 4) == 0) {
				char* syscallAddr = dyldBase + i;
				uint32_t* prev = (uint32_t*)(syscallAddr - 4);
				if (*prev >> 26 == 0x5) {
					fcntlAddr = (char*)prev;
					break;
				}
			}
		}
		if (fcntlAddr) {
			uint32_t* inst = (uint32_t*)fcntlAddr;
			int32_t offset = ((int32_t)((*inst) << 6)) >> 4;
			AppLog(@"Dopamine hook offset = %x", offset);
			dopamineFcntlHookAddr = (void*)((char*)fcntlAddr + offset);
			redirectFunction("dyld_fcntl (Dopamine)", fcntlAddr, hooked___fcntl);
		} else {
			AppLog(@"Dopamine hook not found");
		}
	}
}

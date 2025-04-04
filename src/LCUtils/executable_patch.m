#include <mach/mach.h>
#include <mach/vm_map.h>
#include <mach/vm_prot.h>
#include <mach/vm_region.h>
#include <sys/param.h>
#include <sys/types.h>
#include <unistd.h>
#include <limits.h>
#include <string.h>
#include <signal.h>
#include <mach-o/loader.h>
#include <mach-o/getsect.h>
#include <mach-o/dyld.h>  
#import <Foundation/Foundation.h>

#ifndef AppLog
#define AppLog(fmt, ...) NSLog((@"%s [Line %d] " fmt), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__)
#endif

__attribute__((weak_import))
extern kern_return_t vm_region(
    vm_map_t target_task,
    vm_address_t *address,
    vm_size_t *size,
    vm_region_flavor_t flavor,
    vm_region_info_t info,
    mach_msg_type_number_t *infoCnt,
    mach_port_t *object_name);

__attribute__((weak_import)) 
extern kern_return_t vm_protect(
    vm_map_t target_task,
    vm_address_t address,
    vm_size_t size,
    boolean_t set_maximum,
    vm_prot_t new_protection);

static kern_return_t change_memory_protection(void *address, size_t size, vm_prot_t protection) {
    vm_address_t page_address = (vm_address_t)address & ~(vm_page_size - 1);
    vm_size_t page_size = 0;
    mach_port_t unused;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t info_count = VM_REGION_BASIC_INFO_COUNT_64;
    
    kern_return_t kr = vm_region(mach_task_self(), &page_address, &page_size, 
                               VM_REGION_BASIC_INFO_64, 
                               (vm_region_info_t)&info, 
                               &info_count, &unused);
    if (kr != KERN_SUCCESS) {
        return kr;
    }
    
    return vm_protect(mach_task_self(), page_address, size, FALSE, protection);
}

static void overwriteExecPath_handler(int signo) {
    char path[PATH_MAX];
    uint32_t size = sizeof(path);
    _NSGetExecutablePath(path, &size);
    
    kern_return_t kr = change_memory_protection((void *)path, strlen(path), 
                                               PROT_READ | PROT_WRITE);
    if (kr != KERN_SUCCESS) {
        AppLog(@"Failed to change memory protection: %d", kr);
        return;
    }
    
    strlcpy(path, "/var/containers/Bundle/Application/Geode.app/Geode", sizeof(path));
    change_memory_protection((void *)path, strlen(path), PROT_READ);
}

void overwriteExecPath(void) {
    @try {
        struct sigaction sa;
        sa.sa_handler = overwriteExecPath_handler;
        sigemptyset(&sa.sa_mask);
        sa.sa_flags = SA_SIGINFO;
        
        if (sigaction(SIGBUS, &sa, NULL) != 0) {
            AppLog(@"Failed to setup SIGBUS handler");
            return;
        }
        overwriteExecPath_handler(0);
    } @catch (NSException *exception) {
        AppLog(@"Exception during path overwrite: %@", exception);
    }
}

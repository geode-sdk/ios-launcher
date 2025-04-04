#include <mach/mach.h>
#include <mach/vm_map.h>
#include <mach/vm_statistics.h>
#ifndef VM_MEMORY_REPLACEMENT
#define VM_MEMORY_REPLACEMENT 240
#endif

class JITMemoryManager {
public:
    static void* AllocateJITMemory(size_t size) {
        vm_address_t address = 0;
        kern_return_t ret = vm_allocate(mach_task_self(), 
                                      &address, 
                                      size, 
                                      VM_FLAGS_ANYWHERE | VM_MAKE_TAG(VM_MEMORY_REPLACEMENT));
        
        if (ret != KERN_SUCCESS) return nullptr;
        ret = vm_protect(mach_task_self(), address, size, FALSE, 
                        VM_PROT_READ | VM_PROT_WRITE | VM_PROT_EXECUTE);
        
        return (ret == KERN_SUCCESS) ? (void*)address : nullptr;
    }
    
    static void FreeJITMemory(void* ptr, size_t size) {
        vm_deallocate(mach_task_self(), (vm_address_t)ptr, size);
    }
};
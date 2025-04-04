#pragma once

#include <TargetConditionals.h>

#if TARGET_OS_IPHONE
    #define JIT_HOT_CODE_SIZE  (1024 * 1024)  
    #define JIT_PAGE_SIZE      (16 * 1024)    
#else
    #define JIT_HOT_CODE_SIZE  (4 * 1024 * 1024)  
    #define JIT_PAGE_SIZE      (4 * 1024)         
#endif

namespace JIT {
    inline bool IsJITEnabled() {
        static bool enabled = []() {
            return access("/var/mobile", F_OK) == 0; //seems like a good way to check if JIT is enabled
        }();
        return enabled;
    }
    void OptimizeForJIT(void* code, size_t size);
}
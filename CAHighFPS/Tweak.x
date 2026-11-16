
#import <objc/runtime.h>
#import <objc/message.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <dispatch/dispatch.h>
#include <stdio.h>

static void (*orig_CDFRS_range)(id, SEL, CAFrameRateRange);
static void (*orig_CDL_interval)(id, SEL, NSInteger);
static void (*orig_CDL_range)(id, SEL, CAFrameRateRange);
static void (*orig_CDL_fps)(id, SEL, NSInteger);
static id (*orig_CDL_create)(id, SEL, id, SEL);

static void hookPaused(id self, SEL cmd, BOOL value) {}
static BOOL hookIsPaused(id self, SEL cmd) { return NO; }

static void hookSourceRange(id self, SEL cmd, CAFrameRateRange range) {
    range.minimum = 120;
    range.preferred = 120;
    range.maximum = 120;

    if (orig_CDFRS_range)
        orig_CDFRS_range(self, cmd, range);
}

static void hookReasons(id self, SEL cmd, const unsigned *reasons,
                        unsigned long long count) {}

static void hookInterval(id self, SEL cmd, NSInteger interval) {
    if (orig_CDL_interval)
        orig_CDL_interval(self, cmd, 1);

    if ([self respondsToSelector:@selector(setPreferredFramesPerSecond:)]) {
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(
            self, @selector(setPreferredFramesPerSecond:), 120
        );
    }
}

static void hookRange(id self, SEL cmd, CAFrameRateRange range) {
    range.minimum = 120;
    range.preferred = 120;
    range.maximum = 120;

    if (orig_CDL_range)
        orig_CDL_range(self, cmd, range);
}

static void hookFPS(id self, SEL cmd, NSInteger fps) {
    if (orig_CDL_fps)
        orig_CDL_fps(self, cmd, 120);
}

static id hookCreate(id self, SEL cmd, id target, SEL selector) {
    id link = orig_CDL_create
        ? orig_CDL_create(self, cmd, target, selector)
        : nil;

    if (link && [link respondsToSelector:@selector(setPreferredFrameRateRange:)]) {
        CAFrameRateRange range = CAFrameRateRangeMake(120, 120, 120);

        ((void (*)(id, SEL, CAFrameRateRange))objc_msgSend)(
            link, @selector(setPreferredFrameRateRange:), range
        );
    }

    return link;
}

static BOOL installHook(Class cls, SEL selector,
                        IMP replacement, IMP *original) {
    if (!cls)
        return NO;

    Method method = class_getInstanceMethod(cls, selector);

    if (!method) {
        fprintf(stderr, "[CAHighFPS] Missing method: %s\n",
                sel_getName(selector));
        return NO;
    }

    IMP current = method_getImplementation(method);

    if (current == replacement)
        return YES;

    if (original && *original == NULL)
        *original = current;

    method_setImplementation(method, replacement);
    return YES;
}

static void applyHooks(void) {
    Class source = objc_getClass("CADynamicFrameRateSource");

    if (source) {
        installHook(source, @selector(setPaused:),
                    (IMP)hookPaused, NULL);
        installHook(source, @selector(isPaused),
                    (IMP)hookIsPaused, NULL);
        installHook(source, @selector(setPreferredFrameRateRange:),
                    (IMP)hookSourceRange, (IMP *)&orig_CDFRS_range);
        installHook(source, @selector(setHighFrameRateReasons:count:),
                    (IMP)hookReasons, NULL);
    }

    Class link = objc_getClass("CADisplayLink");

    if (link) {
        installHook(link, @selector(setPaused:),
                    (IMP)hookPaused, NULL);
        installHook(link, @selector(isPaused),
                    (IMP)hookIsPaused, NULL);
        installHook(link, @selector(setFrameInterval:),
                    (IMP)hookInterval, (IMP *)&orig_CDL_interval);
        installHook(link, @selector(setPreferredFrameRateRange:),
                    (IMP)hookRange, (IMP *)&orig_CDL_range);
        installHook(link, @selector(setPreferredFramesPerSecond:),
                    (IMP)hookFPS, (IMP *)&orig_CDL_fps);
        installHook(link, @selector(setHighFrameRateReasons:count:),
                    (IMP)hookReasons, NULL);

        installHook(object_getClass(link),
                    @selector(displayLinkWithTarget:selector:),
                    (IMP)hookCreate, (IMP *)&orig_CDL_create);
    }
}

__attribute__((constructor))
static void initializeCAHighFPS(void) {
    fprintf(stderr, "[CAHighFPS] loaded\n");

    applyHooks();

    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
        dispatch_get_main_queue(), ^{
            applyHooks();
        }
    );

    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC),
        dispatch_get_main_queue(), ^{
            applyHooks();
        }
    );
}

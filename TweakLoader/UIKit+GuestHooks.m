@import UIKit;
//#import <UIKit/UIKit.h>
#import "src/LCUtils/GCSharedUtils.h"
#import "src/LCUtils/UIKitPrivate.h"
#import "utils.h"
#import <LocalAuthentication/LocalAuthentication.h>

NSMutableArray<NSString*>* LCSupportedUrlSchemes = nil;
BOOL usingLiveContainer;

__attribute__((constructor))
static void UIKitGuestHooksInit() {
	if (NSClassFromString(@"LCSharedUtils")) {
		usingLiveContainer = YES;
	} else {
		usingLiveContainer = NO;
	}
    swizzle(UIApplication.class, @selector(_applicationOpenURLAction:payload:origin:), @selector(hook__applicationOpenURLAction:payload:origin:));
    swizzle(UIApplication.class, @selector(_connectUISceneFromFBSScene:transitionContext:), @selector(hook__connectUISceneFromFBSScene:transitionContext:));
    swizzle(UIApplication.class, @selector(openURL:options:completionHandler:), @selector(hook_openURL:options:completionHandler:));
    swizzle(UIApplication.class, @selector(canOpenURL:), @selector(hook_canOpenURL:));
    swizzle(UIScene.class, @selector(scene:didReceiveActions:fromTransitionContext:), @selector(hook_scene:didReceiveActions:fromTransitionContext:));
    swizzle(UIScene.class, @selector(openURL:options:completionHandler:), @selector(hook_openURL:options:completionHandler:));
    swizzle(UIViewController.class, @selector(__supportedInterfaceOrientations), @selector(hook___supportedInterfaceOrientations));
    if([UIDevice.currentDevice userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
        if ([NSUserDefaults.gcUserDefaults boolForKey:@"FIX_ROTATION"]) {
            swizzle(UIApplication.class, @selector(_handleDelegateCallbacksWithOptions:isSuspended:restoreState:), @selector(hook__handleDelegateCallbacksWithOptions:isSuspended:restoreState:));
            swizzle(FBSSceneParameters.class, @selector(initWithXPCDictionary:), @selector(hook_initWithXPCDictionary:));
            swizzle(UIViewController.class, @selector(shouldAutorotateToInterfaceOrientation:), @selector(hook_shouldAutorotateToInterfaceOrientation:));
            swizzle(UIWindow.class, @selector(setAutorotates:forceUpdateInterfaceOrientation:), @selector(hook_setAutorotates:forceUpdateInterfaceOrientation:));
        }
    }
}

NSString* findDefaultContainerWithBundleId(NSString* bundleId) {
    // find app's default container
    NSString *appGroupPath = [NSUserDefaults gcAppGroupPath];
    NSString* appGroupFolder = [appGroupPath stringByAppendingPathComponent:@"Geode"];
    
    NSString* bundleInfoPath = [NSString stringWithFormat:@"%@/Applications/%@/LCAppInfo.plist", appGroupFolder, bundleId];
    NSDictionary* infoDict = [NSDictionary dictionaryWithContentsOfFile:bundleInfoPath];
    if(!infoDict) {
        NSString* lcDocFolder = [[NSString stringWithUTF8String:getenv("GC_HOME_PATH")] stringByAppendingPathComponent:@"Documents"];
        
        bundleInfoPath = [NSString stringWithFormat:@"%@/Applications/%@/LCAppInfo.plist", lcDocFolder, bundleId];
        infoDict = [NSDictionary dictionaryWithContentsOfFile:bundleInfoPath];
    }
    
    return infoDict[@"LCDataUUID"];
}

void openUniversalLink(NSString* decodedUrl) {
    NSURL* urlToOpen = [NSURL URLWithString: decodedUrl];
    if(![urlToOpen.scheme isEqualToString:@"https"] && ![urlToOpen.scheme isEqualToString:@"http"]) {
        NSData *data = [decodedUrl dataUsingEncoding:NSUTF8StringEncoding];
        NSString *encodedUrl = [data base64EncodedStringWithOptions:0];
        
        NSString* finalUrl = [NSString stringWithFormat:@"%@://open-url?url=%@", NSUserDefaults.gcAppUrlScheme, encodedUrl];
        NSURL* url = [NSURL URLWithString: finalUrl];
        
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        return;
    }
    
    UIActivityContinuationManager* uacm = [[UIApplication sharedApplication] _getActivityContinuationManager];
    NSUserActivity* activity = [[NSUserActivity alloc] initWithActivityType:NSUserActivityTypeBrowsingWeb];
    activity.webpageURL = urlToOpen;
    NSDictionary* dict = @{
        @"UIApplicationLaunchOptionsUserActivityKey": activity,
        @"UICanvasConnectionOptionsUserActivityKey": activity,
        @"UIApplicationLaunchOptionsUserActivityIdentifierKey": NSUUID.UUID.UUIDString,
        @"UINSUserActivitySourceApplicationKey": @"com.apple.mobilesafari",
        @"UIApplicationLaunchOptionsUserActivityTypeKey": NSUserActivityTypeBrowsingWeb,
        @"_UISceneConnectionOptionsUserActivityTypeKey": NSUserActivityTypeBrowsingWeb,
        @"_UISceneConnectionOptionsUserActivityKey": activity,
        @"UICanvasConnectionOptionsUserActivityTypeKey": NSUserActivityTypeBrowsingWeb
    };
    
    [uacm handleActivityContinuation:dict isSuspended:nil];
}

void LCOpenWebPage(NSString* webPageUrlString, NSString* originalUrl) {
    if ([NSUserDefaults.gcUserDefaults boolForKey:@"LCOpenWebPageWithoutAsking"]) {
        openUniversalLink(webPageUrlString);
        return;
    }
    
    NSString *message = @"lc.guestTweak.openWebPageTip";
    UIWindow *window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Geode" message:message preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction* okAction = [UIAlertAction actionWithTitle:@"lc.common.ok" style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
        [NSClassFromString(@"GCSharedUtils") setWebPageUrlForNextLaunch:webPageUrlString];
        [NSClassFromString(@"GCSharedUtils") launchToGuestApp];
    }];
    [alert addAction:okAction];
    UIAlertAction* openNowAction = [UIAlertAction actionWithTitle:@"lc.guestTweak.openInCurrentApp" style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
        openUniversalLink(webPageUrlString);
        window.windowScene = nil;
    }];
    if([NSUserDefaults.gcAppUrlScheme isEqualToString:@"geode"] && [UIApplication.sharedApplication canOpenURL:[NSURL URLWithString: @"geode://"]]) {
        UIAlertAction* openlc2Action = [UIAlertAction actionWithTitle:@"lc.guestTweak.openInLc2" style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
            NSURLComponents* newUrlComp = [NSURLComponents componentsWithString:originalUrl];
            [newUrlComp setScheme:@"geode"];
            [UIApplication.sharedApplication openURL:[newUrlComp URL] options:@{} completionHandler:nil];
            window.windowScene = nil;
        }];
        [alert addAction:openlc2Action];
    }
    
    [alert addAction:openNowAction];
    UIAlertAction* cancelAction = [UIAlertAction actionWithTitle:@"lc.common.cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction * action) {
        window.windowScene = nil;
    }];
    [alert addAction:cancelAction];
    window.rootViewController = [UIViewController new];
    window.windowLevel = UIApplication.sharedApplication.windows.lastObject.windowLevel + 1;
    window.windowScene = (id)UIApplication.sharedApplication.connectedScenes.anyObject;
    [window makeKeyAndVisible];
    [window.rootViewController presentViewController:alert animated:YES completion:nil];
    objc_setAssociatedObject(alert, @"window", window, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

void handleLiveContainerLaunch(NSURL* url) {
    // If it's not current app, then switch
    // check if there are other LCs is running this app
    NSString* bundleName = nil;
    NSString* openUrl = nil;
    NSString* containerFolderName = nil;
    NSURLComponents* components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    for (NSURLQueryItem* queryItem in components.queryItems) {
        if ([queryItem.name isEqualToString:@"bundle-name"]) {
            bundleName = queryItem.value;
        } else if ([queryItem.name isEqualToString:@"open-url"]) {
            NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:queryItem.value options:0];
            openUrl = [[NSString alloc] initWithData:decodedData encoding:NSUTF8StringEncoding];
        } else if ([queryItem.name isEqualToString:@"container-folder-name"]) {
            containerFolderName = queryItem.value;
        }
    }
    NSString* containerId = [NSString stringWithUTF8String:getenv("HOME")].lastPathComponent;
    if(!containerFolderName) {
        containerFolderName = findDefaultContainerWithBundleId(bundleName);
    }
    if ([bundleName isEqualToString:NSBundle.mainBundle.bundlePath.lastPathComponent] && [containerId isEqualToString:containerFolderName]) {
        if(openUrl) {
            openUniversalLink(openUrl);
        }
    } else {
        NSString* runningLC = [NSClassFromString(@"GCSharedUtils") getContainerUsingLCSchemeWithFolderName:containerFolderName];
        if(runningLC) {
            NSString* urlStr = [NSString stringWithFormat:@"%@://geode-launch?bundle-name=%@&container-folder-name=%@", runningLC, bundleName, containerFolderName];
            [UIApplication.sharedApplication openURL:[NSURL URLWithString:urlStr] options:@{} completionHandler:nil];
            return;
        }
    }
}

BOOL canAppOpenItself(NSURL* url) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
        NSArray *urlTypes = [infoDictionary objectForKey:@"CFBundleURLTypes"];
        LCSupportedUrlSchemes = [[NSMutableArray alloc] init];
        for (NSDictionary *urlType in urlTypes) {
            NSArray *schemes = [urlType objectForKey:@"CFBundleURLSchemes"];
            for(NSString* scheme in schemes) {
                [LCSupportedUrlSchemes addObject:[scheme lowercaseString]];
            }
        }
    });
    if (LCSupportedUrlSchemes.count == 0) {
        LCSupportedUrlSchemes = [[NSMutableArray alloc] init];
        [LCSupportedUrlSchemes addObject:@"geode"];
    }
    return [LCSupportedUrlSchemes containsObject:[url.scheme lowercaseString]];
}

// Handler for AppDelegate
@implementation UIApplication(GeodeHook)
- (void)hook__applicationOpenURLAction:(id)action payload:(NSDictionary *)payload origin:(id)origin {
    NSString *url = payload[UIApplicationLaunchOptionsURLKey];
    if ([url hasPrefix:[NSString stringWithFormat: @"%@://geode-relaunch", NSUserDefaults.gcAppUrlScheme]]) {
        // Ignore
        return;
    } else if ([url hasPrefix:[NSString stringWithFormat: @"%@://open-web-page?", NSUserDefaults.gcAppUrlScheme]]) {
        // launch to UI and open web page
        NSURLComponents* lcUrl = [NSURLComponents componentsWithString:url];
        NSString* realUrlEncoded = lcUrl.queryItems[0].value;
        if(!realUrlEncoded) return;
        // Convert the base64 encoded url into String
        NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:realUrlEncoded options:0];
        NSString *decodedUrl = [[NSString alloc] initWithData:decodedData encoding:NSUTF8StringEncoding];
        LCOpenWebPage(decodedUrl, url);
        return;
    } else if ([url hasPrefix:[NSString stringWithFormat: @"%@://open-url", NSUserDefaults.gcAppUrlScheme]]) {
        // pass url to guest app
        NSURLComponents* lcUrl = [NSURLComponents componentsWithString:url];
        NSString* realUrlEncoded = lcUrl.queryItems[0].value;
        if(!realUrlEncoded) return;
        // Convert the base64 encoded url into String
        NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:realUrlEncoded options:0];
        NSString *decodedUrl = [[NSString alloc] initWithData:decodedData encoding:NSUTF8StringEncoding];
        // it's a Universal link, let's call -[UIActivityContinuationManager handleActivityContinuation:isSuspended:]
        if([decodedUrl hasPrefix:@"https"]) {
            openUniversalLink(decodedUrl);
        } else {
            NSMutableDictionary* newPayload = [payload mutableCopy];
            newPayload[UIApplicationLaunchOptionsURLKey] = decodedUrl;
            [self hook__applicationOpenURLAction:action payload:newPayload origin:origin];
        }
        
        return;
    } else if ([url hasPrefix:[NSString stringWithFormat: @"%@://geode-launch?bundle-name=", NSUserDefaults.gcAppUrlScheme]]) {
        handleLiveContainerLaunch([NSURL URLWithString:url]);
        // Not what we're looking for, pass it
        
    }
    [self hook__applicationOpenURLAction:action payload:payload origin:origin];
    return;
}

- (void)hook__connectUISceneFromFBSScene:(id)scene transitionContext:(UIApplicationSceneTransitionContext*)context {
#if !TARGET_OS_MACCATALYST
    context.payload = nil;
    context.actions = nil;
#endif
    [self hook__connectUISceneFromFBSScene:scene transitionContext:context];
}

-(BOOL)hook__handleDelegateCallbacksWithOptions:(id)arg1 isSuspended:(BOOL)arg2 restoreState:(BOOL)arg3 {
    BOOL ans = [self hook__handleDelegateCallbacksWithOptions:arg1 isSuspended:arg2 restoreState:arg3];
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [[LSApplicationWorkspace defaultWorkspace] openApplicationWithBundleID:@"com.apple.springboard"];
            if (usingLiveContainer) {
                if (NSClassFromString(@"LCSharedUtils")) {
                    NSString *bundleId = [NSClassFromString(@"GCSharedUtils") liveContainerBundleID];
                    NSLog(@"[GuestHook] Found %@ as the bundle ID!", bundleId);
                    if (bundleId) {
                        [[LSApplicationWorkspace defaultWorkspace] openApplicationWithBundleID:bundleId];
                    }
                }
            } else {
                [[LSApplicationWorkspace defaultWorkspace] openApplicationWithBundleID:NSUserDefaults.gcMainBundle.bundleIdentifier];
            }
        });
    });
    return ans;
}

- (void)hook_openURL:(NSURL *)url options:(NSDictionary<NSString *,id> *)options completionHandler:(void (^)(_Bool))completion {
    if ([url.host isEqualToString:@"relaunch"]) { // assume restart 
        //[NSClassFromString(@"GCSharedUtils") launchToGuestApp];
        if (!usingLiveContainer) {
            if (![NSUserDefaults.gcUserDefaults boolForKey:@"JITLESS"] && ![NSUserDefaults.gcUserDefaults boolForKey:@"FORCE_CERT_JIT"]) {
                UIWindow *window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
                window.rootViewController = [UIViewController new];
                window.windowLevel = UIApplication.sharedApplication.windows.lastObject.windowLevel + 1;
                window.windowScene = (id)UIApplication.sharedApplication.connectedScenes.anyObject;
                [window makeKeyAndVisible];

                [NSClassFromString(@"GCSharedUtils") relaunchApp];
                window.windowScene = nil;
            } else {
                [NSClassFromString(@"GCSharedUtils") relaunchApp];
            }
        } else {
            [NSClassFromString(@"GCSharedUtils") relaunchApp];
        }
        //[UIApplication.sharedApplication suspend];
        return;
    }
    if(canAppOpenItself(url)) {
        NSData *data = [url.absoluteString dataUsingEncoding:NSUTF8StringEncoding];
        NSString *encodedUrl = [data base64EncodedStringWithOptions:0];
        NSString* finalUrlStr = [NSString stringWithFormat:@"%@://open-url?url=%@", NSUserDefaults.gcAppUrlScheme, encodedUrl];
        NSURL* finalUrl = [NSURL URLWithString:finalUrlStr];
        [self hook_openURL:finalUrl options:options completionHandler:completion];
    } else {
        [self hook_openURL:url options:options completionHandler:completion];
    }
}
- (BOOL)hook_canOpenURL:(NSURL *) url {
    if(canAppOpenItself(url)) {
        return YES;
    } else {
        return [self hook_canOpenURL:url];
    }
}

@end

// Handler for SceneDelegate
@implementation UIScene(GeodeHook)
- (void)hook_scene:(id)scene didReceiveActions:(NSSet *)actions fromTransitionContext:(id)context {
    UIOpenURLAction *urlAction = nil;
    for (id obj in actions.allObjects) {
        if ([obj isKindOfClass:UIOpenURLAction.class]) {
            urlAction = obj;
            break;
        }
    }

    // Don't have UIOpenURLAction? pass it
    if (!urlAction) {
        [self hook_scene:scene didReceiveActions:actions fromTransitionContext:context];
        return;
    }

    NSString *url = urlAction.url.absoluteString;
    if ([url hasPrefix:[NSString stringWithFormat: @"%@://geode-relaunch", NSUserDefaults.gcAppUrlScheme]]) {
        // Ignore
    } else if ([url hasPrefix:[NSString stringWithFormat: @"%@://open-web-page?", NSUserDefaults.gcAppUrlScheme]]) {
        NSURLComponents* lcUrl = [NSURLComponents componentsWithString:url];
        NSString* realUrlEncoded = lcUrl.queryItems[0].value;
        if(!realUrlEncoded) return;
        // launch to UI and open web page
        NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:realUrlEncoded options:0];
        NSString *decodedUrl = [[NSString alloc] initWithData:decodedData encoding:NSUTF8StringEncoding];
        LCOpenWebPage(decodedUrl, url);
    } else if ([url hasPrefix:[NSString stringWithFormat: @"%@://open-url", NSUserDefaults.gcAppUrlScheme]]) {
        // Open guest app's URL scheme
        NSURLComponents* lcUrl = [NSURLComponents componentsWithString:url];
        NSString* realUrlEncoded = lcUrl.queryItems[0].value;
        if(!realUrlEncoded) return;
        // Convert the base64 encoded url into String
        NSData *decodedData = [[NSData alloc] initWithBase64EncodedString:realUrlEncoded options:0];
        NSString *decodedUrl = [[NSString alloc] initWithData:decodedData encoding:NSUTF8StringEncoding];
        
        // it's a Universal link, let's call -[UIActivityContinuationManager handleActivityContinuation:isSuspended:]
        if([decodedUrl hasPrefix:@"https"]) {
            openUniversalLink(decodedUrl);
        } else {
            NSMutableSet *newActions = actions.mutableCopy;
            [newActions removeObject:urlAction];
            UIOpenURLAction *newUrlAction = [[UIOpenURLAction alloc] initWithURL:[NSURL URLWithString:decodedUrl]];
            [newActions addObject:newUrlAction];
            [self hook_scene:scene didReceiveActions:newActions fromTransitionContext:context];
        }

    } else if ([url hasPrefix:[NSString stringWithFormat: @"%@://geode-launch?bundle-name=", NSUserDefaults.gcAppUrlScheme]]){
        handleLiveContainerLaunch(urlAction.url);
        
    }

    NSMutableSet *newActions = actions.mutableCopy;
    [newActions removeObject:urlAction];
    [self hook_scene:scene didReceiveActions:newActions fromTransitionContext:context];
}

- (void)hook_openURL:(NSURL *)url options:(UISceneOpenExternalURLOptions *)options completionHandler:(void (^)(BOOL success))completion {
    if(canAppOpenItself(url)) {
        NSData *data = [url.absoluteString dataUsingEncoding:NSUTF8StringEncoding];
        NSString *encodedUrl = [data base64EncodedStringWithOptions:0];
        NSString* finalUrlStr = [NSString stringWithFormat:@"%@://open-url?url=%@", NSUserDefaults.gcAppUrlScheme, encodedUrl];
        NSURL* finalUrl = [NSURL URLWithString:finalUrlStr];
        [self hook_openURL:finalUrl options:options completionHandler:completion];
    } else {
        [self hook_openURL:url options:options completionHandler:completion];
    }
}
@end

@implementation FBSSceneParameters(GeodeHook)
- (instancetype)hook_initWithXPCDictionary:(NSDictionary*)dict {
    FBSSceneParameters* ans = [self hook_initWithXPCDictionary:dict];
    UIMutableApplicationSceneSettings* settings = [ans.settings mutableCopy];
    UIMutableApplicationSceneClientSettings* clientSettings = [ans.clientSettings mutableCopy];
    if ([NSUserDefaults.gcUserDefaults boolForKey:@"FIX_ROTATION"]) {
        [settings setInterfaceOrientation:UIInterfaceOrientationLandscapeRight];
        [clientSettings setInterfaceOrientation:UIInterfaceOrientationLandscapeRight];
    }
    ans.settings = settings;
    ans.clientSettings = clientSettings;
    return ans;
}
@end

@implementation UIViewController(GeodeHook)
- (UIInterfaceOrientationMask)hook___supportedInterfaceOrientations {
    if ([NSUserDefaults.gcUserDefaults integerForKey:@"ASPECT_RATIO_X"] != 0) {
        [self constrainRootViewToAspectRatio];
    }
    if([UIDevice.currentDevice userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
        if ([NSUserDefaults.gcUserDefaults boolForKey:@"FIX_ROTATION"]) {
            return UIInterfaceOrientationMaskLandscape;
        }
    }
    return [self hook___supportedInterfaceOrientations];
}
- (BOOL)hook_shouldAutorotateToInterfaceOrientation:(NSInteger)orientation {
    return YES;
}
- (void)constrainRootViewToAspectRatio {
    //CGFloat targetAspectRatio = 16.0/9.0;
    NSInteger aspectX = [NSUserDefaults.gcUserDefaults integerForKey:@"ASPECT_RATIO_X"];
    NSInteger aspectY = [NSUserDefaults.gcUserDefaults integerForKey:@"ASPECT_RATIO_Y"];
    CGFloat targetAspectRatio = (CGFloat)aspectX/(CGFloat)aspectY;
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    CGFloat screenAspectRatio = screenBounds.size.width / screenBounds.size.height;
    if (fabs(screenAspectRatio - targetAspectRatio) < 0.1) return;
    
    CGRect constrainedFrame;
    
    UIWindow *window = [UIApplication sharedApplication].windows.firstObject;
    window.backgroundColor = [UIColor blackColor];
    // yeah i quickly realized this after taking too many screenshots
    for (UIView *subview in [window.subviews copy]) {
        // no memory leak!!
        if (subview.tag == 6969) {
            [subview removeFromSuperview];
        }
    }
    if (!window) return;
    if (screenAspectRatio > targetAspectRatio) {
        // too wide
        CGFloat newWidth = screenBounds.size.height * targetAspectRatio;
        CGFloat xOffset = (screenBounds.size.width - newWidth) / 2.0;
        constrainedFrame = CGRectMake(xOffset, 0, newWidth, screenBounds.size.height);

        UIView *leftBox = [[UIView alloc] initWithFrame:CGRectMake(0, 0, xOffset, screenBounds.size.height)];
        leftBox.backgroundColor = [UIColor blackColor];
        leftBox.tag = 6969;
        leftBox.userInteractionEnabled = NO;

        UIView *rightBox = [[UIView alloc] initWithFrame:CGRectMake(xOffset + newWidth, 0, xOffset, screenBounds.size.height)];
        rightBox.backgroundColor = [UIColor blackColor]; 
        rightBox.tag = 6969;
        rightBox.userInteractionEnabled = NO;

        [window addSubview:leftBox];
        [window addSubview:rightBox];
    } else {
        CGFloat newHeight = screenBounds.size.width / targetAspectRatio;
        CGFloat yOffset = (screenBounds.size.height - newHeight) / 2.0;
        constrainedFrame = CGRectMake(0, yOffset, screenBounds.size.width, newHeight);

        UIView *topBox = [[UIView alloc] initWithFrame:CGRectMake(0, 0, screenBounds.size.width, yOffset)];
        topBox.backgroundColor = [UIColor blackColor];
        topBox.tag = 6969;
        topBox.userInteractionEnabled = NO;

        UIView *bottomBox = [[UIView alloc] initWithFrame:CGRectMake(0, yOffset + newHeight, screenBounds.size.width, yOffset)];
        bottomBox.backgroundColor = [UIColor blackColor];
        bottomBox.tag = 6969;
        bottomBox.userInteractionEnabled = NO;

        [window addSubview:topBox];
        [window addSubview:bottomBox];
    }
    self.view.frame = constrainedFrame;
    self.view.clipsToBounds = YES;
    //self.view.superview.backgroundColor = [UIColor blackColor];
}

@end

@implementation UIWindow(hook)
- (void)hook_setAutorotates:(BOOL)autorotates forceUpdateInterfaceOrientation:(BOOL)force {
    [self hook_setAutorotates:YES forceUpdateInterfaceOrientation:YES];
}
@end

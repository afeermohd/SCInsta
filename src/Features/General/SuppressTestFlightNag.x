#import "../../Utils.h"
#import <objc/runtime.h>

// Instagram Beta (TestFlight) builds, e.g. 455.0.0, show "It's time to update Instagram Beta" on every
// launch via IGCoreRootTestFlightNagPlugin's TestFlightUpdateNudgeViewController. A sideloaded build can't
// update through TestFlight, so block the nudge:
//   1. Refuse to present it (directly or wrapped in a navigation controller).
//   2. Fallback: if it still appears by another route, remove it as soon as it's about to show.
// App Store builds don't contain this class, so these hooks do nothing there.

// Logos binds this local name to the Swift runtime class in %ctor.
@interface SCITestFlightNudgeViewController : UIViewController
@end

static Class SCITestFlightNudgeClass(void) {
    static Class cls;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cls = objc_getClass("_TtC29IGCoreRootTestFlightNagPlugin35TestFlightUpdateNudgeViewController");
    });
    return cls;
}

static BOOL SCIShouldHideTestFlightNag(void) {
    return [SCIUtils getBoolPref:@"hide_testflight_update_nag"];
}

static BOOL SCIIsTestFlightNudge(UIViewController *viewController) {
    Class nudgeClass = SCITestFlightNudgeClass();
    if (!nudgeClass || !viewController) return NO;

    // The nudge itself, or a container (navigation controller, sheet) already holding it.
    NSMutableArray<UIViewController *> *queue = [NSMutableArray arrayWithObject:viewController];
    NSUInteger visited = 0;
    while (queue.count && visited < 32) {
        UIViewController *current = queue.firstObject;
        [queue removeObjectAtIndex:0];
        visited++;

        if ([current isKindOfClass:nudgeClass]) return YES;
        [queue addObjectsFromArray:current.childViewControllers];
    }
    return NO;
}

%hook UIViewController
- (void)presentViewController:(UIViewController *)viewControllerToPresent animated:(BOOL)animated completion:(void (^)(void))completion {
    if (SCIShouldHideTestFlightNag() && SCIIsTestFlightNudge(viewControllerToPresent)) {
        NSLog(@"[SCInsta] Blocked TestFlight update nudge presentation");
        if (completion) completion();
        return;
    }
    %orig;
}
%end

%group SCITestFlightNudgeFallback
%hook SCITestFlightNudgeViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (!SCIShouldHideTestFlightNag()) return;

    UIViewController *nudge = (UIViewController *)self;
    NSLog(@"[SCInsta] Removing TestFlight update nudge");

    dispatch_async(dispatch_get_main_queue(), ^{
        // Close the outermost container holding the nudge (navigation controller, sheet, ...).
        UIViewController *root = nudge;
        while (root.parentViewController) root = root.parentViewController;

        if (root.presentingViewController) {
            [root dismissViewControllerAnimated:NO completion:nil];
            return;
        }

        UIWindow *window = nudge.viewIfLoaded.window;
        BOOL rootIsOnlyNudge = (root == nudge) ||
            ([root isKindOfClass:[UINavigationController class]] && ((UINavigationController *)root).viewControllers.count == 1);
        if (window && window.rootViewController == root && rootIsOnlyNudge) {
            // Shown in its own window: hide that window and hand key status back to the app.
            // Never hide a window whose root holds anything else (e.g. the main app UI).
            window.hidden = YES;
            for (UIWindow *other in [UIApplication sharedApplication].windows) {
                if (other != window && !other.hidden) {
                    [other makeKeyWindow];
                    break;
                }
            }
            return;
        }

        [nudge willMoveToParentViewController:nil];
        [nudge.viewIfLoaded removeFromSuperview];
        [nudge removeFromParentViewController];
    });
}
%end
%end

%ctor {
    %init;

    Class nudgeClass = SCITestFlightNudgeClass();
    if (nudgeClass) {
        %init(SCITestFlightNudgeFallback, SCITestFlightNudgeViewController = nudgeClass);
    }
}

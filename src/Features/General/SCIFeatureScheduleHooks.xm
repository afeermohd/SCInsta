#import "../../Utils.h"
#import "../../Settings/SCIFeatureSchedule.h"

static void SCIScheduleBlockedHandler(NSString *featureKey) {
    [SCIFeatureSchedule endUseForKey:featureKey];
    [SCIFeatureSchedule notifyAvailabilityChanged];
    [SCIUtils showToastForDuration:3.0
                             title:[NSString stringWithFormat:@"%@ unavailable", [featureKey capitalizedString]]
                          subtitle:[SCIFeatureSchedule unavailableReasonForKey:featureKey]];
}

static void SCIDismissViewControllerIfBlocked(id viewController, NSString *featureKey) {
    if (![SCIFeatureSchedule isScheduleEnabledForKey:featureKey]) return;
    if ([SCIFeatureSchedule isAvailableForKey:featureKey]) return;

    UIViewController *vc = (UIViewController *)viewController;

    [SCIUtils showToastForDuration:3.0
                             title:[NSString stringWithFormat:@"%@ unavailable", [featureKey capitalizedString]]
                          subtitle:[SCIFeatureSchedule unavailableReasonForKey:featureKey]];

    dispatch_async(dispatch_get_main_queue(), ^{
        if (vc.presentingViewController) {
            [vc dismissViewControllerAnimated:YES completion:nil];
        } else if (vc.navigationController && vc.navigationController.viewControllers.count > 1) {
            [vc.navigationController popViewControllerAnimated:YES];
        }
    });
}

static void SCIBeginScheduleTracking(NSString *featureKey) {
    if (![SCIFeatureSchedule isScheduleEnabledForKey:featureKey]) return;
    if (![SCIFeatureSchedule isAvailableForKey:featureKey]) return;

    [SCIFeatureSchedule beginUseForKey:featureKey onBlocked:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            SCIScheduleBlockedHandler(featureKey);
        });
    }];
}

static BOOL SCIViewWillAppearBlocked(id self, NSString *featureKey) {
    if ([SCIFeatureSchedule isScheduleEnabledForKey:featureKey] && ![SCIFeatureSchedule isAvailableForKey:featureKey]) {
        SCIDismissViewControllerIfBlocked(self, featureKey);
        return YES;
    }
    return NO;
}

%hook IGSundialFeedViewController
- (void)viewWillAppear:(BOOL)animated {
    if (SCIViewWillAppearBlocked(self, @"reels")) return;
    %orig;
}
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    SCIBeginScheduleTracking(@"reels");
}
- (void)viewDidDisappear:(BOOL)animated {
    [SCIFeatureSchedule endUseForKey:@"reels"];
    %orig;
}
%end

%hook IGMainFeedViewController
- (void)viewWillAppear:(BOOL)animated {
    if (SCIViewWillAppearBlocked(self, @"feed")) return;
    %orig;
}
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    SCIBeginScheduleTracking(@"feed");
}
- (void)viewDidDisappear:(BOOL)animated {
    [SCIFeatureSchedule endUseForKey:@"feed"];
    %orig;
}
%end

%hook IGMainFeedViewController_objc
- (void)viewWillAppear:(BOOL)animated {
    if (SCIViewWillAppearBlocked(self, @"feed")) return;
    %orig;
}
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    SCIBeginScheduleTracking(@"feed");
}
- (void)viewDidDisappear:(BOOL)animated {
    [SCIFeatureSchedule endUseForKey:@"feed"];
    %orig;
}
%end

%hook IGExploreGridViewController
- (void)viewWillAppear:(BOOL)animated {
    if (SCIViewWillAppearBlocked(self, @"explore")) return;
    %orig;
}
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    SCIBeginScheduleTracking(@"explore");
}
- (void)viewDidDisappear:(BOOL)animated {
    [SCIFeatureSchedule endUseForKey:@"explore"];
    %orig;
}
%end

%hook IGExploreViewController
- (void)viewWillAppear:(BOOL)animated {
    if (SCIViewWillAppearBlocked(self, @"explore")) return;
    %orig;
}
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    SCIBeginScheduleTracking(@"explore");
}
- (void)viewDidDisappear:(BOOL)animated {
    [SCIFeatureSchedule endUseForKey:@"explore"];
    %orig;
}
%end

%hook IGDirectInboxViewController
- (void)viewWillAppear:(BOOL)animated {
    if (SCIViewWillAppearBlocked(self, @"messages")) return;
    %orig;
}
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    SCIBeginScheduleTracking(@"messages");
}
- (void)viewDidDisappear:(BOOL)animated {
    [SCIFeatureSchedule endUseForKey:@"messages"];
    %orig;
}
- (void)presentViewController:(UIViewController *)viewControllerToPresent animated:(BOOL)flag completion:(void (^)(void))completion {
    if ([SCIFeatureSchedule isScheduleEnabledForKey:@"messages"] && ![SCIFeatureSchedule isAvailableForKey:@"messages"]) {
        if (completion) completion();
        return;
    }
    %orig;
}
%end

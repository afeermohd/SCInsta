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

%hook IGSundialFeedViewController
- (void)viewWillAppear:(BOOL)animated {
    if ([SCIFeatureSchedule isScheduleEnabledForKey:@"reels"] && ![SCIFeatureSchedule isAvailableForKey:@"reels"]) {
        SCIDismissViewControllerIfBlocked(self, @"reels");
        return;
    }
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
    if ([SCIFeatureSchedule isScheduleEnabledForKey:@"feed"] && ![SCIFeatureSchedule isAvailableForKey:@"feed"]) {
        SCIDismissViewControllerIfBlocked(self, @"feed");
        return;
    }
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
    if ([SCIFeatureSchedule isScheduleEnabledForKey:@"explore"] && ![SCIFeatureSchedule isAvailableForKey:@"explore"]) {
        SCIDismissViewControllerIfBlocked(self, @"explore");
        return;
    }
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
    if ([SCIFeatureSchedule isScheduleEnabledForKey:@"messages"] && ![SCIFeatureSchedule isAvailableForKey:@"messages"]) {
        SCIDismissViewControllerIfBlocked(self, @"messages");
        return;
    }
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
%end

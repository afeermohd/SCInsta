#import "../../Utils.h"
#import "../../Settings/SCIFeatureSchedule.h"

static void SCIScheduleBlockedHandler(NSString *featureKey) {
    [SCIFeatureSchedule endUseForKey:featureKey];
    [SCIUtils showToastForDuration:3.0
                             title:[NSString stringWithFormat:@"%@ unavailable", [featureKey capitalizedString]]
                          subtitle:[SCIFeatureSchedule unavailableReasonForKey:featureKey]];
    [SCIFeatureSchedule enforceLeavingFeatureIfActive:featureKey];
    [SCIFeatureSchedule notifyAvailabilityChanged];
}

static void SCIBeginScheduleTracking(NSString *featureKey) {
    if (![SCIFeatureSchedule isFeatureNavigationAllowed:featureKey]) return;

    [SCIFeatureSchedule beginUseForKey:featureKey onBlocked:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            SCIScheduleBlockedHandler(featureKey);
        });
    }];
}

static BOOL SCIViewWillAppearBlocked(id self, NSString *featureKey) {
    if (![SCIFeatureSchedule isFeatureNavigationAllowed:featureKey]) {
        SCIScheduleBlockedHandler(featureKey);
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
    if (![SCIFeatureSchedule isFeatureNavigationAllowed:@"messages"]) {
        if (completion) completion();
        return;
    }
    %orig;
}
%end

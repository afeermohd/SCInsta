#import "../../Utils.h"
#import "../../Settings/SCIFeatureSchedule.h"

static void SCIApplyScheduleForViewController(UIViewController *self, NSString *featureKey) {
    if (![SCIFeatureSchedule isScheduleEnabledForKey:featureKey]) {
        [SCIFeatureSchedule hideBlockOverlayOnViewController:self];
        [SCIFeatureSchedule endUseForKey:featureKey];
        return;
    }

    if (![SCIFeatureSchedule isAvailableForKey:featureKey]) {
        [SCIFeatureSchedule endUseForKey:featureKey];
        [SCIFeatureSchedule showBlockOverlayOnViewController:self featureKey:featureKey];
        return;
    }

    [SCIFeatureSchedule hideBlockOverlayOnViewController:self];

    __weak UIViewController *weakSelf = self;
    [SCIFeatureSchedule beginUseForKey:featureKey onBlocked:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            UIViewController *strongSelf = weakSelf;
            if (!strongSelf) return;
            [SCIFeatureSchedule showBlockOverlayOnViewController:strongSelf featureKey:featureKey];
            [SCIUtils showToastForDuration:3.0
                                     title:[NSString stringWithFormat:@"%@ limit reached", [featureKey capitalizedString]]
                                  subtitle:[SCIFeatureSchedule unavailableReasonForKey:featureKey]];
        });
    }];
}

%hook IGSundialFeedViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    SCIApplyScheduleForViewController(self, @"reels");
}
- (void)viewDidDisappear:(BOOL)animated {
    [SCIFeatureSchedule endUseForKey:@"reels"];
    %orig;
}
%end

%hook IGMainFeedViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    SCIApplyScheduleForViewController(self, @"feed");
}
- (void)viewDidDisappear:(BOOL)animated {
    [SCIFeatureSchedule endUseForKey:@"feed"];
    %orig;
}
%end

%hook IGExploreGridViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    SCIApplyScheduleForViewController(self, @"explore");
}
- (void)viewDidDisappear:(BOOL)animated {
    [SCIFeatureSchedule endUseForKey:@"explore"];
    %orig;
}
%end

%hook IGDirectInboxViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    SCIApplyScheduleForViewController(self, @"messages");
}
- (void)viewDidDisappear:(BOOL)animated {
    [SCIFeatureSchedule endUseForKey:@"messages"];
    %orig;
}
%end

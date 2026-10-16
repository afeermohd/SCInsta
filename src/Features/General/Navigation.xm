#import "../../Utils.h"
#import "../../Settings/SCIFeatureSchedule.h"

BOOL isSurfaceShown(IGMainAppSurfaceIntent *surface) {
    NSString *tabString = [surface tabStringFromSurfaceIntent];

    if (![SCIFeatureSchedule isMainAppSurfaceAllowed:tabString]) {
        return NO;
    }

    if ([tabString isEqualToString:@"FEED"] && [SCIUtils getBoolPref:@"hide_feed_tab"]) {
        return NO;
    }
    if ([tabString isEqualToString:@"CLIPS"] && [SCIUtils getBoolPref:@"hide_reels_tab"]) {
        return NO;
    }
    if ([tabString isEqualToString:@"SEARCH"] && [SCIUtils getBoolPref:@"hide_explore_tab"]) {
        return NO;
    }
    if ([(NSNumber *)[surface valueForKey:@"_subtype"] unsignedIntegerValue] == 3 && [SCIUtils getBoolPref:@"hide_create_tab"]) {
        return NO;
    }

    return YES;
}

NSArray *filterSurfacesArray(NSArray *surfaces) {
    NSMutableArray *filteredSurfaces = [NSMutableArray array];

    for (id surface in surfaces) {
        if (![surface isKindOfClass:%c(IGMainAppSurfaceIntent)]) continue;

        if (isSurfaceShown(surface)) {
            [filteredSurfaces addObject:surface];
        }
    }

    return filteredSurfaces;
}

static void SCISetTabBarButtonHidden(id tabBarController, NSString *key, BOOL hidden) {
    @try {
        UIView *button = [tabBarController valueForKey:key];
        if (![button isKindOfClass:[UIView class]]) return;

        button.hidden = hidden;
        button.userInteractionEnabled = !hidden;
        button.alpha = hidden ? 0.0 : 1.0;
    } @catch (__unused NSException *exception) {
    }
}

static void SCIApplyScheduleToTabBarButtons(id tabBarController) {
    SCISetTabBarButtonHidden(tabBarController, @"_homeButton",
                             ![SCIFeatureSchedule isFeatureNavigationAllowed:@"feed"]);
    SCISetTabBarButtonHidden(tabBarController, @"_exploreButton",
                             ![SCIFeatureSchedule isFeatureNavigationAllowed:@"explore"]);
    SCISetTabBarButtonHidden(tabBarController, @"_discoverVideoButton",
                             ![SCIFeatureSchedule isFeatureNavigationAllowed:@"reels"]);
    SCISetTabBarButtonHidden(tabBarController, @"_directInboxButton",
                             ![SCIFeatureSchedule isFeatureNavigationAllowed:@"messages"]);
}

static void SCIShowFeatureBlockedToast(NSString *featureKey) {
    [SCIUtils showToastForDuration:3.0
                             title:[NSString stringWithFormat:@"%@ unavailable", [featureKey capitalizedString]]
                          subtitle:[SCIFeatureSchedule unavailableReasonForKey:featureKey]];
}

static BOOL SCIBlockTabBarAction(NSString *featureKey) {
    if ([SCIFeatureSchedule isFeatureNavigationAllowed:featureKey]) return NO;
    SCIShowFeatureBlockedToast(featureKey);
    return YES;
}

///////////////////////////////////////////////

%hook IGTabBarControllerSwipeCoordinator
- (id)initWithSurfaces:(id)surfaces parentViewController:(id)controller enableHaptics:(_Bool)haptics launcherSet:(id)set {
    return %orig(filterSurfacesArray(surfaces), controller, haptics, set);
}
%end

%hook IGTabBarController
- (void)viewDidLoad {
    %orig;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(sci_featureScheduleAvailabilityChanged:)
                                                 name:SCIFeatureScheduleAvailabilityChangedNotification
                                               object:nil];
}

%new
- (void)sci_featureScheduleAvailabilityChanged:(NSNotification *)notification {
    [self _layoutTabBar];
}

- (void)_layoutTabBar {
    NSArray *_tabBarSurfaces = [SCIUtils getIvarForObj:self name:"_tabBarSurfaces"];

    [SCIUtils setIvarForObj:self name:"_tabBarSurfaces" value:filterSurfacesArray(_tabBarSurfaces)];

    %orig;

    SCIApplyScheduleToTabBarButtons(self);
}

- (id)_buttonForTabBarSurface:(id)surface {
    id button = %orig(surface);

    if (!isSurfaceShown(surface)) {
        return nil;
    }

    return button;
}

- (void)_homeButtonPressed {
    if (SCIBlockTabBarAction(@"feed")) return;
    %orig;
}

- (void)_exploreButtonPressed {
    if (SCIBlockTabBarAction(@"explore")) return;
    %orig;
}

- (void)_discoverVideoButtonPressed {
    if (SCIBlockTabBarAction(@"reels")) return;
    %orig;
}

- (void)_directInboxButtonPressed {
    if (SCIBlockTabBarAction(@"messages")) return;
    %orig;
}

%end

// Demangled name: IGNavConfiguration.IGNavConfiguration
%hook _TtC18IGNavConfiguration18IGNavConfiguration
- (NSInteger)tabOrdering {

    if ([[SCIUtils getStringPref:@"nav_icon_ordering"] isEqualToString:@"classic"]) return 0;
    else if ([[SCIUtils getStringPref:@"nav_icon_ordering"] isEqualToString:@"standard"]) return 1;
    else if ([[SCIUtils getStringPref:@"nav_icon_ordering"] isEqualToString:@"alternate"]) return 2;

    return %orig;

}
- (void)setTabOrdering:(NSInteger)arg1 {
    return;
}

- (BOOL)isTabSwipingEnabled {

    if ([[SCIUtils getStringPref:@"swipe_nav_tabs"] isEqualToString:@"enabled"]) return YES;
    else if ([[SCIUtils getStringPref:@"swipe_nav_tabs"] isEqualToString:@"disabled"]) return NO;

    return %orig;

}
- (void)setIsTabSwipingEnabled:(BOOL)arg1 {
    return;
}
%end

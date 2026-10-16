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

///////////////////////////////////////////////

%hook IGTabBarControllerSwipeCoordinator
- (id)initWithSurfaces:(id)surfaces parentViewController:(id)controller enableHaptics:(_Bool)haptics launcherSet:(id)set {
    // Removes the surface from the main swipeable app collection view
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
    // Prevents the wrong icon from being shown as selected because of mismatched surface array indexes
    NSArray *_tabBarSurfaces = [SCIUtils getIvarForObj:self name:"_tabBarSurfaces"];

    [SCIUtils setIvarForObj:self name:"_tabBarSurfaces" value:filterSurfacesArray(_tabBarSurfaces)];
    
    %orig;
}

- (id)_buttonForTabBarSurface:(id)surface {
    // Prevents the button from being added to the tab bar 
    id button = %orig(surface);

    if (!isSurfaceShown(surface)) {
        return nil;
    }

    return button;
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
#import "SCIFeatureSchedule.h"
#import "../Utils.h"
#import <objc/message.h>

NSNotificationName const SCIFeatureScheduleAvailabilityChangedNotification = @"SCIFeatureScheduleAvailabilityChangedNotification";

NSString *const SCIScheduleFeedPostsKey = @"feed_posts";
NSString *const SCIScheduleStoriesKey   = @"stories";
NSString *const SCIScheduleReelsKey     = @"reels";
NSString *const SCIScheduleExploreKey   = @"explore";

// Preference keys (shared across all limited features)
static NSString *const kSCIScheduleEnabledKey      = @"schedule_enabled";
static NSString *const kSCIScheduleStartHourKey    = @"schedule_start_hour";
static NSString *const kSCIScheduleStartMinuteKey  = @"schedule_start_minute";
static NSString *const kSCIScheduleEndHourKey      = @"schedule_end_hour";
static NSString *const kSCIScheduleEndMinuteKey    = @"schedule_end_minute";
static NSString *const kSCIScheduleLimitMinutesKey = @"schedule_limit_minutes";
static NSString *const kSCIScheduleUsageWindowKey  = @"schedule_usage_window_id";
static NSString *const kSCIScheduleUsageSecondsKey = @"schedule_usage_seconds";

// Seconds before the budget runs out at which a heads-up toast is shown.
static const NSTimeInterval kSCIWarningSeconds = 60.0;

// Tokens ("<feature>:<owner pointer>") of limited surfaces currently on screen. Time is counted once while this set is non-empty,
// so overlapping surfaces (e.g. feed + reels transition) never double count.
static NSMutableSet<NSString *> *SCIActiveFeatureKeys;
static NSDate *SCILastAccountedDate;
static NSTimer *SCIUsageTickTimer;
static NSTimer *SCISchedulePollTimer;
static NSNumber *SCILastUsageAllowed;
static BOOL SCIWarningShownForWindow;
static BOOL SCIIsForceClosing;

@implementation SCIFeatureSchedule

+ (void)initialize {
    if (self != [SCIFeatureSchedule class]) return;

    SCIActiveFeatureKeys = [NSMutableSet set];

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(_applicationDidEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [nc addObserver:self selector:@selector(_applicationWillEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];

    SCISchedulePollTimer = [NSTimer timerWithTimeInterval:10.0 repeats:YES block:^(NSTimer * _Nonnull timer) {
        [SCIFeatureSchedule _pollScheduleAvailability];
    }];
    [[NSRunLoop mainRunLoop] addTimer:SCISchedulePollTimer forMode:NSRunLoopCommonModes];

    dispatch_async(dispatch_get_main_queue(), ^{
        [SCIFeatureSchedule syncScheduleEnforcement];
    });
}

// MARK: - Feature keys

+ (NSArray<NSString *> *)limitedFeatureKeys {
    return @[ SCIScheduleFeedPostsKey, SCIScheduleStoriesKey, SCIScheduleReelsKey, SCIScheduleExploreKey ];
}

+ (BOOL)isLimitedFeatureKey:(NSString *)featureKey {
    return featureKey.length && [[self limitedFeatureKeys] containsObject:featureKey];
}

/// Only the reels tab is ever hidden. Feed stays (camera, stories, DMs live there) and
/// explore stays (search is always available); their content is hidden instead.
+ (nullable NSString *)_featureKeyForSurfaceTabString:(NSString *)tabString {
    if ([tabString isEqualToString:@"CLIPS"] || [tabString isEqualToString:@"REELS"]) {
        return SCIScheduleReelsKey;
    }
    return nil;
}

// MARK: - Preferences

+ (BOOL)isScheduleEnabled {
    return [SCIUtils getBoolPref:kSCIScheduleEnabledKey];
}

+ (BOOL)isScheduleEnabledForKey:(NSString *)featureKey {
    if (![self isLimitedFeatureKey:featureKey] || ![self isScheduleEnabled]) return NO;
    return [SCIUtils getBoolPref:[NSString stringWithFormat:@"schedule_surface_%@", featureKey]];
}

+ (BOOL)isBlockedForKey:(NSString *)featureKey {
    return [self isScheduleEnabledForKey:featureKey] && ![self isUsageAllowed];
}

+ (NSInteger)_startMinutes {
    return (NSInteger)[SCIUtils getDoublePref:kSCIScheduleStartHourKey] * 60 + (NSInteger)[SCIUtils getDoublePref:kSCIScheduleStartMinuteKey];
}

+ (NSInteger)_endMinutes {
    return (NSInteger)[SCIUtils getDoublePref:kSCIScheduleEndHourKey] * 60 + (NSInteger)[SCIUtils getDoublePref:kSCIScheduleEndMinuteKey];
}

+ (NSInteger)_limitMinutes {
    return (NSInteger)[SCIUtils getDoublePref:kSCIScheduleLimitMinutesKey];
}

+ (NSString *)formattedTimeFromMinutes:(NSInteger)minutes {
    minutes = ((minutes % (24 * 60)) + (24 * 60)) % (24 * 60);
    return [NSString stringWithFormat:@"%02ld:%02ld", (long)(minutes / 60), (long)(minutes % 60)];
}

// MARK: - Window

+ (NSInteger)_minutesSinceMidnightForDate:(NSDate *)date {
    NSDateComponents *c = [[NSCalendar currentCalendar] components:(NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:date];
    return c.hour * 60 + c.minute;
}

+ (BOOL)_isWithinWindowAtDate:(NSDate *)date {
    NSInteger start = [self _startMinutes];
    NSInteger end = [self _endMinutes];
    NSInteger now = [self _minutesSinceMidnightForDate:date];

    if (start == end) return YES;                       // all day
    if (start < end) return now >= start && now < end;  // same-day window
    return now >= start || now < end;                   // overnight window
}

/// Identifies the current window occurrence (the day it opened + its start time); usage resets when it changes.
+ (NSString *)_windowIdentifierAtDate:(NSDate *)date {
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSInteger start = [self _startMinutes];
    NSInteger now = [self _minutesSinceMidnightForDate:date];

    NSDate *openedOn = date;
    if (now < start) {
        // Before today's start: we're either in the tail of yesterday's overnight window,
        // or before today's window. Both belong to yesterday's occurrence.
        openedOn = [cal dateByAddingUnit:NSCalendarUnitDay value:-1 toDate:date options:0];
    }

    NSDateComponents *day = [cal components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:openedOn];
    return [NSString stringWithFormat:@"%04ld-%02ld-%02ld-%ld",
            (long)day.year, (long)day.month, (long)day.day, (long)start];
}

// MARK: - Usage storage

+ (void)_resetUsageIfWindowChanged {
    NSString *current = [self _windowIdentifierAtDate:[NSDate date]];
    NSString *stored = [SCIUtils getStringPref:kSCIScheduleUsageWindowKey];

    if (![stored isEqualToString:current]) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setObject:current forKey:kSCIScheduleUsageWindowKey];
        [defaults setDouble:0 forKey:kSCIScheduleUsageSecondsKey];
        SCIWarningShownForWindow = NO;
    }
}

+ (NSTimeInterval)_storedUsageSeconds {
    [self _resetUsageIfWindowChanged];
    return [SCIUtils getDoublePref:kSCIScheduleUsageSecondsKey];
}

/// Adds time elapsed since the last accounting point to the shared usage counter.
+ (void)_flushActiveUsage {
    if (!SCILastAccountedDate) return;

    NSDate *now = [NSDate date];
    NSTimeInterval elapsed = [now timeIntervalSinceDate:SCILastAccountedDate];
    SCILastAccountedDate = SCIActiveFeatureKeys.count ? now : nil;

    // Ticks run every second; clamp to guard against clock jumps or a stalled main thread.
    if (elapsed <= 0) return;
    elapsed = MIN(elapsed, 10.0);

    NSTimeInterval total = [self _storedUsageSeconds] + elapsed;
    [[NSUserDefaults standardUserDefaults] setDouble:total forKey:kSCIScheduleUsageSecondsKey];
}

// MARK: - Availability

+ (BOOL)isUsageAllowed {
    if (![self isScheduleEnabled]) return YES;
    if (![self _isWithinWindowAtDate:[NSDate date]]) return NO;
    return [self remainingSeconds] > 0;
}

+ (NSTimeInterval)remainingSeconds {
    if (![self isScheduleEnabled]) return INFINITY;

    NSInteger limitMinutes = [self _limitMinutes];
    if (limitMinutes <= 0) return INFINITY;

    return MAX(0, limitMinutes * 60.0 - [self _storedUsageSeconds]);
}

+ (BOOL)isFeatureNavigationAllowed:(NSString *)featureKey {
    return ![self isBlockedForKey:featureKey];
}

+ (BOOL)isMainAppSurfaceAllowed:(NSString *)tabStringFromSurfaceIntent {
    NSString *featureKey = [self _featureKeyForSurfaceTabString:tabStringFromSurfaceIntent];
    if (!featureKey) return YES;
    return [self isFeatureNavigationAllowed:featureKey];
}

+ (NSString *)unavailableReason {
    if (![self isScheduleEnabled]) return @"";

    NSString *start = [self formattedTimeFromMinutes:[self _startMinutes]];
    NSString *end = [self formattedTimeFromMinutes:[self _endMinutes]];

    if (![self _isWithinWindowAtDate:[NSDate date]]) {
        return [NSString stringWithFormat:@"Available %@ – %@ each day", start, end];
    }

    NSTimeInterval remaining = [self remainingSeconds];
    if (remaining <= 0) {
        return [NSString stringWithFormat:@"Daily limit reached. Resets at %@", start];
    }
    if (isinf(remaining)) {
        return [NSString stringWithFormat:@"Available until %@", end];
    }

    NSInteger mins = (NSInteger)ceil(remaining / 60.0);
    return [NSString stringWithFormat:@"%ld min left today", (long)mins];
}

// MARK: - Usage tracking

+ (NSString *)_tokenForKey:(NSString *)featureKey owner:(id)owner {
    return [NSString stringWithFormat:@"%@:%p", featureKey, owner];
}

+ (void)beginUseForKey:(NSString *)featureKey owner:(id)owner {
    if (![self isScheduleEnabledForKey:featureKey]) return;

    [self _resetUsageIfWindowChanged];
    if (![self isUsageAllowed]) return;

    [self _flushActiveUsage];
    [SCIActiveFeatureKeys addObject:[self _tokenForKey:featureKey owner:owner]];
    if (!SCILastAccountedDate) SCILastAccountedDate = [NSDate date];

    if (!SCIUsageTickTimer) {
        SCIUsageTickTimer = [NSTimer timerWithTimeInterval:1.0 repeats:YES block:^(NSTimer * _Nonnull timer) {
            [SCIFeatureSchedule _usageTick];
        }];
        [[NSRunLoop mainRunLoop] addTimer:SCIUsageTickTimer forMode:NSRunLoopCommonModes];
    }
}

+ (void)endUseForKey:(NSString *)featureKey owner:(id)owner {
    NSString *token = [self _tokenForKey:featureKey owner:owner];
    if (![SCIActiveFeatureKeys containsObject:token]) return;

    [self _flushActiveUsage];
    [SCIActiveFeatureKeys removeObject:token];

    if (!SCIActiveFeatureKeys.count) {
        SCILastAccountedDate = nil;
        [SCIUsageTickTimer invalidate];
        SCIUsageTickTimer = nil;
    }
}

+ (void)_endAllUse {
    [self _flushActiveUsage];
    [SCIActiveFeatureKeys removeAllObjects];
    SCILastAccountedDate = nil;
    [SCIUsageTickTimer invalidate];
    SCIUsageTickTimer = nil;
}

+ (void)_usageTick {
    if (!SCIActiveFeatureKeys.count) return;

    [self _flushActiveUsage];

    if (![self isUsageAllowed]) {
        // Budget exhausted or window closed while scrolling: shut the app down.
        [self _forceCloseApp];
        return;
    }

    NSTimeInterval remaining = [self remainingSeconds];
    if (!SCIWarningShownForWindow && remaining <= kSCIWarningSeconds) {
        SCIWarningShownForWindow = YES;
        [SCIUtils showToastForDuration:3.0
                                 title:@"1 minute left"
                              subtitle:@"Instagram will close when your time is up"];
    }
}

// MARK: - Force close

+ (void)_forceCloseApp {
    if (SCIIsForceClosing) return;
    SCIIsForceClosing = YES;

    [self _endAllUse];
    [[NSUserDefaults standardUserDefaults] synchronize];

    UIApplication *app = [UIApplication sharedApplication];

    // Keep the process alive long enough to finish exiting after we leave the foreground.
    __block UIBackgroundTaskIdentifier task = [app beginBackgroundTaskWithExpirationHandler:^{
        exit(0);
    }];
    (void)task;

    // Animate back to the home screen like a normal close, then terminate the process.
    SEL suspendSel = NSSelectorFromString(@"suspend");
    if ([app respondsToSelector:suspendSel]) {
        ((void (*)(id, SEL))objc_msgSend)(app, suspendSel);
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        exit(0);
    });
}

// MARK: - Tab enforcement

+ (void)_pollScheduleAvailability {
    if (![self isScheduleEnabled]) {
        if (SCILastUsageAllowed && !SCILastUsageAllowed.boolValue) {
            SCILastUsageAllowed = @YES;
            [self syncScheduleEnforcement];
        }
        return;
    }

    BOOL allowed = [self isUsageAllowed];
    if (SCILastUsageAllowed && SCILastUsageAllowed.boolValue == allowed) return;
    SCILastUsageAllowed = @(allowed);

    if (!allowed && SCIActiveFeatureKeys.count) {
        [self _forceCloseApp];
        return;
    }

    [self syncScheduleEnforcement];
}

+ (nullable id)_findTabBarControllerInViewController:(UIViewController *)viewController {
    if (!viewController) return nil;

    Class tabBarClass = NSClassFromString(@"IGTabBarController");
    if (tabBarClass && [viewController isKindOfClass:tabBarClass]) {
        return viewController;
    }

    for (UIViewController *child in viewController.childViewControllers) {
        id found = [self _findTabBarControllerInViewController:child];
        if (found) return found;
    }

    return [self _findTabBarControllerInViewController:viewController.presentedViewController];
}

+ (nullable id)_mainTabBarController {
    UIWindow *keyWindow = nil;
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        if (window.isKeyWindow) {
            keyWindow = window;
            break;
        }
    }
    if (!keyWindow) {
        keyWindow = [UIApplication sharedApplication].windows.firstObject;
    }
    return [self _findTabBarControllerInViewController:keyWindow.rootViewController];
}

+ (nullable NSString *)_featureKeyForSelectedTabOnTabBarController:(id)tabBarController {
    if (!tabBarController) return nil;

    id surface = nil;
    @try {
        surface = [tabBarController valueForKey:@"_selectedTabBarSurface"];
    } @catch (__unused NSException *exception) {
        return nil;
    }

    if (![surface respondsToSelector:@selector(tabStringFromSurfaceIntent)]) return nil;
    return [self _featureKeyForSurfaceTabString:[surface tabStringFromSurfaceIntent]];
}

+ (void)_switchTabBarController:(id)tabBarController toFirstAllowedSurfaceAnimated:(BOOL)animated {
    if (!tabBarController) return;

    NSArray *surfaces = nil;
    @try {
        surfaces = [tabBarController valueForKey:@"_tabBarSurfaces"];
    } @catch (__unused NSException *exception) {
        surfaces = nil;
    }

    for (id surface in surfaces) {
        if (![surface respondsToSelector:@selector(tabStringFromSurfaceIntent)]) continue;
        if (![self isMainAppSurfaceAllowed:[surface tabStringFromSurfaceIntent]]) continue;

        if ([tabBarController respondsToSelector:@selector(setSelectedTabBarSurface:animated:)]) {
            ((void (*)(id, SEL, id, BOOL))objc_msgSend)(tabBarController, @selector(setSelectedTabBarSurface:animated:), surface, animated);
            return;
        }
    }

    if ([tabBarController respondsToSelector:@selector(_profileButtonPressed)]) {
        ((void (*)(id, SEL))objc_msgSend)(tabBarController, @selector(_profileButtonPressed));
    }
}

+ (void)enforceLeavingFeatureIfActive:(NSString *)featureKey {
    if (!featureKey.length) return;
    if ([self isFeatureNavigationAllowed:featureKey]) return;

    id tabBarController = [self _mainTabBarController];
    NSString *activeKey = [self _featureKeyForSelectedTabOnTabBarController:tabBarController];
    if (![activeKey isEqualToString:featureKey]) return;

    [self _switchTabBarController:tabBarController toFirstAllowedSurfaceAnimated:YES];
}

+ (void)syncScheduleEnforcement {
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self isScheduleEnabled]) {
            for (NSString *featureKey in [self limitedFeatureKeys]) {
                [self enforceLeavingFeatureIfActive:featureKey];
            }
        }
        [self notifyAvailabilityChanged];
    });
}

+ (void)notifyAvailabilityChanged {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:SCIFeatureScheduleAvailabilityChangedNotification object:nil];
    });
}

// MARK: - App lifecycle

+ (void)_applicationDidEnterBackground:(NSNotification *)note {
    // Keep the active set so tracking resumes on foreground, but stop the clock while backgrounded.
    [self _flushActiveUsage];
    SCILastAccountedDate = nil;
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (void)_applicationWillEnterForeground:(NSNotification *)note {
    if (SCIActiveFeatureKeys.count) {
        if (![self isUsageAllowed]) {
            [self _forceCloseApp];
            return;
        }
        SCILastAccountedDate = [NSDate date];
    }
    [self syncScheduleEnforcement];
}

@end

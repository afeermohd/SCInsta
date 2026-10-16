#import "SCIFeatureSchedule.h"
#import "../Utils.h"

static const NSInteger kSCIBlockOverlayTag = 0x5C15001;

static NSMutableDictionary<NSString *, NSDate *> *SCIActiveSessionStarts;
static NSMutableDictionary<NSString *, NSTimer *> *SCIActiveSessionTimers;

@implementation SCIFeatureSchedule

+ (void)initialize {
    if (self != [SCIFeatureSchedule class]) return;

    SCIActiveSessionStarts = [NSMutableDictionary dictionary];
    SCIActiveSessionTimers = [NSMutableDictionary dictionary];

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(_applicationDidEnterBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
}

+ (NSString *)_prefKey:(NSString *)feature suffix:(NSString *)suffix {
    return [NSString stringWithFormat:@"schedule_%@_%@", feature, suffix];
}

+ (BOOL)isScheduleEnabledForKey:(NSString *)featureKey {
    return [SCIUtils getBoolPref:[self _prefKey:featureKey suffix:@"enabled"]];
}

+ (NSInteger)_minutesForFeature:(NSString *)featureKey component:(NSString *)component {
    return (NSInteger)[SCIUtils getDoublePref:[self _prefKey:featureKey suffix:component]];
}

+ (NSInteger)startMinutesForKey:(NSString *)featureKey {
    NSInteger hour = [self _minutesForFeature:featureKey component:@"start_hour"];
    NSInteger minute = [self _minutesForFeature:featureKey component:@"start_minute"];
    return hour * 60 + minute;
}

+ (NSInteger)endMinutesForKey:(NSString *)featureKey {
    NSInteger hour = [self _minutesForFeature:featureKey component:@"end_hour"];
    NSInteger minute = [self _minutesForFeature:featureKey component:@"end_minute"];
    return hour * 60 + minute;
}

+ (NSInteger)limitMinutesForKey:(NSString *)featureKey {
    return (NSInteger)[SCIUtils getDoublePref:[self _prefKey:featureKey suffix:@"limit_minutes"]];
}

+ (NSString *)formattedTimeFromMinutes:(NSInteger)minutes {
    minutes = ((minutes % (24 * 60)) + (24 * 60)) % (24 * 60);
    return [NSString stringWithFormat:@"%02ld:%02ld", (long)(minutes / 60), (long)(minutes % 60)];
}

+ (NSInteger)_minutesSinceMidnightForDate:(NSDate *)date {
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *c = [cal components:(NSCalendarUnitHour | NSCalendarUnitMinute) fromDate:date];
    return c.hour * 60 + c.minute;
}

+ (BOOL)isWithinWindowForKey:(NSString *)featureKey atDate:(NSDate *)date {
    NSInteger start = [self startMinutesForKey:featureKey];
    NSInteger end = [self endMinutesForKey:featureKey];
    NSInteger now = [self _minutesSinceMidnightForDate:date];

    if (start == end) {
        return YES;
    }

    if (start < end) {
        return now >= start && now < end;
    }

    return now >= start || now < end;
}

+ (NSString *)_windowIdentifierForKey:(NSString *)featureKey atDate:(NSDate *)date {
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *day = [cal components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:date];
    NSInteger start = [self startMinutesForKey:featureKey];
    NSInteger now = [self _minutesSinceMidnightForDate:date];

    if (start < [self endMinutesForKey:featureKey] || now >= start) {
        return [NSString stringWithFormat:@"%04ld-%02ld-%02ld-%ld",
                (long)day.year, (long)day.month, (long)day.day, (long)start];
    }

    NSDate *yesterday = [cal dateByAddingUnit:NSCalendarUnitDay value:-1 toDate:date options:0];
    NSDateComponents *prevDay = [cal components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:yesterday];
    return [NSString stringWithFormat:@"%04ld-%02ld-%02ld-%ld",
            (long)prevDay.year, (long)prevDay.month, (long)prevDay.day, (long)start];
}

+ (NSString *)_usageWindowDefaultsKey:(NSString *)featureKey {
    return [self _prefKey:featureKey suffix:@"usage_window_id"];
}

+ (NSString *)_usageSecondsDefaultsKey:(NSString *)featureKey {
    return [self _prefKey:featureKey suffix:@"usage_seconds"];
}

+ (void)_resetUsageIfWindowChangedForKey:(NSString *)featureKey {
    NSString *current = [self _windowIdentifierForKey:featureKey atDate:[NSDate date]];
    NSString *stored = [SCIUtils getStringPref:[self _usageWindowDefaultsKey:featureKey]];

    if (![stored isEqualToString:current]) {
        [[NSUserDefaults standardUserDefaults] setObject:current forKey:[self _usageWindowDefaultsKey:featureKey]];
        [[NSUserDefaults standardUserDefaults] setDouble:0 forKey:[self _usageSecondsDefaultsKey:featureKey]];
    }
}

+ (NSTimeInterval)_storedUsageSecondsForKey:(NSString *)featureKey {
    [self _resetUsageIfWindowChangedForKey:featureKey];
    return [SCIUtils getDoublePref:[self _usageSecondsDefaultsKey:featureKey]];
}

+ (void)_addUsageSeconds:(NSTimeInterval)seconds forKey:(NSString *)featureKey {
    if (seconds <= 0) return;
    [self _resetUsageIfWindowChangedForKey:featureKey];
    NSTimeInterval total = [self _storedUsageSecondsForKey:featureKey] + seconds;
    [[NSUserDefaults standardUserDefaults] setDouble:total forKey:[self _usageSecondsDefaultsKey:featureKey]];
}

+ (BOOL)isAvailableForKey:(NSString *)featureKey {
    if (![self isScheduleEnabledForKey:featureKey]) return YES;
    if (![self isWithinWindowForKey:featureKey atDate:[NSDate date]]) return NO;

    NSInteger limitMinutes = [self limitMinutesForKey:featureKey];
    if (limitMinutes <= 0) return YES;

    NSTimeInterval limitSeconds = limitMinutes * 60.0;
    return [self _storedUsageSecondsForKey:featureKey] < limitSeconds;
}

+ (NSTimeInterval)remainingSecondsForKey:(NSString *)featureKey {
    if (![self isScheduleEnabledForKey:featureKey]) return INFINITY;

    NSInteger limitMinutes = [self limitMinutesForKey:featureKey];
    if (limitMinutes <= 0) return INFINITY;

    NSTimeInterval limitSeconds = limitMinutes * 60.0;
    return MAX(0, limitSeconds - [self _storedUsageSecondsForKey:featureKey]);
}

+ (NSString *)unavailableReasonForKey:(NSString *)featureKey {
    if (![self isScheduleEnabledForKey:featureKey]) return @"";

    if (![self isWithinWindowForKey:featureKey atDate:[NSDate date]]) {
        NSInteger start = [self startMinutesForKey:featureKey];
        NSInteger end = [self endMinutesForKey:featureKey];
        return [NSString stringWithFormat:@"Available %@ – %@ each day",
                [self formattedTimeFromMinutes:start],
                [self formattedTimeFromMinutes:end]];
    }

    NSTimeInterval remaining = [self remainingSecondsForKey:featureKey];
    if (remaining <= 0) {
        NSInteger start = [self startMinutesForKey:featureKey];
        return [NSString stringWithFormat:@"Daily limit reached. Resets at %@",
                [self formattedTimeFromMinutes:start]];
    }

    NSInteger mins = (NSInteger)ceil(remaining / 60.0);
    return [NSString stringWithFormat:@"%ld min remaining in this window", (long)mins];
}

+ (void)_sessionTickForKey:(NSString *)featureKey onBlocked:(void (^)(void))onBlocked {
    if (!SCIActiveSessionStarts[featureKey]) return;

    if (![self isAvailableForKey:featureKey]) {
        [self endUseForKey:featureKey];
        if (onBlocked) onBlocked();
        return;
    }

    NSDate *start = SCIActiveSessionStarts[featureKey];
    NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:start];
    NSTimeInterval stored = [self _storedUsageSecondsForKey:featureKey];
    NSInteger limitMinutes = [self limitMinutesForKey:featureKey];
    if (limitMinutes > 0 && stored + elapsed >= limitMinutes * 60.0) {
        [self _addUsageSeconds:elapsed forKey:featureKey];
        SCIActiveSessionStarts[featureKey] = [NSDate date];
        [self endUseForKey:featureKey];
        if (onBlocked) onBlocked();
    }
}

+ (void)beginUseForKey:(NSString *)featureKey onBlocked:(void (^)(void))onBlocked {
    if (![self isScheduleEnabledForKey:featureKey]) return;

    [self _resetUsageIfWindowChangedForKey:featureKey];

    if (![self isAvailableForKey:featureKey]) {
        if (onBlocked) onBlocked();
        return;
    }

    [self endUseForKey:featureKey];

    SCIActiveSessionStarts[featureKey] = [NSDate date];

    __weak typeof(self) weakSelf = self;
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer * _Nonnull timer) {
        [weakSelf _sessionTickForKey:featureKey onBlocked:onBlocked];
    }];
    SCIActiveSessionTimers[featureKey] = timer;
}

+ (void)endUseForKey:(NSString *)featureKey {
    NSTimer *timer = SCIActiveSessionTimers[featureKey];
    [timer invalidate];
    [SCIActiveSessionTimers removeObjectForKey:featureKey];

    NSDate *start = SCIActiveSessionStarts[featureKey];
    [SCIActiveSessionStarts removeObjectForKey:featureKey];

    if (!start) return;

    NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:start];
    [self _addUsageSeconds:elapsed forKey:featureKey];
}

+ (void)_applicationDidEnterBackground:(NSNotification *)note {
    NSArray *keys = [SCIActiveSessionStarts.allKeys copy];
    for (NSString *key in keys) {
        [self endUseForKey:key];
    }
}

+ (void)showBlockOverlayOnViewController:(UIViewController *)viewController featureKey:(NSString *)featureKey {
    if (!viewController.view) return;

    UIView *existing = [viewController.view viewWithTag:kSCIBlockOverlayTag];
    if (existing) {
        UILabel *detail = [existing viewWithTag:kSCIBlockOverlayTag + 1];
        if ([detail isKindOfClass:[UILabel class]]) {
            detail.text = [self unavailableReasonForKey:featureKey];
        }
        return;
    }

    UIView *overlay = [[UIView alloc] initWithFrame:viewController.view.bounds];
    overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    overlay.tag = kSCIBlockOverlayTag;
    overlay.backgroundColor = [[UIColor systemBackgroundColor] colorWithAlphaComponent:0.92];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 12;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *title = [[UILabel alloc] init];
    title.text = [featureKey capitalizedString];
    title.font = [UIFont boldSystemFontOfSize:22];

    UILabel *detail = [[UILabel alloc] init];
    detail.tag = kSCIBlockOverlayTag + 1;
    detail.text = [self unavailableReasonForKey:featureKey];
    detail.numberOfLines = 0;
    detail.textAlignment = NSTextAlignmentCenter;
    detail.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    detail.textColor = [UIColor secondaryLabelColor];

    [stack addArrangedSubview:title];
    [stack addArrangedSubview:detail];

    [overlay addSubview:stack];
    [viewController.view addSubview:overlay];

    [NSLayoutConstraint activateConstraints:@[
        [stack.centerXAnchor constraintEqualToAnchor:overlay.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:overlay.centerYAnchor],
        [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:overlay.leadingAnchor constant:24],
        [stack.trailingAnchor constraintLessThanOrEqualToAnchor:overlay.trailingAnchor constant:-24],
    ]];
}

+ (void)hideBlockOverlayOnViewController:(UIViewController *)viewController {
    [[viewController.view viewWithTag:kSCIBlockOverlayTag] removeFromSuperview];
}

@end

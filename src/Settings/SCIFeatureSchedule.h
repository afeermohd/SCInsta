#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const SCIFeatureScheduleAvailabilityChangedNotification;

/// Daily time windows and per-window usage limits for Instagram surfaces.
@interface SCIFeatureSchedule : NSObject

+ (BOOL)isScheduleEnabledForKey:(NSString *)featureKey;
+ (BOOL)isAvailableForKey:(NSString *)featureKey;
+ (NSTimeInterval)remainingSecondsForKey:(NSString *)featureKey;
+ (NSString *)unavailableReasonForKey:(NSString *)featureKey;

/// Bottom-nav surface intents (FEED, CLIPS, SEARCH, DIRECT) hidden when schedule blocks the feature.
+ (BOOL)isMainAppSurfaceAllowed:(NSString *)tabStringFromSurfaceIntent;

/// Whether the user may open this feature via tab bar / navigation (feed, reels, explore, messages).
+ (BOOL)isFeatureNavigationAllowed:(NSString *)featureKey;

+ (void)beginUseForKey:(NSString *)featureKey onBlocked:(nullable void (^)(void))onBlocked;
+ (void)endUseForKey:(NSString *)featureKey;
+ (void)notifyAvailabilityChanged;

/// Re-apply schedule state (tab bar, active tab) on the main thread — e.g. after window/limit changes.
+ (void)syncScheduleEnforcement;
+ (void)enforceLeavingFeatureIfActive:(NSString *)featureKey;

+ (NSString *)formattedTimeFromMinutes:(NSInteger)minutes;

@end

NS_ASSUME_NONNULL_END

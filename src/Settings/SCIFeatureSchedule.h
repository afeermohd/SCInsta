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

/// Bottom-nav surface intents (FEED, CLIPS, SEARCH) hidden when schedule blocks the feature.
+ (BOOL)isMainAppSurfaceAllowed:(NSString *)tabStringFromSurfaceIntent;

+ (void)beginUseForKey:(NSString *)featureKey onBlocked:(nullable void (^)(void))onBlocked;
+ (void)endUseForKey:(NSString *)featureKey;
+ (void)notifyAvailabilityChanged;

+ (NSString *)formattedTimeFromMinutes:(NSInteger)minutes;

@end

NS_ASSUME_NONNULL_END

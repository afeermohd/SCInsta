#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Daily time windows and per-window usage limits for Instagram surfaces.
@interface SCIFeatureSchedule : NSObject

+ (BOOL)isScheduleEnabledForKey:(NSString *)featureKey;
+ (BOOL)isAvailableForKey:(NSString *)featureKey;
+ (NSTimeInterval)remainingSecondsForKey:(NSString *)featureKey;
+ (NSString *)unavailableReasonForKey:(NSString *)featureKey;

+ (void)beginUseForKey:(NSString *)featureKey onBlocked:(nullable void (^)(void))onBlocked;
+ (void)endUseForKey:(NSString *)featureKey;

+ (void)showBlockOverlayOnViewController:(UIViewController *)viewController featureKey:(NSString *)featureKey;
+ (void)hideBlockOverlayOnViewController:(UIViewController *)viewController;

+ (NSString *)formattedTimeFromMinutes:(NSInteger)minutes;

@end

NS_ASSUME_NONNULL_END

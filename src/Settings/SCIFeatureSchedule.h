#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const SCIFeatureScheduleAvailabilityChangedNotification;

/// Limited surfaces. Each can be toggled on its own; all share one window and one budget.
FOUNDATION_EXPORT NSString *const SCIScheduleFeedPostsKey;  // posts in the home feed
FOUNDATION_EXPORT NSString *const SCIScheduleStoriesKey;    // stories tray + story viewer
FOUNDATION_EXPORT NSString *const SCIScheduleReelsKey;      // reels tab + reels viewer
FOUNDATION_EXPORT NSString *const SCIScheduleExploreKey;    // explore grid (search always works)

/// One shared daily window + one shared usage budget for the limited surfaces.
/// Time spent on any limited surface counts against the same budget. When the budget runs out or the
/// window closes while a limited surface is on screen, the app is force-closed.
@interface SCIFeatureSchedule : NSObject

/// All feature keys that can be limited.
+ (NSArray<NSString *> *)limitedFeatureKeys;
+ (BOOL)isLimitedFeatureKey:(NSString *)featureKey;

+ (BOOL)isScheduleEnabled;
/// YES when inside the window and the shared budget isn't used up (or limits are off).
+ (BOOL)isUsageAllowed;
+ (NSTimeInterval)remainingSeconds;

/// Limits are on and this surface's own toggle is on.
+ (BOOL)isScheduleEnabledForKey:(NSString *)featureKey;
/// The surface is limited and currently out of time (outside the window or budget used up).
+ (BOOL)isBlockedForKey:(NSString *)featureKey;
+ (NSString *)unavailableReason;

/// Bottom-nav surface intents; only the reels tab (CLIPS) is ever hidden.
+ (BOOL)isMainAppSurfaceAllowed:(NSString *)tabStringFromSurfaceIntent;

/// Whether the user may open this feature via tab bar / navigation.
+ (BOOL)isFeatureNavigationAllowed:(NSString *)featureKey;

/// Start/stop counting time for a limited surface that is on screen. `owner` is the view controller
/// showing it, so several controllers for the same feature don't cancel each other out.
+ (void)beginUseForKey:(NSString *)featureKey owner:(id)owner;
+ (void)endUseForKey:(NSString *)featureKey owner:(id)owner;
+ (void)notifyAvailabilityChanged;

/// Re-apply schedule state (tab bar, active tab) on the main thread.
+ (void)syncScheduleEnforcement;
+ (void)enforceLeavingFeatureIfActive:(NSString *)featureKey;

+ (NSString *)formattedTimeFromMinutes:(NSInteger)minutes;

@end

NS_ASSUME_NONNULL_END

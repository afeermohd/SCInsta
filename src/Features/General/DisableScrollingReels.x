#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import "../../Settings/SCIFeatureSchedule.h"

// Also locks scrolling when reels are out of time (feature limits), so a shared reel can be watched
// but not used to scroll into more reels.
static BOOL SCIShouldDisableReelScrolling(void) {
    return [SCIUtils getBoolPref:@"disable_scrolling_reels"] || [SCIFeatureSchedule isBlockedForKey:SCIScheduleReelsKey];
}

%hook IGUnifiedVideoCollectionView
- (void)didMoveToWindow {
    %orig;

    if (SCIShouldDisableReelScrolling()) {
        NSLog(@"[SCInsta] Disabling scrolling reels");
        
        self.scrollEnabled = false;
    }
}

- (void)setScrollEnabled:(BOOL)arg1 {
    if (SCIShouldDisableReelScrolling()) {
        NSLog(@"[SCInsta] Disabling scrolling reels");
        
        return %orig(NO);
    }

    return %orig;
}
%end

// Disable auto-scrolling reels
%hook _TtC19IGSundialAutoScroll19IGSundialAutoScroll
- (void)setIsEnabled:(BOOL)enabled {
    if (SCIShouldDisableReelScrolling()) {
        %orig(NO);
    }
    else {
        %orig(enabled);
    }
}
%end
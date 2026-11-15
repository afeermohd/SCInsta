#import "../../Utils.h"
#import "../../Settings/SCIFeatureSchedule.h"
#import <objc/message.h>

// Feature limits: feed posts, stories, reels and the explore grid share one window + one usage budget
// (see SCIFeatureSchedule). Time is counted while a limited surface is on screen; when the budget runs
// out or the window closes, SCIFeatureSchedule force-closes the app.
//
// Out of time:
//   - Feed tab stays (camera + stories live there); posts and/or the stories tray are removed.
//   - Explore tab stays and search works; only the grid is hidden.
//   - Reels tab is hidden (Navigation.xm). Reels/posts opened from DMs, profiles etc. still open,
//     silently, but can't be scrolled.

// MARK: - Helpers

static void SCIReloadListAdapterOfViewController(id viewController) {
    for (NSString *key in @[ @"listAdapter", @"_listAdapter", @"adapter", @"_adapter" ]) {
        id adapter = nil;
        @try {
            adapter = [viewController valueForKey:key];
        } @catch (__unused NSException *exception) {
            continue;
        }
        if ([adapter respondsToSelector:@selector(performUpdatesAnimated:completion:)]) {
            ((void (*)(id, SEL, BOOL, id))objc_msgSend)(adapter, @selector(performUpdatesAnimated:completion:), YES, nil);
            return;
        }
    }
}

/// The main vertical scroll view of a list screen (first large scroll view, breadth-first).
static UIScrollView *SCIMainScrollViewInView(UIView *root) {
    if (!root) return nil;

    CGFloat minHeight = root.bounds.size.height * 0.5;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    while (queue.count) {
        UIView *view = queue.firstObject;
        [queue removeObjectAtIndex:0];

        if ([view isKindOfClass:[UIScrollView class]] && view.bounds.size.height >= minHeight) {
            return (UIScrollView *)view;
        }
        [queue addObjectsFromArray:view.subviews];
    }
    return nil;
}

/// When posts are out of time, a post opened from DMs/profile is view-only: no scrolling to more posts.
static void SCIApplyPostViewerScrollLock(UIViewController *viewController) {
    if (![SCIFeatureSchedule isBlockedForKey:SCIScheduleFeedPostsKey]) return;

    UIScrollView *scrollView = SCIMainScrollViewInView(viewController.viewIfLoaded);
    if (scrollView.scrollEnabled) {
        scrollView.scrollEnabled = NO;
    }
}

static void SCIApplyExploreGridVisibility(UIViewController *gridController) {
    BOOL blocked = [SCIFeatureSchedule isBlockedForKey:SCIScheduleExploreKey];
    UIView *view = gridController.viewIfLoaded;
    if (view && view.hidden != blocked) {
        view.hidden = blocked;
    }
}

// MARK: - Feed (posts + stories tray)
// Posts / tray removal happens in HideFeedItems.xm; here we track time and refresh on changes.

%hook IGMainFeedViewController
- (void)viewDidLoad {
    %orig;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(sci_scheduleAvailabilityChanged:)
                                                 name:SCIFeatureScheduleAvailabilityChangedNotification
                                               object:nil];
}
%new
- (void)sci_scheduleAvailabilityChanged:(NSNotification *)notification {
    SCIReloadListAdapterOfViewController(self);
}
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    [SCIFeatureSchedule beginUseForKey:SCIScheduleFeedPostsKey owner:self];
}
- (void)viewDidDisappear:(BOOL)animated {
    [SCIFeatureSchedule endUseForKey:SCIScheduleFeedPostsKey owner:self];
    %orig;
}
%end

%hook IGMainFeedViewController_objc
- (void)viewDidLoad {
    %orig;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(sci_scheduleAvailabilityChanged:)
                                                 name:SCIFeatureScheduleAvailabilityChangedNotification
                                               object:nil];
}
%new
- (void)sci_scheduleAvailabilityChanged:(NSNotification *)notification {
    SCIReloadListAdapterOfViewController(self);
}
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    [SCIFeatureSchedule beginUseForKey:SCIScheduleFeedPostsKey owner:self];
}
- (void)viewDidDisappear:(BOOL)animated {
    [SCIFeatureSchedule endUseForKey:SCIScheduleFeedPostsKey owner:self];
    %orig;
}
%end

// MARK: - Stories viewer

%hook IGStoryViewerViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    [SCIFeatureSchedule beginUseForKey:SCIScheduleStoriesKey owner:self];
}
- (void)viewDidDisappear:(BOOL)animated {
    [SCIFeatureSchedule endUseForKey:SCIScheduleStoriesKey owner:self];
    %orig;
}
%end

// MARK: - Reels
// Out of time, the reels viewer still opens (e.g. a reel shared in DMs) with scrolling disabled
// (DisableScrollingReels.x). Time only counts while in time.

%hook IGSundialFeedViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    [SCIFeatureSchedule beginUseForKey:SCIScheduleReelsKey owner:self];
}
- (void)viewDidDisappear:(BOOL)animated {
    [SCIFeatureSchedule endUseForKey:SCIScheduleReelsKey owner:self];
    %orig;
}
%end

// MARK: - Single post viewers (shared posts, profile posts)

%hook IGContextualFeedViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    SCIApplyPostViewerScrollLock(self);
}
- (void)viewDidLayoutSubviews {
    %orig;
    SCIApplyPostViewerScrollLock(self);
}
%end

%hook IGChainingFeedViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    SCIApplyPostViewerScrollLock(self);
}
- (void)viewDidLayoutSubviews {
    %orig;
    SCIApplyPostViewerScrollLock(self);
}
%end

%hook IGVideoFeedViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    SCIApplyPostViewerScrollLock(self);
}
- (void)viewDidLayoutSubviews {
    %orig;
    SCIApplyPostViewerScrollLock(self);
}
%end

// MARK: - Explore (grid only; search always available)

%hook IGExploreGridViewController
- (void)viewDidLoad {
    %orig;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(sci_scheduleAvailabilityChanged:)
                                                 name:SCIFeatureScheduleAvailabilityChangedNotification
                                               object:nil];
    SCIApplyExploreGridVisibility(self);
}
%new
- (void)sci_scheduleAvailabilityChanged:(NSNotification *)notification {
    SCIApplyExploreGridVisibility(self);
}
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    SCIApplyExploreGridVisibility(self);
}
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    [SCIFeatureSchedule beginUseForKey:SCIScheduleExploreKey owner:self];
}
- (void)viewDidDisappear:(BOOL)animated {
    [SCIFeatureSchedule endUseForKey:SCIScheduleExploreKey owner:self];
    %orig;
}
%end

%hook IGExploreViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (![SCIFeatureSchedule isBlockedForKey:SCIScheduleExploreKey]) return;

    // Hide the loading placeholder grid too.
    UIView *shimmeringGridView = [SCIUtils getIvarForObj:self name:"_shimmeringGridView"];
    if ([shimmeringGridView isKindOfClass:[UIView class]]) {
        shimmeringGridView.hidden = YES;
    }
}
%end

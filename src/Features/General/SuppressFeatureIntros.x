#import "../../Utils.h"
#import "../../InstagramHeaders.h"

static BOOL SCIShouldSuppressFeatureIntros(void) {
    return [SCIUtils getBoolPref:@"suppress_feature_intros"];
}

static BOOL SCIViewControllerLooksLikeFeatureIntro(UIViewController *viewController);
static BOOL SCITextLooksLikeFeatureIntro(NSString *text);

static NSString *SCICollectVisibleTextInView(UIView *view, NSUInteger depth) {
    if (!view || depth > 25) return @"";

    NSMutableArray<NSString *> *parts = [NSMutableArray array];

    if (view.accessibilityLabel.length) [parts addObject:view.accessibilityLabel];
    if (view.accessibilityHint.length) [parts addObject:view.accessibilityHint];
    if (view.accessibilityValue.length) [parts addObject:view.accessibilityValue];

    if ([view isKindOfClass:[UILabel class]]) {
        UILabel *label = (UILabel *)view;
        if (label.text.length) [parts addObject:label.text];
        if (label.attributedText.string.length) [parts addObject:label.attributedText.string];
    } else if ([view isKindOfClass:[UITextView class]]) {
        UITextView *tv = (UITextView *)view;
        if (tv.text.length) [parts addObject:tv.text];
    } else if ([view isKindOfClass:[UIButton class]]) {
        UIButton *button = (UIButton *)view;
        if (button.currentTitle.length) [parts addObject:button.currentTitle];
    }

    for (UIView *sub in view.subviews) {
        NSString *subText = SCICollectVisibleTextInView(sub, depth + 1);
        if (subText.length) [parts addObject:subText];
    }

    return [parts componentsJoinedByString:@" "];
}

static BOOL SCIClassNameSignalsFeatureIntro(NSString *name) {
    if (!name.length) return NO;
    NSString *lower = name.lowercaseString;
    if ([lower containsString:@"friendsmap"] || [lower containsString:@"friends_map"]) return YES;
    if ([lower containsString:@"instagrammap"]) return YES;
    if ([lower containsString:@"mapnux"] || [lower containsString:@"map_nux"]) return YES;
    if ([lower containsString:@"featureintro"] || [lower containsString:@"feature_intro"]) return YES;
    if ([lower containsString:@"quickpromotion"]) return YES;
    if ([lower containsString:@"introducing"] && [lower containsString:@"map"]) return YES;
    return NO;
}

static UIViewController *SCIRepresentativeContentViewController(UIViewController *viewController) {
    if (!viewController) return nil;

    if ([viewController isKindOfClass:[UINavigationController class]]) {
        return [(UINavigationController *)viewController visibleViewController] ?: viewController;
    }

    for (NSString *key in @[ @"contentViewController", @"viewController", @"rootViewController", @"childViewController" ]) {
        @try {
            id value = [viewController valueForKey:key];
            if ([value isKindOfClass:[UIViewController class]]) {
                return (UIViewController *)value;
            }
        } @catch (__unused NSException *exception) {
        }
    }

    if (viewController.childViewControllers.count == 1) {
        return viewController.childViewControllers.firstObject;
    }

    return viewController;
}

static BOOL SCIViewControllerTreeLooksLikeFeatureIntro(UIViewController *viewController, NSUInteger depth) {
    if (!viewController || depth > 6) return NO;

    NSString *className = NSStringFromClass([viewController class]);
    if (SCIClassNameSignalsFeatureIntro(className)) return YES;

    if (SCIViewControllerLooksLikeFeatureIntro(viewController)) return YES;

    UIViewController *content = SCIRepresentativeContentViewController(viewController);
    if (content != viewController && SCIViewControllerTreeLooksLikeFeatureIntro(content, depth + 1)) {
        return YES;
    }

    for (UIViewController *child in viewController.childViewControllers) {
        if (SCIViewControllerTreeLooksLikeFeatureIntro(child, depth + 1)) {
            return YES;
        }
    }

    if (viewController.presentedViewController &&
        SCIViewControllerTreeLooksLikeFeatureIntro(viewController.presentedViewController, depth + 1)) {
        return YES;
    }

    return NO;
}

static BOOL SCIIsPartialModalSheetViewController(UIViewController *viewController) {
    if (!viewController) return NO;
    NSString *name = NSStringFromClass([viewController class]);
    return [name containsString:@"IGPartialModalSheetViewController"];
}

static void SCIRemoveViewFromHierarchy(UIView *view) {
    if (!view || !view.superview) return;
    [view removeFromSuperview];
}

static void SCIRemovePartialModalChromeFromSheet(UIViewController *sheet) {
    if (!sheet) return;

    for (NSString *key in @[ @"_dimmingView", @"_maskingView", @"_blurBackgroundView", @"_backgroundView", @"_containerView" ]) {
        @try {
            SCIRemoveViewFromHierarchy([sheet valueForKey:key]);
        } @catch (__unused NSException *exception) {
        }
    }

    SCIRemoveViewFromHierarchy(sheet.view);
}

static BOOL SCIViewLooksLikePartialModalDimmingOverlay(UIView *view) {
    if (!view || view.hidden || view.alpha < 0.05) return NO;

    NSString *name = NSStringFromClass([view class]);
    if (![name containsString:@"DelegatedHitTest"] && ![name containsString:@"Dimming"]) {
        return NO;
    }

    if (view.alpha > 0.95) return NO;

    UIWindow *window = view.window;
    if (!window) return NO;

    CGRect frameInWindow = [view convertRect:view.bounds toView:window];
    CGFloat viewArea = CGRectGetWidth(frameInWindow) * CGRectGetHeight(frameInWindow);
    CGFloat windowArea = CGRectGetWidth(window.bounds) * CGRectGetHeight(window.bounds);
    if (windowArea <= 0 || viewArea < windowArea * 0.75) return NO;

    return SCITextLooksLikeFeatureIntro(SCICollectVisibleTextInView(view, 0)) == NO;
}

static void SCICleanupOrphanPartialModalDimmingOverlays(void) {
    if (!SCIShouldSuppressFeatureIntros()) return;

    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        for (UIView *subview in [window.subviews copy]) {
            if (SCIViewLooksLikePartialModalDimmingOverlay(subview)) {
                [subview removeFromSuperview];
                NSLog(@"[SCInsta] Removed orphan partial-modal dimming overlay");
            }
        }
    }
}

static void SCITeardownIntroViewController(UIViewController *viewController) {
    if (!viewController) return;

    if (SCIIsPartialModalSheetViewController(viewController)) {
        SCIRemovePartialModalChromeFromSheet(viewController);
    }

    if (viewController.presentingViewController) {
        [viewController.presentingViewController dismissViewControllerAnimated:NO completion:nil];
        SCICleanupOrphanPartialModalDimmingOverlays();
        return;
    }

    if (viewController.parentViewController) {
        [viewController willMoveToParentViewController:nil];
        [viewController.view removeFromSuperview];
        [viewController removeFromParentViewController];
        SCICleanupOrphanPartialModalDimmingOverlays();
    }
}

static void SCIHandleBlockedIntroPresentation(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        SCICleanupOrphanPartialModalDimmingOverlays();
    });
}

static BOOL SCITextLooksLikeFeatureIntro(NSString *text) {
    if (!text.length) return NO;
    NSString *lower = text.lowercaseString;
    if ([lower containsString:@"introducing instagram map"]) return YES;
    if ([lower containsString:@"introducing"] && [lower containsString:@"map"]) return YES;
    if ([lower containsString:@"instagram map"] &&
        ([lower containsString:@"introducing"] || [lower containsString:@"discover"] || [lower containsString:@"see"])) {
        return YES;
    }
    if ([lower hasPrefix:@"introducing"]) return YES;
    return NO;
}

static void SCIStripIntroOverlayIfPresentInView(UIView *view) {
    if (!view || !SCIShouldSuppressFeatureIntros()) return;

    NSString *text = SCICollectVisibleTextInView(view, 0);
    if (!SCITextLooksLikeFeatureIntro(text)) return;

    [view removeFromSuperview];
    NSLog(@"[SCInsta] Removed feature intro overlay from hierarchy");
}

static BOOL SCIViewControllerLooksLikeFeatureIntro(UIViewController *viewController) {
    if (!viewController) return NO;

    if ([viewController isKindOfClass:[UIAlertController class]]) {
        UIAlertController *alert = (UIAlertController *)viewController;
        NSString *blob = [NSString stringWithFormat:@"%@ %@", alert.title ?: @"", alert.message ?: @""];
        if (SCITextLooksLikeFeatureIntro(blob)) return YES;
    }

    if (viewController.title.length && SCITextLooksLikeFeatureIntro(viewController.title)) {
        return YES;
    }

    if (SCITextLooksLikeFeatureIntro(SCICollectVisibleTextInView(viewController.view, 0))) {
        return YES;
    }

    return NO;
}

static BOOL SCIIsBlockedIntroPresentationClass(UIViewController *viewController) {
    NSString *name = NSStringFromClass([viewController class]);

    if ([name containsString:@"Bloks"] && ([name containsString:@"Modal"] || [name containsString:@"Sheet"])) return YES;
    if ([name containsString:@"BottomSheet"] && [name containsString:@"Bloks"]) return YES;
    if (SCIClassNameSignalsFeatureIntro(name)) return YES;

    return NO;
}

static BOOL SCIShouldBlockPresentationOfViewController(UIViewController *viewController) {
    if (!SCIShouldSuppressFeatureIntros() || !viewController) return NO;

    if (SCIViewControllerTreeLooksLikeFeatureIntro(viewController, 0)) return YES;
    if (SCIIsBlockedIntroPresentationClass(viewController)) return YES;

    return NO;
}

static BOOL SCIInboxShouldBlockPartialModalPresentation(UIViewController *viewController) {
    if (!SCIShouldSuppressFeatureIntros() || !viewController) return NO;
    if (SCIShouldBlockPresentationOfViewController(viewController)) return YES;

    NSString *name = NSStringFromClass([viewController class]);
    if ([name containsString:@"IGPartialModalSheetViewController"]) return YES;
    if ([name containsString:@"IGPartialModalSheetNavigationController"]) return YES;

    return NO;
}

%hook IGDirectNUXManager

- (void)showDialogOfTypeIfNecessary:(unsigned long long)type
           presentingViewController:(id)pvc
            alreadyPresentedHandler:(id)alreadyPresented
             confirmActionHandler:(id)confirm
              cancelActionHandler:(id)cancel {
    if (SCIShouldSuppressFeatureIntros()) {
        [self markTooltipOfTypeAsCompleted:type];
        [self markNuxAsCompletedWithKey:@"friends_map"];
        return;
    }
    %orig;
}

- (void)showTooltipOfTypeIfNecessary:(unsigned long long)type
                tooltipTitleOverride:(id)title
                          anchorView:(id)anchor
                         anchorPoint:(struct CGPoint)point
                              offset:(struct CGPoint)offset
                              inView:(id)view
                           direction:(long long)direction
                  willDisplayHandler:(id)willDisplay
                          completion:(id)completion
                         launcherSet:(id)set {
    if (SCIShouldSuppressFeatureIntros()) {
        [self markTooltipOfTypeAsCompleted:type];
        return;
    }
    %orig;
}

- (void)showTooltipOfTypeIfNecessary:(unsigned long long)type
                tooltipTitleOverride:(id)title
                   anchoredAboveView:(id)anchor
                              inView:(id)view
                              offset:(struct CGPoint)offset
                         launcherSet:(id)set {
    if (SCIShouldSuppressFeatureIntros()) {
        [self markTooltipOfTypeAsCompleted:type];
        return;
    }
    %orig;
}

- (void)showBannerOfTypeIfNecessary:(unsigned long long)type anchorView:(id)anchor inView:(id)view {
    if (SCIShouldSuppressFeatureIntros()) {
        [self markTooltipOfTypeAsCompleted:type];
        return;
    }
    %orig;
}

- (_Bool)canDisplayTooltipOfType:(unsigned long long)type {
    if (SCIShouldSuppressFeatureIntros()) return NO;
    return %orig;
}

- (_Bool)nuxWithKeyIsCompleted:(id)key {
    if (SCIShouldSuppressFeatureIntros()) return YES;
    return %orig;
}

- (_Bool)canShowNUXBasedOnLastTimestampForKey:(id)key {
    if (SCIShouldSuppressFeatureIntros()) return NO;
    return %orig;
}

%end

%hook IGViewController

- (void)_superPresentViewController:(UIViewController *)viewControllerToPresent animated:(BOOL)flag completion:(id)completion {
    if (SCIShouldBlockPresentationOfViewController(viewControllerToPresent)) {
        NSLog(@"[SCInsta] Blocked feature intro (_superPresent): %@", NSStringFromClass([viewControllerToPresent class]));
        if (completion) ((void (^)(void))completion)();
        SCIHandleBlockedIntroPresentation();
        return;
    }
    %orig;
}

%end

%hook IGMainFeedAppHeaderController

- (void)_superPresentViewController:(UIViewController *)viewControllerToPresent animated:(BOOL)flag completion:(id)completion {
    if (SCIShouldBlockPresentationOfViewController(viewControllerToPresent)) {
        NSLog(@"[SCInsta] Blocked feature intro (feed header _superPresent): %@", NSStringFromClass([viewControllerToPresent class]));
        if (completion) ((void (^)(void))completion)();
        SCIHandleBlockedIntroPresentation();
        return;
    }
    %orig;
}

%end

%hook IGDirectInboxViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (SCIShouldSuppressFeatureIntros()) {
        SCICleanupOrphanPartialModalDimmingOverlays();
    }
}

- (void)presentViewController:(UIViewController *)viewControllerToPresent
                     animated:(BOOL)flag
                   completion:(void (^)(void))completion {
    if (SCIInboxShouldBlockPartialModalPresentation(viewControllerToPresent)) {
        NSLog(@"[SCInsta] Blocked inbox intro (present): %@", NSStringFromClass([viewControllerToPresent class]));
        if (completion) completion();
        SCIHandleBlockedIntroPresentation();
        return;
    }
    %orig;
}

- (void)_superPresentViewController:(UIViewController *)viewControllerToPresent animated:(BOOL)flag completion:(id)completion {
    if (SCIInboxShouldBlockPartialModalPresentation(viewControllerToPresent)) {
        NSLog(@"[SCInsta] Blocked inbox intro (_superPresent): %@", NSStringFromClass([viewControllerToPresent class]));
        if (completion) ((void (^)(void))completion)();
        SCIHandleBlockedIntroPresentation();
        return;
    }
    %orig;
}

%end

%hook UIViewController

- (void)presentViewController:(UIViewController *)viewControllerToPresent
                     animated:(BOOL)flag
                   completion:(void (^)(void))completion {
    if (SCIShouldBlockPresentationOfViewController(viewControllerToPresent)) {
        NSLog(@"[SCInsta] Blocked feature intro (present): %@", NSStringFromClass([viewControllerToPresent class]));
        if (completion) completion();
        SCIHandleBlockedIntroPresentation();
        return;
    }
    %orig;
}

- (void)addChildViewController:(UIViewController *)childController {
    if (SCIShouldBlockPresentationOfViewController(childController)) {
        NSLog(@"[SCInsta] Blocked feature intro (addChild): %@", NSStringFromClass([childController class]));
        SCIHandleBlockedIntroPresentation();
        return;
    }
    %orig;
}

- (void)viewWillAppear:(BOOL)animated {
    if (SCIShouldSuppressFeatureIntros() && SCIViewControllerTreeLooksLikeFeatureIntro(self, 0)) {
        SCITeardownIntroViewController(self);
        return;
    }
    %orig;
}

%end

static BOOL SCIPartialModalSheetShouldBeSuppressed(UIViewController *sheet) {
    if (!SCIShouldSuppressFeatureIntros() || !sheet) return NO;
    if (SCIViewControllerTreeLooksLikeFeatureIntro(sheet, 0)) return YES;

    UIViewController *content = SCIRepresentativeContentViewController(sheet);
    if (content != sheet && SCIViewControllerTreeLooksLikeFeatureIntro(content, 0)) return YES;

    return NO;
}

%hook IGPartialModalSheetViewController

- (void)viewDidLoad {
    %orig;
    if (SCIPartialModalSheetShouldBeSuppressed(self)) {
        SCITeardownIntroViewController(self);
    }
}

- (void)viewWillAppear:(BOOL)animated {
    if (SCIPartialModalSheetShouldBeSuppressed(self)) {
        SCITeardownIntroViewController(self);
        return;
    }
    %orig;
}

- (void)viewDidAppear:(BOOL)animated {
    if (SCIPartialModalSheetShouldBeSuppressed(self)) {
        SCITeardownIntroViewController(self);
        return;
    }
    %orig;
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    if (SCIShouldSuppressFeatureIntros()) {
        SCICleanupOrphanPartialModalDimmingOverlays();
    }
}

%end

%hook IGPartialModalSheetNavigationController

- (void)viewWillAppear:(BOOL)animated {
    if (SCIPartialModalSheetShouldBeSuppressed(self)) {
        SCITeardownIntroViewController(self);
        return;
    }
    %orig;
}

%end

%hook UIWindow

- (void)addSubview:(UIView *)view {
    %orig;
    if (!SCIShouldSuppressFeatureIntros() || !view) return;

    SCIStripIntroOverlayIfPresentInView(view);

    if (SCIViewLooksLikePartialModalDimmingOverlay(view)) {
        dispatch_async(dispatch_get_main_queue(), ^{
            SCICleanupOrphanPartialModalDimmingOverlays();
        });
    }
}

%end

%hook IGDirectNotesTrayRowCell
- (id)listAdapterObjects {
    NSArray *originalObjs = %orig();
    if (!SCIShouldSuppressFeatureIntros()) return originalObjs;

    NSMutableArray *filteredObjs = [NSMutableArray arrayWithCapacity:[originalObjs count]];

    for (id obj in originalObjs) {
        BOOL shouldHide = NO;

        if ([obj isKindOfClass:%c(IGDirectNotesTrayUserViewModel)]) {
            if ([[obj valueForKey:@"notePk"] isEqualToString:@"friends_map"]) {
                shouldHide = YES;
            }
        }

        if (!shouldHide) {
            [filteredObjs addObject:obj];
        }
    }

    return [filteredObjs copy];
}
%end

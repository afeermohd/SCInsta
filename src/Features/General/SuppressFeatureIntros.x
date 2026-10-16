#import "../../Utils.h"
#import "../../InstagramHeaders.h"

static BOOL SCIShouldSuppressFeatureIntros(void) {
    return [SCIUtils getBoolPref:@"suppress_feature_intros"];
}

static NSString *SCICollectVisibleTextInView(UIView *view, NSUInteger depth) {
    if (!view || depth > 25) return @"";

    NSMutableArray<NSString *> *parts = [NSMutableArray array];

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

static BOOL SCITextLooksLikeFeatureIntro(NSString *text) {
    if (!text.length) return NO;
    NSString *lower = text.lowercaseString;
    if ([lower containsString:@"introducing instagram map"]) return YES;
    if ([lower containsString:@"introducing"] && [lower containsString:@"map"]) return YES;
    if ([lower hasPrefix:@"introducing"]) return YES;
    return NO;
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

    if ([name containsString:@"IGPartialModalSheetViewController"]) return YES;
    if ([name containsString:@"Bloks"] && ([name containsString:@"Modal"] || [name containsString:@"Sheet"])) return YES;

    return NO;
}

static BOOL SCIShouldBlockPresentationOfViewController(UIViewController *viewController) {
    if (!SCIShouldSuppressFeatureIntros() || !viewController) return NO;
    return SCIViewControllerLooksLikeFeatureIntro(viewController);
}

static BOOL SCIInboxShouldBlockPresentation(UIViewController *viewControllerToPresent) {
    if (!SCIShouldSuppressFeatureIntros()) return NO;
    if (SCIShouldBlockPresentationOfViewController(viewControllerToPresent)) return YES;
    return SCIIsBlockedIntroPresentationClass(viewControllerToPresent);
}

%hook IGDirectNUXManager

- (void)showDialogOfTypeIfNecessary:(unsigned long long)type
           presentingViewController:(id)pvc
            alreadyPresentedHandler:(id)alreadyPresented
             confirmActionHandler:(id)confirm
              cancelActionHandler:(id)cancel {
    if (SCIShouldSuppressFeatureIntros()) {
        [self markTooltipOfTypeAsCompleted:type];
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
        return;
    }
    %orig;
}

%end

%hook IGDirectInboxViewController

- (void)presentViewController:(UIViewController *)viewControllerToPresent
                     animated:(BOOL)flag
                   completion:(void (^)(void))completion {
    if (SCIInboxShouldBlockPresentation(viewControllerToPresent)) {
        NSLog(@"[SCInsta] Blocked inbox intro (present): %@", NSStringFromClass([viewControllerToPresent class]));
        if (completion) completion();
        return;
    }
    %orig;
}

- (void)_superPresentViewController:(UIViewController *)viewControllerToPresent animated:(BOOL)flag completion:(id)completion {
    if (SCIInboxShouldBlockPresentation(viewControllerToPresent)) {
        NSLog(@"[SCInsta] Blocked inbox intro (_superPresent): %@", NSStringFromClass([viewControllerToPresent class]));
        if (completion) ((void (^)(void))completion)();
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
        return;
    }
    %orig;
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

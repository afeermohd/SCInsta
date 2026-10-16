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

    NSString *viewText = SCICollectVisibleTextInView(viewController.view, 0);
    if (SCITextLooksLikeFeatureIntro(viewText)) return YES;

    return NO;
}

static BOOL SCIIsLikelyIntroPresentationClass(UIViewController *viewController) {
    NSString *name = NSStringFromClass([viewController class]).lowercaseString;
    if ([name containsString:@"bloks"] || [name containsString:@"bottomsheet"] || [name containsString:@"nux"] ||
        [name containsString:@"promo"] || [name containsString:@"dialog"] || [name containsString:@"modal"]) {
        return YES;
    }
    return NO;
}

static void SCISuppressPresentedViewControllerIfIntro(UIViewController *viewController) {
    if (!SCIShouldSuppressFeatureIntros() || !viewController) return;

    if (!SCIViewControllerLooksLikeFeatureIntro(viewController) && !SCIIsLikelyIntroPresentationClass(viewController)) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if (SCIViewControllerLooksLikeFeatureIntro(viewController)) {
            NSLog(@"[SCInsta] Dismissing feature intro: %@", NSStringFromClass([viewController class]));
            [viewController dismissViewControllerAnimated:YES completion:nil];
        }
    });
}

static BOOL SCIShouldBlockPresentationOfViewController(UIViewController *viewController) {
    if (!SCIShouldSuppressFeatureIntros() || !viewController) return NO;

    if (SCIViewControllerLooksLikeFeatureIntro(viewController)) return YES;

    if (SCIIsLikelyIntroPresentationClass(viewController)) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            SCISuppressPresentedViewControllerIfIntro(viewController);
        });
    }

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
        NSLog(@"[SCInsta] Suppressed feature intro (_superPresent): %@", NSStringFromClass([viewControllerToPresent class]));
        if (completion) ((void (^)(void))completion)();
        return;
    }
    %orig;
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (SCIShouldSuppressFeatureIntros() && SCIViewControllerLooksLikeFeatureIntro(self)) {
        NSLog(@"[SCInsta] Dismissing feature intro (viewDidAppear): %@", NSStringFromClass([self class]));
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

%end

%hook UIViewController

- (void)presentViewController:(UIViewController *)viewControllerToPresent
                     animated:(BOOL)flag
                   completion:(void (^)(void))completion {
    if (SCIShouldBlockPresentationOfViewController(viewControllerToPresent)) {
        NSLog(@"[SCInsta] Suppressed feature intro (present): %@", NSStringFromClass([viewControllerToPresent class]));
        if (completion) completion();
        return;
    }
    %orig;
}

%end

#import "../../Utils.h"

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

static BOOL SCIViewControllerLooksLikeFeatureIntro(UIViewController *viewController) {
    if (!viewController) return NO;

    if ([viewController isKindOfClass:[UIAlertController class]]) {
        UIAlertController *alert = (UIAlertController *)viewController;
        NSString *blob = [NSString stringWithFormat:@"%@ %@", alert.title ?: @"", alert.message ?: @""];
        NSString *lower = blob.lowercaseString;
        if ([lower containsString:@"introducing"] || [lower containsString:@"instagram map"]) {
            return YES;
        }
    }

    if (viewController.title.length) {
        NSString *lower = viewController.title.lowercaseString;
        if ([lower containsString:@"introducing"] || [lower containsString:@"instagram map"]) {
            return YES;
        }
    }

    NSString *viewText = SCICollectVisibleTextInView(viewController.view, 0).lowercaseString;
    if ([viewText containsString:@"introducing instagram map"]) return YES;
    if ([viewText containsString:@"introducing"] && [viewText containsString:@"map"]) return YES;

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

%end

%hook UIViewController

- (void)presentViewController:(UIViewController *)viewControllerToPresent
                     animated:(BOOL)flag
                   completion:(void (^)(void))completion {
    if (SCIShouldSuppressFeatureIntros() && SCIViewControllerLooksLikeFeatureIntro(viewControllerToPresent)) {
        NSLog(@"[SCInsta] Suppressed feature intro presentation: %@", NSStringFromClass([viewControllerToPresent class]));
        if (completion) completion();
        return;
    }
    %orig;
}

%end

#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import <objc/runtime.h>

static NSString * const kSCIInstagramMapIntroCompletedKey = @"sci_instagram_map_intro_completed";
static const void *kSCIMapIntroSheetAssociatedKey = &kSCIMapIntroSheetAssociatedKey;
static BOOL SCIIsMarkingInstagramMapIntroCompleted = NO;

static BOOL SCIViewControllerLooksLikeFeatureIntro(UIViewController *viewController);
static BOOL SCITextLooksLikeFeatureIntro(NSString *text);
static BOOL SCIIsInstagramMapIntroSheet(UIViewController *sheet);

static BOOL SCIShouldSuppressFeatureIntros(void) {
    return [SCIUtils getBoolPref:@"suppress_feature_intros"];
}

static BOOL SCIInstagramMapIntroMarkedCompleted(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kSCIInstagramMapIntroCompletedKey];
}

static IGDirectNUXManager *SCINuxManagerFromInboxViewController(id inboxViewController) {
    if (![inboxViewController isKindOfClass:%c(IGDirectInboxViewController)]) return nil;
    @try {
        id manager = [inboxViewController valueForKey:@"_nuxManager"];
        if ([manager isKindOfClass:%c(IGDirectNUXManager)]) {
            return (IGDirectNUXManager *)manager;
        }
    } @catch (__unused NSException *exception) {
    }
    return nil;
}

static IGDirectNUXManager *SCINuxManagerFromViewControllerTree(UIViewController *viewController) {
    if (!viewController) return nil;

    IGDirectNUXManager *manager = SCINuxManagerFromInboxViewController(viewController);
    if (manager) return manager;

    for (UIViewController *child in viewController.childViewControllers) {
        manager = SCINuxManagerFromViewControllerTree(child);
        if (manager) return manager;
    }

    return SCINuxManagerFromViewControllerTree(viewController.presentedViewController);
}

static IGDirectNUXManager *SCINuxManagerFromResponderChain(UIViewController *viewController) {
    if (viewController) {
        UIResponder *responder = viewController.view ?: (UIResponder *)viewController;
        while (responder) {
            IGDirectNUXManager *manager = SCINuxManagerFromInboxViewController(responder);
            if (manager) return manager;
            responder = responder.nextResponder;
        }
    }

    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        IGDirectNUXManager *manager = SCINuxManagerFromViewControllerTree(window.rootViewController);
        if (manager) return manager;
    }

    return nil;
}

static void SCIMarkInstagramMapIntroCompleted(IGDirectNUXManager *nuxManager) {
    if (SCIIsMarkingInstagramMapIntroCompleted) return;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL alreadyMarked = [defaults boolForKey:kSCIInstagramMapIntroCompletedKey];
    [defaults setBool:YES forKey:kSCIInstagramMapIntroCompletedKey];

    NSArray<NSString *> *keys = @[
        @"friends_map",
        @"instagram_map",
        @"direct_friends_map",
        @"direct_map_nux",
        @"map_nux",
        @"direct_inbox_friends_map",
        @"direct_inbox_map_nux",
        @"direct_notes_friends_map",
        @"FRIENDS_MAP",
        @"INSTAGRAM_MAP",
    ];

    for (NSString *key in keys) {
        [defaults setBool:YES forKey:key];
        [defaults setInteger:999 forKey:[NSString stringWithFormat:@"%@_impression_count", key]];
    }
    [defaults synchronize];

    if (alreadyMarked && !nuxManager) return;

    IGDirectNUXManager *manager = nuxManager ?: SCINuxManagerFromResponderChain(nil);
    if (!manager) return;

    SCIIsMarkingInstagramMapIntroCompleted = YES;
    @try {
        for (NSString *key in keys) {
            [manager markNuxAsCompletedWithKey:key];
        }
    } @finally {
        SCIIsMarkingInstagramMapIntroCompleted = NO;
    }
}

static void SCINoteMapIntroSheet(UIViewController *sheet) {
    if (!sheet) return;
    objc_setAssociatedObject(sheet, kSCIMapIntroSheetAssociatedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL SCIMapIntroSheetWasNoted(UIViewController *sheet) {
    if (!sheet) return NO;
    return [objc_getAssociatedObject(sheet, kSCIMapIntroSheetAssociatedKey) boolValue];
}

static void SCIScanPartialModalForMapIntroAndNote(UIViewController *sheet) {
    if (!sheet) return;
    if (SCIIsInstagramMapIntroSheet(sheet)) {
        SCINoteMapIntroSheet(sheet);
    }
}

/// Skip map intro when user opted out, already dismissed once, or toggle is on (never show).
static BOOL SCIShouldSkipInstagramMapIntro(void) {
    return SCIShouldSuppressFeatureIntros() || SCIInstagramMapIntroMarkedCompleted();
}

static BOOL SCIKeyLooksLikeMapIntroNUX(id key) {
    if (![key isKindOfClass:[NSString class]]) return NO;
    NSString *lower = [(NSString *)key lowercaseString];
    return [lower containsString:@"friends_map"] || [lower containsString:@"instagram_map"] ||
           ([lower containsString:@"map"] && [lower containsString:@"nux"]);
}

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

static BOOL SCITextLooksLikeFeatureIntro(NSString *text) {
    if (!text.length) return NO;
    NSString *lower = text.lowercaseString;
    if ([lower containsString:@"introducing instagram map"]) return YES;
    if ([lower containsString:@"introducing"] && [lower containsString:@"map"]) return YES;
    if ([lower containsString:@"instagram map"] &&
        ([lower containsString:@"introducing"] || [lower containsString:@"discover"] || [lower containsString:@"see"])) {
        return YES;
    }
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

    return NO;
}

static BOOL SCIIsInstagramMapIntroSheet(UIViewController *sheet) {
    if (!sheet) return NO;
    return SCIViewControllerTreeLooksLikeFeatureIntro(sheet, 0);
}

static void SCIDismissInstagramMapIntroSheet(UIViewController *sheet) {
    if (!sheet) return;
    if (!SCIIsInstagramMapIntroSheet(sheet) && !SCIMapIntroSheetWasNoted(sheet)) return;

    SCIMarkInstagramMapIntroCompleted(SCINuxManagerFromResponderChain(sheet));

    if (sheet.presentingViewController) {
        [sheet.presentingViewController dismissViewControllerAnimated:NO completion:nil];
        return;
    }

    if (sheet.parentViewController) {
        [sheet willMoveToParentViewController:nil];
        [sheet.view removeFromSuperview];
        [sheet removeFromParentViewController];
    }
}

static BOOL SCIInboxHostedPartialSheet(UIViewController *sheet) {
    UIResponder *responder = sheet.view ?: (UIResponder *)sheet;
    while (responder) {
        if ([responder isKindOfClass:%c(IGDirectInboxViewController)]) return YES;
        responder = responder.nextResponder;
    }
    return NO;
}

static BOOL SCIShouldDismissRepeatMapIntroSheet(UIViewController *sheet) {
    if (!sheet || !SCIInstagramMapIntroMarkedCompleted()) return NO;
    if (![NSStringFromClass([sheet class]) containsString:@"PartialModal"]) return NO;
    if (!SCIInboxHostedPartialSheet(sheet)) return NO;
    return SCIIsInstagramMapIntroSheet(sheet) || SCIMapIntroSheetWasNoted(sheet);
}

static void SCIMarkMapIntroCompletedIfNotedSheet(UIViewController *sheet) {
    if (!sheet) return;
    if (SCIMapIntroSheetWasNoted(sheet) || SCIIsInstagramMapIntroSheet(sheet)) {
        SCIMarkInstagramMapIntroCompleted(SCINuxManagerFromResponderChain(sheet));
    }
}

%hook IGDirectNUXManager

- (void)showDialogOfTypeIfNecessary:(unsigned long long)type
           presentingViewController:(id)pvc
            alreadyPresentedHandler:(id)alreadyPresented
             confirmActionHandler:(id)confirm
              cancelActionHandler:(id)cancel {
    if (SCIShouldSkipInstagramMapIntro()) {
        [self markTooltipOfTypeAsCompleted:type];
        SCIMarkInstagramMapIntroCompleted(self);
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
    if (SCIInstagramMapIntroMarkedCompleted() && SCIKeyLooksLikeMapIntroNUX(key)) return YES;
    if (SCIShouldSuppressFeatureIntros()) return YES;
    return %orig;
}

- (_Bool)canShowNUXBasedOnLastTimestampForKey:(id)key {
    if (SCIShouldSkipInstagramMapIntro() && SCIKeyLooksLikeMapIntroNUX(key)) return NO;
    if (SCIShouldSuppressFeatureIntros()) return NO;
    return %orig;
}

- (void)markNuxAsCompletedWithKey:(id)key {
    %orig;
    if (SCIIsMarkingInstagramMapIntroCompleted) return;
    if (SCIKeyLooksLikeMapIntroNUX(key)) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kSCIInstagramMapIntroCompletedKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

%end

%hook IGDirectInboxViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (SCIShouldSuppressFeatureIntros() && !SCIInstagramMapIntroMarkedCompleted()) {
        SCIMarkInstagramMapIntroCompleted(SCINuxManagerFromResponderChain(self));
    }
}

%end

%hook IGPartialModalSheetViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;

    SCIScanPartialModalForMapIntroAndNote(self);

    if (SCIShouldDismissRepeatMapIntroSheet(self) ||
        (SCIShouldSkipInstagramMapIntro() && SCIIsInstagramMapIntroSheet(self))) {
        dispatch_async(dispatch_get_main_queue(), ^{
            SCIDismissInstagramMapIntroSheet(self);
        });
        return;
    }

    __weak IGPartialModalSheetViewController *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SCIScanPartialModalForMapIntroAndNote(weakSelf);
        if (!weakSelf) return;
        if (SCIShouldDismissRepeatMapIntroSheet(weakSelf) ||
            (SCIShouldSkipInstagramMapIntro() && SCIIsInstagramMapIntroSheet(weakSelf))) {
            SCIDismissInstagramMapIntroSheet(weakSelf);
        }
    });
}

- (void)viewDidDisappear:(BOOL)animated {
    SCIMarkMapIntroCompletedIfNotedSheet(self);
    %orig;
}

%end

%hook IGPartialModalSheetNavigationController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (SCIShouldDismissRepeatMapIntroSheet(self) ||
        (SCIShouldSkipInstagramMapIntro() && SCIIsInstagramMapIntroSheet(self))) {
        dispatch_async(dispatch_get_main_queue(), ^{
            SCIDismissInstagramMapIntroSheet(self);
        });
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    SCIMarkMapIntroCompletedIfNotedSheet(self);
    %orig;
}

%end

%hook IGDirectNotesTrayRowCell
- (id)listAdapterObjects {
    NSArray *originalObjs = %orig();
    if (!SCIShouldSkipInstagramMapIntro()) return originalObjs;

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

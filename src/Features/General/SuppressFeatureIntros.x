#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import <objc/runtime.h>

static NSString * const kSCIInstagramMapIntroCompletedKey = @"sci_instagram_map_intro_completed";
static NSString * const kSCIInstagramMapIntroPromotionIDsKey = @"sci_instagram_map_intro_promotion_ids";
static NSString * const kSCIInstantsIntroCompletedKey = @"sci_instants_intro_completed";
static NSString * const kSCIInstantsIntroPromotionIDsKey = @"sci_instants_intro_promotion_ids";
static const void *kSCIMapIntroSheetAssociatedKey = &kSCIMapIntroSheetAssociatedKey;
static const void *kSCIMapIntroScanAssociatedKey = &kSCIMapIntroScanAssociatedKey;
static const void *kSCIMapIntroDismissingAssociatedKey = &kSCIMapIntroDismissingAssociatedKey;
static const void *kSCIMapIntroPromoVisibleAssociatedKey = &kSCIMapIntroPromoVisibleAssociatedKey;

// Objective-C entry points verified in the decrypted Instagram 418.2.0 binary.
// Logos binds this local name to the Swift runtime class in %ctor.
@interface SCIMapPromoDialogView : UIView
- (void)secondaryActionTapped:(id)sender;
@end

// Each intro is remembered separately: dismissing the Map intro must not hide the Instants one.
typedef NS_ENUM(NSInteger, SCIIntroKind) {
    SCIIntroKindNone = 0,
    SCIIntroKindMap = 1,
    SCIIntroKindInstants = 2,
};

static SCIIntroKind SCIViewControllerFeatureIntroKind(UIViewController *viewController);
static SCIIntroKind SCIIntroKindForText(NSString *text);
static SCIIntroKind SCIIntroSheetKind(UIViewController *sheet);

static BOOL SCIShouldSuppressFeatureIntros(void) {
    return [SCIUtils getBoolPref:@"suppress_feature_intros"];
}

static NSString *SCIIntroCompletedKey(SCIIntroKind kind) {
    switch (kind) {
        case SCIIntroKindMap: return kSCIInstagramMapIntroCompletedKey;
        case SCIIntroKindInstants: return kSCIInstantsIntroCompletedKey;
        default: return nil;
    }
}

static NSString *SCIIntroPromotionIDsKey(SCIIntroKind kind) {
    switch (kind) {
        case SCIIntroKindMap: return kSCIInstagramMapIntroPromotionIDsKey;
        case SCIIntroKindInstants: return kSCIInstantsIntroPromotionIDsKey;
        default: return nil;
    }
}

static BOOL SCIIntroMarkedCompleted(SCIIntroKind kind) {
    NSString *key = SCIIntroCompletedKey(kind);
    return key && [[NSUserDefaults standardUserDefaults] boolForKey:key];
}

static void SCIMarkIntroCompleted(SCIIntroKind kind) {
    // Do not write guessed Instagram keys or call back into the hooked NUX manager.
    // QP's original finish callback remains responsible for its own event datastore.
    NSString *key = SCIIntroCompletedKey(kind);
    if (!key) return;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults boolForKey:key]) return;
    [defaults setBool:YES forKey:key];
    [defaults synchronize];
}

static void SCINoteIntroSheet(id sheet, SCIIntroKind kind) {
    if (!sheet || kind == SCIIntroKindNone) return;
    objc_setAssociatedObject(sheet, kSCIMapIntroSheetAssociatedKey, @(kind), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static SCIIntroKind SCINotedIntroKind(id sheet) {
    if (!sheet) return SCIIntroKindNone;
    return (SCIIntroKind)[objc_getAssociatedObject(sheet, kSCIMapIntroSheetAssociatedKey) integerValue];
}

/// Skip an intro when the toggle is on (never show) or the user already dismissed it once.
static BOOL SCIShouldSkipIntro(SCIIntroKind kind) {
    if (kind == SCIIntroKindNone) return NO;
    return SCIShouldSuppressFeatureIntros() || SCIIntroMarkedCompleted(kind);
}

/// Cheap gate before inspecting a dialog or sheet: could any intro be skipped right now?
static BOOL SCIShouldSkipAnyIntro(void) {
    return SCIShouldSkipIntro(SCIIntroKindMap) || SCIShouldSkipIntro(SCIIntroKindInstants);
}

static SCIIntroKind SCIIntroKindForNUXKey(id key) {
    if (![key isKindOfClass:[NSString class]]) return SCIIntroKindNone;
    NSString *lower = [(NSString *)key lowercaseString];
    if ([lower containsString:@"friends_map"] || [lower containsString:@"instagram_map"] ||
        ([lower containsString:@"map"] && [lower containsString:@"nux"])) return SCIIntroKindMap;
    if (([lower containsString:@"quicksnap"] || [lower containsString:@"quick_snap"] || [lower containsString:@"instants"]) &&
        ([lower containsString:@"nux"] || [lower containsString:@"intro"] || [lower containsString:@"try"])) return SCIIntroKindInstants;
    return SCIIntroKindNone;
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

static SCIIntroKind SCIIntroKindForClassName(NSString *name) {
    if (!name.length) return SCIIntroKindNone;
    NSString *lower = name.lowercaseString;
    BOOL isIntro = [lower containsString:@"nux"] || [lower containsString:@"intro"] ||
                   [lower containsString:@"onboarding"] || [lower containsString:@"education"];
    if (!isIntro) return SCIIntroKindNone;
    BOOL isMap = [lower containsString:@"friendsmap"] || [lower containsString:@"friends_map"] ||
                 [lower containsString:@"instagrammap"] || [lower containsString:@"instagram_map"] ||
                 [lower containsString:@"mapnux"] || [lower containsString:@"map_nux"];
    if (isMap) return SCIIntroKindMap;
    if ([lower containsString:@"quicksnap"] || [lower containsString:@"instants"]) return SCIIntroKindInstants;
    return SCIIntroKindNone;
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

static SCIIntroKind SCIIntroKindForText(NSString *text) {
    if (!text.length) return SCIIntroKindNone;
    NSString *lower = text.lowercaseString;
    lower = [lower stringByReplacingOccurrencesOfString:@"\\s+" withString:@" " options:NSRegularExpressionSearch range:NSMakeRange(0, lower.length)];
    BOOL isMap = [lower containsString:@"instagram map"] || [lower containsString:@"friends map"];
    if (isMap && ([lower containsString:@"introducing"] || [lower containsString:@"discover"])) return SCIIntroKindMap;
    // Promotional copy only; Instants settings and viewer screens never use these phrases.
    if ([lower containsString:@"instant"] &&
        [lower rangeOfString:@"introducing instants|try instants|meet instants|discover instants|new: instants|instants app|try the instants"
                     options:NSRegularExpressionSearch].location != NSNotFound) return SCIIntroKindInstants;
    return SCIIntroKindNone;
}

static id SCIIntroValueForKey(id object, NSString *key) {
    @try {
        if ([object isKindOfClass:[NSDictionary class]]) return object[key];
        if ([object respondsToSelector:NSSelectorFromString(key)]) return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
    }
    return nil;
}

static SCIIntroKind SCIPromoDialogIntroKind(id dialog) {
    id title = SCIIntroValueForKey(dialog, @"title");
    if ([title isKindOfClass:[NSAttributedString class]]) title = [title string];
    // The promo's title is available before its labels or presentation exist.
    return [title isKindOfClass:[NSString class]] ? SCIIntroKindForText(title) : SCIIntroKindNone;
}

static BOOL SCIHandleIntroPromoDialogBeforeShow(id dialog) {
    SCIIntroKind kind = SCIPromoDialogIntroKind(dialog);
    if (kind == SCIIntroKindNone) {
        // The same dialog object may be configured for a different promotion later.
        objc_setAssociatedObject(dialog, kSCIMapIntroSheetAssociatedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(dialog, kSCIMapIntroDismissingAssociatedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return NO;
    }
    SCINoteIntroSheet(dialog, kind);
    if (!SCIShouldSkipIntro(kind)) return NO;
    if ([objc_getAssociatedObject(dialog, kSCIMapIntroDismissingAssociatedKey) boolValue]) return YES;
    objc_setAssociatedObject(dialog, kSCIMapIntroDismissingAssociatedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // Route through the configured native "Not now" action/delegate, not a
    // fabricated QP event. Never remove the card or its dimming ourselves.
    @try {
        [(SCIMapPromoDialogView *)dialog secondaryActionTapped:nil];
        SCIMarkIntroCompleted(kind);
    } @finally {
        // A skipped, never-attached dialog may be reused for another attempt.
        // Retain the guard only while a visible card is finishing dismissal.
        if (!SCIIntroValueForKey(dialog, @"window")) {
            objc_setAssociatedObject(dialog, kSCIMapIntroDismissingAssociatedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    return YES;
}

static id SCIIntroPromoDialogFromAlertController(id root, Class promoDialogClass) {
    if (![root isKindOfClass:NSClassFromString(@"IGCustomAlertViewController")]) return nil;
    // Verified object ivar in 418.2.0; do not load a VC's view to identify it.
    Ivar alertViewIvar = class_getInstanceVariable([root class], "_alertView");
    const char *encoding = alertViewIvar ? ivar_getTypeEncoding(alertViewIvar) : NULL;
    if (!encoding || encoding[0] != '@') return nil;
    id alertView = object_getIvar(root, alertViewIvar);
    return [alertView isKindOfClass:promoDialogClass] ? alertView : nil;
}

static id SCIIntroPromoDialogFromPopover(id popover, Class promoDialogClass) {
    id navigation = SCIIntroValueForKey(popover, @"navigationController");
    return SCIIntroPromoDialogFromAlertController(SCIIntroValueForKey(navigation, @"topViewController"), promoDialogClass);
}

static id SCIIntroPromoDialogFromPresentation(id controller, Class promoDialogClass) {
    // Only verified native alert hosts. Do not inspect arbitrary VC/view trees or
    // treat a generic Bloks/partial-sheet wrapper as a promotion.
    if ([controller isKindOfClass:NSClassFromString(@"IGPopoverController")]) {
        return SCIIntroPromoDialogFromPopover(controller, promoDialogClass);
    }
    if ([controller isKindOfClass:NSClassFromString(@"IGPopoverNavigationController")]) {
        return SCIIntroPromoDialogFromAlertController(SCIIntroValueForKey(controller, @"topViewController"), promoDialogClass);
    }
    return SCIIntroPromoDialogFromAlertController(controller, promoDialogClass);
}

static BOOL SCIHandleNativeIntroPresentation(id controller, Class promoDialogClass) {
    if (!SCIShouldSkipAnyIntro()) return NO;
    id dialog = SCIIntroPromoDialogFromPresentation(controller, promoDialogClass);
    return dialog && SCIHandleIntroPromoDialogBeforeShow(dialog);
}

static void SCIScanIntroPromoDialog(UIView *dialog) {
    if (!dialog.window) return;
    SCIIntroKind kind = SCIPromoDialogIntroKind(dialog);
    if (kind == SCIIntroKindNone) return;
    SCINoteIntroSheet(dialog, kind);
    if (!SCIShouldSkipIntro(kind)) return;
    __weak UIView *weakDialog = dialog;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *currentDialog = weakDialog;
        if (!currentDialog.window) return;
        for (UIResponder *responder = currentDialog; responder; responder = responder.nextResponder) {
            if (![responder isKindOfClass:[UIViewController class]]) continue;
            for (UIViewController *owner = (UIViewController *)responder; owner; owner = owner.parentViewController) {
                if (owner.isBeingPresented || owner.isBeingDismissed) return;
            }
            break;
        }
        SCIHandleIntroPromoDialogBeforeShow(currentDialog);
    });
}

static void SCIWatchIntroPromoDialog(UIView *dialog) {
    NSObject *generation = [NSObject new];
    objc_setAssociatedObject(dialog, kSCIMapIntroScanAssociatedKey, generation, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    SCIScanIntroPromoDialog(dialog);
    __weak UIView *weakDialog = dialog;
    for (NSNumber *delay in @[ @0.25, @0.5, @1.0, @1.5, @2.0 ]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIView *currentDialog = weakDialog;
            if (currentDialog && objc_getAssociatedObject(currentDialog, kSCIMapIntroScanAssociatedKey) == generation) {
                SCIScanIntroPromoDialog(currentDialog);
            }
        });
    }
}

static SCIIntroKind SCIIntroMetadataKind(id value, NSUInteger depth, NSUInteger *budget) {
    if (!value || depth > 6 || *budget == 0) return SCIIntroKindNone;
    --*budget;
    if ([value isKindOfClass:[NSString class]]) {
        SCIIntroKind kind = SCIIntroKindForText(value);
        return kind != SCIIntroKindNone ? kind : SCIIntroKindForClassName(value);
    }
    id title = SCIIntroValueForKey(value, @"title");
    id content = SCIIntroValueForKey(value, @"content");
    if ([title isKindOfClass:[NSString class]] && [content isKindOfClass:[NSString class]]) {
        SCIIntroKind kind = SCIIntroKindForText([NSString stringWithFormat:@"%@ %@", title, content]);
        if (kind != SCIIntroKindNone) return kind;
    }
    if ([value isKindOfClass:[NSDictionary class]]) {
        for (id key in value) {
            SCIIntroKind kind = SCIIntroMetadataKind(key, depth + 1, budget);
            if (kind == SCIIntroKindNone) kind = SCIIntroMetadataKind(value[key], depth + 1, budget);
            if (kind != SCIIntroKindNone) return kind;
            if (*budget == 0) break;
        }
    } else if ([value isKindOfClass:[NSArray class]]) {
        for (id item in value) {
            SCIIntroKind kind = SCIIntroMetadataKind(item, depth + 1, budget);
            if (kind != SCIIntroKindNone) return kind;
            if (*budget == 0) break;
        }
    } else {
        // IGQPPromotion -> IGQPCreative -> Bloks payload. No arbitrary description/KVC walk.
        for (NSString *key in @[ @"qpCreative", @"title", @"content", @"bloksData" ]) {
            SCIIntroKind kind = SCIIntroMetadataKind(SCIIntroValueForKey(value, key), depth + 1, budget);
            if (kind != SCIIntroKindNone) return kind;
        }
    }
    return SCIIntroKindNone;
}

static SCIIntroKind SCIPromotionIntroKind(id promotion) {
    if (!promotion) return SCIIntroKindNone;
    id promotionID = SCIIntroValueForKey(promotion, @"promotionID");
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([promotionID isKindOfClass:[NSString class]]) {
        for (NSNumber *known in @[ @(SCIIntroKindMap), @(SCIIntroKindInstants) ]) {
            SCIIntroKind kind = (SCIIntroKind)known.integerValue;
            if ([[defaults stringArrayForKey:SCIIntroPromotionIDsKey(kind)] containsObject:promotionID]) return kind;
        }
    }

    NSUInteger budget = 256;
    SCIIntroKind kind = SCIIntroMetadataKind(promotion, 0, &budget);
    if (kind == SCIIntroKindNone) return kind;
    if ([promotionID isKindOfClass:[NSString class]] && [promotionID length]) {
        NSString *idsKey = SCIIntroPromotionIDsKey(kind);
        NSArray *knownIDs = [defaults stringArrayForKey:idsKey] ?: @[];
        [defaults setObject:[knownIDs arrayByAddingObject:promotionID] forKey:idsKey];
        [defaults synchronize];
    }
    return kind;
}

static SCIIntroKind SCIViewControllerFeatureIntroKind(UIViewController *viewController) {
    if (!viewController) return SCIIntroKindNone;

    if ([viewController isKindOfClass:[UIAlertController class]]) {
        UIAlertController *alert = (UIAlertController *)viewController;
        NSString *blob = [NSString stringWithFormat:@"%@ %@", alert.title ?: @"", alert.message ?: @""];
        SCIIntroKind kind = SCIIntroKindForText(blob);
        if (kind != SCIIntroKindNone) return kind;
    }

    if (viewController.title.length) {
        SCIIntroKind kind = SCIIntroKindForText(viewController.title);
        if (kind != SCIIntroKindNone) return kind;
    }

    return SCIIntroKindForText(SCICollectVisibleTextInView(viewController.viewIfLoaded, 0));
}

static SCIIntroKind SCIViewControllerTreeIntroKind(UIViewController *viewController, NSUInteger depth) {
    if (!viewController || depth > 6) return SCIIntroKindNone;

    SCIIntroKind kind = SCIIntroKindForClassName(NSStringFromClass([viewController class]));
    if (kind != SCIIntroKindNone) return kind;

    kind = SCIViewControllerFeatureIntroKind(viewController);
    if (kind != SCIIntroKindNone) return kind;

    UIViewController *content = SCIRepresentativeContentViewController(viewController);
    if (content != viewController) {
        kind = SCIViewControllerTreeIntroKind(content, depth + 1);
        if (kind != SCIIntroKindNone) return kind;
    }

    for (UIViewController *child in viewController.childViewControllers) {
        kind = SCIViewControllerTreeIntroKind(child, depth + 1);
        if (kind != SCIIntroKindNone) return kind;
    }

    return SCIIntroKindNone;
}

static SCIIntroKind SCIIntroSheetKind(UIViewController *sheet) {
    if (!sheet) return SCIIntroKindNone;
    return SCIViewControllerTreeIntroKind(sheet, 0);
}

static void SCIDismissIntroSheet(UIViewController *sheet) {
    if (!sheet) return;
    SCIIntroKind kind = SCINotedIntroKind(sheet);
    if (kind == SCIIntroKindNone) kind = SCIIntroSheetKind(sheet);
    if (kind == SCIIntroKindNone) return;
    if ([objc_getAssociatedObject(sheet, kSCIMapIntroDismissingAssociatedKey) boolValue]) return;

    // A navigation/content wrapper may not itself own the modal presentation.
    UIViewController *owner = sheet;
    while (owner.parentViewController) owner = owner.parentViewController;
    if (!owner.presentingViewController || owner.isBeingDismissed || owner.isBeingPresented) return;
    if ([objc_getAssociatedObject(owner, kSCIMapIntroDismissingAssociatedKey) boolValue]) return;
    // Never dismiss a different sheet that has since been placed above this one.
    if (owner.presentedViewController) return;
    SCINoteIntroSheet(sheet, kind);
    objc_setAssociatedObject(sheet, kSCIMapIntroDismissingAssociatedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(owner, kSCIMapIntroDismissingAssociatedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [owner dismissViewControllerAnimated:NO completion:^{
        SCIMarkIntroCompleted(kind);
        objc_setAssociatedObject(sheet, kSCIMapIntroDismissingAssociatedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(owner, kSCIMapIntroDismissingAssociatedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }];
}

static void SCIScanPartialModalForIntro(UIViewController *sheet) {
    if (!sheet.viewIfLoaded.window) return;
    if (SCINotedIntroKind(sheet) == SCIIntroKindNone) {
        SCINoteIntroSheet(sheet, SCIIntroSheetKind(sheet));
    }
    if (SCIShouldSkipIntro(SCINotedIntroKind(sheet))) {
        // Run outside layout/appearance callbacks, after UIKit finishes presentation.
        __weak UIViewController *weakSheet = sheet;
        dispatch_async(dispatch_get_main_queue(), ^{
            UIViewController *currentSheet = weakSheet;
            if (currentSheet.viewIfLoaded.window && SCIShouldSkipIntro(SCINotedIntroKind(currentSheet))) {
                SCIDismissIntroSheet(currentSheet);
            }
        });
    }
}

static void SCIWatchPartialModalForIntro(UIViewController *sheet) {
    // Sheet controllers can be reused for unrelated DM content.
    objc_setAssociatedObject(sheet, kSCIMapIntroSheetAssociatedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSObject *generation = [NSObject new];
    objc_setAssociatedObject(sheet, kSCIMapIntroScanAssociatedKey, generation, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    SCIScanPartialModalForIntro(sheet);
    __weak UIViewController *weakSheet = sheet;
    // Bloks often supplies its copy after the initial presentation/layout.
    for (NSNumber *delay in @[ @0.25, @0.5, @1.0, @1.5, @2.0 ]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIViewController *currentSheet = weakSheet;
            if (currentSheet && objc_getAssociatedObject(currentSheet, kSCIMapIntroScanAssociatedKey) == generation) {
                SCIScanPartialModalForIntro(currentSheet);
            }
        });
    }
}

static void SCIWillDisappearIntroSheet(UIViewController *sheet) {
    // Capture copy before Bloks tears down its labels, even for an early user close.
    SCIIntroKind detected = SCIIntroSheetKind(sheet);
    if (detected != SCIIntroKindNone) SCINoteIntroSheet(sheet, detected);
    SCIIntroKind kind = SCINotedIntroKind(sheet);
    for (UIViewController *owner = sheet; owner; owner = owner.parentViewController) {
        if (owner.isBeingDismissed || owner.isMovingFromParentViewController) {
            if (kind != SCIIntroKindNone) {
                id<UIViewControllerTransitionCoordinator> transition = owner.transitionCoordinator;
                if (transition) {
                    // A cancelled interactive swipe is not a completed dismissal.
                    [transition animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
                        if (!context.isCancelled) SCIMarkIntroCompleted(kind);
                    }];
                } else {
                    SCIMarkIntroCompleted(kind);
                }
            }
            break;
        }
    }
}

static void SCIDidDisappearIntroSheet(UIViewController *sheet) {
    objc_setAssociatedObject(sheet, kSCIMapIntroScanAssociatedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // Being covered by another VC is not a user dismissal.
    if (!sheet.presentingViewController && !sheet.parentViewController) {
        SCIMarkIntroCompleted(SCINotedIntroKind(sheet));
    }
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
    if (SCIIntroMarkedCompleted(SCIIntroKindForNUXKey(key))) return YES;
    if (SCIShouldSuppressFeatureIntros()) return YES;
    return %orig;
}

- (_Bool)canShowNUXBasedOnLastTimestampForKey:(id)key {
    if (SCIShouldSkipIntro(SCIIntroKindForNUXKey(key))) return NO;
    if (SCIShouldSuppressFeatureIntros()) return NO;
    return %orig;
}

- (void)markNuxAsCompletedWithKey:(id)key {
    %orig;
    SCIMarkIntroCompleted(SCIIntroKindForNUXKey(key));
}

%end

// These signatures are present in public 166.0 dumps, not verified 418.x headers.
// Install only when the live app still exposes the same ABI; fail open otherwise.
%group SCIMapIntroQPEligibility
%hook IGQPEligibilityChecker

- (_Bool)_promotionIsEligible:(id)promotion triggerID:(id)trigger surfaceID:(id)surface triggerContext:(id)context additionalEligibilityBlock:(id)block debugInfo:(id *)debugInfo {
    if (SCIShouldSkipAnyIntro() && SCIShouldSkipIntro(SCIPromotionIntroKind(promotion))) return NO;
    return %orig;
}

%end
%end

%group SCIMapIntroQPCompletion
%hook IGQuickPromotionCoordinator

- (void)qpPresenter:(id)presenter finishedWithEvent:(id)event {
    // Capture before %orig clears currentPromotion. Let Instagram record the real event.
    SCIIntroKind kind = SCIPromotionIntroKind(SCIIntroValueForKey(presenter, @"currentPromotion"));
    %orig;
    SCIMarkIntroCompleted(kind);
}

%end
%end

%group SCIMapIntroQPDismissal
%hook IGQPBasePresenter

- (void)dismissCurrentPromotion {
    // Some presenters clear their promotion before notifying the coordinator.
    SCIIntroKind kind = SCIPromotionIntroKind(SCIIntroValueForKey(self, @"currentPromotion"));
    %orig;
    SCIMarkIntroCompleted(kind);
}

%end
%end

%group SCIMapIntroPromoDialog
%hook SCIMapPromoDialogView

- (void)secondaryActionTapped:(id)sender {
    SCIIntroKind kind = SCIPromoDialogIntroKind(self);
    if (kind != SCIIntroKindNone) {
        SCINoteIntroSheet(self, kind);
        objc_setAssociatedObject(self, kSCIMapIntroDismissingAssociatedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    %orig;
    SCIMarkIntroCompleted(kind);
}

- (void)primaryActionTapped:(id)sender {
    SCIIntroKind kind = SCIPromoDialogIntroKind(self);
    if (kind != SCIIntroKindNone) objc_setAssociatedObject(self, kSCIMapIntroDismissingAssociatedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig;
    SCIMarkIntroCompleted(kind);
}

- (void)dismissAlertView:(id)sender {
    SCINoteIntroSheet(self, SCIPromoDialogIntroKind(self));
    %orig;
    // This is a backdrop gesture handler and may ignore taps inside the card.
    // Only removal from its window below confirms an actual outside dismissal.
}

- (void)didMoveToWindow {
    %orig;
    // Fallback for alternate hosts: never manually tear down a displayed card.
    UIView *dialogView = (UIView *)self;
    if (dialogView.window) {
        if (![objc_getAssociatedObject(self, kSCIMapIntroPromoVisibleAssociatedKey) boolValue]) {
            objc_setAssociatedObject(self, kSCIMapIntroSheetAssociatedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(self, kSCIMapIntroDismissingAssociatedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        objc_setAssociatedObject(self, kSCIMapIntroPromoVisibleAssociatedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        SCIWatchIntroPromoDialog(dialogView);
    } else {
        objc_setAssociatedObject(self, kSCIMapIntroScanAssociatedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if ([objc_getAssociatedObject(self, kSCIMapIntroPromoVisibleAssociatedKey) boolValue]) {
            SCIMarkIntroCompleted(SCINotedIntroKind(self));
        }
        objc_setAssociatedObject(self, kSCIMapIntroPromoVisibleAssociatedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

- (void)layoutSubviews {
    %orig;
    SCIScanIntroPromoDialog((UIView *)self);
}

%end
%end

%group SCIMapIntroPopover
%hook IGPopoverController

- (void)present {
    id dialog = SCIIntroPromoDialogFromPopover(self, NSClassFromString(@"_TtC15IGDSPromoDialog19IGDSPromoDialogView"));
    // This is the native card presenter, before it creates any backdrop. Unlike
    // Swift show thunks, this ObjC entry also covers Swift-to-Swift dialog calls.
    if (dialog && SCIHandleIntroPromoDialogBeforeShow(dialog)) return;
    %orig;
}

%end
%end

%group SCIMapIntroNativePresentation
%hook UIViewController

- (void)presentViewController:(UIViewController *)controller animated:(BOOL)animated completion:(void (^)(void))completion {
    // IGPopoverController's fullscreen/direct-call entry points bypass its
    // ObjC -present hook, but converge here before UIKit attaches any backdrop.
    if (SCIHandleNativeIntroPresentation(controller, NSClassFromString(@"_TtC15IGDSPromoDialog19IGDSPromoDialogView"))) {
        // This is a cancellation via native Not now, not a successful UIKit
        // presentation. Do not run its success completion after cancelling it.
        return;
    }
    %orig;
}

%end
%end

%hook IGPartialModalSheetViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    SCIWatchPartialModalForIntro(self);
}

- (void)viewDidLayoutSubviews {
    %orig;
    SCIScanPartialModalForIntro(self);
}

- (void)viewWillDisappear:(BOOL)animated {
    SCIWillDisappearIntroSheet(self);
    %orig;
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    SCIDidDisappearIntroSheet(self);
}

%end

%hook IGPartialModalSheetNavigationController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    SCIWatchPartialModalForIntro(self);
}

- (void)viewDidLayoutSubviews {
    %orig;
    SCIScanPartialModalForIntro(self);
}

- (void)viewWillDisappear:(BOOL)animated {
    SCIWillDisappearIntroSheet(self);
    %orig;
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    SCIDidDisappearIntroSheet(self);
}

%end

// Instagram 455 moved the notes tray row into Swift; %ctor binds whichever class exists.
@interface SCIIntroNotesTrayRowCell : UIView
- (id)listAdapterObjects;
@end

%group SCIMapIntroNotesTray
%hook SCIIntroNotesTrayRowCell
- (id)listAdapterObjects {
    NSArray *originalObjs = %orig;
    if (!SCIShouldSkipIntro(SCIIntroKindMap) || ![originalObjs isKindOfClass:[NSArray class]]) return originalObjs;

    NSMutableArray *filteredObjs = [NSMutableArray arrayWithCapacity:[originalObjs count]];

    for (id obj in originalObjs) {
        BOOL shouldHide = NO;

        if ([obj isKindOfClass:objc_getClass("IGDirectNotesTrayUserViewModel")]) {
            @try {
                id notePk = [obj valueForKey:@"notePk"];
                shouldHide = [notePk isKindOfClass:[NSString class]] && [notePk isEqualToString:@"friends_map"];
            } @catch (__unused NSException *exception) {
            }
        }

        if (!shouldHide) {
            [filteredObjs addObject:obj];
        }
    }

    return [filteredObjs copy];
}
%end
%end

static BOOL SCIIntroMethodHasSignature(Class cls, SEL selector, const char *returnType, NSArray<NSString *> *argumentTypes) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) return NO;
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    if (strcmp(signature.methodReturnType, returnType) != 0 || signature.numberOfArguments != argumentTypes.count + 2) return NO;
    for (NSUInteger index = 0; index < argumentTypes.count; index++) {
        if (strcmp([signature getArgumentTypeAtIndex:index + 2], argumentTypes[index].UTF8String) != 0) return NO;
    }
    return YES;
}

%ctor {
    %init;
    Class promoDialogClass = NSClassFromString(@"_TtC15IGDSPromoDialog19IGDSPromoDialogView");
    if (SCIIntroMethodHasSignature(promoDialogClass, NSSelectorFromString(@"title"), @encode(id), @[]) &&
        SCIIntroMethodHasSignature(promoDialogClass, NSSelectorFromString(@"secondaryActionTapped:"), @encode(void), @[ @"@" ]) &&
        SCIIntroMethodHasSignature(promoDialogClass, NSSelectorFromString(@"primaryActionTapped:"), @encode(void), @[ @"@" ]) &&
        SCIIntroMethodHasSignature(promoDialogClass, NSSelectorFromString(@"dismissAlertView:"), @encode(void), @[ @"@" ])) {
        %init(SCIMapIntroPromoDialog, SCIMapPromoDialogView = promoDialogClass);
        %init(SCIMapIntroNativePresentation);
        Class popoverClass = NSClassFromString(@"IGPopoverController");
        if (SCIIntroMethodHasSignature(popoverClass, NSSelectorFromString(@"present"), @encode(void), @[]) &&
            SCIIntroMethodHasSignature(popoverClass, NSSelectorFromString(@"navigationController"), @encode(id), @[])) {
            %init(SCIMapIntroPopover);
        }
    }
    Class eligibilityClass = NSClassFromString(@"IGQPEligibilityChecker");
    SEL eligibilitySelector = NSSelectorFromString(@"_promotionIsEligible:triggerID:surfaceID:triggerContext:additionalEligibilityBlock:debugInfo:");
    NSArray *eligibilityArguments = @[ @"@", @"@", @"@", @"@", @"@?", @"^@" ];
    if (SCIIntroMethodHasSignature(eligibilityClass, eligibilitySelector, @encode(BOOL), eligibilityArguments)) {
        %init(SCIMapIntroQPEligibility);
    }
    if (SCIIntroMethodHasSignature(NSClassFromString(@"IGQuickPromotionCoordinator"), NSSelectorFromString(@"qpPresenter:finishedWithEvent:"), @encode(void), @[ @"@", @"@" ])) {
        %init(SCIMapIntroQPCompletion);
    }
    if (SCIIntroMethodHasSignature(NSClassFromString(@"IGQPBasePresenter"), NSSelectorFromString(@"dismissCurrentPromotion"), @encode(void), @[])) {
        %init(SCIMapIntroQPDismissal);
    }
    Class notesTrayRowClass = objc_getClass("IGDirectNotesTrayRowCell")
        ?: objc_getClass("_TtC24IGDirectNotesTrayUISwift24IGDirectNotesTrayRowCell");
    if (SCIIntroMethodHasSignature(notesTrayRowClass, @selector(listAdapterObjects), @encode(id), @[])) {
        %init(SCIMapIntroNotesTray, SCIIntroNotesTrayRowCell = notesTrayRowClass);
    }
}

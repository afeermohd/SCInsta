#import "../../Utils.h"
#import "../../InstagramHeaders.h"
#import <objc/runtime.h>

static NSString * const kSCIInstagramMapIntroCompletedKey = @"sci_instagram_map_intro_completed";
static NSString * const kSCIInstagramMapIntroPromotionIDsKey = @"sci_instagram_map_intro_promotion_ids";
static const void *kSCIMapIntroSheetAssociatedKey = &kSCIMapIntroSheetAssociatedKey;
static const void *kSCIMapIntroScanAssociatedKey = &kSCIMapIntroScanAssociatedKey;
static const void *kSCIMapIntroDismissingAssociatedKey = &kSCIMapIntroDismissingAssociatedKey;
static const void *kSCIMapIntroPromoVisibleAssociatedKey = &kSCIMapIntroPromoVisibleAssociatedKey;

// Objective-C entry points verified in the decrypted Instagram 418.2.0 binary.
// Logos binds this local name to the Swift runtime class in %ctor.
@interface SCIMapPromoDialogView : UIView
- (void)secondaryActionTapped:(id)sender;
@end

static BOOL SCIViewControllerLooksLikeFeatureIntro(UIViewController *viewController);
static BOOL SCITextLooksLikeFeatureIntro(NSString *text);
static BOOL SCIIsInstagramMapIntroSheet(UIViewController *sheet);

static BOOL SCIShouldSuppressFeatureIntros(void) {
    return [SCIUtils getBoolPref:@"suppress_feature_intros"];
}

static BOOL SCIInstagramMapIntroMarkedCompleted(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kSCIInstagramMapIntroCompletedKey];
}

static void SCIMarkInstagramMapIntroCompleted(void) {
    // Do not write guessed Instagram keys or call back into the hooked NUX manager.
    // QP's original finish callback remains responsible for its own event datastore.
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults boolForKey:kSCIInstagramMapIntroCompletedKey]) return;
    [defaults setBool:YES forKey:kSCIInstagramMapIntroCompletedKey];
    [defaults synchronize];
}

static void SCINoteMapIntroSheet(id sheet) {
    if (!sheet) return;
    objc_setAssociatedObject(sheet, kSCIMapIntroSheetAssociatedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static BOOL SCIMapIntroSheetWasNoted(id sheet) {
    if (!sheet) return NO;
    return [objc_getAssociatedObject(sheet, kSCIMapIntroSheetAssociatedKey) boolValue];
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
    BOOL isMap = [lower containsString:@"friendsmap"] || [lower containsString:@"friends_map"] ||
                 [lower containsString:@"instagrammap"] || [lower containsString:@"instagram_map"] ||
                 [lower containsString:@"mapnux"] || [lower containsString:@"map_nux"];
    return isMap && ([lower containsString:@"nux"] || [lower containsString:@"intro"] ||
                     [lower containsString:@"onboarding"] || [lower containsString:@"education"]);
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
    lower = [lower stringByReplacingOccurrencesOfString:@"\\s+" withString:@" " options:NSRegularExpressionSearch range:NSMakeRange(0, lower.length)];
    BOOL isMap = [lower containsString:@"instagram map"] || [lower containsString:@"friends map"];
    return isMap && ([lower containsString:@"introducing"] || [lower containsString:@"discover"]);
}

static id SCIIntroValueForKey(id object, NSString *key) {
    @try {
        if ([object isKindOfClass:[NSDictionary class]]) return object[key];
        if ([object respondsToSelector:NSSelectorFromString(key)]) return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
    }
    return nil;
}

static BOOL SCIIsInstagramMapIntroPromoDialog(id dialog) {
    id title = SCIIntroValueForKey(dialog, @"title");
    if ([title isKindOfClass:[NSAttributedString class]]) title = [title string];
    // The promo's title is available before its labels or presentation exist.
    return [title isKindOfClass:[NSString class]] && SCITextLooksLikeFeatureIntro(title);
}

static BOOL SCIHandleMapIntroPromoDialogBeforeShow(id dialog) {
    if (!SCIIsInstagramMapIntroPromoDialog(dialog)) {
        // The same dialog object may be configured for a different promotion later.
        objc_setAssociatedObject(dialog, kSCIMapIntroSheetAssociatedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(dialog, kSCIMapIntroDismissingAssociatedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return NO;
    }
    SCINoteMapIntroSheet(dialog);
    if (!SCIShouldSkipInstagramMapIntro()) return NO;
    if ([objc_getAssociatedObject(dialog, kSCIMapIntroDismissingAssociatedKey) boolValue]) return YES;
    objc_setAssociatedObject(dialog, kSCIMapIntroDismissingAssociatedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // Route through the configured native "Not now" action/delegate, not a
    // fabricated QP event. Never remove the card or its dimming ourselves.
    @try {
        [(SCIMapPromoDialogView *)dialog secondaryActionTapped:nil];
        SCIMarkInstagramMapIntroCompleted();
    } @finally {
        // A skipped, never-attached dialog may be reused for another attempt.
        // Retain the guard only while a visible card is finishing dismissal.
        if (!SCIIntroValueForKey(dialog, @"window")) {
            objc_setAssociatedObject(dialog, kSCIMapIntroDismissingAssociatedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    return YES;
}

static id SCIMapIntroPromoDialogFromAlertController(id root, Class promoDialogClass) {
    if (![root isKindOfClass:NSClassFromString(@"IGCustomAlertViewController")]) return nil;
    // Verified object ivar in 418.2.0; do not load a VC's view to identify it.
    Ivar alertViewIvar = class_getInstanceVariable([root class], "_alertView");
    const char *encoding = alertViewIvar ? ivar_getTypeEncoding(alertViewIvar) : NULL;
    if (!encoding || encoding[0] != '@') return nil;
    id alertView = object_getIvar(root, alertViewIvar);
    return [alertView isKindOfClass:promoDialogClass] ? alertView : nil;
}

static id SCIMapIntroPromoDialogFromPopover(id popover, Class promoDialogClass) {
    id navigation = SCIIntroValueForKey(popover, @"navigationController");
    return SCIMapIntroPromoDialogFromAlertController(SCIIntroValueForKey(navigation, @"topViewController"), promoDialogClass);
}

static id SCIMapIntroPromoDialogFromPresentation(id controller, Class promoDialogClass) {
    // Only verified native alert hosts. Do not inspect arbitrary VC/view trees or
    // treat a generic Bloks/partial-sheet wrapper as a Map promotion.
    if ([controller isKindOfClass:NSClassFromString(@"IGPopoverController")]) {
        return SCIMapIntroPromoDialogFromPopover(controller, promoDialogClass);
    }
    if ([controller isKindOfClass:NSClassFromString(@"IGPopoverNavigationController")]) {
        return SCIMapIntroPromoDialogFromAlertController(SCIIntroValueForKey(controller, @"topViewController"), promoDialogClass);
    }
    return SCIMapIntroPromoDialogFromAlertController(controller, promoDialogClass);
}

static BOOL SCIHandleNativeMapIntroPresentation(id controller, Class promoDialogClass) {
    if (!SCIShouldSkipInstagramMapIntro()) return NO;
    id dialog = SCIMapIntroPromoDialogFromPresentation(controller, promoDialogClass);
    return dialog && SCIHandleMapIntroPromoDialogBeforeShow(dialog);
}

static void SCIScanMapIntroPromoDialog(UIView *dialog) {
    if (!dialog.window || !SCIIsInstagramMapIntroPromoDialog(dialog)) return;
    SCINoteMapIntroSheet(dialog);
    if (!SCIShouldSkipInstagramMapIntro()) return;
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
        SCIHandleMapIntroPromoDialogBeforeShow(currentDialog);
    });
}

static void SCIWatchMapIntroPromoDialog(UIView *dialog) {
    NSObject *generation = [NSObject new];
    objc_setAssociatedObject(dialog, kSCIMapIntroScanAssociatedKey, generation, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    SCIScanMapIntroPromoDialog(dialog);
    __weak UIView *weakDialog = dialog;
    for (NSNumber *delay in @[ @0.25, @0.5, @1.0, @1.5, @2.0 ]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIView *currentDialog = weakDialog;
            if (currentDialog && objc_getAssociatedObject(currentDialog, kSCIMapIntroScanAssociatedKey) == generation) {
                SCIScanMapIntroPromoDialog(currentDialog);
            }
        });
    }
}

static BOOL SCIMapIntroMetadataMatches(id value, NSUInteger depth, NSUInteger *budget) {
    if (!value || depth > 6 || *budget == 0) return NO;
    --*budget;
    if ([value isKindOfClass:[NSString class]]) {
        return SCITextLooksLikeFeatureIntro(value) || SCIClassNameSignalsFeatureIntro(value);
    }
    id title = SCIIntroValueForKey(value, @"title");
    id content = SCIIntroValueForKey(value, @"content");
    if ([title isKindOfClass:[NSString class]] && [content isKindOfClass:[NSString class]] &&
        SCITextLooksLikeFeatureIntro([NSString stringWithFormat:@"%@ %@", title, content])) return YES;
    if ([value isKindOfClass:[NSDictionary class]]) {
        for (id key in value) {
            if (SCIMapIntroMetadataMatches(key, depth + 1, budget) ||
                SCIMapIntroMetadataMatches(value[key], depth + 1, budget)) return YES;
            if (*budget == 0) break;
        }
    } else if ([value isKindOfClass:[NSArray class]]) {
        for (id item in value) {
            if (SCIMapIntroMetadataMatches(item, depth + 1, budget)) return YES;
            if (*budget == 0) break;
        }
    } else {
        // IGQPPromotion -> IGQPCreative -> Bloks payload. No arbitrary description/KVC walk.
        for (NSString *key in @[ @"qpCreative", @"title", @"content", @"bloksData" ]) {
            if (SCIMapIntroMetadataMatches(SCIIntroValueForKey(value, key), depth + 1, budget)) return YES;
        }
    }
    return NO;
}

static BOOL SCIIsInstagramMapIntroPromotion(id promotion) {
    if (!promotion) return NO;
    id promotionID = SCIIntroValueForKey(promotion, @"promotionID");
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSArray *knownIDs = [defaults stringArrayForKey:kSCIInstagramMapIntroPromotionIDsKey] ?: @[];
    if ([promotionID isKindOfClass:[NSString class]] && [knownIDs containsObject:promotionID]) return YES;

    NSUInteger budget = 256;
    if (!SCIMapIntroMetadataMatches(promotion, 0, &budget)) return NO;
    if ([promotionID isKindOfClass:[NSString class]] && [promotionID length]) {
        [defaults setObject:[knownIDs arrayByAddingObject:promotionID] forKey:kSCIInstagramMapIntroPromotionIDsKey];
        [defaults synchronize];
    }
    return YES;
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

    if (SCITextLooksLikeFeatureIntro(SCICollectVisibleTextInView(viewController.viewIfLoaded, 0))) {
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
    if ([objc_getAssociatedObject(sheet, kSCIMapIntroDismissingAssociatedKey) boolValue]) return;

    // A navigation/content wrapper may not itself own the modal presentation.
    UIViewController *owner = sheet;
    while (owner.parentViewController) owner = owner.parentViewController;
    if (!owner.presentingViewController || owner.isBeingDismissed || owner.isBeingPresented) return;
    if ([objc_getAssociatedObject(owner, kSCIMapIntroDismissingAssociatedKey) boolValue]) return;
    // Never dismiss a different sheet that has since been placed above this one.
    if (owner.presentedViewController) return;
    SCINoteMapIntroSheet(sheet);
    objc_setAssociatedObject(sheet, kSCIMapIntroDismissingAssociatedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(owner, kSCIMapIntroDismissingAssociatedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [owner dismissViewControllerAnimated:NO completion:^{
        SCIMarkInstagramMapIntroCompleted();
        objc_setAssociatedObject(sheet, kSCIMapIntroDismissingAssociatedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(owner, kSCIMapIntroDismissingAssociatedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }];
}

static void SCIScanPartialModalForMapIntro(UIViewController *sheet) {
    if (!sheet.viewIfLoaded.window) return;
    if (!SCIMapIntroSheetWasNoted(sheet) && SCIIsInstagramMapIntroSheet(sheet)) {
        SCINoteMapIntroSheet(sheet);
    }
    if (SCIMapIntroSheetWasNoted(sheet) && SCIShouldSkipInstagramMapIntro()) {
        // Run outside layout/appearance callbacks, after UIKit finishes presentation.
        __weak UIViewController *weakSheet = sheet;
        dispatch_async(dispatch_get_main_queue(), ^{
            UIViewController *currentSheet = weakSheet;
            if (currentSheet.viewIfLoaded.window && SCIShouldSkipInstagramMapIntro()) {
                SCIDismissInstagramMapIntroSheet(currentSheet);
            }
        });
    }
}

static void SCIWatchPartialModalForMapIntro(UIViewController *sheet) {
    // Sheet controllers can be reused for unrelated DM content.
    objc_setAssociatedObject(sheet, kSCIMapIntroSheetAssociatedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSObject *generation = [NSObject new];
    objc_setAssociatedObject(sheet, kSCIMapIntroScanAssociatedKey, generation, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    SCIScanPartialModalForMapIntro(sheet);
    __weak UIViewController *weakSheet = sheet;
    // Bloks often supplies its copy after the initial presentation/layout.
    for (NSNumber *delay in @[ @0.25, @0.5, @1.0, @1.5, @2.0 ]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIViewController *currentSheet = weakSheet;
            if (currentSheet && objc_getAssociatedObject(currentSheet, kSCIMapIntroScanAssociatedKey) == generation) {
                SCIScanPartialModalForMapIntro(currentSheet);
            }
        });
    }
}

static void SCIWillDisappearMapIntroSheet(UIViewController *sheet) {
    // Capture copy before Bloks tears down its labels, even for an early user close.
    if (SCIIsInstagramMapIntroSheet(sheet)) SCINoteMapIntroSheet(sheet);
    for (UIViewController *owner = sheet; owner; owner = owner.parentViewController) {
        if (owner.isBeingDismissed || owner.isMovingFromParentViewController) {
            if (SCIMapIntroSheetWasNoted(sheet)) {
                id<UIViewControllerTransitionCoordinator> transition = owner.transitionCoordinator;
                if (transition) {
                    // A cancelled interactive swipe is not a completed dismissal.
                    [transition animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
                        if (!context.isCancelled) SCIMarkInstagramMapIntroCompleted();
                    }];
                } else {
                    SCIMarkInstagramMapIntroCompleted();
                }
            }
            break;
        }
    }
}

static void SCIDidDisappearMapIntroSheet(UIViewController *sheet) {
    objc_setAssociatedObject(sheet, kSCIMapIntroScanAssociatedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // Being covered by another VC is not a user dismissal.
    if (!sheet.presentingViewController && !sheet.parentViewController && SCIMapIntroSheetWasNoted(sheet)) {
        SCIMarkInstagramMapIntroCompleted();
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
    if (SCIKeyLooksLikeMapIntroNUX(key)) {
        SCIMarkInstagramMapIntroCompleted();
    }
}

%end

// These signatures are present in public 166.0 dumps, not verified 418.x headers.
// Install only when the live app still exposes the same ABI; fail open otherwise.
%group SCIMapIntroQPEligibility
%hook IGQPEligibilityChecker

- (_Bool)_promotionIsEligible:(id)promotion triggerID:(id)trigger surfaceID:(id)surface triggerContext:(id)context additionalEligibilityBlock:(id)block debugInfo:(id *)debugInfo {
    if (SCIShouldSkipInstagramMapIntro() && SCIIsInstagramMapIntroPromotion(promotion)) return NO;
    return %orig;
}

%end
%end

%group SCIMapIntroQPCompletion
%hook IGQuickPromotionCoordinator

- (void)qpPresenter:(id)presenter finishedWithEvent:(id)event {
    // Capture before %orig clears currentPromotion. Let Instagram record the real event.
    BOOL isMapIntro = SCIIsInstagramMapIntroPromotion(SCIIntroValueForKey(presenter, @"currentPromotion"));
    %orig;
    if (isMapIntro) SCIMarkInstagramMapIntroCompleted();
}

%end
%end

%group SCIMapIntroQPDismissal
%hook IGQPBasePresenter

- (void)dismissCurrentPromotion {
    // Some presenters clear their promotion before notifying the coordinator.
    BOOL isMapIntro = SCIIsInstagramMapIntroPromotion(SCIIntroValueForKey(self, @"currentPromotion"));
    %orig;
    if (isMapIntro) SCIMarkInstagramMapIntroCompleted();
}

%end
%end

%group SCIMapIntroPromoDialog
%hook SCIMapPromoDialogView

- (void)secondaryActionTapped:(id)sender {
    BOOL isMapIntro = SCIIsInstagramMapIntroPromoDialog(self);
    if (isMapIntro) {
        SCINoteMapIntroSheet(self);
        objc_setAssociatedObject(self, kSCIMapIntroDismissingAssociatedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    %orig;
    if (isMapIntro) SCIMarkInstagramMapIntroCompleted();
}

- (void)primaryActionTapped:(id)sender {
    BOOL isMapIntro = SCIIsInstagramMapIntroPromoDialog(self);
    if (isMapIntro) objc_setAssociatedObject(self, kSCIMapIntroDismissingAssociatedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig;
    if (isMapIntro) SCIMarkInstagramMapIntroCompleted();
}

- (void)dismissAlertView:(id)sender {
    if (SCIIsInstagramMapIntroPromoDialog(self)) SCINoteMapIntroSheet(self);
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
        SCIWatchMapIntroPromoDialog(self);
    } else {
        objc_setAssociatedObject(self, kSCIMapIntroScanAssociatedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if ([objc_getAssociatedObject(self, kSCIMapIntroPromoVisibleAssociatedKey) boolValue] && SCIMapIntroSheetWasNoted(self)) {
            SCIMarkInstagramMapIntroCompleted();
        }
        objc_setAssociatedObject(self, kSCIMapIntroPromoVisibleAssociatedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

- (void)layoutSubviews {
    %orig;
    SCIScanMapIntroPromoDialog(self);
}

%end
%end

%group SCIMapIntroPopover
%hook IGPopoverController

- (void)present {
    id dialog = SCIMapIntroPromoDialogFromPopover(self, NSClassFromString(@"_TtC15IGDSPromoDialog19IGDSPromoDialogView"));
    // This is the native card presenter, before it creates any backdrop. Unlike
    // Swift show thunks, this ObjC entry also covers Swift-to-Swift dialog calls.
    if (dialog && SCIHandleMapIntroPromoDialogBeforeShow(dialog)) return;
    %orig;
}

%end
%end

%group SCIMapIntroNativePresentation
%hook UIViewController

- (void)presentViewController:(UIViewController *)controller animated:(BOOL)animated completion:(void (^)(void))completion {
    // IGPopoverController's fullscreen/direct-call entry points bypass its
    // ObjC -present hook, but converge here before UIKit attaches any backdrop.
    if (SCIHandleNativeMapIntroPresentation(controller, NSClassFromString(@"_TtC15IGDSPromoDialog19IGDSPromoDialogView"))) {
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
    SCIWatchPartialModalForMapIntro(self);
}

- (void)viewDidLayoutSubviews {
    %orig;
    SCIScanPartialModalForMapIntro(self);
}

- (void)viewWillDisappear:(BOOL)animated {
    SCIWillDisappearMapIntroSheet(self);
    %orig;
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    SCIDidDisappearMapIntroSheet(self);
}

%end

%hook IGPartialModalSheetNavigationController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    SCIWatchPartialModalForMapIntro(self);
}

- (void)viewDidLayoutSubviews {
    %orig;
    SCIScanPartialModalForMapIntro(self);
}

- (void)viewWillDisappear:(BOOL)animated {
    SCIWillDisappearMapIntroSheet(self);
    %orig;
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    SCIDidDisappearMapIntroSheet(self);
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
}

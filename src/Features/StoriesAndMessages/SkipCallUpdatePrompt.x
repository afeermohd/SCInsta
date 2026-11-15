#import "../../Utils.h"
#import <objc/runtime.h>

// Instagram gates calls behind IGRTCUpgradePolicy, which shows an "update Instagram" bottom sheet
// (soft nudge) or full-screen interstitial (hard block) when the calling stack thinks the app is too
// old. Both are reached from:
//   +[IGRTCUpgradePolicy showUpgradePolicyIfNeededWithUserSession:isMetaAI:isOngoingCall:continueBlock:]
// which runs continueBlock when no prompt is needed. Skipping straight to continueBlock lets the call
// proceed without the prompt. Note: if Meta's servers truly reject this app version, the call itself can
// still fail to connect — this only removes the client-side gate.
//
// Verified against Instagram 418.2.0 ObjC metadata. Hooks are only installed when the live method has
// the expected type encoding, so a changed signature in a future version is left untouched.

static NSString *const kSCIPolicyEncoding = @"v40@0:8@16B24B28@?32";
static NSString *const kSCISoftNudgeEncoding = @"v36@0:8@16B24@?28";

static BOOL SCIClassMethodHasEncoding(Class cls, SEL sel, NSString *expected) {
    if (!cls) return NO;
    Method m = class_getClassMethod(cls, sel);
    if (!m) return NO;
    const char *types = method_getTypeEncoding(m);
    return types && [expected isEqualToString:@(types)];
}

%group SCISkipCallUpgradePolicy
%hook _TtC18IGRTCUpgradePolicy18IGRTCUpgradePolicy
+ (void)showUpgradePolicyIfNeededWithUserSession:(id)userSession isMetaAI:(BOOL)isMetaAI isOngoingCall:(BOOL)isOngoingCall continueBlock:(void (^)(void))continueBlock {
    if (![SCIUtils getBoolPref:@"skip_call_update_prompt"]) {
        %orig;
        return;
    }

    NSLog(@"[SCInsta] Skipping call upgrade policy prompt");
    if (continueBlock) continueBlock();
}
%end
%end

%group SCISkipCallUpgradeSoftNudge
%hook _TtC18IGRTCUpgradePolicy29IGRTCUpgradePolicyBottomSheet
+ (void)showRTCUpgradePolicySoftNudgeBottomSheetWithUserSession:(id)userSession isMetaAI:(BOOL)isMetaAI notNowCompletionHandler:(void (^)(void))notNowCompletionHandler {
    if (![SCIUtils getBoolPref:@"skip_call_update_prompt"]) {
        %orig;
        return;
    }

    // Behave as if "Not now" was tapped.
    NSLog(@"[SCInsta] Skipping call upgrade soft nudge");
    if (notNowCompletionHandler) notNowCompletionHandler();
}
%end
%end

%ctor {
    Class policy = objc_getClass("_TtC18IGRTCUpgradePolicy18IGRTCUpgradePolicy");
    if (SCIClassMethodHasEncoding(policy, @selector(showUpgradePolicyIfNeededWithUserSession:isMetaAI:isOngoingCall:continueBlock:), kSCIPolicyEncoding)) {
        %init(SCISkipCallUpgradePolicy);
    } else {
        NSLog(@"[SCInsta] IGRTCUpgradePolicy gate not found or signature changed; not hooking");
    }

    Class sheet = objc_getClass("_TtC18IGRTCUpgradePolicy29IGRTCUpgradePolicyBottomSheet");
    if (SCIClassMethodHasEncoding(sheet, @selector(showRTCUpgradePolicySoftNudgeBottomSheetWithUserSession:isMetaAI:notNowCompletionHandler:), kSCISoftNudgeEncoding)) {
        %init(SCISkipCallUpgradeSoftNudge);
    } else {
        NSLog(@"[SCInsta] IGRTCUpgradePolicyBottomSheet not found or signature changed; not hooking");
    }
}

#!/usr/bin/env python3
"""Run the real Foundation-only intro helpers on macOS (no Theos/IPA needed)."""

import os
from pathlib import Path
import re
import subprocess
import tempfile
import uuid


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "src/Features/General/SuppressFeatureIntros.x").read_text()


def helper(name):
    match = re.search(
        rf"^static [^\n]*\b{name}\([^\n]*\) \{{\n.*?^\}}",
        SOURCE,
        re.MULTILINE | re.DOTALL,
    )
    assert match, f"Missing helper: {name}"
    return match.group().replace(
        "[NSUserDefaults standardUserDefaults]", "SCITestDefaults"
    )


PREAMBLE = r'''
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <assert.h>
static NSUserDefaults *SCITestDefaults;
static NSString * const kSCIInstagramMapIntroCompletedKey = @"sci_instagram_map_intro_completed";
static NSString * const kSCIInstagramMapIntroPromotionIDsKey = @"sci_instagram_map_intro_promotion_ids";
static const void *kSCIMapIntroSheetAssociatedKey = &kSCIMapIntroSheetAssociatedKey;
static const void *kSCIMapIntroDismissingAssociatedKey = &kSCIMapIntroDismissingAssociatedKey;
static BOOL SCIShouldSuppressFeatureIntros(void) {
    return [SCITestDefaults boolForKey:@"suppress_feature_intros"];
}
@interface SCITestQP : NSObject
- (void)finished:(id)presenter event:(id)event;
- (_Bool)eligible:(id)p trigger:(id)t surface:(id)s context:(id)c block:(void (^)(void))b debugInfo:(id *)d;
- (void)changed:(id)presenter event:(NSInteger)event;
@end
@implementation SCITestQP
- (void)finished:(id)presenter event:(id)event {}
- (_Bool)eligible:(id)p trigger:(id)t surface:(id)s context:(id)c block:(void (^)(void))b debugInfo:(id *)d { return YES; }
- (void)changed:(id)presenter event:(NSInteger)event {}
@end
@interface SCIMapPromoDialogView : NSObject
@property(nonatomic, copy) id title;
@property(nonatomic, strong) id window;
@property(nonatomic) NSUInteger secondaryActionCount;
@property(nonatomic) BOOL reenterShow;
- (void)secondaryActionTapped:(id)sender;
@end
@interface IGCustomAlertViewController : NSObject {
@public
    id _alertView;
}
@end
@implementation IGCustomAlertViewController
@end
'''

TESTS = r'''
@implementation SCIMapPromoDialogView
- (void)secondaryActionTapped:(id)sender {
    self.secondaryActionCount++;
    if (self.reenterShow) assert(SCIHandleMapIntroPromoDialogBeforeShow(self));
}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        assert(argc == 3);
        NSString *suite = @(argv[1]);
        SCITestDefaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
        NSString *mode = @(argv[2]);
        if ([mode isEqualToString:@"cleanup"]) {
            [SCITestDefaults removePersistentDomainForName:suite];
            [SCITestDefaults synchronize];
            return 0;
        }
        if ([mode isEqualToString:@"read"]) {
            // A new process, with no rendered copy: persisted completion and real QP ID.
            assert(SCIInstagramMapIntroMarkedCompleted());
            assert(SCIShouldSkipInstagramMapIntro());
            assert(SCIIsInstagramMapIntroPromotion(@{@"promotionID": @"12345"}));
            assert(!SCIIsInstagramMapIntroPromotion(@{@"promotionID": @"unrelated"}));
            return 0;
        }

        assert(!SCIInstagramMapIntroMarkedCompleted());
        assert(!SCIShouldSkipInstagramMapIntro());
        assert(SCITextLooksLikeFeatureIntro(@"Introducing Instagram Map"));
        assert(SCITextLooksLikeFeatureIntro(@"Introducing the Instagram map"));
        assert(SCITextLooksLikeFeatureIntro(@"Introducing the\nInstagram\n\nmap"));
        assert(SCITextLooksLikeFeatureIntro(@"Discover Instagram Map"));
        assert(SCITextLooksLikeFeatureIntro(@"Introducing Friends Map"));
        assert(!SCITextLooksLikeFeatureIntro(@"Introducing a new sitemap"));
        assert(!SCITextLooksLikeFeatureIntro(@"Introducing reactions"));
        assert(!SCITextLooksLikeFeatureIntro(@"Instagram Map"));
        assert(!SCITextLooksLikeFeatureIntro(@"Instagram Map See your friends here"));
        assert(SCIClassNameSignalsFeatureIntro(@"IGFriendsMapNUXViewController"));
        assert(SCIClassNameSignalsFeatureIntro(@"com.bloks.instagram.friends_map.onboarding"));
        assert(!SCIClassNameSignalsFeatureIntro(@"IGFriendsMapViewController"));
        assert(!SCIClassNameSignalsFeatureIntro(@"IGQuickPromotionViewController"));
        assert(!SCIClassNameSignalsFeatureIntro(@"IGBloksViewController"));
        assert(!SCIClassNameSignalsFeatureIntro(@"IGFeatureIntroViewController"));
        assert(!SCIKeyLooksLikeMapIntroNUX(@42));

        NSDictionary *promotion = @{
            @"promotionID": @"12345",
            @"qpCreative": @{@"bloksData": @{@"children": @[@{@"text": @"Introducing Instagram Map"}]}}
        };
        assert(SCIIsInstagramMapIntroPromotion(promotion));
        assert(SCIIsInstagramMapIntroPromotion(@{@"qpCreative": @{@"title": @"Introducing", @"content": @"Instagram Map"}}));
        // Recognizing/allowing an intro does not mark it completed.
        assert(!SCIInstagramMapIntroMarkedCompleted());
        assert(!SCIShouldSkipInstagramMapIntro());
        assert(!SCIIsInstagramMapIntroPromotion(@{@"qpCreative": @{@"title": @"Introducing reactions"}}));
        assert(!SCIIsInstagramMapIntroPromotion([NSObject new]));
        assert(!SCIIsInstagramMapIntroPromotion(nil));

        NSUInteger budget = 8;
        NSMutableArray *largePayload = [NSMutableArray array];
        for (int i = 0; i < 1000; i++) [largePayload addObject:@"unrelated"];
        assert(!SCIMapIntroMetadataMatches(largePayload, 0, &budget));
        assert(budget == 0);

        assert(SCIIntroMethodHasSignature([SCITestQP class], @selector(finished:event:), @encode(void), @[@"@", @"@"]));
        assert(SCIIntroMethodHasSignature([SCITestQP class], @selector(eligible:trigger:surface:context:block:debugInfo:), @encode(_Bool), @[@"@", @"@", @"@", @"@", @"@?", @"^@"]));
        assert(!SCIIntroMethodHasSignature([SCITestQP class], @selector(changed:event:), @encode(void), @[@"@", @"@"]));
        assert(!SCIIntroMethodHasSignature([SCITestQP class], NSSelectorFromString(@"missing"), @encode(void), @[]));
        assert(!SCIIntroMethodHasSignature(Nil, @selector(finished:event:), @encode(void), @[@"@", @"@"]));

        SCIMapPromoDialogView *dialog = [SCIMapPromoDialogView new];
        dialog.title = @"Introducing the Instagram map";
        assert(SCIIsInstagramMapIntroPromoDialog(dialog));
        assert(!SCIHandleMapIntroPromoDialogBeforeShow(dialog)); // OFF: allow first show.
        assert(SCIMapIntroSheetWasNoted(dialog));
        assert(dialog.secondaryActionCount == 0);
        assert(!SCIInstagramMapIntroMarkedCompleted());
        IGCustomAlertViewController *root = [IGCustomAlertViewController new];
        root->_alertView = dialog;
        NSDictionary *popover = @{@"navigationController": @{@"topViewController": root}};
        assert(SCIMapIntroPromoDialogFromPopover(popover, [SCIMapPromoDialogView class]) == dialog);
        assert(SCIMapIntroPromoDialogFromPopover(popover, [NSString class]) == nil);
        assert(SCIMapIntroPromoDialogFromPopover(@{@"navigationController": @{@"topViewController": [NSObject new]}}, [SCIMapPromoDialogView class]) == nil);
        assert(SCIMapIntroPromoDialogFromPopover([NSObject new], [SCIMapPromoDialogView class]) == nil);

        [SCITestDefaults setBool:YES forKey:@"suppress_feature_intros"];
        assert(SCIShouldSkipInstagramMapIntro());
        assert(!SCIInstagramMapIntroMarkedCompleted());
        dialog.window = [NSObject new]; // A displayed card awaiting native removal.
        dialog.reenterShow = YES;
        assert(SCIHandleMapIntroPromoDialogBeforeShow(dialog)); // ON: native Not now.
        assert(SCIHandleMapIntroPromoDialogBeforeShow(dialog)); // No repeated native action.
        assert(dialog.secondaryActionCount == 1);
        assert(SCIInstagramMapIntroMarkedCompleted());
        [SCITestDefaults setBool:NO forKey:@"suppress_feature_intros"];

        SCIMapPromoDialogView *repeat = [SCIMapPromoDialogView new];
        repeat.title = [[NSAttributedString alloc] initWithString:@"Introducing the Instagram map"];
        assert(SCIHandleMapIntroPromoDialogBeforeShow(repeat)); // OFF + completed: skip.
        assert(repeat.secondaryActionCount == 1);
        SCIMapPromoDialogView *prePresentation = [SCIMapPromoDialogView new];
        prePresentation.title = @"Introducing the Instagram map";
        prePresentation.reenterShow = YES;
        assert(SCIHandleMapIntroPromoDialogBeforeShow(prePresentation));
        assert(prePresentation.secondaryActionCount == 1);
        assert(SCIHandleMapIntroPromoDialogBeforeShow(prePresentation));
        assert(prePresentation.secondaryActionCount == 2); // New attempt, not a stuck guard.
        repeat.title = @"Introducing reactions"; // Reused card: do not dismiss unrelated QP.
        assert(!SCIHandleMapIntroPromoDialogBeforeShow(repeat));
        assert(!SCIMapIntroSheetWasNoted(repeat));
        assert(repeat.secondaryActionCount == 1);
        repeat.title = @"Instagram Map"; // Actual Map UI is not the intro.
        assert(!SCIHandleMapIntroPromoDialogBeforeShow(repeat));

        SCIMarkInstagramMapIntroCompleted();
        SCIMarkInstagramMapIntroCompleted(); // Idempotent; no NUX callback/recursion.
        assert(SCIInstagramMapIntroMarkedCompleted());
        assert(SCIShouldSkipInstagramMapIntro());
        assert([SCITestDefaults objectForKey:@"friends_map"] == nil);
        assert([SCITestDefaults objectForKey:@"friends_map_impression_count"] == nil);
    }
    return 0;
}
'''


def main():
    names = [
        "SCIInstagramMapIntroMarkedCompleted",
        "SCIMarkInstagramMapIntroCompleted",
        "SCIShouldSkipInstagramMapIntro",
        "SCINoteMapIntroSheet",
        "SCIMapIntroSheetWasNoted",
        "SCIKeyLooksLikeMapIntroNUX",
        "SCIClassNameSignalsFeatureIntro",
        "SCITextLooksLikeFeatureIntro",
        "SCIIntroValueForKey",
        "SCIIsInstagramMapIntroPromoDialog",
        "SCIHandleMapIntroPromoDialogBeforeShow",
        "SCIMapIntroPromoDialogFromPopover",
        "SCIMapIntroMetadataMatches",
        "SCIIsInstagramMapIntroPromotion",
        "SCIIntroMethodHasSignature",
    ]
    suite = "SCInsta.IntroTests." + uuid.uuid4().hex
    with tempfile.TemporaryDirectory(prefix="scinsta-intro-", dir=os.environ.get("TMPDIR")) as directory:
        source = Path(directory) / "IntroTests.m"
        executable = Path(directory) / "IntroTests"
        source.write_text(PREAMBLE + "\n\n".join(map(helper, names)) + TESTS)
        subprocess.run([
            "xcrun", "--sdk", "macosx", "clang", "-fobjc-arc", "-fblocks",
            "-framework", "Foundation", str(source), "-o", str(executable),
        ], check=True)
        try:
            for mode in ["write", "read"]:
                subprocess.run([str(executable), suite, mode], check=True)
        finally:
            subprocess.run([str(executable), suite, "cleanup"], check=True)
    print("PASS: native promo-card skip/reentrancy/reuse, intro matching, QP IDs, ABI guards, and restart persistence")


if __name__ == "__main__":
    main()

# Feature intro regression checks

## Local automated checks

On macOS with Xcode command-line tools:

```sh
python3 tests/test_suppress_feature_intros.py
```

This compiles and runs the Foundation-only helpers extracted from the actual
Logos source. It checks Map-only matching, nested Bloks creative metadata,
bounded payload traversal, runtime signature guards, and persisted completion
and promotion IDs in a second process. It also tests the native promo-card title,
popover-to-alert lookup, native Not now dispatch, reentrancy, and card reuse with
Foundation mocks. It uses an isolated defaults suite and
removes that suite afterward; it does not change Instagram's preferences.

It does **not** exercise UIKit transitions, Instagram's QP implementation, or IPA
packaging. Hooks are only installed if the live methods have the expected
argument/return encodings.

## 418.2.0 binary investigation

The decrypted IPA used by packaging run `39014706839` identifies itself as
Instagram **418.2.0**, build **893787717**. Its Objective-C metadata confirms:

- `_TtC15IGDSPromoDialog19IGDSPromoDialogView`: `title` (`@16@0:8`),
  `secondaryActionTapped:`, `primaryActionTapped:`, and `dismissAlertView:`
  (each `v24@0:8@16`). This is a **UIView**, not a partial-sheet controller.
- `IGCustomAlertViewController`: object ivar `_alertView`, and native
  `customAlertView:didTapAction:` delegate callback.
- `IGPopoverController` in `FBSharedFramework`: `present` (`v16@0:8`) and
  `navigationController` (`@16@0:8`). The native promo dialog uses this popover
  host, which can be intercepted before backdrop presentation even when Swift
  callers bypass the dialog's Objective-C `show` thunk.
- The native secondary-action implementation forwards the configured action to
  the alert delegate. Its sender is not used for touch-coordinate calculations.
  In contrast, `dismissAlertView:` is a **gesture handler** that ignores taps
  inside the card. Do not synthesize a nil gesture or mark every invocation as
  completion; window removal confirms outside-tap dismissal.

The screenshot's title is **"Introducing the Instagram map"**. Test this exact
copy, including embedded newlines, rather than only the earlier assumed copy.
Only matching Map titles inside this specific alert/popover structure are
suppressed; native Not now handles its normal action and dismissal callbacks.

The previous QP eligibility selector came from public Instagram 166.0 headers
at `iCrazeiOS/Class-Dumped-Apps`. **`IGQPEligibilityChecker` is absent in this
418.2.0 binary**, so that guarded legacy hook cannot be the primary solution.
The current partial-sheet class names also use `IGDSPartialModal...` rather than
the older `IGPartialModal...` hooks. Keep legacy hooks as optional compatibility
paths; do not mistake their successful compilation for coverage of this card.

## Required device checks (Instagram 418.2.0)

Use separate fresh test containers for the ON and OFF scenarios. An existing
`sci_instagram_map_intro_completed` flag intentionally remains respected; old
builds may already have set it just from opening the inbox with suppression on.

- **ON:** Cold-launch into DMs several times. Confirm no Map intro, no DM crash,
  and no remaining gray dimming/touch-blocking overlay. Check other intro surfaces.
- **OFF:** Allow the first Map intro to render, including slow Bloks loads beyond
  0.5 seconds. Close it using its button, outside tap, and completed swipe in
  separate fresh-container runs. Force-quit, relaunch, and verify no repeat.
- **Cancelled swipe:** Cancel an interactive dismissal with suppression OFF.
  Confirm that the sheet remains usable and has not been treated as completed.
- **Ordinary sheets:** Open normal inbox sheets, a non-Map QP, and the actual Map
  screen. They should not be dismissed merely because of their wrapper class.
- **Reuse/covering:** Cover the intro with another controller, then return. Reuse
  sheets for unrelated DM content. Verify no stale Map flag dismisses that content.
- **Feature limits:** Smoke-test scheduled tab limits unchanged.

For the native promo card, `IGPopoverController` is the pre-presentation path.
The view-window/layout fallback handles alternate hosts with the native Not now
action after presentation settles. Legacy sheets use UIKit dismissal. Fallbacks
cannot promise zero frames of visible intro, and deliberately leave unknown
custom containers alone rather than tearing down views or guessing state enums.

Finally run **Build and Package SCInsta** with the decrypted target IPA. Local
helper tests or compilation of this hook alone do not replace that CI build.

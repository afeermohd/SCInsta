# Feature intro regression checks

## Local automated checks

On macOS with Xcode command-line tools:

```sh
python3 tests/test_suppress_feature_intros.py
```

This compiles and runs the Foundation-only helpers extracted from the actual
Logos source. It checks Map-only matching, nested Bloks creative metadata,
bounded payload traversal, runtime signature guards, and persisted completion
and promotion IDs in a second process. It uses an isolated defaults suite and
removes that suite afterward; it does not change Instagram's preferences.

It does **not** exercise UIKit transitions, Instagram's QP implementation, or IPA
packaging. The QP selectors were found in public Instagram 166.0 headers at
`iCrazeiOS/Class-Dumped-Apps`, not a verified 418.2.0 dump. The hooks are only
installed if the live methods have the expected argument/return encodings.

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

QP eligibility rejection is the pre-presentation path. If Instagram no longer
exposes that method or the promotion has no recognizable metadata, the fallback
waits for visible Map copy and uses UIKit dismissal. That fallback cannot promise
zero frames of visible intro, and deliberately leaves non-presented custom
containers alone rather than tearing down views or guessing sheet-state enums.

Finally run **Build and Package SCInsta** with the decrypted target IPA. Local
helper tests or compilation of this hook alone do not replace that CI build.

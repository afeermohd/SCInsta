#import "../../Utils.h"
#import <objc/runtime.h>

#define QUICKSNAPENABLED(orig) return [SCIUtils getBoolPref:@"disable_instants_creation"] ? false : orig;

// Demangled name: IGQuickSnapExperimentation.IGQuickSnapExperimentationHelper
%hook _TtC26IGQuickSnapExperimentation32IGQuickSnapExperimentationHelper
+ (_Bool)isQuicksnapEnabled:(id)enabled {
    QUICKSNAPENABLED(%orig);
}
+ (_Bool)isQuicksnapEnabledInFeed:(id)feed {
    QUICKSNAPENABLED(%orig);
}
+ (_Bool)isQuicksnapEnabledInInbox:(id)inbox {
    QUICKSNAPENABLED(%orig);
}
+ (_Bool)isQuicksnapEnabledInStories:(id)stories {
    QUICKSNAPENABLED(%orig);
}
+ (_Bool)isQuicksnapEnabledInNotesTray:(id)tray {
    QUICKSNAPENABLED(%orig);
}
+ (_Bool)isQuicksnapEnabledInNotesTrayWithPeek:(id)peek {
    QUICKSNAPENABLED(%orig);
}
+ (_Bool)isQuicksnapEnabledInNotesTrayWithPog:(id)pog {
    QUICKSNAPENABLED(%orig);
}
+ (_Bool)isQuicksnapNotesTrayEmptyPogEnabled:(id)enabled {
    QUICKSNAPENABLED(%orig);
}
// Instagram 455
+ (_Bool)isQuicksnapCornerstackEnabledInProfile:(id)profile {
    QUICKSNAPENABLED(%orig);
}
+ (_Bool)shouldAttachQuickSnapServiceForBadging:(id)badging {
    QUICKSNAPENABLED(%orig);
}
// + (_Bool)isStoriesSpringEnabled:(id)enabled {
//     return true;
// }
// + (_Bool)shouldEnableScreenshotBlocking:(id)blocking {
//     return false;
// }
// + (_Bool)areFiltersEnabled:(id)enabled {
//     return true;
// }
// + (_Bool)isBottomsheetCustomAudienceEnabled:(id)enabled {
//     return true;
// }
// + (_Bool)isVideoCaptureEnabled:(id)enabled {
//     return true;
// }
%end

// %hook IGDirectNotesTrayRowCell
// - (_Bool)isQuicksnapPeekVisible {
//     return true;
// }
// %end

// %hook IGDirectNotesTrayRowSectionController
// - (_Bool)isQuicksnapPeekVisible {
//     return true;
// }
// %end
// Instagram 455 checks Instants mostly from Swift, which skips the helper's ObjC entry points above.
// Block the inbox entry points that are still reached through ObjC. %ctor binds the Swift classes.
@interface SCIInstantsDelegateImpl : NSObject
- (BOOL)shouldShowTryInstants;
@end
@interface SCIDirectInboxViewController : UIViewController
- (void)tryShowQuickSnapPeek;
@end
@interface SCIDirectInboxCameraMediaCoordinator : NSObject
- (void)tryShowQuickSnapPeek;
@end

static BOOL SCIInstantsDisabled(void) {
    return [SCIUtils getBoolPref:@"disable_instants_creation"];
}

%group SCIInstantsTryPrompt
%hook SCIInstantsDelegateImpl
- (BOOL)shouldShowTryInstants {
    if (SCIInstantsDisabled()) return NO;
    return %orig;
}
%end
%end

%group SCIInstantsInboxPeek
%hook SCIDirectInboxViewController
- (void)tryShowQuickSnapPeek {
    if (SCIInstantsDisabled()) return;
    %orig;
}
%end
%end

%group SCIInstantsCameraPeek
%hook SCIDirectInboxCameraMediaCoordinator
- (void)tryShowQuickSnapPeek {
    if (SCIInstantsDisabled()) return;
    %orig;
}
%end
%end

static BOOL SCIInstantsClassHasMethod(Class cls, SEL selector, const char *types) {
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    return method && strcmp(method_getTypeEncoding(method), types) == 0;
}

%ctor {
    %init;

    Class delegateClass = objc_getClass("_TtC18IGInstantsDelegate22IGInstantsDelegateImpl");
    if (SCIInstantsClassHasMethod(delegateClass, @selector(shouldShowTryInstants), "B16@0:8")) {
        %init(SCIInstantsTryPrompt, SCIInstantsDelegateImpl = delegateClass);
    }

    Class inboxClass = objc_getClass("_TtC27IGDirectInboxViewController27IGDirectInboxViewController");
    if (SCIInstantsClassHasMethod(inboxClass, @selector(tryShowQuickSnapPeek), "v16@0:8")) {
        %init(SCIInstantsInboxPeek, SCIDirectInboxViewController = inboxClass);
    }

    Class cameraClass = objc_getClass("_TtC32IGDirectInboxViewControllerSwift35IGDirectInboxCameraMediaCoordinator");
    if (SCIInstantsClassHasMethod(cameraClass, @selector(tryShowQuickSnapPeek), "v16@0:8")) {
        %init(SCIInstantsCameraPeek, SCIDirectInboxCameraMediaCoordinator = cameraClass);
    }
}

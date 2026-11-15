#import "../../Utils.h"
#import <objc/runtime.h>

// Instagram 455 rewrote the notes tray in Swift (IGDirectNotesTrayUISwift); %ctor binds whichever row
// cell class exists. The map pog is removed three ways so a missed path still leaves it hidden:
//   1. The experiment gate reports the friends map as disabled.
//   2. The tray row drops the map item from its list adapter objects.
//   3. The 455 map section controller renders no items.

// Logos binds these local names to the runtime classes in %ctor.
@interface SCINotesTrayRowCell : UIView
- (id)listAdapterObjects;
@end
@interface SCINotesTrayFriendMapSectionController : NSObject
- (long long)numberOfItems;
@end
@interface SCINotesExperimentHelper : NSObject
+ (BOOL)friendMapEnabled:(id)launcherSet userDefaults:(id)userDefaults shouldExpose:(BOOL)shouldExpose;
@end

static BOOL SCIShouldHideFriendsMap(void) {
    return [SCIUtils getBoolPref:@"hide_friends_map"];
}

static BOOL SCIIsFriendsMapTrayObject(id obj) {
    if (!obj) return NO;

    NSString *className = NSStringFromClass([obj class]).lowercaseString;
    if ([className containsString:@"friendmap"] || [className containsString:@"friendsmap"]) return YES;

    if ([obj isKindOfClass:objc_getClass("IGDirectNotesTrayUserViewModel")]) {
        @try {
            id notePk = [obj valueForKey:@"notePk"];
            if ([notePk isKindOfClass:[NSString class]] && [notePk isEqualToString:@"friends_map"]) return YES;
        } @catch (__unused NSException *exception) {
        }
    }
    return NO;
}

%group SCIHideFriendsMapTray
%hook SCINotesTrayRowCell
- (id)listAdapterObjects {
    NSArray *originalObjs = %orig;
    if (!SCIShouldHideFriendsMap() || ![originalObjs isKindOfClass:[NSArray class]]) return originalObjs;

    NSMutableArray *filteredObjs = [NSMutableArray arrayWithCapacity:originalObjs.count];
    for (id obj in originalObjs) {
        if (SCIIsFriendsMapTrayObject(obj)) {
            NSLog(@"[SCInsta] Hiding friends map");
            continue;
        }
        [filteredObjs addObject:obj];
    }
    return [filteredObjs copy];
}
%end
%end

%group SCIHideFriendsMapSection
%hook SCINotesTrayFriendMapSectionController
- (long long)numberOfItems {
    if (SCIShouldHideFriendsMap()) return 0;
    return %orig;
}
%end
%end

%group SCIHideFriendsMapGate
%hook SCINotesExperimentHelper
+ (BOOL)friendMapEnabled:(id)launcherSet userDefaults:(id)userDefaults shouldExpose:(BOOL)shouldExpose {
    if (SCIShouldHideFriendsMap()) return NO;
    return %orig;
}
%end
%end

static BOOL SCIClassHasMethod(Class cls, SEL selector, BOOL isClassMethod, const char *types) {
    if (!cls) return NO;
    Method method = isClassMethod ? class_getClassMethod(cls, selector) : class_getInstanceMethod(cls, selector);
    return method && strcmp(method_getTypeEncoding(method), types) == 0;
}

%ctor {
    Class rowCellClass = objc_getClass("IGDirectNotesTrayRowCell")
        ?: objc_getClass("_TtC24IGDirectNotesTrayUISwift24IGDirectNotesTrayRowCell");
    if (SCIClassHasMethod(rowCellClass, @selector(listAdapterObjects), NO, "@16@0:8")) {
        %init(SCIHideFriendsMapTray, SCINotesTrayRowCell = rowCellClass);
    }

    Class sectionClass = objc_getClass("_TtC24IGDirectNotesTrayUISwift43IGDirectNotesTrayFriendMapSectionController");
    if (SCIClassHasMethod(sectionClass, @selector(numberOfItems), NO, "q16@0:8")) {
        %init(SCIHideFriendsMapSection, SCINotesTrayFriendMapSectionController = sectionClass);
    }

    Class helperClass = objc_getClass("_TtC34IGDirectNotesExperimentHelperSwift29IGDirectNotesExperimentHelper");
    if (SCIClassHasMethod(helperClass, @selector(friendMapEnabled:userDefaults:shouldExpose:), YES, "B36@0:8@16@24B32")) {
        %init(SCIHideFriendsMapGate, SCINotesExperimentHelper = helperClass);
    }
}

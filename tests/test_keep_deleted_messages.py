#!/usr/bin/env python3
"""Exercise the real Iris filtering helpers with Foundation mocks on macOS."""

import os
from pathlib import Path
import re
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "src/Features/StoriesAndMessages/KeepDeletedMessages.x").read_text()


def helper(name):
    match = re.search(
        rf"^static [^\n]*\b{name}\([^\n]*\) \{{\n.*?^\}}",
        SOURCE,
        re.MULTILINE | re.DOTALL,
    )
    assert match, f"Missing helper: {name}"
    return match.group()


PREAMBLE = r'''
#import <Foundation/Foundation.h>
#include <assert.h>

static BOOL keepDeletedMessages;
@interface SCIUtils : NSObject
+ (BOOL)getBoolPref:(NSString *)key;
@end
@implementation SCIUtils
+ (BOOL)getBoolPref:(NSString *)key {
    assert([key isEqualToString:@"keep_deleted_message"]);
    return keepDeletedMessages;
}
@end

@interface IGDirectRealtimeIrisDelta : NSObject
@property(nonatomic, strong) id payload;
@end
@implementation IGDirectRealtimeIrisDelta
@end
@interface IGDirectRealtimeIrisDeltaPayload : NSObject
@property(nonatomic, strong) id threadDeltaPayload;
@end
@implementation IGDirectRealtimeIrisDeltaPayload
@end
@interface IGDirectRealtimeIrisThreadDeltaPayload : NSObject
@property(nonatomic, strong) id threadDelta;
@end
@implementation IGDirectRealtimeIrisThreadDeltaPayload
@end
@interface IGDirectRealtimeIrisThreadDelta : NSObject
@property(nonatomic, strong) id removeItem_messageId;
@end
@implementation IGDirectRealtimeIrisThreadDelta
@end

@interface SCIThrowingIrisDelta : IGDirectRealtimeIrisDelta
@end
@implementation SCIThrowingIrisDelta
- (id)valueForKey:(NSString *)key {
    @throw [NSException exceptionWithName:NSUndefinedKeyException reason:@"Changed Instagram key" userInfo:nil];
}
@end
@interface SCIThreadDeltaSubclass : IGDirectRealtimeIrisThreadDelta
@end
@implementation SCIThreadDeltaSubclass
@end

static IGDirectRealtimeIrisDelta *deltaForThread(id thread) {
    IGDirectRealtimeIrisThreadDeltaPayload *threadPayload = [IGDirectRealtimeIrisThreadDeltaPayload new];
    threadPayload.threadDelta = thread;
    IGDirectRealtimeIrisDeltaPayload *payload = [IGDirectRealtimeIrisDeltaPayload new];
    payload.threadDeltaPayload = threadPayload;
    IGDirectRealtimeIrisDelta *delta = [IGDirectRealtimeIrisDelta new];
    delta.payload = payload;
    return delta;
}
static IGDirectRealtimeIrisDelta *deltaForMessageID(id messageID) {
    IGDirectRealtimeIrisThreadDelta *thread = [IGDirectRealtimeIrisThreadDelta new];
    thread.removeItem_messageId = messageID;
    return deltaForThread(thread);
}
'''

TESTS = r'''
int main(void) {
    @autoreleasepool {
        IGDirectRealtimeIrisDelta *removal = deltaForMessageID(@"message-123");
        IGDirectRealtimeIrisDelta *normalUpdate = deltaForMessageID(nil);
        IGDirectRealtimeIrisDelta *emptyID = deltaForMessageID(@"");
        IGDirectRealtimeIrisDelta *wrongIDType = deltaForMessageID(@42);
        IGDirectRealtimeIrisDelta *unknownPayload = [IGDirectRealtimeIrisDelta new];
        unknownPayload.payload = [NSObject new];
        IGDirectRealtimeIrisDelta *nonThreadEvent = [IGDirectRealtimeIrisDelta new];
        nonThreadEvent.payload = [IGDirectRealtimeIrisDeltaPayload new];
        NSObject *unknownDelta = [NSObject new];
        SCIThrowingIrisDelta *changedKey = [SCIThrowingIrisDelta new];
        IGDirectRealtimeIrisDelta *unknownThread = deltaForThread([NSObject new]);
        NSArray *retained = @[normalUpdate, emptyID, wrongIDType, unknownPayload,
                              nonThreadEvent, unknownDelta, changedKey, unknownThread];
        NSMutableArray *batch = [retained mutableCopy];
        [batch insertObject:removal atIndex:2];
        [batch addObject:deltaForMessageID(@"message-456")];
        NSArray *original = [batch copy];

        keepDeletedMessages = NO;
        assert(SCIFilterMessageRemovalIrisDeltas(batch) == batch);
        keepDeletedMessages = YES;
        assert(SCIIsMessageRemovalIrisDelta(removal));
        assert([SCIFilterMessageRemovalIrisDeltas(batch) isEqualToArray:retained]);
        assert([batch isEqualToArray:original]); // Never mutate Instagram's input.
        assert(SCIFilterMessageRemovalIrisDeltas(retained) == retained);
        for (id delta in retained) assert(!SCIIsMessageRemovalIrisDelta(delta));
        assert(!SCIIsMessageRemovalIrisDelta(nil));
        assert(SCIFilterMessageRemovalIrisDeltas(nil) == nil);
        NSArray *empty = @[];
        assert(SCIFilterMessageRemovalIrisDeltas(empty) == empty);
        assert(SCIFilterMessageRemovalIrisDeltas(@[removal]).count == 0);

        SCIThreadDeltaSubclass *subclass = [SCIThreadDeltaSubclass new];
        subclass.removeItem_messageId = @"message-subclass";
        assert(SCIIsMessageRemovalIrisDelta(deltaForThread(subclass)));
        keepDeletedMessages = NO;
        assert(SCIFilterMessageRemovalIrisDeltas(batch) == batch); // Toggle remains live.
    }
    return 0;
}
'''


def main():
    helpers = "\n\n".join(map(helper, [
        "SCIIsMessageRemovalIrisDelta", "SCIFilterMessageRemovalIrisDeltas",
    ]))
    with tempfile.TemporaryDirectory(prefix="scinsta-iris-", dir=os.environ.get("TMPDIR")) as directory:
        source = Path(directory) / "IrisTests.m"
        executable = Path(directory) / "IrisTests"
        source.write_text(PREAMBLE + helpers + TESTS)
        subprocess.run([
            "xcrun", "--sdk", "macosx", "clang", "-fobjc-arc",
            "-framework", "Foundation", str(source), "-o", str(executable),
        ], check=True)
        subprocess.run([str(executable)], check=True)
    print("PASS: removal filtering, toggle passthrough, unknown/malformed deltas, KVC failures, input order and immutability")


if __name__ == "__main__":
    main()

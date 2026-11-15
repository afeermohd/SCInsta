#import "../../Utils.h"
#import "../../InstagramHeaders.h"

static BOOL SCIIsMessageRemovalIrisDelta(id delta) {
    // Unknown delta shapes must pass through: Iris carries more than message updates.
    @try {
        if (![delta isKindOfClass:NSClassFromString(@"IGDirectRealtimeIrisDelta")]) return NO;
        id payload = [delta valueForKey:@"payload"];
        if (![payload isKindOfClass:NSClassFromString(@"IGDirectRealtimeIrisDeltaPayload")]) return NO;
        id threadPayload = [payload valueForKey:@"threadDeltaPayload"];
        if (![threadPayload isKindOfClass:NSClassFromString(@"IGDirectRealtimeIrisThreadDeltaPayload")]) return NO;
        id threadDelta = [threadPayload valueForKey:@"threadDelta"];
        if (![threadDelta isKindOfClass:NSClassFromString(@"IGDirectRealtimeIrisThreadDelta")]) return NO;

        id messageID = [threadDelta valueForKey:@"removeItem_messageId"];
        return [messageID isKindOfClass:[NSString class]] && [messageID length] > 0;
    } @catch (__unused NSException *exception) {
        return NO;
    }
}

static NSArray *SCIFilterMessageRemovalIrisDeltas(NSArray *deltas) {
    if (![SCIUtils getBoolPref:@"keep_deleted_message"] || deltas.count == 0) return deltas;

    NSMutableArray *filtered = [NSMutableArray arrayWithCapacity:deltas.count];
    for (id delta in deltas) {
        if (!SCIIsMessageRemovalIrisDelta(delta)) [filtered addObject:delta];
    }
    return filtered.count == deltas.count ? deltas : [filtered copy];
}

// Modern Instagram versions (ported from SoCuul/SCInsta@19d21e2).
%hook IGDirectRealtimeIrisDeltaHandler
- (void)handleIrisDeltas:(NSArray<IGDirectRealtimeIrisDelta *> *)deltas {
    NSArray *filteredDeltas = SCIFilterMessageRemovalIrisDeltas(deltas);
    %orig(filteredDeltas);
}
%end

// Legacy versions fallback.
%hook IGDirectRealtimeIrisThreadDelta
+ (id)removeItemWithMessageId:(id)arg1 {
    if ([SCIUtils getBoolPref:@"keep_deleted_message"]) {
        arg1 = NULL;
    }

    return %orig(arg1);
}
%end

%hook IGDirectMessageUpdate
+ (id)removeMessageWithMessageId:(id)arg1 {
    if ([SCIUtils getBoolPref:@"keep_deleted_message"]) {
        arg1 = NULL;
    }
    
    return %orig(arg1);
}
%end

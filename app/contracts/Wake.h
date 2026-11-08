// Wake: what came for a session that waits on someone else (a pull request's review, its ticket moved, your answer to
// one of its tasks), and the modules that can tell it (WakeSource). The waits module asks each source what a waiting
// session waits on and what has come for it since, and never reads a source's own state; a source knows nothing of
// waiting, only what it watches. Plain data.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

@class Row;

// One thing that came: the source's word for where it came from ("pull request", "ticket", "task"), what came
// (`kind`, the source's own word: approved, commented, merged, moved, answered), the source's few words for the row
// ("#12 approved"), when it came (ms since 1970), whether it's your own answer (`yours`, which goes over the gear, as
// your answer always carries a session on), and what the session is told of it (`facts`, as JSON: a login or a key in
// it is outside text, which the session reads as someone else's words).
@interface Wake : NSObject
@property (copy) NSString *source, *kind, *says;
@property (assign) double at;
@property (assign) BOOL yours;
@property (copy) NSDictionary *facts;
+ (instancetype)wakeFrom:(NSString *)source kind:(NSString *)kind says:(NSString *)says at:(double)at
                   facts:(NSDictionary *)facts;
@end

// What a source would wake a session on: its few words for the row ("#12"), the same for VoiceOver ("pull request
// 12"), what it is (`on`, the source's own ids, {source, url} or {source, tracker, site, key}, which the row's `wait`
// carries for other modules to read), and why it can't be read now (`cant`: "gh isn't signed in"), nil when it can.
@interface WaitOn : NSObject
@property (copy) NSString *says, *spoken, *cant;
@property (copy) NSDictionary *on;
+ (instancetype)waitOn:(NSDictionary *)on says:(NSString *)says spoken:(NSString *)spoken;
@end

// A module that can tell what came for a session. The core finds them (modulesThat:).
@protocol WakeSource <NSObject>
// What it would wake this session on now, or nil when it has nothing of the session's. For one it watches, what it
// watches.
- (WaitOn *)waitsOn:(Row *)row;
// Watches what it waits on for that session, counting only what comes after `since` (ms since 1970), until unwatch:,
// and says whether it now watches something of the session's. `options` are the wait's: {comments: YES} for comments
// too, and `on`, what the wait began on as each source named it (WaitOn's `on`), for a wait read back after a restart:
// a source takes its own from there, so it watches the same thing even before it could name it again. Watching it again
// starts afresh.
- (BOOL)watch:(Row *)row since:(double)since options:(NSDictionary *)options;
- (void)unwatch:(NSString *)sessionId;
// What has come for a watched session since its watch began, oldest first: none for one it doesn't watch.
- (NSArray<Wake *> *)wakesFor:(NSString *)sessionId;
@end

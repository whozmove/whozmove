// Transcripts: what's new in a session's transcript, read a little at a time.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// Follows the listed sessions' transcripts, reading only what's new each time.
@interface Transcripts : NSObject
// Every listed session, running or not; set on every tick.
@property (copy) NSArray<NSString *> *sessionIds;
// Called when a read turns up new PR links.
@property (copy) void (^onPRLinks)(void);
// Starts reading what's new in each listed session's transcript, and forgets the sessions no longer listed.
- (void)readNew;
// What's been read for a session so far: {path, offset, prs, usage, mode, modeAt, messageAt, title, writings,
// waiting, edits (its sub-agents' included, and what their shell commands changed), editIds, subOffsets, and the
// shell commands' modes (AddShellNews)}, or nil.
- (NSDictionary *)stateOf:(NSString *)sessionId;
// One of a session's writings, read off the main thread; `done` gets ReadWriting's answer on the main thread.
- (void)readWriting:(NSString *)writingId of:(NSString *)sessionId done:(void (^)(NSDictionary *read))done;
// Where a session's transcript is, or nil while it has none. Once a read has found it, it isn't looked for again.
- (NSString *)pathOf:(NSString *)sessionId;
// The session's current topic, which Claude Code also puts in its terminal tab's title ("✳ <topic>"), or nil.
- (NSString *)topicOf:(NSString *)sessionId;
// Its topic as the last read found it (they run every 10s), without reading the transcript again: for a check made
// every second on the main thread.
- (NSString *)lastTopicOf:(NSString *)sessionId;
// Whether any read is still out. A test run waits until none is.
@property (readonly) BOOL reading;
@end

// Transcripts: what's new in a session's transcript, read a little at a time.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// The start of today on this Mac, in ms since 1970: where a day's use starts.
double StartOfToday(void);
// The tokens a part of a transcript's replies used today (from `today`, StartOfToday's): input, cache writes, cache
// reads and output. Claude Code writes a line for each part of a reply as it streams (its thinking, its text, each
// tool call), each with the reply's usage so far, so each reply counts once, by its message id, as the most any of
// its lines says; a reply going on from the read before adds only what it grew by. `was` is what the read before of
// the same file left ({day, tokens, lastId, lastTokens}); `fromStart` a read from the file's start (the first, or after
// the file was rewritten), which counts afresh, as does a new day. "<synthetic>" replies (API errors) don't count.
NSDictionary *SpentAdd(NSDictionary *was, NSData *chunk, NSUInteger end, BOOL fromStart, double today);
// What a session's replies and its sub-agents' used today, from its `spent` ({main, subs: {file: …}}, SpentAdd's).
long long SpentToday(NSDictionary *spent, double today);

// Claude's last reply in the turn whose prompt is exactly `prompt` (spaces at either end aside), sent after `since` (ms
// since 1970), in a chunk of transcript (`whole`: from the file's start, else its first line may be cut and is
// skipped), or nil while that turn has no reply yet. A later turn with the same words counts instead; a sub-agent's
// lines and Claude Code's own don't count. At most kMostReply characters, cut short with "…".
extern const NSUInteger kMostReply;
NSString *ReplyAfter(NSData *chunk, BOOL whole, NSString *prompt, double since);

// Words a hook handed into a session (`words`, its additional context), as a chunk of transcript records them taken in
// after `since` (ms since 1970), and what Claude wrote after them: {at, how, reply, turnEnded}, or nil while the
// transcript doesn't show them. `at` is when they were taken in, `how` the hook's event (PostToolBatch or Stop),
// `reply` Claude's words since then in that turn (nil while none, at most kMostReply characters), and `turnEnded`
// whether you've sent another prompt since. A sub-agent's lines don't count. `whole` as ReplyAfter's.
NSDictionary *AfterHandedWords(NSData *chunk, BOOL whole, NSString *words, double since);

// What the reads found is kept across restarts, so a copy of Whozmove that's just started reads only what's new: for
// each session, a file in a folder of its own in Whozmove's folder (ReadsFolder, reads/<session id>.json), which only
// the Transcripts reader writes. It holds the whole of a session's state but whether a read is out, each reader saying
// how its own part is kept (KeptWritings, KeptEdits), with where the reads had got to in each file (its inode, its
// offset, and the mark of its bytes just before there), the shape of what the reads keep, and the app's version. The
// mode, the topic and the newest message's time aren't kept, nor where they were: GoOnFrom reads them back from the
// transcript.
// kReadsShape goes up whenever what a read finds changes (a part added, or one found differently): every kept read of
// another shape is read afresh.
extern const NSInteger kReadsShape;
NSString *ReadsFolder(void);
// What's kept of a session's state (`state`, as stateOf: gives it), without the files' marks, which KeepRead takes; nil
// for a session whose id isn't plain (it names the file) or that hasn't been read.
NSDictionary *KeptRead(NSDictionary *state, NSString *sessionId, NSString *version);
// Writes a kept read into `folder`, whole, only for you to read (a 0700 folder, a 0600 file), once each file it read is
// still the one read and at least as long, with the marks taken; NO when not. Nothing is kept, and what was kept before
// goes, when anything in it is shaped like a key (LooksLikeSecret): that session is read from its start next time.
BOOL KeepRead(NSString *folder, NSDictionary *kept);
// A kept read as a session's state to go on from, every value checked for its kind (PR links for https), its limits and
// its place (the transcript where Claude Code keeps it, named for the session); nil when anything doesn't fit.
NSMutableDictionary *TakeBackRead(NSDictionary *kept, NSString *sessionId);
// The files a kept read read, as they are now: {main, subs: {name: …}}, each {inode, size, mark} ({} when it isn't
// there), the mark taken where the kept read had got to.
NSDictionary *KeptReadFilesNow(NSDictionary *kept);
// Why a read can't go on from a kept one, with its files as they are `now` (KeptReadFilesNow's) and Whozmove's
// `version`, in a few words; nil when it can: kept in this shape by this version, and each file it read (the transcript
// and each sub-agent's record) still there, the same file, at least as long, and the same up to where it was read.
NSString *WhyNotGoOnFrom(NSDictionary *kept, NSDictionary *now, NSString *version);
// A kept read as the state a read of the session's transcript at `path` goes on from: taken back (TakeBackRead),
// applying to its files as they are (WhyNotGoOnFrom), and with its mode, the newest message's time and its topic read
// back from the transcript, from where the kept read stopped, never from the kept file; nil, with `why` in a few
// words, when any of that fails, and the session is read from its start.
NSMutableDictionary *GoOnFrom(NSDictionary *kept, NSString *sessionId, NSString *path, NSString *version,
                              NSString **why);
// The kept reads in `folder` to take away, by file name, at `at` (seconds since 1970): those whose transcript has gone
// (cleared, or moved to the Trash), is another file now or is shorter than what was read, those not `listed` now and
// not kept for kKeptFor, and any other file (one not named for a session, or one a write stopped half way left).
NSArray<NSString *> *KeptReadsToDrop(NSString *folder, NSSet<NSString *> *listed, NSTimeInterval at);

// In a chunk of transcript up to `end`: the session's topic as Claude Code last named it (its newest aiTitle record),
// the name you gave it last (its newest custom-title record, /rename's), each nil for none; and when the conversation
// last moved, its newest message's time in ms since 1970, or 0.
NSString *NewestTitle(NSData *chunk, NSUInteger end);
NSString *NewestCustomTitle(NSData *chunk, NSUInteger end);
double LatestMessageAt(NSData *chunk, NSUInteger end);

// Follows the listed sessions' transcripts, reading only what's new each time.
@interface Transcripts : NSObject
// Every listed session, running or not; set on every tick.
@property (copy) NSArray<NSString *> *sessionIds;
// Called when a read turns up new PR links.
@property (copy) void (^onPRLinks)(void);
// Starts reading what's new in each listed session's transcript, and forgets the sessions no longer listed.
- (void)readNew;
// What's been read for a session so far: {path, offset, prs, usage, spent, mode, modeAt, messageAt, compactedAt (when
// it last compacted, ms since 1970), title, writings, waiting, edits (its sub-agents' included, and what their shell
// commands changed), editIds, subOffsets, and the shell commands' modes (AddShellNews)}, or nil. `spent` is what its
// replies and its sub-agents' used, SpentToday's.
- (NSDictionary *)stateOf:(NSString *)sessionId;
// One of a session's writings, read off the main thread; `done` gets ReadWriting's answer on the main thread.
- (void)readWriting:(NSString *)writingId of:(NSString *)sessionId done:(void (^)(NSDictionary *read))done;
// ReplyAfter in a session's transcript, its last part read off the main thread; `done` gets it on the main thread, nil
// for none (no transcript, or no reply yet). Nothing of it is kept.
- (void)replyTo:(NSString *)prompt of:(NSString *)sessionId since:(double)since done:(void (^)(NSString *reply))done;
// AfterHandedWords in a session's transcript, its last part read off the main thread; `done` gets it on the main
// thread, nil for none. Nothing of it is kept.
- (void)afterWords:(NSString *)words of:(NSString *)sessionId since:(double)since
              done:(void (^)(NSDictionary *found))done;
// Where a session's transcript is, or nil while it has none. Once a read has found it, it isn't looked for again.
- (NSString *)pathOf:(NSString *)sessionId;
// The session's current topic, which Claude Code also puts in its terminal tab's title ("✳ <topic>"), or nil.
- (NSString *)topicOf:(NSString *)sessionId;
// Its topic as the last read found it (they run every 10s), without reading the transcript again: for a check made
// every second on the main thread.
- (NSString *)lastTopicOf:(NSString *)sessionId;
// Whether any read is still out. A test run waits until none is.
@property (readonly) BOOL reading;
// From launch on, never in a print run but --print-reads, which keeps them in a folder of its own: each session's
// state is kept in `folder` once its reads have moved on, with no read of it out, at most every 30 minutes (a few at a
// time), and a session first read since then goes on from what was kept, while that still applies (WhyNotGoOnFrom);
// what's kept is pruned once the sessions listed are known, then every hour (KeptReadsToDrop).
- (void)keepIn:(NSString *)folder;
// Keeps every state that has changed at once, and waits for it to be written, 4 seconds at most: as Whozmove quits.
- (void)keepNow;
// Where today starts, in ms since 1970, for what was spent today: StartOfToday, unless a test says otherwise.
@property (copy) double (^dayStart)(void);
// How many bytes of transcripts the reads have read.
@property (readonly) unsigned long long bytesRead;
@end

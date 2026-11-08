// KeyScan: the keys left where they shouldn't be on this Mac, found by the bundled Betterleaks on a queue of its own,
// and what's done about each. A key itself goes no further than the line it was found in: what's kept and told is its
// kind, its masked form (the part every key of its kind starts with, and its last 4 characters), every place it is,
// a fingerprint made with a secret of this Mac's, and from its line, a sign-in token's own end date, what it's set as
// or for (a name before = or :, or an address's host) and whether it starts as a provider's keys do, in Whozmove's own
// folder.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
#import "Agent.h"

// Where a key is, most exposed first: in a commit not pushed yet, already pushed, sent to Claude, in another AI tool's
// records, in a file other accounts can read, and in your files.
extern NSArray<NSString *> *const kKeyGroups;

@interface KeyScan : NSObject
// Kept in `folder` (Whozmove's own, made readable by you only): what the last look found, the keys you ignored or
// marked replaced, how far each record was read, what was masked in Whozmove's records, the keys the line was put
// away for (closed.json, the storage module's), the fingerprints' secret, and Betterleaks' own home folder.
- (instancetype)initWithFolder:(NSString *)folder;
// Betterleaks' path: the app's own copy, or the one a print run is given.
@property (copy) NSString *scanner;
// How long one run of Betterleaks may take, in seconds, before it's stopped and its place read again next time: 300.
// A print run gives its sample look as long as it takes, so a busy Mac never cuts it short.
@property (assign) NSTimeInterval runFor;
// How many AI tools' records a look reads between keeping how far it has got (records.json): 300. A look a restart cuts
// off goes on, next time, from what it kept. How many it read in the last look (`recordsRead`); and for a print run, a
// look stopped, as a restart would stop it, once it has read `stopAfter` and kept that (`stopped` is told how many).
@property (assign) NSUInteger keepEvery, stopAfter;
@property (readonly) NSUInteger recordsRead;
@property (copy) void (^stopped)(NSUInteger read);
// Opens a file at a line in the editor you chose (the changes module's, FilesAtLines); NO while none is chosen.
@property (copy) BOOL (^openAtLine)(NSString *path, NSInteger line);
// The agents whose records are looked in (AgentRecords), each a key found there tied to its session and its project's
// folder; and what opens a session's conversation, or says why it can't (it isn't listed now).
@property (copy) NSArray<id<AgentRecords>> *agents;
@property (copy) NSString *(^openConversation)(NSString *sessionId);
// Whether macOS lets Whozmove look in Downloads (Full Disk Access), as last told.
@property (assign) BOOL fullDiskAccess;
// What the last look found, kept in found.json (nil for one a build that kept another shape left, `shape`): {lookedAt,
// shape, keys: [{id, rule, name, masked, group, band (now, soon or
// sample), left, sample, real (sample, ended, test, shape, kept, typed, sent or file), ends, shaped, actions, ways:
// [{action, place, title, menu}], places: [{group, how, where, file, line, checkout, project, repo, copy, inProject,
// commit, history, named, app, kind, session, folder, clear, downloads, trash, item, can, keep (why its file doesn't
// go to the Trash)}]}], putAway (the keys marked replaced or not a key, the same way, each
// with `put`: replaced or ignored), problem (what it couldn't finish), stopped (why it couldn't look at all), getAgain
// (what stopped it is put right by getting Whozmove again), tools (projects waiting on Apple's developer tools),
// skipped ({protected, downloads, most}: what it left out for want of Full Disk Access, or past 50,000 files),
// fullDiskAccess}, or nil before one. onChange is told the same, with `looking`; and while it looks, its keys and
// putAway are what this look has found as each of its places is read, with the last look's keys it hasn't come to yet,
// so none goes missing while it reads, and `soFar` says how far it has got: {read (how many places it has read), of
// (how many it reads), found (how many keys it has found that count)}. A press acts on the keys as they're told.
@property (readonly, copy) NSDictionary *found;
// What onChange is told, as it stands now: what was found, with `looking`, and while a look is under way, the keys as
// they're found and `soFar`. What's shown of Keys is this, never `found` alone, which is only the last look's.
- (NSDictionary *)told;
// Told on the main thread each time what was found changes, or a look starts or ends: `told`.
@property (copy) void (^onChange)(NSDictionary *found);
// Looks again, on its queue, in these checkouts and every other place; one look at a time.
- (void)lookIn:(NSArray<NSString *> *)checkouts;
// The same, waited for: what it found. Blocking; call off the main thread (a print run calls it on its own).
- (NSDictionary *)lookNowIn:(NSArray<NSString *> *)checkouts;
// The same, telling `soFar` on the look's own thread what it has found each time it has read one of its places: {keys,
// putAway, read, of, found}, as onChange's `soFar` says.
- (NSDictionary *)lookNowIn:(NSArray<NSString *> *)checkouts soFar:(void (^)(NSDictionary *found))soFar;
@property (readonly) BOOL looking;
// One of a key's actions, by the key's id: replace (its provider's page), replaced (marked replaced there, which
// Whozmove can't see), ignore, or undo (a key put away, brought back); or one of a place's, by its index in
// the key's places: open (the file at its line), private (a credential file made readable by you only), trash (the
// file to the Trash, never where an agent in `busy` is at work), conversation (its session opened) or clear (the
// agent's command that clears its records of the place's folder, put on the clipboard for you to run). Nil once done,
// else why it wasn't, or for clear what to do with the command. Only what this scan found is acted on, checked again
// first: with `file`, the place must still be about that file. On the main thread.
- (NSString *)act:(NSString *)action on:(NSString *)keyId place:(NSInteger)index file:(NSString *)file
            busy:(NSArray<NSString *> *)busy;
@end

// For the tests: how Keys judges a find in a line, as Betterleaks would report `match` (a part of `line`) under `rule`,
// by the plain functions a look uses: {judged (no key, id or counts), last (its last 4 characters), named (what it's
// set as or for)}. Betterleaks' own rules decide what's found; this checks what Keys makes of it, line by line.
NSDictionary *KeyJudged(NSString *rule, NSString *line, NSString *match);

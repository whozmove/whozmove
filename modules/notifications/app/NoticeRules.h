// NoticeRules: what the notifications module keeps for the user, as plain functions over its record
// (AppDir/notifications.json): what they put away, and until when. Checked by --print-notices, with no window.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
#import "Notice.h"

// The record, in the shape it's kept in:
//   { away: { "<from>/<key>": { since, at, awayFor } },   what × put away, and when (ms since 1970)
//     awayHere: { "<from>/<key>": since                   a page sender's notice put away, while it's said the same
//                 or { since, at, awayFor } },            way, or until `awayFor` seconds after `at` (ms since 1970)
//     besideSeen: { "<id>": since },                      what of each notice has been seen beside the folded panel
//                                                         (or was out there), so a restart brings out only what's new
//     besideSeenAt: { "<id>": at } }                      and when each was first seen (ms since 1970), kept apart so
//                                                         besideSeen stays one since for each id
// Every function returns a new record, and takes nil for none.

// A notice's id in the record: its sender, then its key.
NSString *NoticeId(Notice *notice);

// Whether `notice` is put away now, at `now` (ms since 1970): put away with the same `since`, and its `awayFor` (if it
// has one) not yet passed.
BOOL NoticeKeptAway(NSDictionary *record, Notice *notice, double now);
// Its ×: kept away until its `since` changes, or its `awayFor` passes.
NSDictionary *NoticePutAway(NSDictionary *record, Notice *notice, double now);
// A page sender's notice (core.noticeSenders) put away at `now`, by its id, while what makes it new is `since` (nil
// forgets it), or until `awayFor` seconds have passed (0 for only until it changes). One is kept for each id, the last
// put away, so the record stays small. The page decides from these which of its own it leaves out, or folds.
NSDictionary *NoticePutAwayHere(NSDictionary *record, NSString *noticeId, NSString *since, NSTimeInterval awayFor,
                                double now);

// Quiet hours: whether it's night at `minute` (minutes after midnight, by the Mac's clock), with quiet hours `on`
// from `from` to `to` (each minutes after midnight, 0 to 1439), which may cross midnight: from included, to not. The
// same from and to is never quiet. At night only what's urgent is said; the rest waits for the morning.
BOOL NoticeQuietAt(NSInteger minute, BOOL on, NSInteger from, NSInteger to);

// What of each notice the page has seen beside the folded panel, or had out there (`seen`: by its id, what made it new
// then, its `since`), kept at `now` so the page has it again after a restart: only a notice's ids (its sender and key,
// "from/key", each plain) and short sinces, 200 at most, those seen latest kept. One seen the same as before keeps when
// it was first seen.
NSDictionary *NoticeSeen(NSDictionary *record, NSDictionary *seen, double now);
// What the record keeps of that for the page, by id, its since; nil when it keeps none (a first launch), or keeps only
// what isn't a notice's.
NSDictionary *NoticeSeenKept(NSDictionary *record);

// --print-notices: each case, what the record's rules make of it.
int PrintNotices(NSArray<NSString *> *arguments);

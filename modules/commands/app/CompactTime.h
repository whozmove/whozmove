// CompactTime: whether now is a natural break to compact a session, the one rule the context ring's "Compact now" and
// Compact at Breaks both go by.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

@class Row;

// The kinds of break (CompactTime's `kind`): its work is saved, it's nearly full, or nobody has been on it for an hour.
extern NSString *const kCompactSaved, *const kCompactFull, *const kCompactAway;

// Whether now is a good time to compact a session, as {why, kind}, or nil. Only while it sits idle at its prompt with
// nothing asked, nothing going in from the panel, and a compaction able to go in (`noCompact` not set); not again
// once one from the panel has compacted it since its last message (`compactedAt`, in ms since 1970, or 0; for a
// session started before Whozmove's hooks, which record no messages, until its transcript moves again); and only
// once it's worth it, 200k or more in context (half that with a 200k window). Then at a natural break: once its work
// has just been saved (a turn that committed or went further, or its edits in its own checkout with nothing left to
// commit there); once it's nearly full (85%), as Claude would soon compact it by itself, in the middle of a task; or
// once neither it nor you have been on it for an hour (`onItAt`, `focused`: when you were last on it, and whether it's
// the one you're on), after which the next message has Claude read all of it again. Never for its size alone: a long
// conversation half-way through a task needs what it holds. A plain function, so --print-compact-time checks every
// case.
NSDictionary *CompactTime(Row *row, double onItAt, BOOL focused, double compactedAt, double now);

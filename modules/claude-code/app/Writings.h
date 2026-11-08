// Writings: what a session wrote for you to read (its plans, prototypes and notes), found in its transcript.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// What a part of a transcript says about writings: the calls that made them, oldest first, and the results of
// calls made earlier (`waiting`, the ids still without one) or in this part. Read on the transcripts' queue.
// `base` is where `chunk` starts in the file, so a plan's line can be found again to read it.
NSDictionary *WritingNews(NSData *chunk, NSUInteger end, unsigned long long base, NSSet<NSString *> *waiting);

// Adds that news to what's known of a session's writings, `state` being its transcript state: `writings`
// (key -> writing) and `waiting` (call id -> the writing it decides). On the main thread.
void AddWritingNews(NSMutableDictionary *state, NSDictionary *news);

// How this part of a session's transcript state is kept across restarts (Transcripts' kept reads): its writings and
// the calls they wait on, as they are, plain JSON; and taken back into `state`, every value checked for its kind (a
// page's address for https) and the count for its limits. NO, with `state` as it was, for any that doesn't fit.
NSDictionary *KeptWritings(NSDictionary *state);
BOOL TakeBackWritings(NSDictionary *kept, NSMutableDictionary *state);

// A session's writings for its row, newest first, without where each is kept in the transcript.
NSArray<NSDictionary *> *RowWritings(NSDictionary *state);

// One writing's text: a plan as it was when Claude asked, from the transcript, or a file as it is now.
// {text} or {missing: why it can't be shown}. Off the main thread: a file can be large.
NSDictionary *ReadWriting(NSString *transcriptPath, NSDictionary *writing);

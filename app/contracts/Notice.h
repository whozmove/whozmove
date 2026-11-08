// Notice: what a module has to tell the user now, and how important it is. A module lists its notices each time it's
// asked; the notifications module decides what shows, when and where, and a press on one runs the sender's own `press`,
// so no module ever calls another.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// How much it needs the user: nothing to do; something to do when they can; something stops or waits without them.
// The sender says which, and nothing raises or lowers it.
typedef NS_ENUM(NSInteger, NoticeLevel) {
    NoticeGoodToKnow,
    NoticeSoon,
    NoticeUrgent,
};

@interface Notice : NSObject
+ (instancetype)noticeWithKey:(NSString *)key level:(NoticeLevel)level text:(NSString *)text;
@property (readonly, copy) NSString *key;    // the sender's own, one to each of its notices: "update", "disk"
@property (readonly) NoticeLevel level;
@property (readonly, copy) NSString *text;   // one sentence, as the line under the header says it
// A few words, for a place that has a title of its own (macOS's banner); nil for the sender's name.
@property (copy) NSString *title;
// What makes it new: put away with its ×, it stays away until this changes, or until `awayFor` seconds have passed
// (0 for only until it changes).
@property (copy) NSString *since;
@property NSTimeInterval awayFor;
// The one thing it asks of the user ("Try It"), or nil; and what pressing it does, always the sender's own.
@property (copy) NSString *button;
@property (copy) void (^press)(void);
// Said on the button a moment after a press ("Copied"), or nil.
@property (copy) NSString *pressedWord;
// What a press set going is under way, so its button waits; it has a ×; it says all went well (a tick, and it goes by
// itself once seen).
@property BOOL busy, closes, done;
// A word drawn before its sentence as the kit's Tag ("New"), or nil.
@property (copy) NSString *tag;
// The sender says the user is looking at what it's about now (its own page open on it), so it isn't said meanwhile.
@property BOOL seenNow;
// It answers something the user has just done (why a press did nothing), so it's said at once, at night too.
@property BOOL answersYou;
// The id of the session it's about, or nil for one about no session.
@property (copy) NSString *session;
// How long it's out at most where it comes out by itself, in seconds, or 0 for none: beside the folded panel takes
// only one that says.
@property NSTimeInterval outFor;
// The sender's module name, set as the notices are gathered (NoticeGathering.h), never by the sender.
@property (readonly, copy) NSString *from;
// What a place does for a press on its button, and for its ×. A press runs the sender's `press`, and nothing while the
// button waits (`busy`).
- (void)pressButton;
- (void)putAway;
@end


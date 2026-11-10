// Asks: permission requests waiting in the panel, asked by the permission hook over its line to the panel (HookLine),
// and the answers given there, which go back only down that line.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// The requests waiting, the oldest per session: sessionId -> the request as its card shows it. A session that started
// before Whozmove's update runs a hook that leaves its request in a file instead, which the panel shows, marked
// `legacy`, but never answers, as anything running as you could answer it that way too. One that goes by itself if no
// one answers (`expiresAt`) carries its session's whole wait (`waits`, ms: Don't Wait on Me's).
NSDictionary<NSString *, NSDictionary *> *PendingAsks(void);
// Whether a request's card is given its input cut short (`truncated`, as PendingAsks marks it), for that request
// itself, whichever of its session's is the oldest.
BOOL AskShownCut(NSDictionary *request);
// Passes an answer given in the panel down its request's line, for the hook to pass on.
void AnswerAsk(NSDictionary *msg);
// A request's id as the hook makes them (hex), or nil for anything else.
NSString *AskId(id value);
// The reply an answer sends down a request's line, from what the panel's page sends ({allow, answers, message, stop}):
// the answers clipped and at most four, notes and stop only with a deny. And sending it, once: NO if the request has
// gone or was answered already.
NSDictionary *AskReply(NSDictionary *msg);
BOOL SendAnswer(NSString *askId, NSDictionary *reply);
// Holds a request while you're answering it, in the panel or in its session's tab: no session you allow answers it for
// you meanwhile, and one that goes by itself if no one answers (Don't Wait on Me) gets at least another minute from now.
void HoldAsk(NSString *askId);

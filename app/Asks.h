// Asks: permission requests waiting in the panel, left by the permission hook, and the answers given there.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// The requests waiting, the oldest per session: sessionId -> the request as its card shows it.
NSDictionary<NSString *, NSDictionary *> *PendingAsks(void);
// Leaves an answer given in the panel for the hook to pass on.
void AnswerAsk(NSDictionary *msg);

// JiraCard: what Jira's page on the panel's back says (the apps module's card: {figure, lines, actions}) for each way
// the sign-in can stand, with a way forward from each. A plain function, so the tests print every state.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
#import "Tracker.h"

// `sites`, the Jira sites you're on; `why`, the sign-in's own reason when it isn't signed in; `copied`, whether What to
// Ask has just been copied; `readsOnly`, whether the sign-in held can't write (kept before Whozmove asked to), so
// moving tickets needs signing in again.
NSDictionary *JiraCard(TrackerSignIn state, NSArray<NSString *> *sites, NSString *why, BOOL copied, BOOL readsOnly);

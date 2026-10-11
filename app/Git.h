// Git: a checkout's branch, worktree and status.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

NSDictionary *GitInfo(NSString *cwd);
NSDictionary *FetchCheckoutState(NSString *root);

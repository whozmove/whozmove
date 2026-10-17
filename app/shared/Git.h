// Git: a checkout's branch, worktree, status, its base branch and its new files.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

NSDictionary *GitInfo(NSString *cwd);
NSDictionary *FetchCheckoutState(NSString *root);
NSDictionary *FetchChangeCounts(NSString *root, NSDictionary *state);
NSString *BranchStart(NSString *root, NSString **base, NSString **baseRef);

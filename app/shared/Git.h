// Git: a checkout's branch, worktree, status, its base branch (GitHub's and this Mac's), its new files, when its last
// commit was made, and the branches GitHub's copy of its repo has.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

NSDictionary *GitInfo(NSString *cwd);
NSDictionary *FetchCheckoutState(NSString *root);
NSDictionary *FetchChangeCounts(NSString *root);
NSArray<NSString *> *RemoteBranches(NSString *root);
NSString *BranchStart(NSString *root, NSString **base, NSString **baseRef);
NSString *LocalBaseBranch(NSString *root);

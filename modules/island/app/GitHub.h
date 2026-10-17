// GitHub: what gh says about pull requests and their checks.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

extern BOOL NeverAskGitHub;
NSString *GhPath(void);
extern NSString *const kPRFields;
NSDictionary *FetchPRStatus(NSString *gh, NSString *url);
NSString *ChecksState(NSArray *rollup);
id FetchBranchPR(NSString *gh, NSString *root, NSString *branch, BOOL *found);

// GitHub: what gh says about pull requests and their checks.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

extern BOOL NeverAskGitHub;
NSString *GhPath(void);
extern NSString *const kPRFields;
NSDictionary *FetchPRStatus(NSString *gh, NSString *url);
NSString *ChecksState(NSArray *rollup);
id FetchBranchPR(NSString *gh, NSString *root, NSString *branch, BOOL *found);
// A waiting session's pull request, as gh gives it with its comments and reviews (kPRActivityFields), or nil. Blocking.
extern NSString *const kPRActivityFields;
NSDictionary *FetchPRActivity(NSString *gh, NSString *url);
// What it has had, oldest first, each {kind, by, at}: commented, approved or changes (a review asking for changes),
// only from someone GitHub marks as able to change the repo and never a bot; merged; closed. Times in ms since 1970.
NSArray<NSDictionary *> *PRActivityEvents(NSDictionary *activity);

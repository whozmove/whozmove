// PullRequests: the PRs each session made or worked on, and their state.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

@class Transcripts;

@interface PullRequests : NSObject
// The PRs are the ones these transcripts recorded.
- (instancetype)initWithTranscripts:(Transcripts *)transcripts;
// Asks GitHub about each listed session's PRs that are due a check.
- (void)check;
// A session's PRs with what's known about them, newest first.
- (NSArray *)prsFor:(NSString *)sessionId;
@end

// Ghostty: finding a session's Ghostty tab, focusing it and typing into it, through AppleScript.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
#import "Terminal.h"

@class Transcripts;

@interface Ghostty : NSObject <Terminal>
// A session's tab is told by the topic Claude Code gives it, which its transcript records.
- (instancetype)initWithTranscripts:(Transcripts *)transcripts;
@end

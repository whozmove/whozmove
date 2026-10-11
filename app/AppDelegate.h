// AppDelegate: the app itself. It creates the pieces and wires them together, runs the 1-second tick and opens
// sessions.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>

@class Row, Checkouts, Transcripts, AgentDetails;

@interface AppDelegate : NSObject <NSApplicationDelegate>
// The rows for the page: every listed session, with all that's known about it. Their files are read alongside
// (Sessions) and the rest is added on the main thread, where `done` gets them, or nil if something went wrong
// (it's logged).
- (void)readRows:(void (^)(NSArray<Row *> *rows))done;
// The pieces a test run looks into (main.m).
@property (readonly) Checkouts *checkouts;
@property (readonly) Transcripts *transcripts;
@property (readonly) AgentDetails *agentDetails;
@end

// Commands: a slash command from the panel (model, effort, mode, compact), from its menu to its result.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>

@class Page, PanelWindow, AgentDetails, Transcripts, ClaudeDesktop, Row;
@protocol Terminal;

@interface Commands : NSObject
// Commands go into sessions in these terminals, and into Claude Desktop conversations; their results show in the
// sessions' transcripts.
- (instancetype)initWithPage:(Page *)page window:(PanelWindow *)window agentDetails:(AgentDetails *)agentDetails
                 transcripts:(Transcripts *)transcripts terminals:(NSArray<id<Terminal>> *)terminals
               claudeDesktop:(ClaudeDesktop *)claudeDesktop;
// The rows last sent to the page, by session id: what the menus and cards act on.
@property (copy) NSDictionary<NSString *, Row *> *rowsById;
// Called when a row has something new to show: a pick, or a compaction starting or ending.
@property (copy) void (^onChange)(void);

// The page's messages: a click on a model, effort or mode (its menu), the Compact card's choice, and an answer
// to "Switch model?" asked in the panel.
- (void)pick:(NSDictionary *)msg;
- (void)compact:(NSDictionary *)msg;
- (void)answerSwitch:(NSDictionary *)msg;

// For a session's row: what was picked for it and not confirmed yet, and when a /compact sent from the panel
// began.
- (NSDictionary *)chosenFor:(NSString *)sessionId;
- (NSNumber *)compactingSince:(NSString *)sessionId;
// Forgets what was picked for sessions no longer listed, once nothing can still be waiting on it.
- (void)keepPicksOf:(NSArray<Row *> *)rows;
@end

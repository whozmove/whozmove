// ClaudeCode: Claude Code's face for the core (contracts/Module.h), and the agent it is (contracts/Agent.h): its
// sessions as the rows are read (its terminal sessions kept once they've ended too), what its transcripts say added to
// each row, its menus' choices and commands and reading their results, its prompt, your plan's usage, new sessions and
// ended ones carried on, folder trust, and its page's messages.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
#import "Module.h"
#import "Agent.h"

@class Transcripts, AgentDetails;

@interface ClaudeCode : NSObject <Module, AgentWork, AgentCommands, AgentPrompt, AgentUsage, AgentStarts>
// What its sessions' transcripts say, and each session's details, which its print modes look into.
@property (readonly) Transcripts *transcripts;
@property (readonly) AgentDetails *details;
@end

// Its print modes, for the tests (ClaudeCodePrints.m).
NSDictionary<NSString *, PrintMode> *ClaudeCodePrintModes(void);

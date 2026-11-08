// ClaudeCode: Claude Code's face for the core (contracts/Module.h), and the agent it is (contracts/Agent.h): its
// sessions as the rows are read (its terminal sessions kept once they've ended too), what its transcripts say added to
// each row, questions asked on a session's side, its menus' choices and commands and reading their results, its
// prompt, your plan's usage, new sessions and
// ended ones carried on, folder trust, Whozmove's hooks in it, the sessions that don't wait on you, its voice mode,
// where it keeps what its sessions were told and read, and its page's messages.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
#import "Module.h"
#import "Agent.h"

@class Transcripts, AgentDetails, AnswerFor;

@interface ClaudeCode : NSObject <Module, AgentWork, AgentBetweenSteps, AgentAside, AgentCommands, AgentPrompt,
                                    AgentUsage, AgentStarts, AgentInstall, AgentVoice, AgentRecords,
                                    AgentConversations>
// What its sessions' transcripts say, each session's details, and what a session you allow answers for you, which its
// print modes look into.
@property (readonly) Transcripts *transcripts;
@property (readonly) AgentDetails *details;
@property (readonly) AnswerFor *answerFor;
// Takes away Don't Wait on Me's file for each session whose switch isn't kept, as it does as the app opens, and returns
// those sessions.
- (NSArray<NSString *> *)dropDontWaitWithoutSwitch;
@end

// Its print modes, for the tests (ClaudeCodePrints.m).
NSDictionary<NSString *, PrintMode> *ClaudeCodePrintModes(void);

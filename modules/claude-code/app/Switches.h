// Switches: Claude Code's "Switch model?" for a switch the panel asks for, through the permission hook's part for model
// switches (PreModelSwitch, in hooks/whozmove-claude-permission.py): the panel's note that it's switching a session's
// model, the hook's question while it waits for the panel, and the panel's answer, in the switches folder of
// Whozmove's own folder.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// Leaves the note right before /model goes in: the hook then takes the switch to that model, within kNoteLasts, as the
// panel's, once. With no model, takes it back, once the command is over.
void NoteSwitch(NSString *sessionId, NSString *model);
// The hook's question for a session while its hook waits for the panel: {from, to, tokens} (the models, and how much
// the conversation holds, or NSNull), else nil.
NSDictionary *SwitchQuestion(NSString *sessionId);
// The panel's answer to that question: switch, or keep the model.
void AnswerSwitch(NSString *sessionId, BOOL allow);
// Whether the session with that process has the hook that asks in the panel: Claude Code gives a session the hooks it
// had as the session started, so the hooks put in place in Whozmove's folder have that part, and the session started
// after hooks with it first were (not after they were last put in place, which every later change of them moves).
BOOL SessionAsksSwitches(pid_t pid);

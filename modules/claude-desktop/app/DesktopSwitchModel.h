// DesktopSwitchModel: Claude Desktop's "Switch model?", which it asks before re-reading a cached conversation: whether
// it would ask, never asking again once "Don't ask again" is chosen, whether its box is up, and answering it.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

@class Row;

BOOL ClaudeMayAskToSwitch(Row *row);
void StopClaudeAskingToSwitch(void);
BOOL ClaudeShowsSwitchBox(void);
// Answers Claude's box. NO if it isn't up.
BOOL AnswerClaudeSwitchBox(BOOL switchModel, BOOL dontAskAgain);

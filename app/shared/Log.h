// Log: the panel's log file, panel.log in Whozmove's own folder.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

void PanelLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
void LogProblem(NSString *text);

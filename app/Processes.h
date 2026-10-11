// Processes: running processes, the app each belongs to, the flags it started with, and running tools.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>

BOOL ProcessAlive(pid_t pid);
NSString *ProcessKey(pid_t pid, NSString *procStart);
NSRunningApplication *OwningApp(pid_t pid);
NSArray<NSString *> *ProcessArguments(pid_t pid);
NSString *FlagValue(NSArray<NSString *> *args, NSString *flag);
NSDictionary *RunTool(NSString *path, NSArray<NSString *> *arguments, NSString *directory);
NSString *RunAppleScript(NSString *source);

// ToolsFacts: what Whozmove relies on about how macOS puts Apple's command line developer tools in, which a new macOS
// could change. When it does, the fix goes here. The version these were last checked with is in the README ("Tested
// with").
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// The command that asks for them, `xcode-select --install`: macOS asks whether to install them, in a window of its
// own, and puts them in from there. It returns at once, before you've answered.
extern NSString *const kToolsInstallCommand, *const kToolsInstallFlag;
// That window's app (Install Command Line Developer Tools, in /System/Library/CoreServices), open from its question
// until they're in or you close it.
extern NSString *const kToolsInstallerId;

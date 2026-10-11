// Files: where Whozmove's and Claude Code's files are, and reading them: JSON, JSONL lines, times.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

NSString *Home(void);
NSString *ClaudeDir(NSString *sub);
NSString *AppDir(NSString *sub);
extern BOOL MachineFilesInHome;
NSString *MachineFile(NSString *path);
id ReadJSON(NSString *path);
NSString *Clip(NSString *text, NSUInteger max);
double TimestampMs(id iso);
id JSONLineAt(NSData *chunk, NSUInteger location, NSUInteger end, NSRange *line);

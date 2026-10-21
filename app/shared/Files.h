// Files: where Whozmove's files are, and reading files: JSON, JSONL lines, times.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

NSString *Home(void);
// Whether that home folder is the account's own, not a throwaway one a test gives: a print run that would change what's
// in it refuses to run there.
BOOL HomeIsYourOwn(void);
NSString *AppDir(NSString *sub);
extern BOOL MachineFilesInHome;
NSString *MachineFile(NSString *path);
id ReadJSON(NSString *path);
// What comes from outside (a JSON file, the page, another app) checked for its kind: anything else counts as missing.
NSString *AsText(id value);
NSNumber *AsNumber(id value);
NSArray *AsList(id value);
NSDictionary *AsRecord(id value);
NSString *RealPath(NSString *path);
NSString *Clip(NSString *text, NSUInteger max);
double TimestampMs(id iso);
id JSONLineAt(NSData *chunk, NSUInteger location, NSUInteger end, NSRange *line);

// Files: where Whozmove's files are, and reading files: JSON, JSONL lines, times.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

NSString *Home(void);
// Whether that home folder is the account's own, not a throwaway one a test gives: a print run that would change what's
// in it refuses to run there. One that can't be told counts as yours.
BOOL HomeIsYourOwn(void);
// The same, but one that can't be told doesn't count: for what must never happen from a throwaway home.
BOOL HomeSurelyYourOwn(void);
NSString *AppDir(NSString *sub);
// Whether macOS lets Whozmove read what it keeps from apps (Full Disk Access), found without asking anything.
BOOL FullDiskAccess(void);
// Opens System Settings at Full Disk Access, with Whozmove in its list, switched off, for you to turn on; nothing is
// asked of you on the way.
void ShowFullDiskAccessSettings(void);
extern BOOL MachineFilesInHome;
NSString *MachineFile(NSString *path);
id ReadJSON(NSString *path);
// ReadJSON, and a small text file, kept: a file is read again only once it has changed (its size, its date or the file
// itself), as most of those read every second haven't. What comes back is shared, so it's never changed. Nothing is
// kept for a file that isn't there or can't be read, so one caught half-written is read again the next time.
id ReadJSONKept(NSString *path);
NSString *ReadTextKept(NSString *path);
// When a file was last written, in seconds since 1970 (0 when it isn't there), from stat: NSFileManager's attributes
// read every extended attribute of the file too.
double FileModifiedAt(NSString *path);
// What comes from outside (a JSON file, the page, another app) checked for its kind: anything else counts as missing.
NSString *AsText(id value);
NSNumber *AsNumber(id value);
NSArray *AsList(id value);
NSDictionary *AsRecord(id value);
NSString *RealPath(NSString *path);
// Whether `path` is `folder` or inside it, by their real paths (a link to either counts as where it leads): no when
// either is missing or empty.
BOOL PathWithin(NSString *path, NSString *folder);
NSString *Clip(NSString *text, NSUInteger max);
double TimestampMs(id iso);
id JSONLineAt(NSData *chunk, NSUInteger location, NSUInteger end, NSRange *line);

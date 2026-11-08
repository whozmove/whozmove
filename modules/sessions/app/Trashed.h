// Trashed: the conversations Sessions moved to the Trash, each with where every one of its files went, so Undo and Put
// Back bring it back whole, until the Trash is emptied.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

@interface Trashed : NSObject
// Its notes, one file per conversation in `folder` (only yours can read them). Files go to macOS's own Trash, each
// moved by a run of `helper` (the app's own executable) with --helper-trash-item, or, given `standIn` (a print run's,
// as macOS's Trash is your account's whatever HOME says), into that folder instead: moved there by `helper` when the
// print run gives a stand-in one, else by Trashed itself. `isPlace` says whether a path is
// where one of a conversation's files would be (the agent's isPlaceOfConversation:): nothing goes back anywhere else.
- (instancetype)initWithFolder:(NSString *)folder helper:(NSString *)helper standIn:(NSString *)standIn
                       isPlace:(BOOL (^)(NSString *path))isPlace;
// Moves every one of a conversation's files to the Trash, or none: if one can't go, those that went come back. `about`
// is kept with them ({title, folder}). Nil once it's done, else why not, in a few words, with the file that stayed
// (`stuck`); or, `lost`, a file that went to the Trash without saying where, the rest having come back.
- (NSString *)trash:(NSString *)conversationId files:(NSArray<NSString *> *)files about:(NSDictionary *)about
              stuck:(NSString **)stuck lost:(BOOL *)lost;
// Puts each of a conversation's files back where it was, only while it's still in the Trash and nothing is there in its
// place. Nil once it's done, else why not.
- (NSString *)putBack:(NSString *)conversationId;
// What's in the Trash now, newest first, each {id, title, folder, at}; one with none of its files left there (the Trash
// emptied, or Finder's Put Back) is forgotten, and a file Finder put back under the name the Trash gave it gets its
// own back.
- (NSArray<NSDictionary *> *)now;
// Where a conversation's files are in the Trash, for Show in Finder.
- (NSArray<NSString *> *)placesOf:(NSString *)conversationId;
@end

// A plain absolute path, with no "." or ".." in it.
BOOL PlainPath(NSString *path);
// The Trash a file in `folder` goes to: the home folder's (from HOME), or, on another disk, that disk's own; nil when
// the folder can't be read.
NSString *TrashFolderFor(NSString *folder);

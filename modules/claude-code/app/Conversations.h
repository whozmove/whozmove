// Conversations: every conversation Claude Code keeps on this Mac, for Sessions on the panel's back
// (AgentConversations): each read from its transcript's first and last parts, and kept by the file's size and date.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

@interface Conversations : NSObject
// Each conversation, newest first, as {id, folder, title, movedAt, ranIn}: see AgentConversations. A file is read again
// only once its size or date has changed, so asking every few seconds costs little. Off the main thread.
- (NSArray<NSDictionary *> *)all;
@end

// The files a conversation is made of, each a path there now: its transcript, the folder beside it (its sub-agents'
// and tools' records), its copies of the files it edited, and Whozmove's own note of it (the hook's record, and the one
// kept once it ended).
NSArray<NSString *> *ConversationFiles(NSString *conversationId);
// Whether a path is where one of those files would be, there now or not: <id>.jsonl or <id> in a project's folder (not
// one that's a link), file-history's <id>, or Whozmove's notes of it, with only the folders they're kept in resolved.
BOOL IsConversationPlace(NSString *path);

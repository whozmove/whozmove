// Talking: whether you're talking to an agent right now, by voice, from who is recording from a microphone (Audio):
// one of an agent's sessions taking your voice (Claude Code's voice mode), an app that holds sessions as its own
// (Claude Desktop's dictation), or any other app whose recording began while you were on a session (a dictation app
// such as macOS Dictation into its terminal tab or Claude Desktop, or into one of the panel's own boxes). A recording
// that was already going when you came to the session (a call) never counts. It follows the recording, not your voice:
// a pause inside one talk is still talking; only the recording stopping ends it.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

@class Core, Row;

@interface Talking : NSObject
- (instancetype)initWithCore:(Core *)core;
// Tells `changed` each time you start or stop talking to an agent, from now on, until what this returns is given to
// unfollow:. Microphones are listened to only while something follows, and never in a print run. Before macOS 14, which
// can't say who records, nothing is ever talking.
- (id)follow:(void (^)(BOOL talking))changed;
- (void)unfollow:(id)follower;
// Why a recording counts, from what was known as it began: "voice" (one of an agent's sessions takes your voice),
// "app" (an app that holds sessions as its own, while they're tracked), "panel" (a window of Whozmove's had the
// keyboard: one of its boxes), "front" (Claude Desktop in front, or a terminal whose tab shows a listed session), or
// nil for none. `recording` is {pid, parent, path, app}: its process, that process's parent, its program, and the app
// it belongs to; `then` is {front, tab, keyboard, going}: the app in front, the listed session its tab shows, whether
// a window of Whozmove's had the keyboard, and whether the recording was already going when listening began.
- (NSString *)whyCounts:(NSDictionary *)recording then:(NSDictionary *)then rows:(NSArray<Row *> *)rows;
@end

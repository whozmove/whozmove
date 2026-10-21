// LyricsStore: what LRCLIB found about the songs played, kept on this Mac, so a song played again has its lyrics at once
// without asking LRCLIB. One file a song, in a folder of Whozmove's own, for the last 1,000 songs.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

@interface LyricsStore : NSObject
- (instancetype)initWithFolder:(NSString *)folder;
// What's kept about `track` (as `keep:` was given it, with `keptAt`), or nil, handed to `then` on the main thread.
- (void)read:(NSString *)track then:(void (^)(NSDictionary *kept))then;
// What LRCLIB answered about a song, `{state, track, …}`, kept with when (`keptAt`, ms).
- (void)keep:(NSDictionary *)found;
// Everything kept goes, the folder too.
- (void)forgetAll;
@end

// The parts modules/spotify/tests/test.sh checks, through --print-spotify.
// The name of the file `track` is kept in: a hash of it, as a track can be any length and hold any character.
NSString *LyricsKeptName(NSString *track);

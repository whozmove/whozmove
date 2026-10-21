// SpotifyToken: Spotify's round token, tucked half under the panel at its bottom corner, on the side facing the
// screen's middle (the core's EdgeIcon). It plays, resumes, or gets Spotify, as Spotify.m's TokenFor says, and gives
// way to the now-playing strip while a song plays.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "EdgeIcon.h"

@interface SpotifyToken : EdgeIcon
// What to show, as TokenFor gives it; a state of hidden tucks it under the glass.
- (void)show:(NSDictionary *)token;
// The now-playing strip has folded away: a paused song's token comes out now, not before.
- (void)stripFolded;
// The token was pressed, in the state it showed. For Play, it's called once the token has gone under the glass.
@property (copy) void (^onPress)(NSString *state);
@end

// SpotifyToken: Spotify's round token, tucked half under the panel at its bottom corner, on the side facing the
// screen's middle. It plays, resumes, or gets Spotify, as Spotify.m's TokenFor says, and gives way to the now-playing
// strip while a song plays.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>

@interface SpotifyToken : NSObject
// Its own small window, which the panel holds under itself (PanelWindow attachBelow:).
@property (readonly) NSWindow *window;
// Off (its switch, or Show the song, on Spotify's page on the panel's back), the token tucks away and stays away.
@property (nonatomic) BOOL shown;
// What to show, as TokenFor gives it; a state of hidden tucks it under the glass.
- (void)show:(NSDictionary *)token;
// Where the panel's glass is on the screen, where its list is (the reader grows beside it), and the screen's room; it
// gets there over `duration` seconds (the reader growing and folding), or at once (a drag).
- (void)glassAt:(NSRect)glass list:(NSRect)list screen:(NSRect)screen duration:(NSTimeInterval)duration;
// The pointer, wherever it is: the token leans toward it as it comes near, and takes clicks only while it's over it.
- (void)pointerAt:(NSPoint)point;
// The now-playing strip has folded away: a paused song's token comes out now, not before.
- (void)stripFolded;
// The panel is opening out of the cat: the token stays under the glass until the glass has come to rest, then comes
// out with one small bounce.
- (void)panelOpening;
// Back out after a press that couldn't go through.
- (void)untuck;
// The token was pressed, in the state it showed. For Play, it's called once the token has gone under the glass.
@property (copy) void (^onPress)(NSString *state);
@end

// Which side of the panel the token is on, from where the list is on the screen: the side facing the screen's middle,
// so a panel at the left has it at its right. Across the middle it changes only past a little leeway, so a panel
// dragged along the middle doesn't send it back and forth. `current` is nil at first.
NSString *TokenSideFor(NSRect list, NSRect screen, NSString *current);

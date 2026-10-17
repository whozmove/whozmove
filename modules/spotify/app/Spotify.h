// Spotify: the song the Spotify app on this Mac is playing, for the now-playing strip, what its token at the panel's
// corner shows (SpotifyToken), and its controls.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>

@class Page;

@interface Spotify : NSObject
- (instancetype)initWithPage:(Page *)page;
// The pawn menu's Spotify ▸ Remove Spotify turns it off, Add Spotify on. While it's off the page gets nothing and Spotify is never asked anything, so
// macOS never asks whether Whozmove may control it.
@property (nonatomic) BOOL shown;
// A freshly loaded page gets what's known.
- (void)resend;
// A control pressed on the strip: playpause, next, previous, seek (to `fraction` of the song), open (Spotify comes
// forward) or settings (System Settings, where Whozmove is allowed to control Spotify).
- (void)control:(NSString *)action fraction:(double)fraction;
// Play, pressed on the token: Spotify opens in the background if it isn't running, and plays what it last had. With
// nothing to play (signed out, or a new account), Spotify comes forward instead, and plays by itself if a song turns
// up within a few minutes (once you've signed in). NO if it can't start (Spotify gone, say), so the token comes back.
- (BOOL)play;
// Whether the panel is folded to its header: the strip has no room then, so the token stands in for it.
@property (nonatomic) BOOL collapsed;
// Spotify's download page, in your browser: Whozmove installs nothing itself, and notices once Spotify is installed.
- (void)getSpotify;
// What the token shows, as TokenFor gives it, each time that changes; and looked at again now (the strip has folded).
@property (copy) void (^onToken)(NSDictionary *token);
- (void)refreshToken;
@end

// Whether Spotify is on this Mac (and not in the Bin).
BOOL SpotifyInstalled(void);

// The parts tests/rows.sh checks, through --print-spotify. Each gives the song as the page gets it (docs say what's
// in it, in Spotify.m), with `now` in milliseconds since 1970 as when its position was right; nil when nothing plays.
// From what Spotify tells the whole Mac when the song or its state changes:
NSDictionary *SongFromAnnouncement(NSDictionary *info, double now);
// From what reading it returns: the track's id, name, artist, album, length (ms), position (s), the state and the
// cover's address, in that order; none when Spotify is stopped.
NSDictionary *SongFromReply(NSArray *fields, double now);
// Whether an Apple event's error is macOS refusing Whozmove control of Spotify.
BOOL ControlRefused(OSStatus status);
// Whether the song is in the now-playing strip at `now`: while it plays, and for 15 minutes after it's paused.
BOOL SongInStrip(NSDictionary *song, double now);
// What the token shows: {state, title, artist, artUrl, progress}, where state is missing (Download), ready (Play),
// paused (the song, to resume), playing (the song, to pause: only while the panel is folded), refused (macOS hasn't
// allowed Whozmove to control Spotify: Open Settings) or hidden (Spotify starting, or the song in the strip: then
// `strip` is YES). `allowed` is macOS's answer, nil until known; `collapsed`, whether the panel is folded.
NSDictionary *TokenFor(BOOL installed, NSDictionary *song, BOOL starting, NSNumber *allowed, BOOL collapsed,
                       double now);

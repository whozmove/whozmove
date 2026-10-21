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
// Whether the panel is folded into the cat: neither the strip nor the token shows then.
@property (nonatomic) BOOL collapsed;
// Spotify's download page, in your browser: Whozmove installs nothing itself, and notices once Spotify is installed.
- (void)getSpotify;
// Spotify comes forward, opening if it isn't running (the pawn menu's Spotify ▸ Open Spotify).
- (void)open;
// What the token shows, as TokenFor gives it, each time that changes; and looked at again now (the strip has folded).
@property (copy) void (^onToken)(NSDictionary *token);
- (void)refreshToken;
// The song each time it changes, as the page gets it, or nil once nothing plays or Spotify is removed: for its lyrics.
@property (copy) void (^onSong)(NSDictionary *song);
// While the song's lyrics follow it: where Spotify is in it is asked every few seconds, so a jump made in Spotify
// itself (or the song starting over) shows in the lyrics within a few seconds, rather than at the next full read.
@property (nonatomic) BOOL following;
@end

// Whether Spotify is on this Mac (and not in the Bin).
BOOL SpotifyInstalled(void);

// The parts modules/spotify/tests/test.sh checks, through --print-spotify. Each gives the song as the page gets it
// (docs say what's in it, in Spotify.m), with `now` in milliseconds since 1970 as when its position was right; nil
// when nothing plays.
// From what Spotify tells the whole Mac when the song or its state changes:
NSDictionary *SongFromAnnouncement(NSDictionary *info, double now);
// From what reading it returns: the track's id, name, artist, album, length (ms), position (s), the state and the
// cover's address, in that order; none when Spotify is stopped.
NSDictionary *SongFromReply(NSArray *fields, double now);
// Whether an Apple event's error is macOS refusing Whozmove control of Spotify.
BOOL ControlRefused(OSStatus status);
// Whether the song is in the now-playing strip at `now`: while it plays, and for 15 minutes after it's paused.
BOOL SongInStrip(NSDictionary *song, double now);
// Whether Spotify's position `positionMs`, read at `at`, is far enough from where `song` says it would be by then that
// the page is told: the song was jumped in, in Spotify itself, or it started over.
BOOL PositionMoved(NSDictionary *song, double positionMs, double at);
// What the token shows: {state, title, artist, artUrl, progress}, where state is missing (Download), ready (Play),
// paused (the song, to resume), refused (macOS hasn't allowed Whozmove to control Spotify: Open Settings) or hidden
// (the panel folded into the cat, Spotify starting, or the song in the strip: then `strip` is YES). `allowed` is
// macOS's answer, nil until known; `collapsed`, whether the panel is folded.
NSDictionary *TokenFor(BOOL installed, NSDictionary *song, BOOL starting, NSNumber *allowed, BOOL collapsed,
                       double now);

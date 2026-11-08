// SpotifyVolume: Spotify quieter while you talk to an agent (the core's Talking), and back after. It turns the music
// down a point at a time to a share of its volume as you start, and once you've stopped, back up the same way to
// exactly the volume it had, never above it. If you change Spotify's volume yourself meanwhile, it lets go and leaves
// yours.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

@interface SpotifyVolume : NSObject
// Whether it's on (Quieter while you talk to Claude): turned off while the music is lowered, it brings it back first.
@property (nonatomic) BOOL on;
// How far down, as a share of the volume Spotify had (0 to 1).
@property (assign) double share;
// You've started or stopped talking to an agent.
- (void)talking:(BOOL)talking;
// Each time the music goes down, and each time it starts back up or is let go: for the now-playing strip's sign.
@property (copy) void (^onQuieter)(BOOL quieter);
// Puts back a volume a quit or a crash left lowered (kept in the app's preferences), now and each time Spotify starts.
- (void)start;
// Whether Whozmove may control Spotify, which lowering the music needs, for the card on Spotify's page: "allowed",
// "ask" (macOS hasn't asked yet), "denied", "closed" (Spotify isn't open, so macOS can't say), or nil until known. It's
// what was last found, looked up again off the main thread once it's a few seconds old.
- (NSString *)control;
// Your press on the card's Allow: macOS asks you whether Whozmove may control Spotify, `allowing` until you've
// answered.
- (void)allowControl;
@property (readonly) BOOL allowing;
@end

// The parts modules/spotify/tests/test.sh checks, through --print-spotify.
// The volume to lower `from` to, for a share of it: never 0, and NSNotFound when that isn't below `from`.
NSInteger SpotifyQuieterTarget(NSInteger from, double share);
// The volume `ms` into turning it from `from` to `to`, as a steady hand turns a knob: one point at once, then one more
// every 60 ms going down, or every 30 ms going up, until it's there.
NSInteger SpotifyTurnAt(NSInteger from, NSInteger to, double ms);
// What to set for Spotify to read back `volume`, or as close under it as it can be (SpotifyFacts.h, its rounding).
NSInteger SpotifyVolumeToSet(NSInteger volume);
// Whether a volume read back is one Whozmove left: within one of the last it set, or of one it set a moment before
// `now` (ms), as Spotify answers a moment late. `sent` is each it set, as [volume, ms].
BOOL SpotifyVolumeIsOurs(NSInteger read, NSArray<NSArray<NSNumber *> *> *sent, double now);
// Whether the record a quit or a crash left ({from, to, at}) has the volume read put back to `from`: it's still where
// Whozmove left it, or on its way there, and the record isn't a day old.
BOOL SpotifyKeptBringsBack(NSDictionary *kept, NSInteger read, double now);
// The volume to bring back once you've stopped, for a talk starting at the volume `read`: the record's own when it says
// the music was left lowered (`kept`, or nil); the one the last bring-back brought back when it landed just there
// (`landed`, [read, brought back], or nil), so Spotify's rounding never creeps it down over many talks; else `read`.
NSInteger SpotifyVolumeToBringBack(NSInteger read, NSArray<NSNumber *> *landed, NSDictionary *kept, double now);

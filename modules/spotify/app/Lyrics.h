// Lyrics: the words of the song Spotify is playing, from LRCLIB, for the now-playing strip and the lyrics beside the
// list. Asked for only once you've said yes, and only about a song (not an ad or a podcast).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

@class Page;

@interface Lyrics : NSObject
- (instancetype)initWithPage:(Page *)page;
// Whether Spotify is in Whozmove at all (`shown`), whether you've said yes to lyrics (`on`), and whether you've
// answered the strip's question about them (`asked`). Off, LRCLIB is asked nothing, and what was kept of its answers
// goes, from this Mac too.
- (void)shown:(BOOL)shown on:(BOOL)on asked:(BOOL)asked;
// The song Spotify is playing (as Spotify.m has it), or nil: a new one's lyrics come from this Mac if they're kept
// there, and are looked up otherwise, once it has played a moment.
- (void)songIs:(NSDictionary *)song;
// A freshly loaded page gets what's known.
- (void)resend;
// Whether the song playing now has lyrics with times, each time that changes: Spotify's position is checked more often
// meanwhile.
@property (copy) void (^onFollowing)(BOOL following);
@end

// The parts modules/spotify/tests/test.sh checks, through --print-spotify. Where LRCLIB is asked about `song` (as the
// page gets it from Spotify.m), in turn, each only if the ones before found no lyrics with times: the song as Spotify
// names it; without its album; with its name tidied of what Spotify adds to say which version it is (" - Remastered
// 2011", "(feat. …)"); and LRCLIB's search, by name and artist, the only one for a song longer than LRCLIB takes a
// length for. None for an ad, a podcast episode, or something without a name, an artist or a length.
NSArray<NSURL *> *LyricsAsksFor(NSDictionary *song);
// What one of LRCLIB's answers about `song` says, from its HTTP status (0 when nothing came back) and its body: its
// lyrics, {kind: timed, lrc} or {kind: plain, plain}; {kind: instrumental}, a song with no words; {kind: missing},
// nothing found (LRCLIB doesn't have it, won't take the question, or answered with more than can be read), so the next
// ask goes; or {kind: trouble}: LRCLIB was busy, was asked too often, failed, or answered with something that doesn't
// read, so it's to be asked again.
NSDictionary *LyricsAnswerOf(NSInteger status, NSData *body, NSDictionary *song);
// How long to wait before asking again once LRCLIB has had trouble with `tries` of a song's asks: 1, 2, 4, 8 and 16
// seconds, then a minute each time; a fifth shorter or longer by `chance` (0 to 1), so Macs that LRCLIB turned away at
// once don't ask again at once; and never sooner than LRCLIB asked (`asked`, seconds), nor later than an hour.
NSTimeInterval LyricsWaitBefore(NSUInteger tries, NSTimeInterval asked, double chance);
// What the page is told about `track` from what was kept of it (on this Mac, by LyricsStore, or in memory) at `nowMs`,
// or nil, when it's to be asked about: nothing kept, something that doesn't read (lyrics with times but no line to sing
// among them), or untimed lyrics or none kept a week ago or more.
NSDictionary *LyricsFromKept(NSDictionary *kept, NSString *track, double nowMs);

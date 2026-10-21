// LRCLIBFacts: what Whozmove relies on about LRCLIB (lrclib.net), the free library of lyrics the now-playing strip's
// lyrics come from, that LRCLIB could change. When it does, the fix goes here. The README's "Tested with" names it.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// Where a song's lyrics are asked for: a GET with its name, its artist, its album (left out when there's none) and its
// length in whole seconds. LRCLIB tidies the names (case, accents, most punctuation) and matches them exactly, the
// album too when one is sent, and the length within kLRCLIBLeeway seconds of its own; of the songs that match, it
// answers with the one it has had longest, whether or not its lyrics have times.
extern NSString *const kLRCLIBGet;
extern NSString *const kLRCLIBTrack, *const kLRCLIBArtist, *const kLRCLIBAlbum, *const kLRCLIBDuration;
extern const double kLRCLIBLeeway;
// The longest length it takes there (seconds): a longer song can only be searched for.
extern const long kLRCLIBLongest;
// Its answer, a JSON object: syncedLyrics, the words with when each line starts, as LRC ("[01:02.50]words", a line
// each, and a line with no words where the singing stops for a while); plainLyrics, the same words with no times;
// either may be null; and instrumental, true for a song with no words. A song it doesn't know is a 404, and a question
// it won't take (a length past kLRCLIBLongest, say) a 400: asked again, it answers the same.
extern NSString *const kLRCLIBSynced, *const kLRCLIBPlain, *const kLRCLIBInstrumental;
enum { kLRCLIBNotFound = 404 };
// Where songs are searched for by name and artist (track_name and artist_name, as above), each found anywhere in a
// song's own, so a name finds every version of the song. The answer is a list of up to 20 songs, each like the answer
// above with its name (trackName) and the length it has (duration, in seconds) too.
extern NSString *const kLRCLIBSearch;
extern NSString *const kLRCLIBFoundName;
// When it's busy (a 503) or asked too often (a 429), it turns a request away, and this header says how many seconds to
// wait before asking again.
extern NSString *const kLRCLIBRetryAfter;
// What Whozmove says it is in each request, as LRCLIB asks of apps: its name, its version and its home page.
NSString *LRCLIBUserAgent(void);

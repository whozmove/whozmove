// SpotifyFacts: what Whozmove relies on about Spotify that Spotify could change. When it does, the fix goes here. The
// version these were last checked with is in the README ("Tested with").
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// Its app id.
extern NSString *const kSpotifyAppId;

// Spotify: what it tells the whole Mac each time the song or its state changes (no permission needed to hear it), the
// fields Whozmove takes from it, and where to get it. Its length is in milliseconds, its position in seconds, and its
// state is "Playing", "Paused" or "Stopped". Anything more (the cover, the position later on) and every control are
// asked of it with Apple events, by the codes in its scripting dictionary (Spotify.sdef in the app), below.
extern NSString *const kSpotifyAnnouncement;
extern NSString *const kSpotifyTrackKey, *const kSpotifyNameKey, *const kSpotifyArtistKey, *const kSpotifyAlbumKey,
                *const kSpotifyDurationKey, *const kSpotifyPositionKey, *const kSpotifyStateKey;
extern NSString *const kSpotifyPlaying, *const kSpotifyStopped;
extern NSString *const kSpotifyDownloadPage;
// Spotify's scripting dictionary: its own suite's commands, the application's properties, a track's, and the player's
// states. A track's duration comes in milliseconds, though the dictionary says seconds.
enum : FourCharCode {
    kSpotifySuite = 'spfy', kSpotifyPlay = 'Play', kSpotifyPlayPause = 'PlPs', kSpotifyNext = 'Next',
    kSpotifyPrevious = 'Prev',
    kSpotifyCurrentTrack = 'pTrk', kSpotifyPlayerState = 'pPlS', kSpotifyPlayerPosition = 'pPos',
    kSpotifyTrackId = 'ID  ', kSpotifyTrackName = 'pnam', kSpotifyTrackArtist = 'pArt', kSpotifyTrackAlbum = 'pAlb',
    kSpotifyTrackDuration = 'pDur', kSpotifyTrackArtwork = 'aUrl',
    kSpotifyStatePlaying = 'kPSP', kSpotifyStatePaused = 'kPSp', kSpotifyStateStopped = 'kPSS',
};

// SpotifyModule: Spotify's face for the core (Module). It makes Spotify, its token and its lyrics when the app starts,
// holds the token under the panel and follows the glass and the pointer for it, answers the now-playing strip's
// presses, puts Spotify ▸ in the pawn menu, and has the print mode the tests check.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Module.h"
#import "Core.h"
#import "PanelWindow.h"
#import "Files.h"
#import "Menus.h"
#import "Printing.h"
#import "Spotify.h"
#import "SpotifyToken.h"
#import "Lyrics.h"
#import "LyricsStore.h"

// Its switches in the pawn menu, kept in the app's preferences: Spotify itself (its token and song) and its side icon,
// each on until removed or hidden; and lyrics, off until you say yes to the strip's question (or Show Lyrics in the
// pawn menu), with whether you've answered that question.
static NSString *const kSpotifyOn = @"showNowPlaying", *const kSpotifySideIcon = @"spotifySideIcon";
static NSString *const kSpotifyLyrics = @"spotifyLyrics", *const kSpotifyLyricsAsked = @"spotifyLyricsAsked";

// `Whozmove --print-spotify <file>…`: for each JSON file, by its name, what the now-playing strip would take from it,
// as JSON, then quit: from what Spotify tells the whole Mac (announce-…), from what reading it returns (reply-…), or
// whether an Apple event's error number (error-…) is macOS refusing control. And for Spotify's token: what it shows
// (token-…, from {installed, song, starting, allowed, collapsed}, a paused song's pause as pausedMinutesAgo), and which
// side of the panel it's on (side-…, from {list, screen} as [x, y, width, height] and the side it was on, `current`).
// And for its lyrics: where LRCLIB would be asked about a song, in turn (lyrics-ask-…); what one of LRCLIB's answers
// says (lyrics-answer-…, from {status, body} with the body as JSON, or {status, text} with it as it came, about the
// sample song or `song`), long lyrics shown by their length and last line; how long it's waited before asking again
// after trouble (lyrics-wait-…, from {tries: [...], asked, chance}); what the page would be told from what this Mac
// kept about a song, and the file it's kept in (lyrics-kept-…, from {track, kept}, its keptAt as keptDaysAgo); and
// whether a position read from Spotify is a jump the page is told (position-…, from {song, readMs}, the song's `at` as
// atSecondsAgo). Nothing is asked of LRCLIB or Spotify, and nothing is read or kept on disk.
// modules/spotify/tests/test.sh checks them against recorded ones.
static id Shortened(id found) {
    NSMutableDictionary *shown = [AsRecord(found) mutableCopy];
    for (NSString *key in @[@"lrc", @"plain"]) {
        NSString *text = AsText(shown[key]);
        if (text.length <= 300) continue;
        NSString *last = [text componentsSeparatedByString:@"\n"].lastObject;
        shown[key] = [NSString stringWithFormat:@"%lu characters, ending: %@", (unsigned long)text.length, last];
    }
    return shown ?: found;
}

static int PrintSpotify(NSArray<NSString *> *files) {
    NSMutableDictionary *read = [NSMutableDictionary dictionary];
    double now = NSDate.date.timeIntervalSince1970 * 1000;
    for (NSString *file in files) {
        NSString *name = file.lastPathComponent;
        id json = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:file] ?: NSData.data
                                                  options:NSJSONReadingFragmentsAllowed error:nil];
        id found = NSNull.null;
        if ([name hasPrefix:@"announce-"] && [json isKindOfClass:NSDictionary.class])
            found = SongFromAnnouncement(json, now) ?: NSNull.null;
        else if ([name hasPrefix:@"reply-"] && [json isKindOfClass:NSArray.class])
            found = SongFromReply(json, now) ?: NSNull.null;
        else if ([name hasPrefix:@"error-"] && [json isKindOfClass:NSNumber.class])
            found = @{@"refused": @(ControlRefused([json intValue]))};
        else if ([name hasPrefix:@"token-"] && [json isKindOfClass:NSDictionary.class])
        {
            // A paused song's pausedSince, as minutes before now (pausedMinutesAgo).
            NSMutableDictionary *song = [AsRecord(json[@"song"]) mutableCopy];
            if (AsNumber(song[@"pausedMinutesAgo"]))
                song[@"pausedSince"] = @(now - [song[@"pausedMinutesAgo"] doubleValue] * 60000);
            found = TokenFor([json[@"installed"] boolValue], song, [json[@"starting"] boolValue],
                             AsNumber(json[@"allowed"]), [json[@"collapsed"] boolValue], now);
        }
        else if ([name hasPrefix:@"side-"] && [json isKindOfClass:NSDictionary.class]) {
            NSRect (^rect)(id) = ^NSRect(id list) {
                NSArray *n = AsList(list);
                return n.count == 4 ? NSMakeRect([n[0] doubleValue], [n[1] doubleValue], [n[2] doubleValue],
                                                 [n[3] doubleValue]) : NSZeroRect;
            };
            found = TokenSideFor(rect(json[@"list"]), rect(json[@"screen"]), AsText(json[@"current"]));
        }
        else if ([name hasPrefix:@"lyrics-ask-"] && [json isKindOfClass:NSDictionary.class])
            found = [LyricsAsksFor(json) valueForKey:@"absoluteString"];
        else if ([name hasPrefix:@"lyrics-answer-"] && [json isKindOfClass:NSDictionary.class]) {
            id body = json[@"body"];
            NSData *data = AsText(json[@"text"]) ? [json[@"text"] dataUsingEncoding:NSUTF8StringEncoding]
                         : body ? [NSJSONSerialization dataWithJSONObject:body options:NSJSONWritingFragmentsAllowed
                                                                    error:nil]
                                : nil;
            NSDictionary *song = AsRecord(json[@"song"]) ?: @{@"title": @"Example Song", @"durationMs": @200000};
            found = Shortened(LyricsAnswerOf(AsNumber(json[@"status"]).integerValue, data, song));
        }
        else if ([name hasPrefix:@"lyrics-wait-"] && [json isKindOfClass:NSDictionary.class]) {
            NSMutableArray *waits = [NSMutableArray array];
            for (NSNumber *tries in AsList(json[@"tries"]))
                [waits addObject:[NSString stringWithFormat:@"%.1f s", LyricsWaitBefore(
                    tries.unsignedIntegerValue, AsNumber(json[@"asked"]).doubleValue,
                    AsNumber(json[@"chance"]).doubleValue)]];
            found = waits;
        }
        else if ([name hasPrefix:@"lyrics-kept-"] && [json isKindOfClass:NSDictionary.class]) {
            NSMutableDictionary *kept = [AsRecord(json[@"kept"]) mutableCopy];
            if (AsNumber(kept[@"keptDaysAgo"]))
                kept[@"keptAt"] = @(now - [kept[@"keptDaysAgo"] doubleValue] * 24 * 3600 * 1000);
            NSString *track = AsText(json[@"track"]);
            found = @{@"found": LyricsFromKept(kept, track, now) ?: NSNull.null,
                      @"file": track ? LyricsKeptName(track) : NSNull.null};
        }
        else if ([name hasPrefix:@"position-"] && [json isKindOfClass:NSDictionary.class]) {
            NSMutableDictionary *song = [AsRecord(json[@"song"]) mutableCopy];
            song[@"at"] = @(now - AsNumber(song[@"atSecondsAgo"]).doubleValue * 1000);
            found = @{@"moved": @(PositionMoved(song, AsNumber(json[@"readMs"]).doubleValue, now))};
        }
        read[name] = found;
    }
    return PrintJSON(read);
}

@interface SpotifyModule : NSObject <Module>
@property (weak) Core *core;
@property (strong) Spotify *spotify;
@property (strong) SpotifyToken *token;
@property (strong) Lyrics *lyrics;
@property (strong) NSMenuItem *openItem;        // Spotify ▸ Open Spotify
@property (strong) NSMenuItem *lyricsItem;      // Spotify ▸ Show Lyrics, ticked while they're on
@property (strong) NSMenuItem *sideIconItem;    // Spotify ▸ Hide Side Icon, or Show Side Icon
@property (strong) NSMenuItem *removeItem;      // Spotify ▸ Remove Spotify, or Add Spotify
@end

@implementation SpotifyModule

+ (NSString *)moduleName {
    return @"spotify";
}

- (instancetype)initWithCore:(Core *)core {
    if (!(self = [super init])) return nil;
    self.core = core;
    [NSUserDefaults.standardUserDefaults registerDefaults:@{kSpotifyOn: @YES, kSpotifySideIcon: @YES,
                                                            kSpotifyLyrics: @NO, kSpotifyLyricsAsked: @NO}];
    return self;
}

// Spotify, its lyrics, and its token held under the panel: the lyrics follow Spotify's song, and Spotify's position is
// checked more often while they do; the token shows what Spotify says, follows the glass and the pointer, and a press
// goes to Spotify. Made only here, so a print run (which never launches a module) asks LRCLIB nothing.
- (void)launch {
    __weak typeof(self) weakSelf = self;
    self.spotify = [[Spotify alloc] initWithPage:self.core.page];
    self.lyrics = [[Lyrics alloc] initWithPage:self.core.page];
    self.spotify.onSong = ^(NSDictionary *song) { [weakSelf.lyrics songIs:song]; };
    self.lyrics.onFollowing = ^(BOOL following) { weakSelf.spotify.following = following; };
    self.token = [SpotifyToken new];
    [self.core.window attachBelow:self.token.window];
    [self.core.window followGlass:^(NSRect glass, NSRect list, NSRect screen, NSTimeInterval duration) {
        [weakSelf.token glassAt:glass list:list screen:screen duration:duration];
    }];
    [self.core.window followPointer:^(NSPoint point) { [weakSelf.token pointerAt:point]; }];
    self.spotify.onToken = ^(NSDictionary *token) { [weakSelf.token show:token]; };
    self.token.onPress = ^(NSString *state) {
        Spotify *spotify = weakSelf.spotify;
        if ([state isEqual:@"missing"]) [spotify getSpotify];
        else if ([state isEqual:@"refused"]) [spotify control:@"settings" fraction:0];
        else if (![spotify play]) [weakSelf.token untuck];
    };
    [self applySwitches];
}

- (void)pageLoaded {
    [self applySwitches];
    [self.spotify resend];
    [self.lyrics resend];
}

// Whether Spotify is on in Whozmove, whether its token shows, and whether its lyrics are looked up. Coming in, the
// lyrics are told first, so they're ready for the song Spotify finds; going, Spotify is, so the page folds the strip
// away before the lyrics beside the list close.
- (void)applySwitches {
    BOOL on = SwitchedOn(kSpotifyOn);
    self.token.shown = on && SwitchedOn(kSpotifySideIcon);
    if (!on) self.spotify.shown = NO;
    [self.lyrics shown:on on:SwitchedOn(kSpotifyLyrics) asked:SwitchedOn(kSpotifyLyricsAsked)];
    self.spotify.shown = on;
}

// Your answer about lyrics, from the strip's question or the pawn menu: either way, the question has been answered.
- (void)answerLyrics:(BOOL)on {
    [NSUserDefaults.standardUserDefaults setBool:on forKey:kSpotifyLyrics];
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:kSpotifyLyricsAsked];
    [self applySwitches];
}

// The now-playing strip's presses, your answer about lyrics, and what the page tells about the panel: folded into the
// cat (neither the strip nor the token shows), or the strip folded away (a paused song's token comes out).
- (NSDictionary<NSString *, void (^)(NSDictionary *)> *)messages {
    __weak typeof(self) weakSelf = self;
    return @{@"spotify": ^(NSDictionary *msg) {
        if ([msg[@"action"] isEqual:@"collapsed"]) {
            BOOL on = [msg[@"on"] boolValue];
            // Opening out of the cat, the token waits under the glass until the panel has opened.
            if (!on && weakSelf.spotify.collapsed) [weakSelf.token panelOpening];
            weakSelf.spotify.collapsed = on;
        } else if ([msg[@"action"] isEqual:@"folded"]) {
            [weakSelf.spotify refreshToken];  // a song paused long enough leaves the strip now, not at the next look
            [weakSelf.token stripFolded];
        } else if ([msg[@"action"] isEqual:@"lyrics"]) {
            [weakSelf answerLyrics:[AsNumber(msg[@"on"]) boolValue]];
        } else if ([msg[@"action"] isKindOfClass:NSString.class]) {
            [weakSelf.spotify control:msg[@"action"] fraction:[msg[@"fraction"] doubleValue]];
        }
    }};
}

// Spotify ▸ in the pawn menu: Open Spotify (once lyrics are on, pressing the strip opens them instead), Show Lyrics
// (ticked while they're on) and Hide Side Icon (or Show) while it's on; Remove Spotify, or Add Spotify once it's
// removed.
- (NSArray<MenuEntry *> *)menuEntries {
    NSMenu *menu = [NSMenu new];
    menu.autoenablesItems = NO;
    self.openItem = [menu addItemWithTitle:@"Open Spotify" action:@selector(openSpotify) keyEquivalent:@""];
    self.openItem.target = self;
    self.lyricsItem = [menu addItemWithTitle:@"Show Lyrics" action:@selector(toggleLyrics) keyEquivalent:@""];
    self.lyricsItem.target = self;
    self.sideIconItem = [menu addItemWithTitle:@"Hide Side Icon" action:@selector(toggleSideIcon) keyEquivalent:@""];
    self.sideIconItem.target = self;
    self.removeItem = [menu addItemWithTitle:@"Remove Spotify" action:@selector(toggleSpotify) keyEquivalent:@""];
    self.removeItem.target = self;
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Spotify" action:nil keyEquivalent:@""];
    item.submenu = menu;
    MenuEntry *entry = [MenuEntry entryIn:MenuSectionFeatures order:20 item:item];
    __weak typeof(self) weakSelf = self;
    entry.willOpen = ^{
        BOOL on = SwitchedOn(kSpotifyOn);
        weakSelf.openItem.hidden = !on || !SpotifyInstalled();
        weakSelf.lyricsItem.hidden = !on;
        weakSelf.lyricsItem.state = SwitchedOn(kSpotifyLyrics) ? NSControlStateValueOn : NSControlStateValueOff;
        weakSelf.sideIconItem.hidden = !on;
        weakSelf.sideIconItem.title = SwitchedOn(kSpotifySideIcon) ? @"Hide Side Icon" : @"Show Side Icon";
        weakSelf.removeItem.title = on ? @"Remove Spotify" : @"Add Spotify";
    };
    return @[entry];
}

- (void)openSpotify {
    [self.spotify open];
}

- (void)toggleLyrics {
    [self answerLyrics:!SwitchedOn(kSpotifyLyrics)];
}

- (void)toggleSideIcon {
    FlipSwitch(kSpotifySideIcon);
    [self applySwitches];
}

- (void)toggleSpotify {
    FlipSwitch(kSpotifyOn);
    [self applySwitches];
}

+ (NSDictionary<NSString *, PrintMode> *)printModes {
    return @{@"--print-spotify": ^int(Core *core, NSArray<NSString *> *arguments) { return PrintSpotify(arguments); }};
}

@end

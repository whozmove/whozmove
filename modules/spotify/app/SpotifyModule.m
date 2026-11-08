// SpotifyModule: Spotify's face for the core (Module). It makes Spotify, its token and its lyrics when the app starts,
// has the panel hold the token under its glass (EdgeIcon, parts/edge), answers the now-playing strip's presses, has
// Spotify's page on the panel's back, with its switches, and the print mode the tests check.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Module.h"
#import "Core.h"
#import "PanelWindow.h"
#import "Files.h"
#import "Menus.h"
#import "Printing.h"
#import "Spotify.h"
#import "SpotifyFacts.h"
#import "SpotifyToken.h"
#import "Lyrics.h"
#import "LyricsStore.h"
#import "SpotifyVolume.h"
#import "Talking.h"

// Its switches on its page on the panel's back, kept in the app's preferences: Spotify itself (its token and song) and
// its token, each on until turned off; lyrics, off until you say yes to the strip's question (or turn them on there),
// with whether you've answered that question; and the music quieter while you talk to Claude, on until turned off,
// with how much quieter (one of kQuieterLevels' keys).
static NSString *const kSpotifyOn = @"showNowPlaying", *const kSpotifySideIcon = @"spotifySideIcon";
static NSString *const kSpotifyLyrics = @"spotifyLyrics", *const kSpotifyLyricsAsked = @"spotifyLyricsAsked";
static NSString *const kSpotifyQuieter = @"spotifyQuieter", *const kSpotifyQuieterTo = @"spotifyQuieterTo";

// How much quieter, a choice of one on Spotify's page: its key, its name and line there, and the share of the volume
// Spotify had that it goes down to.
static NSArray<NSArray *> *QuieterLevels(void) {
    return @[@[@"little", @"A little", @"To about two thirds of its volume", @0.67],
             @[@"half", @"Half", @"To half its volume", @0.5],
             @[@"much", @"Much quieter", @"To a quarter of its volume", @0.25]];
}

static NSArray *QuieterLevel(void) {
    NSString *chosen = [NSUserDefaults.standardUserDefaults stringForKey:kSpotifyQuieterTo];
    for (NSArray *level in QuieterLevels())
        if ([level[0] isEqual:chosen]) return level;
    return QuieterLevels()[1];
}

// Before macOS 14, macOS can't say who is recording, so the music is never lowered there, and the switch isn't shown.
static BOOL QuieterOffered(void) {
    if (@available(macOS 14.0, *)) return YES;
    return NO;
}

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
// atSecondsAgo). And for the music quieter while you talk: where it goes down to (quieter-target-…, from {from,
// share}), the volume at moments as it's turned (quieter-turn-…, from {from, to, at: [ms…]}), what's set for
// Spotify to read back each volume (quieter-set-…, a list), whether a volume read is one Whozmove left (quieter-ours-…,
// from {read, sent: [[volume, msAgo]…]}), the volume a talk starting at `read` brings back (quieter-from-…, from {read,
// landed, kept}), and whether a record a quit left has it put back (quieter-kept-…, from {kept: {from, to, hoursAgo},
// read}). Nothing is asked of LRCLIB or Spotify, and nothing is read or kept on disk.
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
            found = EdgeSideFor(rect(json[@"list"]), rect(json[@"screen"]), AsText(json[@"current"]));
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
        else if ([name hasPrefix:@"quieter-target-"] && [json isKindOfClass:NSDictionary.class]) {
            NSInteger to = SpotifyQuieterTarget([json[@"from"] integerValue], [json[@"share"] doubleValue]);
            found = to == NSNotFound ? NSNull.null : @(to);
        }
        else if ([name hasPrefix:@"quieter-turn-"] && [json isKindOfClass:NSDictionary.class]) {
            NSMutableArray *volumes = [NSMutableArray array];
            for (NSNumber *ms in AsList(json[@"at"]))
                [volumes addObject:@(SpotifyTurnAt([json[@"from"] integerValue], [json[@"to"] integerValue],
                                                   ms.doubleValue))];
            found = volumes;
        }
        else if ([name hasPrefix:@"quieter-set-"] && [json isKindOfClass:NSArray.class]) {
            NSMutableDictionary *set = [NSMutableDictionary dictionary];
            for (NSNumber *volume in json) set[volume.stringValue] = @(SpotifyVolumeToSet(volume.integerValue));
            found = set;
        }
        else if ([name hasPrefix:@"quieter-ours-"] && [json isKindOfClass:NSDictionary.class]) {
            // Each value set as [volume, msAgo].
            NSMutableArray *sent = [NSMutableArray array];
            for (NSArray *each in AsList(json[@"sent"])) [sent addObject:@[each[0], @(now - [each[1] doubleValue])]];
            found = @{@"ours": @(SpotifyVolumeIsOurs([json[@"read"] integerValue], sent, now))};
        }
        else if ([name hasPrefix:@"quieter-from-"] && [json isKindOfClass:NSDictionary.class]) {
            // A record's `at` as hoursAgo, as below.
            NSMutableDictionary *kept = [AsRecord(json[@"kept"]) mutableCopy];
            if (kept) kept[@"at"] = @(now - [kept[@"hoursAgo"] doubleValue] * 3600 * 1000);
            found = @(SpotifyVolumeToBringBack([json[@"read"] integerValue], AsList(json[@"landed"]), kept, now));
        }
        else if ([name hasPrefix:@"quieter-kept-"] && [json isKindOfClass:NSDictionary.class]) {
            // The record's `at` as hoursAgo.
            NSMutableDictionary *kept = [AsRecord(json[@"kept"]) mutableCopy];
            kept[@"at"] = @(now - [kept[@"hoursAgo"] doubleValue] * 3600 * 1000);
            found = @{@"bringsBack": @(SpotifyKeptBringsBack(kept, [json[@"read"] integerValue], now))};
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
@property (strong) SpotifyVolume *volume;
@property (strong) id talkingFollower;  // following the core's Talking, while the music is lowered as you talk
@end

@implementation SpotifyModule

+ (NSString *)moduleName {
    return @"spotify";
}

- (instancetype)initWithCore:(Core *)core {
    if (!(self = [super init])) return nil;
    self.core = core;
    [NSUserDefaults.standardUserDefaults registerDefaults:@{kSpotifyOn: @YES, kSpotifySideIcon: @YES,
                                                            kSpotifyLyrics: @NO, kSpotifyLyricsAsked: @NO,
                                                            kSpotifyQuieter: @YES, kSpotifyQuieterTo: @"half"}];
    return self;
}

// Spotify, its lyrics, its token held under the panel, and its volume: the lyrics follow Spotify's song, and Spotify's
// position is checked more often while they do; the token shows what Spotify says, follows the glass and the pointer,
// and a press goes to Spotify; the volume follows your talking, and the strip shows when it's lowered. Made only here,
// so a print run (which never launches a module) asks LRCLIB and Spotify nothing.
- (void)launch {
    __weak typeof(self) weakSelf = self;
    self.spotify = [[Spotify alloc] initWithPage:self.core.page];
    self.lyrics = [[Lyrics alloc] initWithPage:self.core.page];
    self.spotify.onSong = ^(NSDictionary *song) { [weakSelf.lyrics songIs:song]; };
    self.lyrics.onFollowing = ^(BOOL following) { weakSelf.spotify.following = following; };
    self.token = [SpotifyToken new];
    // Under the panel's glass, following it, the pointer and the turn (EdgeIcon, parts/edge).
    [self.token holdBy:self.core.window];
    self.spotify.onToken = ^(NSDictionary *token) { [weakSelf.token show:token]; };
    self.token.onPress = ^(NSString *state) {
        Spotify *spotify = weakSelf.spotify;
        if ([state isEqual:@"missing"]) [spotify getSpotify];
        else if ([state isEqual:@"refused"]) [spotify control:@"settings" fraction:0];
        else if (![spotify play]) [weakSelf.token untuck];
    };
    self.volume = [SpotifyVolume new];
    self.volume.onQuieter = ^(BOOL quieter) { weakSelf.spotify.quieter = quieter; };
    [self.volume start];
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
    [self applyQuieter];
}

// The music quieter while you talk to Claude, whether the song shows or not: the core's Talking is followed only while
// it's on, and turned off, the volume is brought back before it stops.
- (void)applyQuieter {
    if (!self.volume) return;
    BOOL quieter = QuieterOffered() && SwitchedOn(kSpotifyQuieter);
    self.volume.share = [QuieterLevel()[3] doubleValue];
    self.volume.on = quieter;
    if (quieter && !self.talkingFollower) {
        __weak typeof(self) weakSelf = self;
        self.talkingFollower = [self.core.talking follow:^(BOOL talking) { [weakSelf.volume talking:talking]; }];
    } else if (!quieter && self.talkingFollower) {
        [self.core.talking unfollow:self.talkingFollower];
        self.talkingFollower = nil;
    }
}

// Your answer about lyrics, from the strip's question or Spotify's page on the panel's back: either way, the question
// has been answered.
- (void)answerLyrics:(BOOL)on {
    SetSwitch(kSpotifyLyrics, on);
    SetSwitch(kSpotifyLyricsAsked, YES);
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

// Spotify on the panel's back: what Whozmove does with it, macOS's Automation, which reading and playing the song
// needs, and its switches: the song under your sessions, and while that's on, its lyrics and its token; and the music
// quieter while you talk to Claude, with how much quieter under it while it's on, a choice of one. Listed whether it's
// on this Mac or not, as its token offers to get it.
- (NSArray<AppEntry *> *)appEntries {
    __weak typeof(self) weakSelf = self;
    AppEntry *spotify = [AppEntry appWithId:kSpotifyAppId name:@"Spotify"
                                       does:@"Shows the song playing under your sessions, with its buttons, and its "
                                            @"lyrics line by line, once they're on; and makes it quieter while you "
                                            @"talk to Claude."
                                      order:50];
    spotify.present = ^BOOL { return YES; };
    spotify.permission = AppPermissionAutomation;
    spotify.permissionFor = @"Reads the song, plays, pauses and skips, and lowers the music while you talk";
    AppSwitch *song = [AppSwitch switchWithKey:@"song" title:@"Show the song"
                                          help:@"Under your sessions, with its buttons"
                                            on:^BOOL { return SwitchedOn(kSpotifyOn); }
                                           set:^(BOOL on) { [weakSelf set:kSpotifyOn on:on]; }];
    AppSwitch *lyrics = [AppSwitch switchWithKey:@"lyrics" title:@"Lyrics"
                                            help:@"Line by line as they're sung, in the strip and beside the list"
                                              on:^BOOL { return SwitchedOn(kSpotifyLyrics); }
                                             set:^(BOOL on) { [weakSelf answerLyrics:on]; }];
    AppSwitch *token = [AppSwitch switchWithKey:@"token" title:@"Its icon at the panel's corner"
                                           help:@"To play a song, or carry on a paused one, while none shows"
                                             on:^BOOL { return SwitchedOn(kSpotifySideIcon); }
                                            set:^(BOOL on) { [weakSelf set:kSpotifySideIcon on:on]; }];
    lyrics.shown = token.shown = ^BOOL { return SwitchedOn(kSpotifyOn); };
    AppSwitch *quieter = [AppSwitch switchWithKey:@"quieter" title:@"Quieter while you talk to Claude"
                                             help:@"Lowers the music while you speak to Claude, and brings it back "
                                                  @"after"
                                               on:^BOOL { return SwitchedOn(kSpotifyQuieter); }
                                              set:^(BOOL on) { [weakSelf set:kSpotifyQuieter on:on]; }];
    quieter.shown = ^BOOL { return QuieterOffered(); };
    NSMutableArray<AppSwitch *> *switches = [@[song, lyrics, token, quieter] mutableCopy];
    for (NSArray *level in QuieterLevels()) {
        AppSwitch *choice = [AppSwitch switchWithKey:[@"quieter-" stringByAppendingString:level[0]] title:level[1]
                                                help:level[2]
                                                  on:^BOOL { return [QuieterLevel()[0] isEqual:level[0]]; }
                                                 set:^(BOOL on) {
            if (!on) return;
            [NSUserDefaults.standardUserDefaults setObject:level[0] forKey:kSpotifyQuieterTo];
            [weakSelf applyQuieter];
        }];
        choice.group = @"spotifyQuieterLevel";
        choice.shown = ^BOOL { return QuieterOffered() && SwitchedOn(kSpotifyQuieter); };
        [switches addObject:choice];
    }
    spotify.switches = switches;
    AppStatus *control = [AppStatus statusWithKey:@"quieterControl" title:@"Quieter music"
                                              now:^NSDictionary *{ return [weakSelf controlCard]; }
                                            press:^{ [weakSelf pressedControlCard]; }];
    spotify.statuses = @[control];
    return @[spotify];
}

// The card on Spotify's page while the music is to be quieter but Whozmove may not control Spotify: why, and the way
// to it. macOS is asked only on your press of Allow, never by itself in the middle of a talk; refused, it's changed in
// System Settings; and with Spotify closed, it's opened first, as only a running Spotify can be asked about. Nil (no
// card) while it's allowed, not known yet, or the music isn't to be quieter.
- (NSDictionary *)controlCard {
    if (!self.volume || !QuieterOffered() || !SwitchedOn(kSpotifyQuieter)) return nil;
    NSString *control = [self.volume control];
    NSString *needs = @"Lowering the music while you talk needs Whozmove to control Spotify.";
    if ([control isEqual:@"denied"])
        return @{@"said": @"Not allowed",
                 @"note": [needs stringByAppendingString:@" Turn on Spotify under Whozmove in Automation."],
                 @"button": @"Open Settings"};
    if (![control isEqual:@"ask"]) return nil;
    if (![NSRunningApplication runningApplicationsWithBundleIdentifier:kSpotifyAppId].count)
        return @{@"said": @"Not allowed yet", @"note": [needs stringByAppendingString:@" Open Spotify to allow it."],
                 @"button": @"Open Spotify"};
    return @{@"said": @"Not allowed yet", @"note": [needs stringByAppendingString:@" macOS asks when you press Allow."],
             @"button": @"Allow", @"busy": @(self.volume.allowing)};
}

- (void)pressedControlCard {
    NSString *control = [self.volume control];
    if ([control isEqual:@"denied"]) [self.spotify control:@"settings" fraction:0];
    else if (![NSRunningApplication runningApplicationsWithBundleIdentifier:kSpotifyAppId].count) [self.spotify open];
    else if ([control isEqual:@"ask"]) [self.volume allowControl];
}

- (void)set:(NSString *)key on:(BOOL)on {
    SetSwitch(key, on);
    [self applySwitches];
}

+ (NSDictionary<NSString *, PrintMode> *)printModes {
    return @{@"--print-spotify": ^int(Core *core, NSArray<NSString *> *arguments) { return PrintSpotify(arguments); }};
}

@end

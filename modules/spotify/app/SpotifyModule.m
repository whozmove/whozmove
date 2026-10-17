// SpotifyModule: Spotify's face for the core (Module). It makes Spotify and its token when the app starts, holds the
// token under the panel and follows the glass and the pointer for it, answers the now-playing strip's presses, puts
// Spotify ▸ in the pawn menu, and has the print mode the tests check.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Module.h"
#import "Core.h"
#import "PanelWindow.h"
#import "Files.h"
#import "Menus.h"
#import "Printing.h"
#import "Spotify.h"
#import "SpotifyToken.h"

// Its switches in the pawn menu, kept in the app's preferences: Spotify itself (its token and song) and its side icon,
// each on until removed or hidden.
static NSString *const kSpotifyOn = @"showNowPlaying", *const kSpotifySideIcon = @"spotifySideIcon";

// `Whozmove --print-spotify <file>…`: for each JSON file, by its name, what the now-playing strip would take from it,
// as JSON, then quit: from what Spotify tells the whole Mac (announce-…), from what reading it returns (reply-…), or
// whether an Apple event's error number (error-…) is macOS refusing control. And for Spotify's token: what it shows
// (token-…, from {installed, song, starting, allowed, collapsed}, a paused song's pause as pausedMinutesAgo), and which
// side of the panel it's on (side-…, from {list, screen} as [x, y, width, height] and the side it was on, `current`).
// modules/spotify/tests/test.sh checks them against recorded ones.
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
        read[name] = found;
    }
    return PrintJSON(read);
}

@interface SpotifyModule : NSObject <Module>
@property (weak) Core *core;
@property (strong) Spotify *spotify;
@property (strong) SpotifyToken *token;
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
    [NSUserDefaults.standardUserDefaults registerDefaults:@{kSpotifyOn: @YES, kSpotifySideIcon: @YES}];
    return self;
}

// Spotify, and its token held under the panel: the token shows what Spotify says, follows the glass and the pointer,
// and a press goes to Spotify.
- (void)launch {
    __weak typeof(self) weakSelf = self;
    self.spotify = [[Spotify alloc] initWithPage:self.core.page];
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
        else if ([state isEqual:@"playing"] || ([state isEqual:@"paused"] && spotify.collapsed))
            [spotify control:@"playpause" fraction:0];
        else if (![spotify play]) [weakSelf.token untuck];
    };
    [self applySwitches];
}

- (void)pageLoaded {
    [self applySwitches];
    [self.spotify resend];
}

// Whether Spotify is on in Whozmove, and whether its token shows.
- (void)applySwitches {
    self.token.shown = SwitchedOn(kSpotifyOn) && SwitchedOn(kSpotifySideIcon);
    self.spotify.shown = SwitchedOn(kSpotifyOn);
}

// The now-playing strip's presses, and what the page tells about the panel: folded to its header (the token stands
// in for the strip), or the strip folded away (a paused song's token comes out).
- (NSDictionary<NSString *, void (^)(NSDictionary *)> *)messages {
    __weak typeof(self) weakSelf = self;
    return @{@"spotify": ^(NSDictionary *msg) {
        if ([msg[@"action"] isEqual:@"collapsed"]) {
            weakSelf.spotify.collapsed = [msg[@"on"] boolValue];
        } else if ([msg[@"action"] isEqual:@"folded"]) {
            [weakSelf.spotify refreshToken];  // a song paused long enough leaves the strip now, not at the next look
            [weakSelf.token stripFolded];
        } else if ([msg[@"action"] isKindOfClass:NSString.class]) {
            [weakSelf.spotify control:msg[@"action"] fraction:[msg[@"fraction"] doubleValue]];
        }
    }};
}

// Spotify ▸ in the pawn menu: Hide Side Icon (or Show) while it's on; Remove Spotify, or Add Spotify once it's
// removed.
- (NSArray<MenuEntry *> *)menuEntries {
    NSMenu *menu = [NSMenu new];
    menu.autoenablesItems = NO;
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
        weakSelf.sideIconItem.hidden = !on;
        weakSelf.sideIconItem.title = SwitchedOn(kSpotifySideIcon) ? @"Hide Side Icon" : @"Show Side Icon";
        weakSelf.removeItem.title = on ? @"Remove Spotify" : @"Add Spotify";
    };
    return @[entry];
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

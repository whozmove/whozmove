// SpotifyVolume: Spotify's volume changed through Apple events (never AppleScript), on a queue of its own, so a bring-
// back never waits behind Spotify's own queue (its Play can wait there for 20 s). Every decision is made on the main
// thread. Each move (down, back up, down again) has a turn number: turning from an earlier move stops at its next
// point, and its answer is dropped, so two moves never set the volume at once.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// The volume is turned as a steady hand turns a knob, one point at a time at an even pace, from wherever it is: 70, 69,
// 68… down to where it goes, and back up the same way. Before the first change, the volume it had is kept in the app's
// preferences ({from, to, at}): a build's restart or a crash stops Whozmove with no time to put it back, and Spotify,
// quit while lowered, keeps the low volume for its next launch, so the record has it put back when either starts again.
#import <Cocoa/Cocoa.h>
#import "SpotifyVolume.h"
#import "SpotifyFacts.h"
#import "AppleEvents.h"
#import "Audio.h"
#import "Files.h"
#import "Log.h"

static double NowMs(void) { return NSDate.date.timeIntervalSince1970 * 1000; }

// The volume is turned as a steady hand turns a knob: one point at a time, down from wherever it is as you start
// talking, one every kDownPointMs, so half of it takes about 3 s; and back up once you've stopped, one every
// kUpPointMs, about a second and a half for half.
static const double kDownPointMs = 60, kUpPointMs = 30;
// How long the music stays down once you've stopped, so pressing to talk again straight after doesn't bob it up and
// down; and a talk shorter than this is a stray key, which brings it back at once.
static const NSTimeInterval kWaitAfter = 3, kStrayUnder = 0.3;
// A moment for Spotify to settle a change, before the last read of a bring-back.
static const useconds_t kSettleMicroseconds = 100000;
// How long a value set is taken as Spotify's answer: it answers a moment late.
static const double kAnswersLateMs = 200;
// Each Apple event waits this long at most.
static const NSTimeInterval kTimeout = 1;
// A bring-back Spotify didn't answer (busy loading a song, say) is tried again this often, this many times.
static const NSTimeInterval kNoAnswerEvery = 1;
static const NSUInteger kNoAnswerTries = 5;
// A record a quit or a crash left is good for this long (ms); a running Spotify is asked this often, this many times,
// until it answers (one just started takes a few seconds).
static const double kKeptForMs = 24 * 3600 * 1000;
static const NSTimeInterval kStartingEvery = 1;
static const NSUInteger kStartingTries = 20;
// Whether Whozmove may control Spotify, as last found, is looked up again once it's this old (ms), as the card on
// Spotify's page asks.
static const double kControlKnownForMs = 3000;
// The record kept while the music is lowered, in the app's preferences.
static NSString *const kKept = @"spotifyQuieterKept";

NSInteger SpotifyQuieterTarget(NSInteger from, double share) {
    NSInteger to = MAX(1, (NSInteger)floor(from * share));
    return to < from ? to : NSNotFound;
}

NSInteger SpotifyTurnAt(NSInteger from, NSInteger to, double ms) {
    NSInteger points = (NSInteger)floor(MAX(0, ms) / (from > to ? kDownPointMs : kUpPointMs)) + 1;
    return from > to ? MAX(to, from - points) : MIN(to, from + points);
}

NSInteger SpotifyVolumeToSet(NSInteger volume) {
    if (volume % kSpotifyVolumeExactEvery == 0 || (volume + 1) % kSpotifyVolumeExactEvery == 0) return volume;
    return volume + 1;
}

BOOL SpotifyVolumeIsOurs(NSInteger read, NSArray<NSArray<NSNumber *> *> *sent, double now) {
    for (NSArray<NSNumber *> *each in sent)
        if ((each == sent.lastObject || now - each[1].doubleValue <= kAnswersLateMs)
            && labs(read - each[0].integerValue) <= 1) return YES;
    return NO;
}

BOOL SpotifyKeptBringsBack(NSDictionary *kept, NSInteger read, double now) {
    NSNumber *from = AsNumber(kept[@"from"]), *to = AsNumber(kept[@"to"]), *at = AsNumber(kept[@"at"]);
    if (!from || !to || !at || now - at.doubleValue > kKeptForMs) return NO;
    return read >= to.integerValue - 1 && read < from.integerValue;
}

NSInteger SpotifyVolumeToBringBack(NSInteger read, NSArray<NSNumber *> *landed, NSDictionary *kept, double now) {
    if (SpotifyKeptBringsBack(kept, read, now)) return [AsNumber(kept[@"from"]) integerValue];
    if (landed.count == 2 && read == landed[0].integerValue) return landed[1].integerValue;
    return read;
}

static pid_t RunningSpotify(void) {
    return [NSRunningApplication runningApplicationsWithBundleIdentifier:kSpotifyAppId].firstObject.processIdentifier;
}

static NSInteger ReadVolume(pid_t pid) {
    OSStatus status = noErr;
    NSAppleEventDescriptor *volume = SendAppleEvent(pid, kAECoreSuite, kAEGetData,
                                                    AppleEventProperty(kSpotifySoundVolume, nil), nil, kTimeout,
                                                    &status);
    return volume ? volume.int32Value : NSNotFound;
}

static BOOL SetVolume(pid_t pid, NSInteger volume) {
    OSStatus status = noErr;
    return SendAppleEvent(pid, kAECoreSuite, kAESetData, AppleEventProperty(kSpotifySoundVolume, nil),
                          [NSAppleEventDescriptor descriptorWithInt32:(SInt32)volume], kTimeout, &status) != nil;
}

// Where the music is: as it was, going down, down, down and waiting once you've stopped, or coming back up.
typedef NS_ENUM(NSInteger, Quieter) { QuieterOff, QuieterDown, QuieterLow, QuieterWaiting, QuieterUp };
// How turning it went: to its end with the volume still Whozmove's (or another move took over from it), stopped as the
// volume was changed by someone else, or stopped as Spotify didn't answer (busy, or gone).
typedef NS_ENUM(NSInteger, Glide) { GlideOurs, GlideTaken, GlideNoAnswer };

@interface SpotifyVolume ()
@property (strong) dispatch_queue_t queue;
@property (strong) dispatch_queue_t checks;   // macOS asked whether Whozmove may control Spotify, apart from turning it
@property (atomic) NSUInteger turn;
@property (assign) Quieter phase;
@property (assign) BOOL asking;            // Spotify being asked whether to lower it: nothing has changed yet
@property (assign) NSInteger from, to;     // the volume it had, and the one it's lowered to
@property (assign) double talkedAt;        // when the talk began (ms)
@property (assign) NSUInteger tries;       // bring-backs Spotify didn't answer, since the music went down
@property (strong) NSTimer *wait;
@property (strong) NSTimer *starting;      // a running Spotify, asked until it answers, for a kept record
@property (copy) NSString *knownControl;   // whether Whozmove may control Spotify, as last found
@property (assign) double controlAt;
@property (assign) BOOL checkingControl;
@property (assign) BOOL allowing;
// On the queue only: each volume set since the music last went down, as [volume, ms], the first being what it read
// then; and where the last bring-back landed, with the volume it brought back.
@property (strong) NSMutableArray<NSArray<NSNumber *> *> *sent;
@property (copy) NSArray<NSNumber *> *landed;
@end

@implementation SpotifyVolume

- (instancetype)init {
    if (!(self = [super init])) return nil;
    self.queue = dispatch_queue_create("whozmove.spotify-volume", DISPATCH_QUEUE_SERIAL);
    self.checks = dispatch_queue_create("whozmove.spotify-control", DISPATCH_QUEUE_SERIAL);
    self.sent = [NSMutableArray array];
    self.share = 0.5;
    __weak typeof(self) weakSelf = self;
    [NSWorkspace.sharedWorkspace.notificationCenter addObserverForName:NSWorkspaceDidLaunchApplicationNotification
                                                                object:nil queue:NSOperationQueue.mainQueue
                                                            usingBlock:^(NSNotification *note) {
        NSRunningApplication *app = note.userInfo[NSWorkspaceApplicationKey];
        if (![app.bundleIdentifier isEqual:kSpotifyAppId]) return;
        [weakSelf bringBackKept];
        [weakSelf checkControl];
    }];
    [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationWillTerminateNotification object:nil
                                                     queue:NSOperationQueue.mainQueue
                                                usingBlock:^(NSNotification *note) { [weakSelf quitting]; }];
    return self;
}

- (void)start {
    [self bringBackKept];
    [self checkControl];
}

- (void)setOn:(BOOL)on {
    if (on == _on) return;
    _on = on;
    if (on) return [self checkControl];
    if (self.asking) [self stopAsking];
    else if (self.phase != QuieterOff) [self bringBack];
}

- (void)talking:(BOOL)talking {
    if (talking) {
        self.talkedAt = NowMs();
        if (!self.on) return;
        [self.wait invalidate];
        self.wait = nil;
        if (self.phase == QuieterOff && !self.asking) [self lower];
        else if (self.phase == QuieterWaiting) {
            self.phase = QuieterLow;
            if (self.onQuieter) self.onQuieter(YES);
        } else if (self.phase == QuieterUp) [self lowerAgain];
        return;
    }
    if (self.asking) return [self stopAsking];
    if (self.phase != QuieterDown && self.phase != QuieterLow) return;
    if (NowMs() - self.talkedAt < kStrayUnder * 1000) return [self bringBack];
    self.phase = QuieterWaiting;
    __weak typeof(self) weakSelf = self;
    self.wait = [NSTimer scheduledTimerWithTimeInterval:kWaitAfter repeats:NO block:^(NSTimer *timer) {
        [weakSelf bringBack];
    }];
}

#pragma mark Down

// Only while Spotify is playing, here on this Mac, Whozmove may control it without asking (macOS's question never
// comes in the middle of a talk: the card on Spotify's page asks, on your press), and its volume is above where it
// would go. A talk taking over from a kept record being put back takes that record's volume as the one to bring back.
- (void)lower {
    pid_t pid = RunningSpotify();
    if (pid <= 0) return;
    [self stopBringingBackKept];
    self.asking = YES;
    NSUInteger turn = ++self.turn;
    double share = self.share;
    NSDictionary *kept = [self kept];
    dispatch_async(self.queue, ^{
        NSInteger from = [self volumeToLowerIn:pid kept:kept];
        NSInteger to = from == NSNotFound ? NSNotFound : SpotifyQuieterTarget(from, share);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (turn != self.turn) return;
            self.asking = NO;
            if (to == NSNotFound) return;
            self.phase = QuieterDown;
            self.from = from;
            self.to = to;
            self.tries = 0;
            [NSUserDefaults.standardUserDefaults setObject:@{@"from": @(from), @"to": @(to), @"at": @(NowMs())}
                                                    forKey:kKept];
            PanelLog(@"quieter: Spotify %ld -> %ld while you talk", (long)from, (long)to);
            if (self.onQuieter) self.onQuieter(YES);
            [self down:pid turn:turn];
        });
    });
}

// On the queue: the volume to bring back once you've stopped, when the music is to be lowered; else NSNotFound.
- (NSInteger)volumeToLowerIn:(pid_t)pid kept:(NSDictionary *)kept {
    if (AutomationPermission(pid, NO) != noErr) return NSNotFound;
    OSStatus status = noErr;
    NSAppleEventDescriptor *state = SendAppleEvent(pid, kAECoreSuite, kAEGetData,
                                                   AppleEventProperty(kSpotifyPlayerState, nil), nil, kTimeout,
                                                   &status);
    if (state.enumCodeValue != kSpotifyStatePlaying || !ProcessPlaysSound(pid)) return NSNotFound;
    NSInteger volume = ReadVolume(pid);
    if (volume == NSNotFound) return NSNotFound;
    [self.sent removeAllObjects];
    [self.sent addObject:@[@(volume), @(NowMs())]];
    return SpotifyVolumeToBringBack(volume, self.landed, kept, NowMs());
}

// You stopped, or it was turned off, before Spotify had answered: nothing has changed, and its answer is dropped.
- (void)stopAsking {
    self.asking = NO;
    self.turn++;
}

// A change of yours during the fall is noticed as it ends. Spotify not answering leaves the music wherever it got to,
// to be brought back from there once you've stopped.
- (void)down:(pid_t)pid turn:(NSUInteger)turn {
    [self glideTo:self.to pid:pid turn:turn checks:NO done:^(Glide glide) {
        if (glide == GlideTaken) return [self letGo];
        if (self.phase == QuieterDown) self.phase = QuieterLow;
    }];
}

// Talking again while it comes back up: down again from where it is, to where it went, worked out from the volume it
// had, so it never ends lower than the first time.
- (void)lowerAgain {
    pid_t pid = RunningSpotify();
    if (pid <= 0) return;
    NSUInteger turn = ++self.turn;
    self.phase = QuieterDown;
    if (self.onQuieter) self.onQuieter(YES);
    [self down:pid turn:turn];
}

#pragma mark Back up

// Even if Spotify was paused meanwhile, so it's right when you play again. A change of yours is left as you made it.
// While Spotify doesn't answer (busy), it's tried again a moment later, a few times; once it has quit, the record
// stays, and the volume is put back when it starts again.
- (void)bringBack {
    [self.wait invalidate];
    self.wait = nil;
    NSUInteger turn = ++self.turn;
    self.phase = QuieterUp;
    if (self.onQuieter) self.onQuieter(NO);
    pid_t pid = RunningSpotify();
    if (pid <= 0) {
        self.phase = QuieterOff;
        return;
    }
    NSInteger from = self.from;
    dispatch_async(self.queue, ^{
        NSInteger read = ReadVolume(pid);
        Glide glide = read == NSNotFound ? GlideNoAnswer
                    : !SpotifyVolumeIsOurs(read, self.sent, NowMs()) ? GlideTaken
                    : [self glide:from pid:pid turn:turn checks:YES];
        if (glide == GlideOurs && turn == self.turn) [self land:from pid:pid];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (turn != self.turn) return;
            if (glide == GlideTaken) return [self letGo];
            if (glide == GlideNoAnswer) return [self tryAgain];
            PanelLog(@"quieter: Spotify back to %ld", (long)from);
            [self forget];
        });
    });
}

// Spotify didn't answer: the music is brought back a moment later, from wherever it got to, a few times; then, while
// Spotify runs, the kept record is put back as after a quit; once it has quit, when it starts again.
- (void)tryAgain {
    if (++self.tries > kNoAnswerTries || RunningSpotify() <= 0) {
        PanelLog(@"quieter: Spotify isn't answering; its volume is put back once it does");
        self.phase = QuieterOff;
        [self bringBackKept];
        return;
    }
    self.phase = QuieterWaiting;
    __weak typeof(self) weakSelf = self;
    self.wait = [NSTimer scheduledTimerWithTimeInterval:kNoAnswerEvery repeats:NO block:^(NSTimer *timer) {
        [weakSelf bringBack];
    }];
}

// On the queue: the bring-back's last step, ending at exactly `volume` where Spotify's rounding allows (else one under,
// never over), noted for the next talk.
- (void)land:(NSInteger)volume pid:(pid_t)pid {
    usleep(kSettleMicroseconds);
    NSInteger read = ReadVolume(pid);
    if (read != NSNotFound && read != volume && SetVolume(pid, SpotifyVolumeToSet(volume))) {
        usleep(kSettleMicroseconds);
        read = ReadVolume(pid);
    }
    if (read != NSNotFound && read > volume && SetVolume(pid, volume)) read = ReadVolume(pid);
    self.landed = read == NSNotFound ? nil : @[@(read), @(volume)];
}

- (void)letGo {
    PanelLog(@"quieter: Spotify's volume was changed meanwhile, so it's left as it was set");
    [self.wait invalidate];
    self.wait = nil;
    if (self.onQuieter) self.onQuieter(NO);
    [self forget];
}

- (void)forget {
    self.phase = QuieterOff;
    self.tries = 0;
    [NSUserDefaults.standardUserDefaults removeObjectForKey:kKept];
}

#pragma mark Gliding

// Turns Spotify's volume from where it was last set (or read) to `to`, on the queue. `done` gets, on the main thread
// and only while no other move has started, how it went.
- (void)glideTo:(NSInteger)to pid:(pid_t)pid turn:(NSUInteger)turn checks:(BOOL)checks
           done:(void (^)(Glide glide))done {
    dispatch_async(self.queue, ^{
        Glide glide = [self glide:to pid:pid turn:turn checks:checks];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (turn == self.turn) done(glide);
        });
    });
}

// On the queue: one point at a time, the first at once, then one every kDownPointMs going down or kUpPointMs going up,
// never two at once: a point Spotify answers late is followed by the next as soon as it has answered, not by a jump to
// catch up. While `checks` (coming back up), the volume is read just before each point, so a change of yours always
// wins; and at the end, it's read once more either way.
- (Glide)glide:(NSInteger)to pid:(pid_t)pid turn:(NSUInteger)turn checks:(BOOL)checks {
    NSInteger volume = self.sent.lastObject[0].integerValue;
    double next = NowMs(), every = volume > to ? kDownPointMs : kUpPointMs;
    while (turn == self.turn && volume != to) {
        double wait = next - NowMs();
        if (wait > 0) usleep((useconds_t)(wait * 1000));
        if (turn != self.turn) break;
        if (checks) {
            NSInteger read = ReadVolume(pid);
            if (read == NSNotFound) return GlideNoAnswer;
            if (!SpotifyVolumeIsOurs(read, self.sent, NowMs())) return GlideTaken;
        }
        NSInteger point = volume > to ? volume - 1 : volume + 1;
        if (!SetVolume(pid, SpotifyVolumeToSet(point))) return GlideNoAnswer;
        [self.sent addObject:@[@(point), @(NowMs())]];
        volume = point;
        next = MAX(next + every, NowMs());
    }
    if (turn != self.turn) return GlideOurs;
    NSInteger read = ReadVolume(pid);
    return read == NSNotFound ? GlideNoAnswer : SpotifyVolumeIsOurs(read, self.sent, NowMs()) ? GlideOurs : GlideTaken;
}

#pragma mark A quit or a crash

// The record a quit or a crash left, while it's good; one a day old is forgotten.
- (NSDictionary *)kept {
    NSDictionary *kept = AsRecord([NSUserDefaults.standardUserDefaults objectForKey:kKept]);
    if (kept && NowMs() - [AsNumber(kept[@"at"]) doubleValue] > kKeptForMs) {
        [NSUserDefaults.standardUserDefaults removeObjectForKey:kKept];
        return nil;
    }
    return kept;
}

// A record a quit or a crash left: the volume put back if it's still where Whozmove left it, then the record goes;
// changed since, the record just goes. A running Spotify is asked every second until it answers, 20 times at most;
// one that isn't running is asked nothing until it starts (heard starting). A talk takes over from it.
- (void)bringBackKept {
    [self stopBringingBackKept];
    if (![self kept] || self.phase != QuieterOff || self.asking || RunningSpotify() <= 0) return;
    __block NSUInteger tries = 0;
    __weak typeof(self) weakSelf = self;
    void (^ask)(NSTimer *) = ^(NSTimer *timer) {
        SpotifyVolume *volume = weakSelf;
        NSDictionary *kept = [volume kept];
        pid_t pid = RunningSpotify();
        if (!volume || !kept || pid <= 0 || volume.phase != QuieterOff || volume.asking || ++tries > kStartingTries)
            return [volume stopBringingBackKept];
        [volume bringBackKept:kept pid:pid];
    };
    self.starting = [NSTimer scheduledTimerWithTimeInterval:kStartingEvery repeats:YES block:ask];
    ask(self.starting);
}

- (void)stopBringingBackKept {
    [self.starting invalidate];
    self.starting = nil;
}

- (void)bringBackKept:(NSDictionary *)kept pid:(pid_t)pid {
    NSUInteger turn = ++self.turn;
    NSInteger from = [AsNumber(kept[@"from"]) integerValue];
    dispatch_async(self.queue, ^{
        NSInteger read = AutomationPermission(pid, NO) == noErr ? ReadVolume(pid) : NSNotFound;
        BOOL back = read != NSNotFound && SpotifyKeptBringsBack(kept, read, NowMs());
        if (back) {
            [self.sent removeAllObjects];
            [self.sent addObject:@[@(read), @(NowMs())]];
            if ([self glide:from pid:pid turn:turn checks:YES] == GlideOurs && turn == self.turn)
                [self land:from pid:pid];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (turn != self.turn || read == NSNotFound) return;  // not answering yet: asked again in a moment
            [self stopBringingBackKept];
            if (back) PanelLog(@"quieter: Spotify back to %ld, left lowered when Whozmove or Spotify last quit",
                               (long)from);
            [self forget];
        });
    });
}

// Whozmove quitting with the music lowered: it's put back at once, in one step, if it's still Whozmove's.
- (void)quitting {
    if (self.phase == QuieterOff) return;
    self.turn++;
    pid_t pid = RunningSpotify();
    NSInteger from = self.from;
    __block BOOL answered = NO;
    if (pid > 0)
        dispatch_sync(self.queue, ^{
            NSInteger read = ReadVolume(pid);
            answered = read != NSNotFound;
            if (answered && SpotifyVolumeIsOurs(read, self.sent, NowMs())) SetVolume(pid, SpotifyVolumeToSet(from));
        });
    if (answered) [self forget];
}

#pragma mark Whether Whozmove may control Spotify

- (NSString *)control {
    if (!self.checkingControl && NowMs() - self.controlAt > kControlKnownForMs) [self checkControl];
    return self.knownControl;
}

// Asked of macOS without asking you anything, off the main thread: it can only say while Spotify is open.
- (void)checkControl {
    if (self.checkingControl) return;
    self.checkingControl = YES;
    pid_t pid = RunningSpotify();
    dispatch_async(self.checks, ^{
        OSStatus status = pid > 0 ? AutomationPermission(pid, NO) : procNotFound;
        NSString *control = status == noErr ? @"allowed" : status == errAEEventNotPermitted ? @"denied"
                          : status == errAEEventWouldRequireUserConsent ? @"ask" : @"closed";
        dispatch_async(dispatch_get_main_queue(), ^{
            self.checkingControl = NO;
            self.knownControl = control;
            self.controlAt = NowMs();
        });
    });
}

- (void)allowControl {
    pid_t pid = RunningSpotify();
    if (pid <= 0 || self.allowing) return;
    self.allowing = YES;
    dispatch_async(self.checks, ^{
        AutomationPermission(pid, YES);
        dispatch_async(dispatch_get_main_queue(), ^{
            self.allowing = NO;
            [self checkControl];
        });
    });
}

@end

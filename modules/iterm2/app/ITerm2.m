// ITerm2: finding a session's iTerm2 tab and bringing it forward, and running a command in a new tab, through
// AppleScript, and which tab it shows, through its Apple events. iTerm2 says which terminal device each of its sessions
// has, so a session is found by its own.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "ITerm2.h"
#import "ITerm2Facts.h"
#import <AppKit/AppKit.h>
#include <sys/param.h>
#import "Row.h"
#import "Log.h"
#import "AppleEvents.h"
#import "AppleScript.h"
#import "Processes.h"
#import "Text.h"

// How long an iTerm2 started for a new tab is waited for while it starts.
static const NSTimeInterval kStartingFor = 20;

// iTerm2's process while it's running, else 0.
static pid_t ITerm2Process(void) {
    return [NSRunningApplication runningApplicationsWithBundleIdentifier:kITerm2AppId].firstObject.processIdentifier;
}

// The running iTerm2s' processes, by pid.
static NSSet<NSNumber *> *ITerm2Processes(void) {
    return [NSSet setWithArray:[[NSRunningApplication runningApplicationsWithBundleIdentifier:kITerm2AppId]
                                   valueForKey:@"processIdentifier"]];
}

// The first process of the iTerm2 session a process runs in, the one iTerm2 started for the session: under its server,
// or under iTerm2 itself when it keeps none. 0 when the process isn't in an iTerm2 session. `apps` are the running
// iTerm2s' processes.
static pid_t SessionStart(pid_t pid, NSSet<NSNumber *> *apps) {
    for (pid_t up = pid; up > 1;) {
        pid_t parent = ProcessParent(up);
        if ([apps containsObject:@(parent)] || [ProcessPath(parent).lastPathComponent hasPrefix:kITerm2ServerPrefix])
            return up;
        up = parent;
    }
    return 0;
}

// The terminal device of the iTerm2 session a process runs in: the one iTerm2 gave the session, which its first
// process holds, so a `claude` on a terminal of its own inside the session (under `script`, say) is found by the
// session's. NODEV while the process isn't in its own terminal's foreground, as a `claude` suspended in its shell has
// no tab, and when it isn't in an iTerm2 session.
static dev_t SessionTerminal(pid_t pid, NSSet<NSNumber *> *apps) {
    if (ProcessTerminal(pid, YES) == NODEV) return NODEV;
    pid_t start = SessionStart(pid, apps);
    return start > 0 ? ProcessTerminal(start, NO) : NODEV;
}

// A terminal device's path, if it's one a script may name: /dev/ttys and digits, as every iTerm2 session's is.
static NSString *Nameable(NSString *tty) {
    NSString *number = [tty hasPrefix:@"/dev/ttys"] ? [tty substringFromIndex:9] : nil;
    NSCharacterSet *notDigit = [NSCharacterSet characterSetWithCharactersInString:@"0123456789"].invertedSet;
    return number.length && [number rangeOfCharacterFromSet:notDigit].location == NSNotFound ? tty : nil;
}

// The folder a new tab's file of commands waits in until the tab runs it: your temporary folder's, which only you can
// read, as its path, unlike Whozmove's own folder's, is one iTerm2 takes as it is (ITerm2Facts.h).
static NSString *TabFilesFolder(void) {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:@"whozmove-iterm2"];
}

// Whether text is one word iTerm2 takes as it is, in a command it's given (ITerm2Facts.h).
static BOOL Plain(NSString *text) {
    NSCharacterSet *other = [NSCharacterSet characterSetWithCharactersInString:kITerm2PlainCharacters].invertedSet;
    return text.length && [text rangeOfCharacterFromSet:other].location == NSNotFound;
}

// Whether `shell` is bash, which takes a tab's file of commands as its startup file (TabProgram).
static BOOL IsBash(NSString *shell) {
    return [shell.lastPathComponent isEqualToString:@"bash"];
}

// What a new tab runs, as a file of commands at `path` for `shell`: it takes the file away, runs the command in the
// folder, and leaves your shell in the tab once the command ends. bash reads it as its startup file, after your login
// files, and is your shell afterwards, so Ctrl+Z pauses the command and `fg` brings it back, as in any tab. zsh can't
// stay on as your shell after a file, so it gives its place to a new zsh once the command ends; but only the zsh that
// started the command could bring it back from a pause, so it brings it back at once, and Ctrl+Z there does no more
// than make it draw itself again.
static NSString *TabCommands(NSString *path, NSString *folder, NSString *command, NSString *shell) {
    NSString *run = [NSString stringWithFormat:@"rm -f -- %@\ncd -- %@ && %@\n", ShellWord(path), ShellWord(folder),
                                               command];
    if (IsBash(shell))
        return [@"[ -r /etc/profile ] && . /etc/profile\n"
                @"for f in ~/.bash_profile ~/.bash_login ~/.profile; do [ -r \"$f\" ] && { . \"$f\"; break; }; done\n"
                @"unset f\n" stringByAppendingString:run];
    return [run stringByAppendingFormat:@"while jobs %%%% >/dev/null 2>&1; do fg %%%% >/dev/null 2>&1 || break; done\n"
                                        @"exec %@ -l\n", ShellWord(shell)];
}

// The tab's own program, as the words iTerm2 is given: bash with the file as its startup file, else the shell started
// as your terminal starts it, reading the file. Nil when the shell's path or the file's isn't plain (ITerm2Facts.h).
static NSString *TabProgram(NSString *path, NSString *shell) {
    if (!Plain(path) || !Plain(shell)) return nil;
    return [NSString stringWithFormat:IsBash(shell) ? @"%@ --rcfile %@ -i" : @"%@ -l -i %@", shell, path];
}

// Writes a new tab's file of commands, which only you can read. NO if it couldn't.
static BOOL KeepTabCommands(NSString *commands, NSString *path) {
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent
                            withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @0700} error:nil];
    NSData *contents = [commands dataUsingEncoding:NSUTF8StringEncoding];
    return [NSFileManager.defaultManager createFileAtPath:path contents:contents
                                               attributes:@{NSFilePosixPermissions: @0600}];
}

// What opens a new tab whose own program is `program` (TabProgram): in iTerm2's frontmost window that isn't a hotkey
// window (which may be hidden), else in a window of its own, with iTerm2 brought forward (`forward`; a new window comes
// forward anyway). Nothing is typed into the tab, where Broadcast Input could copy it into the window's other sessions,
// and the command iTerm2 is given is plain words, so nothing in it is iTerm2's to change. The window is held by what
// iTerm2 answers for it (its id), not by its place, as a new tab reorders them.
static NSString *NewTabScript(NSString *program, BOOL forward) {
    return [NSString stringWithFormat:@"set tabCommand to \"%@\"\n"
                                      @"set w to missing value\n"
                                      @"if (count of windows) > 0 then\n"
                                      @"  set hotkeys to is hotkey window of windows\n"
                                      @"  repeat with i from 1 to count of hotkeys\n"
                                      @"    if not (item i of hotkeys) then\n"
                                      @"      set w to window i\n"
                                      @"      exit repeat\n"
                                      @"    end if\n"
                                      @"  end repeat\n"
                                      @"end if\n"
                                      @"if w is missing value then\n"
                                      @"  create window with default profile command tabCommand\n"
                                      @"else\n"
                                      @"%@"
                                      @"  tell w to create tab with default profile command tabCommand\n"
                                      @"%@"
                                      @"end if%@", program,
                                      forward ? @"  if miniaturized of w then set miniaturized of w to false\n" : @"",
                                      forward ? @"  select w\n" : @"", forward ? @"\nactivate" : @""];
}

// Runs AppleScript in iTerm2, and returns what it returns, only while iTerm2 is running: `tell` would start it, so it's
// checked before the script and again in it. Each question iTerm2 hasn't answered in 2s gives up, rather than holding
// the panel for AppleScript's own 2 minutes. So macOS's question whether Whozmove may control iTerm2, which a script's
// first question would bring up, is asked before (ask:then:), with no limit on your answer.
static NSString *RunInITerm2(NSString *body) {
    if (ITerm2Process() <= 0) return nil;
    return RunAppleScript([NSString stringWithFormat:@"with timeout of 2 seconds\n"
                                                     @"  if application id \"%@\" is running then\n"
                                                     @"    tell application id \"%@\"\n"
                                                     @"%@\n"
                                                     @"    end tell\n"
                                                     @"  end if\n"
                                                     @"end timeout\n"
                                                     @"return \"\"", kITerm2AppId, kITerm2AppId, body]);
}

@interface ITerm2 ()
// Asking which tab iTerm2 shows (whichShows:done:), and whether Whozmove may control it, on a queue of its own.
@property (strong) dispatch_queue_t queue;
@property (assign) BOOL asking;  // an answer is on its way; on the main thread only
// Whether macOS lets Whozmove control iTerm2, as far as it's known (iTerm2 answered, or macOS said so); whether it's
// asking you now, for a press (askToControl:then:); and what the press opens once you've allowed it, unless you've
// gone to another app meanwhile. On the main thread only.
@property (assign) BOOL allowed, askingToControl;
@property (copy) void (^onceAllowed)(void);
@end

@implementation ITerm2

+ (NSString *)moduleName {
    return @"iterm2";
}

- (instancetype)initWithCore:(Core *)core {
    if (!(self = [super init])) return nil;
    self.queue = dispatch_queue_create("whozmove.iterm2", DISPATCH_QUEUE_SERIAL);
    return self;
}

// `Whozmove --print-iterm2-tab <shell> <file> <folder> <command>`: what a new tab running the command in the folder,
// through that shell, would have in its file of commands at that path, and what iTerm2 would be told to open it, or
// that it wouldn't be, then quit. Nothing is written, and nothing is sent to iTerm2.
+ (NSDictionary<NSString *, PrintMode> *)printModes {
    return @{@"--print-iterm2-tab": ^(Core *core, NSArray<NSString *> *a) {
        if (a.count != 4) {
            fprintf(stderr, "usage: Whozmove --print-iterm2-tab <shell> <file> <folder> <command>\n");
            return 2;
        }
        NSString *program = TabProgram(a[1], a[0]);
        if (!program) printf("(not given to iTerm2: the shell's path or the file's isn't plain)\n");
        else printf("-- its file of commands\n%s-- what iTerm2 is told\n%s\n",
                    TabCommands(a[1], a[2], a[3], a[0]).UTF8String, NewTabScript(program, YES).UTF8String);
        return 0;
    }};
}

// Whether macOS lets Whozmove control iTerm2 already, found out without asking you, so a press or a new tab needn't
// wait to know. Files of commands left from new tabs that never ran go, once they're a minute old: one for a tab still
// opening as the panel restarts is still wanted. A press waiting for macOS's answer is let go once you go to another
// app, as it isn't what you're after any more.
- (void)launch {
    NSString *files = TabFilesFolder();
    dispatch_async(self.queue, ^{
        NSFileManager *manager = NSFileManager.defaultManager;
        for (NSString *name in [manager contentsOfDirectoryAtPath:files error:nil]) {
            NSString *path = [files stringByAppendingPathComponent:name];
            NSDate *made = [manager attributesOfItemAtPath:path error:nil].fileModificationDate;
            if (made && -made.timeIntervalSinceNow > 60) [manager removeItemAtPath:path error:nil];
        }
    });
    __weak typeof(self) weakSelf = self;
    [NSWorkspace.sharedWorkspace.notificationCenter addObserverForName:NSWorkspaceDidActivateApplicationNotification
                                                                object:nil queue:NSOperationQueue.mainQueue
                                                            usingBlock:^(NSNotification *note) {
        NSRunningApplication *app = note.userInfo[NSWorkspaceApplicationKey];
        if (app.activationPolicy == NSApplicationActivationPolicyRegular
            && ![app.bundleIdentifier isEqualToString:kITerm2AppId])
            weakSelf.onceAllowed = nil;
    }];
    pid_t pid = ITerm2Process();
    if (pid <= 0) return;
    dispatch_async(self.queue, ^{
        OSStatus status = AutomationPermission(pid, NO);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (status == noErr) self.allowed = YES;
        });
    });
}

- (NSString *)appId {
    return kITerm2AppId;
}

- (NSString *)name {
    return kITerm2Name;
}

// A process runs in iTerm2 when iTerm2 or its server is up its tree. The core asks only when no ordinary app is: the
// server has outlived iTerm2 (after a crash, say), or iTerm2 is kept out of the Dock, which no ordinary app is.
- (BOOL)runsProcess:(pid_t)pid {
    return SessionStart(pid, ITerm2Processes()) > 0;
}

// Until macOS has let Whozmove control iTerm2, that's asked first, off the main thread, as its question waits for your
// answer: iTerm2 comes forward meanwhile (NO), and the session once you've allowed it.
- (BOOL)open:(Row *)row {
    pid_t pid = ITerm2Process();
    NSString *tty = pid > 0 ? Nameable(TerminalPath(SessionTerminal(row.pid, ITerm2Processes()))) : nil;
    if (!tty) {
        PanelLog(@"open terminal session pid %d -> no iTerm2 session on its terminal", row.pid);
        return NO;
    }
    if (self.allowed) return [self show:tty of:row];
    __weak typeof(self) weakSelf = self;
    [self askToControl:pid then:^{ [weakSelf show:tty of:row]; }];
    return NO;
}

// Asks macOS whether Whozmove may control iTerm2, asking you if it hasn't yet, for a press: one question at a time, and
// a press meanwhile only changes what's opened once you've answered (nothing, if you've gone to another app).
- (void)askToControl:(pid_t)pid then:(void (^)(void))then {
    self.onceAllowed = then;
    if (self.askingToControl) return;
    self.askingToControl = YES;
    [self ask:pid then:^(BOOL allowed) {
        void (^next)(void) = self.onceAllowed;
        self.onceAllowed = nil;
        self.askingToControl = NO;
        if (allowed && next) next();
    }];
}

// Asks macOS whether Whozmove may control iTerm2, asking you if it hasn't yet, off the main thread, as its question
// waits for your answer as long as you take. `then` gets whether it may, on the main thread: NO too once that iTerm2
// has gone.
- (void)ask:(pid_t)pid then:(void (^)(BOOL allowed))then {
    dispatch_async(self.queue, ^{
        OSStatus status = AutomationPermission(pid, YES);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (status == noErr) self.allowed = YES;
            else PanelLog(@"iTerm2: Whozmove isn't allowed to control it (%d)", (int)status);
            then(status == noErr && ITerm2Process() == pid);
        });
    });
}

// One question lists every session's tty, window by window and tab by tab, and the session's own is found in that list
// inside the script. Its tab and its split are selected before its window, so the window shows them as it comes
// forward; a hotkey window is shown as its hotkey shows it, as selecting a hidden one would leave it unseen. Each is
// held by what iTerm2 answers (a window by its id, a session by its own), not by its place, as selecting a window
// reorders them. It went through only if the script got to its end. A script that failed may have lost Whozmove's leave
// to control iTerm2, so the next press asks macOS again.
- (BOOL)show:(NSString *)tty of:(Row *)row {
    NSString *script = [NSString stringWithFormat:@"set found to tty of sessions of tabs of windows\n"
                                                  @"repeat with i from 1 to count of found\n"
                                                  @"  repeat with j from 1 to count of item i of found\n"
                                                  @"    repeat with k from 1 to count of item j of item i of found\n"
                                                  @"      if item k of item j of item i of found is \"%@\" then\n"
                                                  @"        set w to window i\n"
                                                  @"        set t to tab j of w\n"
                                                  @"        set s to session k of t\n"
                                                  @"        if miniaturized of w then set miniaturized of w to false\n"
                                                  @"        select t\n"
                                                  @"        select s\n"
                                                  @"        if is hotkey window of w then\n"
                                                  @"          reveal hotkey window w\n"
                                                  @"        else\n"
                                                  @"          select w\n"
                                                  @"        end if\n"
                                                  @"        activate\n"
                                                  @"        return \"focused\"\n"
                                                  @"      end if\n"
                                                  @"    end repeat\n"
                                                  @"  end repeat\n"
                                                  @"end repeat", tty];
    NSString *done = RunInITerm2(script);
    if (!done) self.allowed = NO;
    if (![done isEqualToString:@"focused"]) {
        PanelLog(@"open terminal session pid %d -> no iTerm2 session on %@", row.pid, tty);
        return NO;
    }
    PanelLog(@"open terminal session pid %d -> selected iTerm2 session on %@", row.pid, tty);
    return YES;
}

// A command in a new tab, with iTerm2 started first if it isn't running. Until macOS has let Whozmove control iTerm2,
// that's asked first, and the tab opens once you've allowed it; each new tab asked for opens. The tab shows what runs
// in it, which names itself (Claude Code does), so `name` isn't needed. A tab that doesn't open takes its file away.
- (void)newTabIn:(NSString *)folder running:(NSString *)command named:(NSString *)name forward:(BOOL)forward
            done:(void (^)(NSString *why))done {
    NSString *shell = LoginShell(), *path = [TabFilesFolder() stringByAppendingPathComponent:
                                              [NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"sh"]];
    void (^finish)(NSString *) = ^(NSString *why) {
        if (why) [NSFileManager.defaultManager removeItemAtPath:path error:nil];
        done(why);
    };
    NSString *program = TabProgram(path, shell);
    if (!program || !KeepTabCommands(TabCommands(path, folder, command, shell), path)) {
        PanelLog(@"new terminal session in %@ -> not in iTerm2: no file of commands for it at a path iTerm2 takes as "
                 @"it is (%@)", folder, path);
        return finish(@"Couldn't give iTerm2 what to run");
    }
    NSString *script = NewTabScript(program, forward);
    __weak typeof(self) weakSelf = self;
    void (^openWhenAllowed)(pid_t) = ^(pid_t pid) {
        if (pid <= 0) return finish(@"iTerm2 didn't start");
        if (weakSelf.allowed) return finish([weakSelf openTab:script in:folder]);
        [weakSelf ask:pid then:^(BOOL allowed) {
            ITerm2 *iterm2 = weakSelf;
            if (allowed) return finish([iterm2 openTab:script in:folder]);
            finish(iterm2.allowed ? @"iTerm2 quit before it opened a tab"
                                  : @"Whozmove isn't allowed to control iTerm2: allow it in System Settings, Privacy "
                                    @"& Security, Automation");
        }];
    };
    pid_t pid = ITerm2Process();
    if (pid > 0) return openWhenAllowed(pid);
    NSURL *app = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:kITerm2AppId];
    if (!app) return finish(@"iTerm2 isn't on this Mac");
    NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration configuration];
    configuration.activates = forward;
    [NSWorkspace.sharedWorkspace openApplicationAtURL:app configuration:configuration
                                    completionHandler:^(NSRunningApplication *started, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!started) {
                PanelLog(@"new terminal session in %@ -> iTerm2 didn't start: %@", folder, error.localizedDescription);
                return openWhenAllowed(0);
            }
            NSDate *until = [NSDate dateWithTimeIntervalSinceNow:kStartingFor];
            [weakSelf once:started hasStarted:openWhenAllowed until:until];
        });
    }];
}

// An iTerm2 just started, once it has finished starting: `then` gets its process, on the main thread, or 0 for one that
// quit, or hasn't by `until`.
- (void)once:(NSRunningApplication *)app hasStarted:(void (^)(pid_t pid))then until:(NSDate *)until {
    if (app.finishedLaunching) return then(app.processIdentifier);
    if (app.terminated || until.timeIntervalSinceNow < 0) {
        PanelLog(@"iTerm2 didn't finish starting");
        return then(0);
    }
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf once:app hasStarted:then until:until];
    });
}

// Opens a new tab: nil once it has, else why not. It went through only if the script got to its end. One that failed
// may have lost Whozmove's leave to control iTerm2, so the next asks macOS again.
- (NSString *)openTab:(NSString *)script in:(NSString *)folder {
    if (RunInITerm2(script)) {
        PanelLog(@"new terminal session in %@, in iTerm2", folder);
        return nil;
    }
    self.allowed = NO;
    PanelLog(@"new terminal session in %@ -> iTerm2 didn't open a tab for it", folder);
    return @"iTerm2 didn't open a tab for it";
}

// The panel asks this on every tick while iTerm2 is in front, so the answer is waited for on a queue of iTerm2's own:
// the ttys of the sessions in its current window's current tab, and when the tab is split, the one with the keyboard.
// Each session's own terminal is found there too, as that takes a few system calls for each process up its tree, and
// devices are compared as numbers. The tab marks the session with the keyboard, else the only one of these in it; none
// of them in it says it's certainly none; two of them, neither with the keyboard, can't be told apart.
- (void)whichShows:(NSArray<Row *> *)rows done:(void (^)(Row *row))done {
    pid_t pid = ITerm2Process();
    if (pid <= 0 || self.asking) return;
    NSSet<NSNumber *> *apps = ITerm2Processes();
    NSMutableArray<NSNumber *> *pids = [NSMutableArray array];
    for (Row *row in rows) [pids addObject:@(row.pid)];
    self.asking = YES;
    dispatch_async(self.queue, ^{
        // Each row's place among them, by its session's terminal device.
        NSMutableDictionary<NSNumber *, NSNumber *> *sessionOn = [NSMutableDictionary dictionary];
        for (NSUInteger i = 0; i < pids.count; i++) {
            dev_t device = SessionTerminal(pids[i].intValue, apps);
            if (device != NODEV) sessionOn[@(device)] = @(i);
        }
        NSAppleEventDescriptor *tab =
            AppleEventProperty(kITerm2CurrentTab, AppleEventProperty(kITerm2CurrentWindow, nil));
        NSArray<NSString *> *inTab = AskEvery(pid, kITerm2SessionClass, kITerm2Tty, tab, 1);
        NSString *current = inTab.count > 1
            ? AskQuietly(pid, AppleEventProperty(kITerm2Tty, AppleEventProperty(kITerm2CurrentSession, tab)),
                         1).stringValue
            : inTab.firstObject;
        NSMutableArray<NSNumber *> *shown = [NSMutableArray array];
        for (NSString *tty in inTab) {
            NSNumber *at = sessionOn[@(TerminalAt(tty))];
            if (at) [shown addObject:at];
        }
        NSNumber *withKeyboard = current ? sessionOn[@(TerminalAt(current))] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            self.asking = NO;
            if (!inTab.count) return;  // no answer, or no window
            self.allowed = YES;
            NSNumber *at = withKeyboard ?: (shown.count == 1 ? shown.firstObject : nil);
            if (at || !shown.count) done(at ? rows[at.unsignedIntegerValue] : nil);
        });
    });
}

#pragma mark On the panel's back

// iTerm2 on the panel's back: what Whozmove does with it, and macOS's Automation, which finding its tabs and opening
// new ones needs.
- (NSArray<AppEntry *> *)appEntries {
    AppEntry *iterm = [AppEntry appWithId:self.appId name:self.name
                                     does:@"Lists the Claude Code sessions in its tabs and opens them, and starts new "
                                          @"conversations in a new tab."
                                    order:30];
    iterm.permission = AppPermissionAutomation;
    iterm.permissionFor = @"Finds each session's tab, and opens new ones";
    return @[iterm];
}

@end

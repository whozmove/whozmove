// Processes: running processes, the app each belongs to, the flags it started with, and running tools.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Processes.h"
#include <libproc.h>
#include <sys/param.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <sys/wait.h>
#include <signal.h>
#include <errno.h>
#include <fcntl.h>
#include <spawn.h>
#include <poll.h>
#include <pwd.h>
#include <unistd.h>

extern char **environ;
#import "Log.h"

BOOL ProcessAlive(pid_t pid) {
    return pid > 0 && (kill(pid, 0) == 0 || errno == EPERM);
}

// When a process started, in microseconds since 1970, or 0 if there's no such process: with its pid, it tells a
// process apart from a later one given the same pid.
long long ProcessStartedAt(pid_t pid) {
    struct kinfo_proc info;
    size_t size = sizeof(info);
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, pid};
    if (pid <= 0 || sysctl(mib, 4, &info, &size, NULL, 0) != 0 || size == 0) return 0;
    struct timeval started = info.kp_proc.p_starttime;
    return (long long)started.tv_sec * 1000000 + started.tv_usec;
}

// Whether a process is paused (Ctrl+Z in its terminal, or SIGSTOP): it's still there, but runs nothing until it's
// carried on.
BOOL ProcessStopped(pid_t pid) {
    struct kinfo_proc info;
    size_t size = sizeof(info);
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, pid};
    if (pid <= 0 || sysctl(mib, 4, &info, &size, NULL, 0) != 0 || size == 0) return NO;
    return info.kp_proc.p_stat == SSTOP;
}

// A session's process, told apart from a later one given the same pid: pid and start time.
NSString *ProcessKey(pid_t pid, NSString *procStart) {
    return [NSString stringWithFormat:@"%d %@", pid, procStart ?: @""];
}

// A process's parent, or 0 when it can't be read. sysctl, not proc_pidinfo: the latter is refused for root-owned
// ancestors such as `login`, which sits between every terminal app and its shell.
pid_t ProcessParent(pid_t pid) {
    struct kinfo_proc info;
    size_t size = sizeof(info);
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, pid};
    if (sysctl(mib, 4, &info, &size, NULL, 0) != 0 || size == 0) return 0;
    return info.kp_eproc.e_ppid;
}

// The program a process runs, by its path, or nil when there's no such process. Root-owned ones, such as `login`, can
// be read too.
NSString *ProcessPath(pid_t pid) {
    char path[PROC_PIDPATHINFO_MAXSIZE];
    int length = pid > 0 ? proc_pidpath(pid, path, sizeof path) : 0;
    return length > 0 ? [[NSString alloc] initWithBytes:path length:(NSUInteger)length encoding:NSUTF8StringEncoding]
                      : nil;
}

// The terminal device a process has, as a number (NODEV for none). With `foregroundOnly`, only while the process is in
// its terminal's foreground, so a `claude` suspended with Ctrl+Z while its shell has the terminal has none.
dev_t ProcessTerminal(pid_t pid, BOOL foregroundOnly) {
    struct kinfo_proc info;
    size_t size = sizeof(info);
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, pid};
    if (pid <= 0 || sysctl(mib, 4, &info, &size, NULL, 0) != 0 || size == 0) return NODEV;
    if (foregroundOnly && info.kp_eproc.e_pgid != info.kp_eproc.e_tpgid) return NODEV;
    return info.kp_eproc.e_tdev;
}

// A terminal device's path ("/dev/ttys012"), or nil. It's looked for through /dev, which takes most of a millisecond,
// so devices are compared as numbers, and a path is found only for a script that names one.
NSString *TerminalPath(dev_t device) {
    char name[64];
    if (device == NODEV || !devname_r(device, S_IFCHR, name, (int)sizeof name)) return nil;
    return [@"/dev/" stringByAppendingString:@(name)];
}

// The terminal device at a path ("/dev/ttys012"), as a number, or NODEV.
dev_t TerminalAt(NSString *path) {
    struct stat info;
    if (!path.length || stat(path.fileSystemRepresentation, &info) != 0 || !S_ISCHR(info.st_mode)) return NODEV;
    return info.st_rdev;
}

// The app a terminal session runs in: the first ordinary app up its process tree.
NSRunningApplication *OwningApp(pid_t pid) {
    for (; pid > 1; pid = ProcessParent(pid)) {
        NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
        if (app && app.activationPolicy == NSApplicationActivationPolicyRegular) return app;
    }
    return nil;
}

// The command-line flags a process was started with (`claude --model … --effort …`), via KERN_PROCARGS2.
NSArray<NSString *> *ProcessArguments(pid_t pid) {
    int mib[3] = {CTL_KERN, KERN_PROCARGS2, pid};
    size_t size = 0;
    if (sysctl(mib, 3, NULL, &size, NULL, 0) != 0 || size < sizeof(int)) return @[];
    NSMutableData *buffer = [NSMutableData dataWithLength:size];
    if (sysctl(mib, 3, buffer.mutableBytes, &size, NULL, 0) != 0) return @[];
    const char *bytes = buffer.bytes, *end = bytes + size;
    int argc = *(const int *)bytes;
    const char *p = bytes + sizeof(int);
    p += strnlen(p, end - p);                  // executable path
    while (p < end && *p == '\0') p++;        // padding
    NSMutableArray *args = [NSMutableArray array];
    for (int i = 0; i < argc && p < end; i++) {
        size_t length = strnlen(p, end - p);
        [args addObject:[[NSString alloc] initWithBytes:p length:length encoding:NSUTF8StringEncoding] ?: @""];
        p += length + 1;
    }
    return args;
}

// A flag's value, given either as `--flag value` or as `--flag=value`.
NSString *FlagValue(NSArray<NSString *> *args, NSString *flag) {
    for (NSUInteger i = 0; i < args.count; i++) {
        if ([args[i] isEqualToString:flag] && i + 1 < args.count) return args[i + 1];
        if ([args[i] hasPrefix:[flag stringByAppendingString:@"="]])
            return [args[i] substringFromIndex:flag.length + 1];
    }
    return nil;
}

// Runs a command-line tool: {status, out, err}, or nil if it couldn't start. Killed after 20s.
// Blocking; call off the main thread.
NSDictionary *RunTool(NSString *path, NSArray<NSString *> *arguments, NSString *directory) {
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:path];
    task.arguments = arguments;
    if (directory) task.currentDirectoryURL = [NSURL fileURLWithPath:directory];
    // With no files left to open, a pipe can't be made, and what the tool says would go nowhere and read as nothing
    // (a checkout with no changes, say), so it isn't run.
    NSPipe *out = [NSPipe pipe], *err = [NSPipe pipe];
    if (!out || !err) return nil;
    task.standardOutput = out;
    task.standardError = err;
    if (![task launchAndReturnError:nil]) return nil;
    // The timer holds the task weakly, and its pipes are closed the moment it's done: held for the timer's 20s, the
    // pipes of git run many times a second would run the app out of files to open.
    __weak NSTask *weakTask = task;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSTask *running = weakTask;
        if (running.isRunning) [running terminate];
    });
    __block NSData *errData = nil;
    dispatch_group_t group = dispatch_group_create();  // stderr is read alongside stdout, so neither pipe fills up
    dispatch_group_async(group, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        errData = [err.fileHandleForReading readDataToEndOfFile];
    });
    NSData *outData = [out.fileHandleForReading readDataToEndOfFile];
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    [task waitUntilExit];
    [out.fileHandleForReading closeAndReturnError:nil];
    [err.fileHandleForReading closeAndReturnError:nil];
    return @{@"status": @(task.terminationStatus), @"out": outData ?: NSData.data,
             @"err": [[NSString alloc] initWithData:errData ?: NSData.data encoding:NSUTF8StringEncoding] ?: @""};
}

// Starts a tool with posix_spawn, its standard input, output and errors set up by `files`: in a session of its own
// (setsid), with no terminal, and with nothing of this app's but what it's given. It starts with signals as a new
// program has them: the queue threads that call this block most of them, and a tool would otherwise keep that, so it
// couldn't be stopped, and a tool that stops a helper of its own, or times itself out, would wait for nothing. Only
// the descriptors `files` sets up go with it, never one this app has open at that moment (another tool's pipe, which
// would stay open for as long as this one runs). `environment` replaces this app's when given. Returns posix_spawn's
// answer, 0 when it started.
static int Spawn(pid_t *pid, NSString *path, NSArray<NSString *> *arguments,
                 NSDictionary<NSString *, NSString *> *environment, posix_spawn_file_actions_t *files) {
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    // A session leader's process group is its own pid, so killpg still reaches everything it started.
    // (POSIX_SPAWN_SETPGROUP alongside SETSID makes posix_spawn fail.)
    posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETSID | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF
                                    | POSIX_SPAWN_CLOEXEC_DEFAULT);
    sigset_t noSignals, allSignals;
    sigemptyset(&noSignals);
    sigfillset(&allSignals);
    posix_spawnattr_setsigmask(&attr, &noSignals);
    posix_spawnattr_setsigdefault(&attr, &allSignals);
    // The arguments go as UTF-8, as typed: a path's file-system form would decompose accented letters in a command.
    NSMutableArray<NSString *> *all = [NSMutableArray arrayWithObject:path];
    [all addObjectsFromArray:arguments];
    char **argv = calloc(all.count + 1, sizeof(char *));
    for (NSUInteger i = 0; i < all.count; i++) argv[i] = (char *)all[i].UTF8String;
    NSMutableArray<NSString *> *pairs = [NSMutableArray array];
    for (NSString *key in environment) [pairs addObject:[NSString stringWithFormat:@"%@=%@", key, environment[key]]];
    char **env = environ;
    if (environment) {
        env = calloc(pairs.count + 1, sizeof(char *));
        for (NSUInteger i = 0; i < pairs.count; i++) env[i] = (char *)pairs[i].UTF8String;
    }
    int started = posix_spawn(pid, path.fileSystemRepresentation, files, &attr, argv, env);
    free(argv);
    if (environment) free(env);
    posix_spawnattr_destroy(&attr);
    return started;
}

// Starts a command-line tool that outlives this app: in a session of its own (Spawn), so when launchd stops the app's
// login item, which takes the app's process group with it, the tool carries on. Its output goes to the file `log`
// (made afresh), or nowhere when that's nil. `ended`, when given, is called once it has ended (on a global queue),
// should this app still be running then. Returns its pid, or 0 if it didn't start.
pid_t SpawnDetached(NSString *path, NSArray<NSString *> *arguments, NSDictionary<NSString *, NSString *> *environment,
                    NSString *log, void (^ended)(void)) {
    posix_spawn_file_actions_t files;
    posix_spawn_file_actions_init(&files);
    posix_spawn_file_actions_addopen(&files, 0, "/dev/null", O_RDONLY, 0);
    const char *output = log ? log.fileSystemRepresentation : "/dev/null";
    posix_spawn_file_actions_addopen(&files, 1, output, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    posix_spawn_file_actions_adddup2(&files, 1, 2);
    pid_t pid = 0;
    int status = Spawn(&pid, path, arguments, environment, &files);
    posix_spawn_file_actions_destroy(&files);
    if (status != 0) return 0;
    // Reaped when it ends, should this app still be running then, so it doesn't linger as a zombie. Told by the
    // kernel rather than waited for, which would hold a thread for as long as the tool runs. One that ended before
    // the source was set up is reaped straight away. Both go on one serial queue, so it's reaped, and `ended` called,
    // once.
    static dispatch_queue_t reaper;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ reaper = dispatch_queue_create("whozmove.reaper", DISPATCH_QUEUE_SERIAL); });
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_PROC, pid, DISPATCH_PROC_EXIT, reaper);
    __block BOOL reaped = NO;
    void (^reap)(void) = ^{
        if (reaped || waitpid(pid, NULL, WNOHANG) != pid) return;
        reaped = YES;
        dispatch_source_cancel(source);
        if (ended) dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ended);
    };
    dispatch_source_set_event_handler(source, reap);
    dispatch_resume(source);
    dispatch_async(reaper, reap);
    return pid;
}

// Waits for a tool Spawn started to end, until `until`: its wait status, or -1 if it's still running then.
static int WaitUntil(pid_t pid, NSDate *until) {
    int status = 0;
    for (;;) {
        pid_t ended = waitpid(pid, &status, WNOHANG);
        if (ended == pid) return status;
        if (ended < 0 && errno != EINTR) return 0;  // already reaped: nothing left to wait for
        if (until.timeIntervalSinceNow <= 0) return -1;
        usleep(10000);
    }
}

// Stops a tool Spawn started, with everything it started, and waits for it: its wait status.
static int StopGroup(pid_t pid) {
    int status = 0;
    killpg(pid, SIGKILL);
    while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {}
    return status;
}

// A tool's exit code as a shell gives it: 128 plus the signal for one that was stopped.
static int ExitCode(int status) {
    return WIFEXITED(status) ? WEXITSTATUS(status) : 128 + (WIFSIGNALED(status) ? WTERMSIG(status) : 0);
}

// Runs a command-line tool and waits for it, for `seconds` at most: {status, out, timedOut, clipped}, or nil if it
// couldn't start. Its output is kept up to `cap` bytes, the last of them (where a failing tool says why), starting on
// a whole character; with `errors` its error output joins it, else that goes nowhere. It runs in a session of its own
// (Spawn), so a login shell can't take over the terminal this app was started from, and one that runs too long is
// stopped along with everything it started. `environment` replaces this app's when given. Blocking; call off the main
// thread.
NSDictionary *RunBriefly(NSString *path, NSArray<NSString *> *arguments, NSDictionary<NSString *, NSString *> *environment,
                         NSTimeInterval seconds, NSUInteger cap, BOOL errors) {
    int output[2];
    if (pipe(output) != 0) return nil;
    posix_spawn_file_actions_t files;
    posix_spawn_file_actions_init(&files);
    posix_spawn_file_actions_addopen(&files, 0, "/dev/null", O_RDONLY, 0);
    posix_spawn_file_actions_adddup2(&files, output[1], 1);
    if (errors) posix_spawn_file_actions_adddup2(&files, output[1], 2);
    else posix_spawn_file_actions_addopen(&files, 2, "/dev/null", O_WRONLY, 0);
    pid_t pid = 0;
    int started = Spawn(&pid, path, arguments, environment, &files);
    posix_spawn_file_actions_destroy(&files);
    close(output[1]);
    if (started != 0) {
        close(output[0]);
        return nil;
    }
    NSMutableData *out = [NSMutableData data];
    BOOL timedOut = NO, clipped = NO;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
    char buffer[16384];
    for (;;) {
        struct pollfd ready = {output[0], POLLIN, 0};
        int waited = poll(&ready, 1, (int)MAX(0, deadline.timeIntervalSinceNow * 1000));
        if (waited < 0 && errno == EINTR) continue;
        if (waited == 0) timedOut = YES;
        if (waited <= 0) break;
        ssize_t got = read(output[0], buffer, sizeof buffer);
        if (got < 0 && errno == EINTR) continue;
        if (got <= 0) break;  // its output closed: it has ended, or is about to
        [out appendBytes:buffer length:(NSUInteger)got];
        if (out.length > cap) {
            [out replaceBytesInRange:NSMakeRange(0, out.length - cap) withBytes:NULL length:0];
            clipped = YES;
        }
    }
    close(output[0]);
    // Cut part-way through a character, what's kept wouldn't read as text at all: it starts at the next whole one.
    if (clipped) {
        const uint8_t *bytes = out.bytes;
        NSUInteger skip = 0;
        while (skip < out.length && skip < 3 && (bytes[skip] & 0xC0) == 0x80) skip++;
        [out replaceBytesInRange:NSMakeRange(0, skip) withBytes:NULL length:0];
    }
    // Its output can close before it ends (or something it started can hold the output open), so the wait for it
    // to end keeps to the same time.
    int status = timedOut ? -1 : WaitUntil(pid, deadline);
    if (status == -1) {
        timedOut = YES;
        status = StopGroup(pid);
    }
    return @{@"status": @(ExitCode(status)), @"out": out, @"timedOut": @(timedOut), @"clipped": @(clipped)};
}

// Runs a command-line tool that answers requests on its input, one line each, and stops it once it has answered:
// {status, answered, timedOut}, or nil if it couldn't start. `send` goes to its input; each line of its output goes to
// `line` until that says it's the answer (YES), for `seconds` at most. Then its input closes, which is how it's told
// to finish, and it gets 3 seconds to end on its own (tidying up after itself, as Claude Code removes its session
// file), then SIGTERM, then a second later SIGKILL, each to everything it started. It runs in a session of its own
// (Spawn), in `folder`. Blocking; call off the main thread.
NSDictionary *RunConversation(NSString *path, NSArray<NSString *> *arguments,
                              NSDictionary<NSString *, NSString *> *environment, NSString *folder, NSData *send,
                              BOOL (^line)(NSData *line), NSTimeInterval seconds) {
    int input[2], output[2];
    if (pipe(input) != 0) return nil;
    if (pipe(output) != 0) {
        close(input[0]);
        close(input[1]);
        return nil;
    }
    // Every end is closed on exec, so nothing else this app starts meanwhile (a deploy) holds them open; the tool gets
    // its own copies. And a tool that has already ended makes writing to it fail rather than end this app (SIGPIPE).
    for (int fd = 0; fd < 2; fd++) {
        fcntl(input[fd], F_SETFD, FD_CLOEXEC);
        fcntl(output[fd], F_SETFD, FD_CLOEXEC);
    }
    fcntl(input[1], F_SETNOSIGPIPE, 1);
    posix_spawn_file_actions_t files;
    posix_spawn_file_actions_init(&files);
    posix_spawn_file_actions_adddup2(&files, input[0], 0);
    posix_spawn_file_actions_adddup2(&files, output[1], 1);
    posix_spawn_file_actions_addopen(&files, 2, "/dev/null", O_WRONLY, 0);
    // The _np form is the one every SDK has: macOS 26's names its replacement (and calls this one deprecated), which
    // older SDKs, CI's among them, don't have.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if (folder) posix_spawn_file_actions_addchdir_np(&files, folder.fileSystemRepresentation);
#pragma clang diagnostic pop
    pid_t pid = 0;
    int started = Spawn(&pid, path, arguments, environment, &files);
    posix_spawn_file_actions_destroy(&files);
    close(input[0]);
    close(output[1]);
    if (started != 0) {
        close(input[1]);
        close(output[0]);
        return nil;
    }
    const uint8_t *bytes = send.bytes;
    for (NSUInteger sent = 0; sent < send.length;) {
        ssize_t wrote = write(input[1], bytes + sent, send.length - sent);
        if (wrote < 0 && errno == EINTR) continue;
        if (wrote <= 0) break;  // it has ended: what it said, if anything, is read below
        sent += (NSUInteger)wrote;
    }
    NSMutableData *pending = [NSMutableData data];
    BOOL answered = NO, timedOut = NO, ended = NO;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
    char buffer[16384];
    while (!answered) {
        struct pollfd ready = {output[0], POLLIN, 0};
        int waited = poll(&ready, 1, (int)MAX(0, deadline.timeIntervalSinceNow * 1000));
        if (waited < 0 && errno == EINTR) continue;
        if (waited == 0) timedOut = YES;
        if (waited <= 0) break;
        ssize_t got = read(output[0], buffer, sizeof buffer);
        if (got < 0 && errno == EINTR) continue;
        if (got <= 0) {
            ended = YES;
            break;
        }
        [pending appendBytes:buffer length:(NSUInteger)got];
        for (;;) {
            const void *newline = memchr(pending.bytes, '\n', pending.length);
            if (!newline) break;
            NSUInteger length = (NSUInteger)((const char *)newline - (const char *)pending.bytes);
            NSData *each = [pending subdataWithRange:NSMakeRange(0, length)];
            [pending replaceBytesInRange:NSMakeRange(0, length + 1) withBytes:NULL length:0];
            if (each.length && line(each)) {
                answered = YES;
                break;
            }
        }
        if (pending.length > 8 * 1024 * 1024) pending.length = 0;  // no answer is that long; don't keep it growing
    }
    close(input[1]);
    // While it finishes, what it still says is read and dropped, so a full pipe can't keep it from ending.
    NSDate *grace = [NSDate dateWithTimeIntervalSinceNow:3];
    while (!ended && grace.timeIntervalSinceNow > 0) {
        struct pollfd ready = {output[0], POLLIN, 0};
        int waited = poll(&ready, 1, (int)MAX(0, grace.timeIntervalSinceNow * 1000));
        if (waited < 0 && errno == EINTR) continue;
        if (waited <= 0) break;
        ssize_t got = read(output[0], buffer, sizeof buffer);
        if (got < 0 && errno == EINTR) continue;
        if (got <= 0) ended = YES;
    }
    close(output[0]);
    int status = WaitUntil(pid, grace);
    if (status == -1) {
        killpg(pid, SIGTERM);
        status = WaitUntil(pid, [NSDate dateWithTimeIntervalSinceNow:1]);
    }
    if (status == -1) status = StopGroup(pid);
    return @{@"status": @(ExitCode(status)), @"answered": @(answered), @"timedOut": @(timedOut)};
}

// Your shell, as your terminal starts it, when it's one that takes the scripts Whozmove gives it (zsh or bash); else
// zsh. What you set up for your terminal (the PATH, version managers) is set up there.
NSString *LoginShell(void) {
    struct passwd *account = getpwuid(getuid());
    NSString *shell = account && account->pw_shell
        ? [NSFileManager.defaultManager stringWithFileSystemRepresentation:account->pw_shell
                                                                    length:strlen(account->pw_shell)] : nil;
    BOOL takesScript = [@[@"zsh", @"bash"] containsObject:shell.lastPathComponent ?: @""];
    return takesScript && [NSFileManager.defaultManager isExecutableFileAtPath:shell] ? shell : @"/bin/zsh";
}

// The PATH your terminal has, as your login shell sets it up: the app starts from launchd with only the system's own
// folders, where a tool installed with Homebrew or a version manager isn't found. Kept once the shell has said; a shell
// that didn't (too slow, as just after logging in) is asked again five minutes later, and meanwhile the app's own PATH
// with Homebrew's folders added stands in. Blocking; call off the main thread.
NSString *LoginPath(void) {
    static NSString *found;
    static NSTimeInterval failedAt;
    static NSLock *lock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lock = [NSLock new]; });
    [lock lock];
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    if (!found && now - failedAt >= 300) {
        NSDictionary *run = RunBriefly(LoginShell(), @[@"-l", @"-i", @"-c", @"printf '\\n__whozmove_path__%s\\n' \"$PATH\""],
                                       nil, 5, 64 * 1024, NO);
        // Looked for in the bytes, so something a startup file prints that isn't UTF-8 can't hide it.
        NSData *out = run[@"out"], *mark = [@"\n__whozmove_path__" dataUsingEncoding:NSUTF8StringEncoding];
        NSRange at = out.length ? [out rangeOfData:mark options:NSDataSearchBackwards range:NSMakeRange(0, out.length)]
                                : NSMakeRange(NSNotFound, 0);
        if (at.location != NSNotFound) {
            NSData *rest = [out subdataWithRange:NSMakeRange(NSMaxRange(at), out.length - NSMaxRange(at))];
            NSString *line = [[[NSString alloc] initWithData:rest encoding:NSUTF8StringEncoding]
                              componentsSeparatedByString:@"\n"].firstObject;
            if (line.length) found = line;
        }
        if (!found) failedAt = now;
    }
    NSString *path = found;
    [lock unlock];
    if (path) return path;
    NSString *own = NSProcessInfo.processInfo.environment[@"PATH"] ?: @"/usr/bin:/bin:/usr/sbin:/sbin";
    return [own stringByAppendingString:@":/opt/homebrew/bin:/usr/local/bin"];
}

// The git in the folder xcode-select names (Apple's command line developer tools, or Xcode), or nil without one there.
// xcode-select isn't one of the stand-ins in /usr/bin that run a developer tool, so asking it never sets off macOS's
// offer to install them. It's run with RunBriefly, whose wait for it takes a few milliseconds where RunTool's can take
// 70, as every call waits for the first answer.
static NSString *DeveloperGit(void) {
    NSDictionary *run = RunBriefly(@"/usr/bin/xcode-select", @[@"-p"], nil, 5, 4096, NO);
    if (!run || [run[@"status"] intValue] != 0) return nil;
    NSString *folder = [[[NSString alloc] initWithData:run[@"out"] encoding:NSUTF8StringEncoding]
                        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!folder.isAbsolutePath) return nil;
    NSString *git = [folder stringByAppendingPathComponent:@"usr/bin/git"];
    return [NSFileManager.defaultManager isExecutableFileAtPath:git] ? git : nil;
}

// The git in Apple's command line developer tools, or Xcode, once they're installed, else nil. Until they are,
// /usr/bin/git (and the other stand-ins there) offers to install them each time it's run, so Whozmove runs no git of
// its own before this names one: git itself runs from here (RunGit), never through the stand-in, and gh, which runs
// git, a new worktree's git and the claude asked about your plan's usage, which may run it, wait for it too
// (DeveloperToolsReady). The git found is checked on every call, which starts nothing, so tools taken away while
// Whozmove runs are noticed at once. Until they're there, it asks xcode-select again at most every 5 minutes, timed by
// the Mac's uptime, which is never set back, one ask at a time, on a queue of its own. Every call waits for the first
// answer, wherever it's made; after that, a call off the main thread waits for an ask under way, and one on it never
// waits.
NSString *DeveloperToolsGit(void) {
    static NSString *git;            // the git found, while it's there
    static NSTimeInterval askedAt;   // when xcode-select was last asked, by the Mac's uptime (0: never, or ask now)
    static BOOL asking, answered;
    static NSObject *guard;
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        guard = [NSObject new];
        queue = dispatch_queue_create("whozmove.developer-tools", DISPATCH_QUEUE_SERIAL);
    });
    @synchronized (guard) {
        if (git && access(git.fileSystemRepresentation, X_OK) != 0) {
            git = nil;
            askedAt = 0;
        }
        NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
        if (!git && !asking && (!askedAt || now - askedAt >= 5 * 60)) {
            askedAt = now;
            asking = YES;
            // Set going while the guard is held, so a call that waits for the answer is queued behind it.
            dispatch_async(queue, ^{
                NSString *found = DeveloperGit();
                @synchronized (guard) {
                    git = found;
                    asking = NO;
                    answered = YES;
                }
            });
        }
        if (!asking || (answered && NSThread.isMainThread)) return git;
    }
    dispatch_sync(queue, ^{});
    @synchronized (guard) {
        return git;
    }
}

// Whether Apple's command line developer tools, or Xcode, are installed (DeveloperToolsGit).
BOOL DeveloperToolsReady(void) {
    return DeveloperToolsGit() != nil;
}

// Runs a command from a checkout: in your shell (LoginShell) with your terminal's PATH (LoginPath), but without your
// shell's startup files, which a command the panel runs shouldn't wait on; and as yours, not
// an agent's, so the marks agents put on their commands (`marks`, the core's agentMarks) are taken off. With `errors`,
// its error output joins what it prints. Blocking. Nil, and nothing runs, until the marks are known: what an agent left
// on the panel's environment must never reach the command.
NSDictionary *RunInCheckout(NSString *command, NSString *folder, NSTimeInterval seconds, BOOL errors,
                            NSArray<NSString *> *marks) {
    if (!marks) return nil;
    NSString *shell = LoginShell();
    NSArray *noStartupFiles = [shell.lastPathComponent isEqual:@"bash"] ? @[@"--noprofile", @"--norc"] : @[@"-f"];
    NSString *unset = marks.count ? [NSString stringWithFormat:@"unset %@; ", [marks componentsJoinedByString:@" "]]
                                  : @"";
    NSString *script = [unset stringByAppendingString:@"cd -- \"$1\" && eval \"$2\""];
    NSMutableDictionary *environment = [NSProcessInfo.processInfo.environment mutableCopy];
    [environment removeObjectsForKeys:marks ?: @[]];
    environment[@"PATH"] = LoginPath();
    NSMutableArray *arguments = [noStartupFiles mutableCopy];
    [arguments addObjectsFromArray:@[@"-c", script, shell.lastPathComponent, folder, command]];
    return RunBriefly(shell, arguments, environment, seconds, 64 * 1024, errors);
}

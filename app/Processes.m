// Processes: running processes, the app each belongs to, the flags it started with, and running tools.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Processes.h"
#include <sys/sysctl.h>
#include <signal.h>
#include <errno.h>
#import "Log.h"

BOOL ProcessAlive(pid_t pid) {
    return pid > 0 && (kill(pid, 0) == 0 || errno == EPERM);
}

// A session's process, told apart from a later one given the same pid: pid and start time.
NSString *ProcessKey(pid_t pid, NSString *procStart) {
    return [NSString stringWithFormat:@"%d %@", pid, procStart ?: @""];
}

// sysctl, not proc_pidinfo: the latter is refused for root-owned ancestors such as `login`,
// which sits between every terminal app and its shell.
static pid_t ParentOf(pid_t pid) {
    struct kinfo_proc info;
    size_t size = sizeof(info);
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, pid};
    if (sysctl(mib, 4, &info, &size, NULL, 0) != 0 || size == 0) return 0;
    return info.kp_eproc.e_ppid;
}

// The app a terminal session runs in: the first ordinary app up its process tree.
NSRunningApplication *OwningApp(pid_t pid) {
    for (; pid > 1; pid = ParentOf(pid)) {
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
    NSPipe *out = [NSPipe pipe], *err = [NSPipe pipe];
    task.standardOutput = out;
    task.standardError = err;
    if (![task launchAndReturnError:nil]) return nil;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        if (task.isRunning) [task terminate];
    });
    __block NSData *errData = nil;
    dispatch_group_t group = dispatch_group_create();  // stderr is read alongside stdout, so neither pipe fills up
    dispatch_group_async(group, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        errData = [err.fileHandleForReading readDataToEndOfFile];
    });
    NSData *outData = [out.fileHandleForReading readDataToEndOfFile];
    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    [task waitUntilExit];
    return @{@"status": @(task.terminationStatus), @"out": outData ?: NSData.data,
             @"err": [[NSString alloc] initWithData:errData ?: NSData.data encoding:NSUTF8StringEncoding] ?: @""};
}

NSString *RunAppleScript(NSString *source) {
    NSDictionary *error = nil;
    NSAppleEventDescriptor *result = [[[NSAppleScript alloc] initWithSource:source] executeAndReturnError:&error];
    if (!result) PanelLog(@"AppleScript failed: %@", error);
    return result.stringValue;
}

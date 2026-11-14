// The programs a running app starts, for tools/energy.sh: for a number of seconds, each process it starts in that
// time, by name, and for git and gh the folder each ran in. It only reads, and never keeps or prints any other
// argument, since a command can carry a token; it reads a program's arguments only up to their count, never the
// environment after them, and skips a program whose arguments it couldn't read whole.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
//   programs PID SECONDS   one line a program: its name, a tab, and for git and gh the folder it ran in (else nothing)
#include <libproc.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/proc_info.h>
#include <sys/sysctl.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

// How often it looks for new programs, in microseconds: most git runs last tens of milliseconds, so a few are missed.
static const useconds_t kLookEvery = 20000;

// The programs already told, each by its pid and when it started, so a pid macOS gives again is a new program.
typedef struct { pid_t pid; long long started; } Program;
static Program told[65536];
static int toldCount;

// When a process started, in microseconds since 1970, or -1 when it can't be read (it has ended).
static long long StartedAt(pid_t pid) {
    struct proc_bsdinfo info;
    if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, sizeof info) != sizeof info) return -1;
    return (long long)info.pbi_start_tvsec * 1000000 + (long long)info.pbi_start_tvusec;
}

static int Told(pid_t pid, long long started) {
    for (int i = toldCount - 1; i >= 0; i--)
        if (told[i].pid == pid && told[i].started == started) return 1;
    return 0;
}

// Tells a program started since `since`: its name, and its folder for git and gh, the `-C` it was given or else the
// folder it runs in (Whozmove starts gh in the checkout's folder), none when that's the app's own. NO while it can't be
// told yet: it hasn't started its own program (a copy of the app between fork and exec), or its arguments can't be
// read; it's looked at again then, until it has ended.
static int Tell(pid_t pid, const char *appFolder, char *buffer, size_t size) {
    struct proc_bsdinfo info;
    if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, sizeof info) != sizeof info || !(info.pbi_flags & PROC_FLAG_EXEC))
        return 0;
    int mib[3] = {CTL_KERN, KERN_PROCARGS2, pid};
    size_t length = size;
    if (sysctl(mib, 3, buffer, &length, NULL, 0) != 0) return 0;
    // A read that fills the buffer may have been cut, and what's at its start then isn't the arguments: skip it.
    if (length >= size || length < sizeof(int)) return 1;
    buffer[length] = 0;
    int count;
    memcpy(&count, buffer, sizeof count);
    char *end = buffer + length, *at = buffer + sizeof count;
    at += strnlen(at, (size_t)(end - at));  // the program's path as it was started
    while (at < end && !*at) at++;
    char *arguments[64];
    int kept = 0;
    for (int i = 0; i < count && kept < 64 && at < end; i++) {
        arguments[kept++] = at;
        at += strnlen(at, (size_t)(end - at)) + 1;
    }
    if (!kept || !*arguments[0]) return 1;  // nothing to name it by: counted as told, never printed
    char *name = strrchr(arguments[0], '/') ? strrchr(arguments[0], '/') + 1 : arguments[0];
    const char *folder = "";
    struct proc_vnodepathinfo where;
    if (!strcmp(name, "git") || !strcmp(name, "gh")) {
        for (int i = 1; i + 1 < kept && !*folder; i++)
            if (!strcmp(arguments[i], "-C")) folder = arguments[i + 1];
        if (!*folder && proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &where, sizeof where) == sizeof where
            && strcmp(where.pvi_cdir.vip_path, appFolder))
            folder = where.pvi_cdir.vip_path;
    }
    printf("%s\t%s\n", name, folder);
    fflush(stdout);
    return 1;
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: programs PID SECONDS\n");
        return 2;
    }
    pid_t app = (pid_t)atoi(argv[1]);
    // The app's own folder: a program started there wasn't given a checkout's.
    struct proc_vnodepathinfo where;
    const char *appFolder = proc_pidinfo(app, PROC_PIDVNODEPATHINFO, 0, &where, sizeof where) == sizeof where
        ? where.pvi_cdir.vip_path : "";
    // Room for the longest arguments and environment macOS allows a program.
    int mib[2] = {CTL_KERN, KERN_ARGMAX}, argmax = 0;
    size_t argmaxSize = sizeof argmax;
    if (sysctl(mib, 2, &argmax, &argmaxSize, NULL, 0) != 0 || argmax <= 0) argmax = 1 << 20;
    size_t size = (size_t)argmax + 1;
    char *buffer = malloc(size);
    if (!buffer) return 1;
    struct timeval now;
    gettimeofday(&now, NULL);
    // Only programs started from now on: one already running was started before the reading.
    long long since = (long long)now.tv_sec * 1000000 + now.tv_usec;
    time_t end = time(NULL) + atoi(argv[2]);
    while (time(NULL) < end) {
        pid_t children[1024];
        int count = proc_listchildpids(app, children, sizeof children);
        for (int i = 0; i < count && i < 1024; i++) {
            long long started = StartedAt(children[i]);
            if (started < since || Told(children[i], started)) continue;
            if (!Tell(children[i], appFolder, buffer, size)) continue;
            if (toldCount == (int)(sizeof told / sizeof *told)) toldCount = 0;  // a very long reading starts over
            told[toldCount++] = (Program){children[i], started};
        }
        usleep(kLookEvery);
    }
    free(buffer);
    return 0;
}

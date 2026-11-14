// A snapshot of what a running app has cost since it started, for tools/energy.sh: the app's own CPU time, wakeups,
// disk reads and writes and memory, each other live process macOS counts with it (its web pages, and anything still
// running that it started), and the whole group's totals, which include the programs it started that have ended. It
// only reads.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
//   procs PID   one line for the app (with when it started, in seconds since 1970, and its group's id), one for each
//               other live process in its group, and one for the group: "group refused" when macOS won't say which
//               group the app is in, "group totals-refused" when it won't tell the group's totals
//   procs --started PID…   each pid and when it started, in microseconds since 1970 (-1 when it isn't running)
#include <libproc.h>
#include <mach/mach_time.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// The group is the app's resource coalition, which macOS's power log also counts as one app. Asking which coalition a
// process is in, and what it has used, isn't in the public SDK, so the shapes are written here: the answer's first
// fields, in their order. When a macOS refuses either, the group line says so, and the app's own figures still stand.
#define PROC_PIDCOALITIONINFO 20
struct coalition_ids { uint64_t ids[2]; uint64_t reserved[3]; };
struct coalition_usage {
    uint64_t tasks_started, tasks_exited, time_nonempty, cpu_time, interrupt_wakeups, platform_idle_wakeups, bytesread,
        byteswritten, rest[64];
};
extern int coalition_info_resource_usage(uint64_t coalition, struct coalition_usage *usage, size_t size);

static mach_timebase_info_data_t timebase;

// Mach time as nanoseconds.
static uint64_t Nanoseconds(uint64_t ticks) {
    return ticks * timebase.numer / timebase.denom;
}

// One process's line, `kind` naming it, with `more` at its end; NO when it can't be read (it has ended, or isn't ours
// to read). Its age is how long it has run while the Mac was awake; its start is the clock's, sleep included.
static int PrintProcess(const char *kind, pid_t pid, const char *more) {
    struct rusage_info_v4 usage;
    if (proc_pid_rusage(pid, RUSAGE_INFO_V4, (rusage_info_t *)&usage) != 0) return 0;
    char name[2 * MAXCOMLEN + 1] = "?";
    proc_name(pid, name, sizeof name);
    // A name is one word in the line: "Google Chrome Helper" is written Google-Chrome-Helper.
    for (char *c = name; *c; c++)
        if (*c == ' ' || *c == '\t') *c = '-';
    struct proc_bsdinfo info;
    long long start = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, sizeof info) == sizeof info
        ? (long long)info.pbi_start_tvsec : -1;
    printf("%s %d %s start=%lld age=%llu cpu=%llu wakeups=%llu read=%llu written=%llu memory=%llu%s\n", kind, pid, name,
           start,
           (unsigned long long)((Nanoseconds(mach_absolute_time() - usage.ri_proc_start_abstime)) / 1000000000ULL),
           (unsigned long long)Nanoseconds(usage.ri_user_time + usage.ri_system_time),
           (unsigned long long)(usage.ri_pkg_idle_wkups + usage.ri_interrupt_wkups),
           (unsigned long long)usage.ri_diskio_bytesread, (unsigned long long)usage.ri_diskio_byteswritten,
           (unsigned long long)usage.ri_phys_footprint, more);
    return 1;
}

int main(int argc, char **argv) {
    if (argc >= 2 && !strcmp(argv[1], "--started")) {
        for (int i = 2; i < argc; i++) {
            struct proc_bsdinfo info;
            pid_t pid = (pid_t)atoi(argv[i]);
            long long started = pid > 0 && proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, sizeof info) == sizeof info
                ? (long long)info.pbi_start_tvsec * 1000000 + (long long)info.pbi_start_tvusec : -1;
            printf("%d %lld\n", pid, started);
        }
        return 0;
    }
    if (argc != 2) {
        fprintf(stderr, "usage: procs PID\n");
        return 2;
    }
    pid_t app = (pid_t)atoi(argv[1]);
    mach_timebase_info(&timebase);
    struct coalition_ids mine, theirs;
    int grouped = proc_pidinfo(app, PROC_PIDCOALITIONINFO, 0, &mine, sizeof mine) == sizeof mine;
    char more[64] = "";
    if (grouped) snprintf(more, sizeof more, " coalition=%llu", (unsigned long long)mine.ids[0]);
    if (!PrintProcess("app", app, more)) {
        fprintf(stderr, "procs: can't read process %d\n", app);
        return 1;
    }
    if (!grouped) {
        puts("group refused");
        return 0;
    }
    pid_t all[8192];
    int count = proc_listallpids(all, sizeof all);
    for (int i = 0; i < count; i++)
        if (all[i] != app && proc_pidinfo(all[i], PROC_PIDCOALITIONINFO, 0, &theirs, sizeof theirs) == sizeof theirs
            && theirs.ids[0] == mine.ids[0])
            PrintProcess("proc", all[i], "");
    struct coalition_usage usage = {0};
    if (coalition_info_resource_usage(mine.ids[0], &usage, sizeof usage) != 0) {
        puts("group totals-refused");  // its members are listed above; only its totals aren't told
        return 0;
    }
    printf("group tasks=%llu cpu=%llu wakeups=%llu read=%llu written=%llu\n", (unsigned long long)usage.tasks_started,
           (unsigned long long)Nanoseconds(usage.cpu_time),
           (unsigned long long)(usage.interrupt_wakeups + usage.platform_idle_wakeups),
           (unsigned long long)usage.bytesread, (unsigned long long)usage.byteswritten);
    return 0;
}

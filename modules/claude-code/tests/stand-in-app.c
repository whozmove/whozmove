// The stand-in for the panel's own process, for the Claude Code module's tests (test.sh) and the real Claude Code run
// (real.sh): compiled under the app's name, since the permission hook asks only while a process with that name runs,
// and only over a line to it. Given a socket and a command, it listens there as the panel does, and runs the command
// (stand-in-panel.py) listening as file 3 on a socket of its own beside it (the panel's socket's path and ".stand-in"):
// each line a hook opens is accepted here, a line to the command opened for it, and the bytes passed on both ways. So
// the hook's line is only ever touched by this process, and the hook finds it at the other end: macOS names as the
// other end whichever process last used it, so a line accepted or read by the command would name the command, whenever
// it got there before the hook looked. No line is handed from one process to another, which macOS was seen to close
// before its first word. Without a command it only waits. A compiled program, not a copy of /bin/sleep: macOS kills a
// copied system binary.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

enum { kMostLines = 64, kRuns = 600 };

// What became of each line, with its time, in the log STAND_IN_LOG names (the stand-in panel's folder's), which the
// test shows when a request it waited for never came.
static void Note(const char *format, ...) {
    const char *path = getenv("STAND_IN_LOG");
    int log = path ? open(path, O_WRONLY | O_APPEND | O_CREAT, 0600) : -1;
    if (log < 0) return;
    struct timeval now;
    gettimeofday(&now, NULL);
    char line[256];
    int n = snprintf(line, sizeof line, "%ld.%03d app: ", (long)now.tv_sec, (int)(now.tv_usec / 1000));
    va_list args;
    va_start(args, format);
    vsnprintf(line + n, sizeof line - (size_t)n, format, args);
    va_end(args);
    strlcat(line, "\n", sizeof line);
    write(log, line, strlen(line));
    close(log);
}

// A socket's address, for a path that fits one.
static int AddressOf(const char *path, struct sockaddr_un *a) {
    memset(a, 0, sizeof *a);
    a->sun_family = AF_UNIX;
    return strlcpy(a->sun_path, path, sizeof a->sun_path) < sizeof a->sun_path ? 0 : -1;
}

// A socket listening at the path, or -1.
static int Listen(const char *path) {
    struct sockaddr_un a;
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0 || AddressOf(path, &a) != 0) return -1;
    unlink(path);
    if (bind(fd, (struct sockaddr *)&a, sizeof a) != 0 || listen(fd, 16) != 0) return -1;
    return fd;
}

// What came in on one side, written whole to the other: NULL, or why the line is done.
static const char *PassOn(int from, int to) {
    char buf[65536];
    ssize_t n = read(from, buf, sizeof buf);
    if (n == 0) return "closed";
    if (n < 0) return strerror(errno);
    for (ssize_t done = 0; done < n;) {
        ssize_t w = write(to, buf + done, (size_t)(n - done));
        if (w <= 0) return strerror(errno);
        done += w;
    }
    return NULL;
}

int main(int argc, char **argv) {
    if (argc <= 2) {
        sleep(kRuns);
        return 0;
    }
    signal(SIGPIPE, SIG_IGN);
    char beside[sizeof ((struct sockaddr_un *)0)->sun_path];
    snprintf(beside, sizeof beside, "%s.stand-in", argv[1]);
    struct sockaddr_un command;
    int fd = Listen(argv[1]), way = Listen(beside);
    if (fd < 0 || way < 0 || AddressOf(beside, &command) != 0) return 1;
    if (fork() == 0) {
        close(fd);
        dup2(way, 3);
        execvp(argv[2], argv + 2);
        _exit(1);
    }
    close(way);
    // Each line: the hook's end (outer) and this one's line to the command for it (inner).
    int outer[kMostLines], inner[kMostLines], count = 0;
    time_t until = time(NULL) + kRuns;
    while (time(NULL) < until) {
        struct pollfd p[1 + 2 * kMostLines];
        p[0] = (struct pollfd){ fd, POLLIN, 0 };
        for (int i = 0; i < count; i++) {
            p[1 + 2 * i] = (struct pollfd){ outer[i], POLLIN, 0 };
            p[2 + 2 * i] = (struct pollfd){ inner[i], POLLIN, 0 };
        }
        if (poll(p, (nfds_t)(1 + 2 * count), 1000) <= 0) continue;
        for (int i = count - 1; i >= 0; i--) {
            const char *done = NULL;
            if (p[1 + 2 * i].revents && (done = PassOn(outer[i], inner[i])))
                Note("line %d done, from the hook's end: %s", outer[i], done);
            else if (p[2 + 2 * i].revents && (done = PassOn(inner[i], outer[i])))
                Note("line %d done, from the stand-in panel's end: %s", outer[i], done);
            if (done) {
                close(outer[i]);
                close(inner[i]);
                count--;
                outer[i] = outer[count];
                inner[i] = inner[count];
            }
        }
        if (p[0].revents & POLLIN) {
            int line = accept(fd, NULL, NULL);
            if (line < 0) {
                Note("couldn't accept a line: %s", strerror(errno));
                continue;
            }
            int to = count < kMostLines ? socket(AF_UNIX, SOCK_STREAM, 0) : -1;
            if (to < 0 || connect(to, (struct sockaddr *)&command, sizeof command) != 0) {
                Note("line %d refused: %s", line, count == kMostLines ? "too many open" : strerror(errno));
                if (to >= 0) close(to);
                close(line);
                continue;
            }
            Note("line %d accepted, and one opened to the stand-in panel", line);
            outer[count] = line;
            inner[count] = to;
            count++;
        }
    }
    Note("stopped, after %d seconds", kRuns);
    return 0;
}

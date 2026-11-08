// A stand-in for a program, under whatever name it's copied to (claude, node, other): it runs `/bin/bash -c <script>
// <words…>` as its child and waits for it, so the process a test points at is this one, named as its copy is. A copy
// of a program of macOS's own wouldn't do: macOS won't run one from another folder. Ended (SIGTERM), it ends its child
// too, so nothing it started is left behind.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#include <signal.h>
#include <spawn.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;
static pid_t child;

// Its child runs in a process group of its own, so ending the group ends what the child is waiting on too.
static void end(int signal) {
    if (child > 0) kill(-child, SIGTERM);
    _exit(128 + signal);
}

int main(int argc, char **argv) {
    if (argc < 3) return 2;
    char **words = calloc((size_t)argc + 1, sizeof *words);
    if (!words) return 1;
    words[0] = "bash";
    for (int i = 1; i < argc; i++) words[i] = argv[i];
    signal(SIGTERM, end);
    posix_spawnattr_t attributes;
    posix_spawnattr_init(&attributes);
    posix_spawnattr_setflags(&attributes, POSIX_SPAWN_SETPGROUP);
    posix_spawnattr_setpgroup(&attributes, 0);
    if (posix_spawn(&child, "/bin/bash", NULL, &attributes, words, environ) != 0) return 1;
    int status = 0;
    while (waitpid(child, &status, 0) < 0) {}
    return WIFEXITED(status) ? WEXITSTATUS(status) : 1;
}

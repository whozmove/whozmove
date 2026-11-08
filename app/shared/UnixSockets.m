// UnixSockets: listening, telling who's at the other end, and writing without waiting.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "UnixSockets.h"
#import "Log.h"
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

// Room for an answer to go at once (four answers to a question, or a plan's notes, at their longest), so it's never
// written in parts.
static const int kSendRoom = 512 * 1024;

dispatch_source_t ListenAtSocket(NSString *path, dispatch_queue_t queue, NSString *what, ino_t *inode,
                                 void (^take)(int fd, pid_t pid)) {
    struct sockaddr_un address = {.sun_family = AF_UNIX};
    const char *at = path.fileSystemRepresentation;
    if (strlen(at) >= sizeof address.sun_path) {
        LogProblem([NSString stringWithFormat:@"no %@: the socket's path is too long: %@", what, path]);
        return nil;
    }
    strlcpy(address.sun_path, at, sizeof address.sun_path);
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return nil;
    unlink(at);
    struct stat made;
    if (bind(fd, (struct sockaddr *)&address, sizeof address) != 0 || chmod(at, 0600) != 0 || listen(fd, 16) != 0
        || stat(at, &made) != 0) {
        LogProblem([NSString stringWithFormat:@"no %@: couldn't listen at %@ (%d)", what, path, errno]);
        close(fd);
        return nil;
    }
    if (inode) *inode = made.st_ino;
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, (uintptr_t)fd, 0, queue);
    dispatch_source_set_event_handler(source, ^{
        int client = accept(fd, NULL, NULL);
        if (client < 0) return;
        int one = 1, room = kSendRoom;
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one);
        setsockopt(client, SOL_SOCKET, SO_SNDBUF, &room, sizeof room);
        uid_t uid;
        gid_t gid;
        pid_t pid = 0;
        socklen_t size = sizeof pid;
        if (getpeereid(client, &uid, &gid) != 0 || uid != getuid()
            || getsockopt(client, SOL_LOCAL, LOCAL_PEERPID, &pid, &size) != 0 || pid <= 0) {
            close(client);
            return;
        }
        take(client, pid);
    });
    dispatch_source_set_cancel_handler(source, ^{ close(fd); });
    dispatch_resume(source);
    return source;
}

BOOL SocketStillAt(NSString *path, ino_t inode) {
    struct stat now;
    return stat(path.fileSystemRepresentation, &now) == 0 && S_ISSOCK(now.st_mode) && now.st_ino == inode;
}

BOOL SendWithoutWaiting(int fd, NSData *data) {
    ssize_t sent = send(fd, data.bytes, data.length, MSG_DONTWAIT);
    return sent == (ssize_t)data.length;
}

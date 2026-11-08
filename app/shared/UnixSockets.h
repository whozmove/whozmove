// UnixSockets: a socket in Whozmove's own folder that only you can connect to, for a process on this Mac to ask the
// app something (a session's ask, the permission hook's line), who's at the other end of a connection, and writing to
// one without ever waiting on it.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// Listens at `path`, taking the place of whatever was there, only you able to connect (the socket 0600, in a folder
// that's yours alone), on `queue`: `take` gets each connection, from a process running as you, with its pid as macOS
// names it. The listening socket's inode goes in *inode, to tell later it's still this one. Cancel the source to stop;
// nil, with the problem logged, if it couldn't listen. `what` names it in the log.
dispatch_source_t ListenAtSocket(NSString *path, dispatch_queue_t queue, NSString *what, ino_t *inode,
                                 void (^take)(int fd, pid_t pid));
// Whether the socket at `path` is still the one listened on (same inode): something may have taken it away.
BOOL SocketStillAt(NSString *path, ino_t inode);
// Writes all of `data` to a connection without waiting: NO if it couldn't all go now (the other end isn't reading, or
// has gone), and then the connection should be dropped.
BOOL SendWithoutWaiting(int fd, NSData *data);

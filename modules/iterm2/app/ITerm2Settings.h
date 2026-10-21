// ITerm2Settings: iTerm2's own Settings window, through the Accessibility API, for the one setting the panel helps you
// change there: its Python API (ITerm2Facts.h).
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

// Whether iTerm2's settings have its Python API on, as iTerm2 last wrote them; only read.
BOOL ITerm2APIOn(void);
// Turns iTerm2's Python API on or off as you would, in the iTerm2 with that pid: its Settings open (if they aren't),
// General, then Magic, and the Enable Python API box ticked or unticked, unless it's so already. Ticking it has iTerm2
// ask you first, holding the tick until you've answered, so this runs off the main thread, and doesn't wait for your
// answer. Returns nil once the box is pressed, or is so already (*already), else what it didn't find, which leaves
// iTerm2's Settings as far as it got, for you to take on.
NSString *ITerm2SetAPI(pid_t pid, BOOL on, BOOL *already);

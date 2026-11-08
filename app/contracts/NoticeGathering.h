// What only the gathering of notices sets on them: the module that sent each (Modules), and what putting one away does
// (the notifications module, which keeps it away). A sender never imports this.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Notice.h"

@interface Notice ()
@property (readwrite, copy) NSString *from;
@property (copy) void (^whenPutAway)(Notice *notice);
@end

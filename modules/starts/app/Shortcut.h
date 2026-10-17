// Shortcut: ⌃⌥N from any app, which brings up the panel's box for a new conversation.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
//
// A hot key is one macOS hands straight to the app that asked for it: that needs no permission, and the app sees no
// other key.
#import <Foundation/Foundation.h>

@interface Shortcut : NSObject
// `pressed` runs on the main thread each time the keys are pressed, while the shortcut is on.
- (instancetype)initWithAction:(void (^)(void))pressed;
@property (nonatomic) BOOL on;
@end

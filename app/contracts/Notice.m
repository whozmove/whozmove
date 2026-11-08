// Notice: what a module has to tell the user now.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "NoticeGathering.h"

@implementation Notice

+ (instancetype)noticeWithKey:(NSString *)key level:(NoticeLevel)level text:(NSString *)text {
    Notice *notice = [self new];
    notice->_key = [key copy];
    notice->_level = level;
    notice->_text = [text copy];
    return notice;
}

- (void)pressButton {
    if (self.press && !self.busy) self.press();
}

- (void)putAway {
    if (self.whenPutAway) self.whenPutAway(self);
}

- (NSString *)description {
    return [NSString stringWithFormat:@"%@/%@ (%@): %@", self.from ?: @"?", self.key,
            @[@"good to know", @"soon", @"urgent"][self.level], self.text];
}

@end

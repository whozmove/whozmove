// ITerm2API: iTerm2's Python API, reached without Python: a WebSocket on its Unix socket, held open once made, so text
// goes in the moment it's sent, never after a connection is made, by when a session could have moved on to a prompt.
// The connection is made off the main thread, but for the cookie, which is asked of iTerm2's scripting; text is sent
// on the main thread, as typing through its scripting is, and its answer waited for.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "ITerm2API.h"
#import "ITerm2Facts.h"
#import "Text.h"
#import "Log.h"
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

NSString *const ITerm2APIClientName = @"Whozmove";
// How long a write or a read waits, as a script to iTerm2 does; how long after a try at connecting the next may be
// made, doubled after each try that reached iTerm2 and still failed (up to 64 times), as each asks iTerm2 for a cookie,
// which its Script Console lists; and the most a frame from iTerm2 may hold, far more than any answer to a send.
static const NSTimeInterval kWait = 2, kTryAgainAfter = 5;
static const uint64_t kMostFrame = 16 << 20;
// WebSocket frames' opcodes (RFC 6455).
enum { kOpBinary = 0x2, kOpClose = 0x8, kOpPing = 0x9, kOpPong = 0xA };

#pragma mark The messages

// A protobuf varint.
static void PutVarint(NSMutableData *out, uint64_t value) {
    do {
        uint8_t byte = value & 0x7f;
        value >>= 7;
        if (value) byte |= 0x80;
        [out appendBytes:&byte length:1];
    } while (value);
}

// A field's tag: its number, and its wire type (0 a varint, 2 bytes with their length before them).
static void PutTag(NSMutableData *out, uint32_t field, uint8_t wire) {
    PutVarint(out, ((uint64_t)field << 3) | wire);
}

static void PutBytes(NSMutableData *out, uint32_t field, NSData *bytes) {
    PutTag(out, field, 2);
    PutVarint(out, bytes.length);
    [out appendData:bytes];
}

NSData *ITerm2APISendTextMessage(int64_t messageId, NSString *sessionId, NSString *text) {
    NSMutableData *request = [NSMutableData data];
    PutBytes(request, kITerm2APITextSession, [sessionId dataUsingEncoding:NSUTF8StringEncoding]);
    PutBytes(request, kITerm2APITextText, [text dataUsingEncoding:NSUTF8StringEncoding]);
    PutTag(request, kITerm2APITextNoBroadcast, 0);
    PutVarint(request, 1);
    NSMutableData *message = [NSMutableData data];
    PutTag(message, kITerm2APIMessageId, 0);
    PutVarint(message, (uint64_t)messageId);
    PutBytes(message, kITerm2APISendText, request);
    return message;
}

// Reads the varint at *at, and moves past it: NO if the bytes end first, or it's longer than a varint can be.
static BOOL GetVarint(const uint8_t *bytes, NSUInteger length, NSUInteger *at, uint64_t *value) {
    *value = 0;
    for (int shift = 0; shift < 64 && *at < length; shift += 7) {
        uint8_t byte = bytes[(*at)++];
        *value |= (uint64_t)(byte & 0x7f) << shift;
        if (!(byte & 0x80)) return YES;
    }
    return NO;
}

// Each field of a message, given to `field` with its number, its wire type, and its value: a varint's number, or where
// its bytes are. Fields of other wire types are passed over. NO if the message can't be read to its end.
static BOOL EachField(NSData *message, void (^field)(uint64_t number, uint8_t wire, uint64_t value, NSRange bytes)) {
    const uint8_t *bytes = message.bytes;
    NSUInteger length = message.length, at = 0;
    while (at < length) {
        uint64_t tag, value = 0;
        if (!GetVarint(bytes, length, &at, &tag)) return NO;
        uint8_t wire = tag & 7;
        NSRange range = NSMakeRange(at, 0);
        switch (wire) {
            case 0:
                if (!GetVarint(bytes, length, &at, &value)) return NO;
                break;
            case 1:
                if (length - at < 8) return NO;
                at += 8;
                break;
            case 5:
                if (length - at < 4) return NO;
                at += 4;
                break;
            case 2:
                if (!GetVarint(bytes, length, &at, &value) || value > length - at) return NO;
                range = NSMakeRange(at, (NSUInteger)value);
                at += (NSUInteger)value;
                break;
            default:
                return NO;
        }
        field(tag >> 3, wire, value, range);
    }
    return YES;
}

// An answer to the request is its error, if it has one, else its response's status. Anything else (a notification,
// another request's answer, a message that can't be read) isn't its answer.
NSInteger ITerm2APIAnswerIn(NSData *message, int64_t messageId) {
    __block BOOL ours = NO, error = NO, answered = NO;
    __block uint64_t status = kITerm2APITextTaken;
    BOOL read = EachField(message, ^(uint64_t number, uint8_t wire, uint64_t value, NSRange bytes) {
        if (number == kITerm2APIMessageId && wire == 0) {
            ours = value == (uint64_t)messageId;
        } else if (number == kITerm2APIError && wire == 2) {
            error = YES;
        } else if (number == kITerm2APISendText && wire == 2) {
            answered = YES;
            BOOL whole = EachField([message subdataWithRange:bytes], ^(uint64_t inner, uint8_t innerWire,
                                                                       uint64_t innerValue, NSRange unused) {
                if (inner == kITerm2APITextStatus && innerWire == 0) status = innerValue;
            });
            if (!whole) status = UINT64_MAX;
        }
    });
    if (!read || !ours || (!error && !answered)) return -1;
    if (error) return ITerm2APIFailed;
    return status == kITerm2APITextTaken ? ITerm2APITaken
         : status == kITerm2APITextSessionGone ? ITerm2APISessionGone : ITerm2APIFailed;
}

#pragma mark The connection

NSString *ITerm2APIHandshake(NSString *cookie, NSString *key, NSString *secKey) {
    return [NSString stringWithFormat:@"GET / HTTP/1.1\r\n"
                                      @"Host: localhost\r\n"
                                      @"Upgrade: websocket\r\n"
                                      @"Connection: Upgrade\r\n"
                                      @"Sec-WebSocket-Version: 13\r\n"
                                      @"Sec-WebSocket-Key: %@\r\n"
                                      @"Sec-WebSocket-Protocol: %@\r\n"
                                      @"Origin: ws://localhost/\r\n"
                                      @"x-iterm2-library-version: %@\r\n"
                                      @"x-iterm2-advisory-name: %@\r\n"
                                      @"x-iterm2-disable-auth-ui: true\r\n"
                                      @"x-iterm2-cookie: %@\r\n"
                                      @"x-iterm2-key: %@\r\n"
                                      @"\r\n", secKey, kITerm2APIProtocol, kITerm2APILibrary, ITerm2APIClientName,
                                      cookie, key];
}

// A frame as a client sends it: whole, and masked, as the protocol asks of every client's frame.
static NSData *Frame(uint8_t opcode, NSData *payload, uint32_t mask) {
    NSMutableData *frame = [NSMutableData data];
    uint8_t first = 0x80 | opcode;
    [frame appendBytes:&first length:1];
    NSUInteger length = payload.length;
    if (length < 126) {
        uint8_t size = 0x80 | (uint8_t)length;
        [frame appendBytes:&size length:1];
    } else if (length < 65536) {
        uint8_t size[3] = {0x80 | 126, (uint8_t)(length >> 8), (uint8_t)length};
        [frame appendBytes:size length:3];
    } else {
        uint8_t size[9] = {0x80 | 127};
        for (int i = 0; i < 8; i++) size[8 - i] = (uint8_t)((uint64_t)length >> (8 * i));
        [frame appendBytes:size length:9];
    }
    uint8_t key[4] = {(uint8_t)(mask >> 24), (uint8_t)(mask >> 16), (uint8_t)(mask >> 8), (uint8_t)mask};
    [frame appendBytes:key length:4];
    const uint8_t *bytes = payload.bytes;
    for (NSUInteger i = 0; i < length; i++) {
        uint8_t masked = bytes[i] ^ key[i % 4];
        [frame appendBytes:&masked length:1];
    }
    return frame;
}

NSData *ITerm2APIFrame(NSData *payload, uint32_t mask) {
    return Frame(kOpBinary, payload, mask);
}

static BOOL WriteAll(int fd, NSData *data) {
    const uint8_t *bytes = data.bytes;
    NSUInteger left = data.length;
    while (left) {
        ssize_t wrote = write(fd, bytes, left);
        if (wrote < 0 && errno == EINTR) continue;
        if (wrote <= 0) return NO;
        bytes += wrote;
        left -= (NSUInteger)wrote;
    }
    return YES;
}

// Reads exactly `length` bytes: NO once the connection has closed, or nothing came for as long as a read waits.
static BOOL ReadAll(int fd, uint8_t *into, NSUInteger length) {
    while (length) {
        ssize_t got = read(fd, into, length);
        if (got < 0 && errno == EINTR) continue;
        if (got <= 0) return NO;
        into += got;
        length -= (NSUInteger)got;
    }
    return YES;
}

// The next frame iTerm2 sends, its payload unmasked, and its opcode in *opcode; nil once the connection fails, or for
// a frame bigger than any of its answers.
static NSData *ReadFrame(int fd, uint8_t *opcode) {
    uint8_t head[2];
    if (!ReadAll(fd, head, 2)) return nil;
    *opcode = head[0] & 0x0f;
    uint64_t length = head[1] & 0x7f;
    if (length == 126) {
        uint8_t size[2];
        if (!ReadAll(fd, size, 2)) return nil;
        length = (uint64_t)size[0] << 8 | size[1];
    } else if (length == 127) {
        uint8_t size[8];
        if (!ReadAll(fd, size, 8)) return nil;
        length = 0;
        for (int i = 0; i < 8; i++) length = length << 8 | size[i];
    }
    uint8_t key[4] = {0};
    BOOL masked = (head[1] & 0x80) != 0;
    if ((masked && !ReadAll(fd, key, 4)) || length > kMostFrame) return nil;
    NSMutableData *payload = [NSMutableData dataWithLength:(NSUInteger)length];
    uint8_t *bytes = payload.mutableBytes;
    if (length && !ReadAll(fd, bytes, (NSUInteger)length)) return nil;
    if (masked)
        for (NSUInteger i = 0; i < length; i++) bytes[i] ^= key[i % 4];
    return payload;
}

// A connection to iTerm2's socket, or -1 while nothing listens there (the API is off, or iTerm2 isn't running). Its
// reads and writes wait kWait at most, and a write to it once it has closed fails rather than ending the app.
static int ConnectSocket(void) {
    NSString *support = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES)
                            .firstObject;
    const char *path = [support stringByAppendingPathComponent:kITerm2APISocket].fileSystemRepresentation;
    struct sockaddr_un address = {.sun_family = AF_UNIX};
    if (!path || strlen(path) >= sizeof(address.sun_path)) return -1;
    strlcpy(address.sun_path, path, sizeof(address.sun_path));
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    int on = 1;
    struct timeval wait = {.tv_sec = (time_t)kWait};
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, sizeof(on));
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &wait, sizeof(wait));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &wait, sizeof(wait));
    if (connect(fd, (struct sockaddr *)&address, sizeof(address)) != 0) {
        close(fd);
        return -1;
    }
    return fd;
}

// Asks for the connection on a socket iTerm2 has taken: the HTTP status it answers with (101 once it's open, 401 for a
// cookie it didn't take), or 0 when it doesn't answer. Its answer is read a byte at a time, so nothing after it is.
static NSInteger Upgrade(int fd, NSString *cookie, NSString *key) {
    uint8_t random[16];
    arc4random_buf(random, sizeof(random));
    NSString *secKey = [[NSData dataWithBytes:random length:sizeof(random)] base64EncodedStringWithOptions:0];
    if (!WriteAll(fd, [ITerm2APIHandshake(cookie, key, secKey) dataUsingEncoding:NSUTF8StringEncoding])) return 0;
    NSMutableData *answer = [NSMutableData data];
    while (answer.length < 16384) {
        uint8_t byte;
        if (!ReadAll(fd, &byte, 1)) return 0;
        [answer appendBytes:&byte length:1];
        if (answer.length >= 4 && !memcmp((const uint8_t *)answer.bytes + answer.length - 4, "\r\n\r\n", 4)) break;
    }
    NSString *text = [[NSString alloc] initWithData:answer encoding:NSUTF8StringEncoding];
    NSArray<NSString *> *words = [[text componentsSeparatedByString:@"\r\n"].firstObject
                                     componentsSeparatedByString:@" "];
    return words.count >= 2 && [words[0] hasPrefix:@"HTTP/"] ? words[1].integerValue : 0;
}

// Whether a cookie or a key is what iTerm2 hands out (plain, of any length), and so safe in a header.
static BOOL Plain(NSString *word) {
    return IsPlainId(word, NSUIntegerMax);
}

@implementation ITerm2API {
    dispatch_queue_t _queue;  // making a connection
    int _socket;              // the open connection, or -1; on the main thread only
    BOOL _connecting;
    NSDate *_triedAt;
    NSInteger _failures;  // tries in a row that reached iTerm2 and still didn't connect
    int64_t _lastId;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _queue = dispatch_queue_create("whozmove.iterm2-api", DISPATCH_QUEUE_SERIAL);
    _socket = -1;
    return self;
}

// A connection iTerm2 has closed reads as ended at once; one still open has nothing to read, or something it sent of
// its own, which a send reads past.
- (BOOL)open {
    if (_socket < 0) return NO;
    uint8_t byte;
    ssize_t peeked = recv(_socket, &byte, 1, MSG_PEEK | MSG_DONTWAIT);
    if (peeked > 0 || (peeked < 0 && (errno == EAGAIN || errno == EINTR))) return YES;
    [self drop:@"iTerm2 closed it"];
    return NO;
}

- (void)drop:(NSString *)why {
    if (_socket < 0) return;
    close(_socket);
    _socket = -1;
    PanelLog(@"iTerm2's Python API: connection closed, %@", why);
}

- (void)connectWithCookie:(NSString *(^)(void))cookie {
    NSTimeInterval wait = kTryAgainAfter * (1 << MIN(_failures, 6));
    if (_connecting || self.open || (_triedAt && -_triedAt.timeIntervalSinceNow < wait)) return;
    _connecting = YES;
    _triedAt = [NSDate date];
    [self connect:cookie tries:2];
}

// A cookie iTerm2 didn't take (401) is tried once more with a fresh one: each is good for one connection only.
- (void)connect:(NSString *(^)(void))cookie tries:(NSInteger)tries {
    dispatch_async(_queue, ^{
        int fd = ConnectSocket();
        dispatch_async(dispatch_get_main_queue(), ^{
            if (fd < 0) {
                self->_connecting = NO;
                return;
            }
            NSArray<NSString *> *given = [cookie() componentsSeparatedByString:@" "];
            if (given.count != 2 || !Plain(given[0]) || !Plain(given[1])) {
                close(fd);
                self->_connecting = NO;
                self->_failures++;
                PanelLog(@"iTerm2's Python API: no cookie to connect with");
                return;
            }
            dispatch_async(self->_queue, ^{
                NSInteger status = Upgrade(fd, given[0], given[1]);
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (status == 101) {
                        self->_socket = fd;
                        self->_connecting = NO;
                        self->_failures = 0;
                        PanelLog(@"iTerm2's Python API: connected");
                        return;
                    }
                    close(fd);
                    if (status == 401 && tries > 1) {
                        [self connect:cookie tries:tries - 1];
                        return;
                    }
                    self->_connecting = NO;
                    self->_failures++;
                    PanelLog(@"iTerm2's Python API didn't take a connection (%ld)", (long)status);
                });
            });
        });
    });
}

// Whatever iTerm2 sends of its own before the answer is read past, and a ping answered. A connection that fails, or
// whose answer is a refusal, is closed, so the window rule is back until it's made again; one that says the session
// is gone is still good.
- (ITerm2APIAnswer)send:(NSString *)text toSession:(NSString *)sessionId {
    if (!self.open) return ITerm2APIFailed;
    int64_t messageId = ++_lastId;
    if (!WriteAll(_socket, ITerm2APIFrame(ITerm2APISendTextMessage(messageId, sessionId, text), arc4random()))) {
        [self drop:@"it didn't take a request"];
        return ITerm2APIFailed;
    }
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:kWait];
    while (until.timeIntervalSinceNow > 0) {
        uint8_t opcode = 0;
        NSData *payload = ReadFrame(_socket, &opcode);
        if (!payload || opcode == kOpClose) break;
        if (opcode == kOpPing) {
            if (!WriteAll(_socket, Frame(kOpPong, payload, arc4random()))) break;
            continue;
        }
        NSInteger answer = opcode == kOpBinary ? ITerm2APIAnswerIn(payload, messageId) : -1;
        if (answer < 0) continue;
        if (answer == ITerm2APIFailed) [self drop:@"it refused a request"];
        return answer;
    }
    [self drop:@"no answer"];
    return ITerm2APIFailed;
}

@end

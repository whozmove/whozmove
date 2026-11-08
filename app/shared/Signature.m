// Signature: who signed a running program, from the copy of its signature the system keeps while it runs.
// Copyright (C) 2026 Satyaraj · SPDX-License-Identifier: GPL-3.0-or-later
#import "Signature.h"
#import <Security/Security.h>
#import <CommonCrypto/CommonDigest.h>
#include <errno.h>

// The system's own call for a process's code signature. It has no public header, so it's declared here as the system
// defines it (sys/codesign.h in its sources), with the few operations and flags read here.
int csops(pid_t pid, unsigned int ops, void *useraddr, size_t usersize);
enum { kStatus = 0, kCDHash = 5, kBlob = 10, kIdentity = 11, kTeam = 14 };
enum { kValid = 0x1 };

// The signature's pieces, as the system lays them out: one superblob, indexing the code directories and the CMS message
// that signs the first of them.
enum : uint32_t {
    kSuperBlob = 0xfade0cc0, kCodeDirectory = 0xfade0c02, kBlobWrapper = 0xfade0b01,
    kFirstDirectory = 0, kSignatureSlot = 0x10000,
};

// Apple Root CA, the root of every Developer ID certificate, by the SHA-256 of its certificate. Kept here so the chain
// ends at Apple's own root, whatever roots are trusted on this Mac.
static NSString *const kAppleRoot = @"B0B1730ECBC7FF4505142C49F1295E6EDA6BCAED7E2C68C5BE91B5A11001F024";
// Apple's marks: on a Developer ID Application certificate, and on the Developer ID certification authority that issues
// them.
static NSString *const kDeveloperIDApplication = @"1.2.840.113635.100.6.1.13";
static NSString *const kDeveloperIDAuthority = @"1.2.840.113635.100.6.2.6";
static NSString *const kOrganizationalUnit = @"2.5.4.11";

static uint32_t BigEndian(NSData *data, NSUInteger at) {
    if (at > data.length || data.length - at < 4) return 0;
    const uint8_t *b = (const uint8_t *)data.bytes + at;
    return (uint32_t)b[0] << 24 | (uint32_t)b[1] << 16 | (uint32_t)b[2] << 8 | b[3];
}

// A blob the system gives back starts with 8 bytes of its own (a magic number and the length): only what follows.
static NSString *Text(pid_t pid, unsigned int operation) {
    char buffer[1024] = {0};
    if (csops(pid, operation, buffer, sizeof buffer - 1) != 0) return nil;
    NSString *text = @(buffer + 8);
    return text.length ? text : nil;
}

// The whole signature, asked for once with room for its header only, which says how long it is, then whole.
static NSData *WholeSignature(pid_t pid) {
    uint32_t header[2] = {0};
    if (csops(pid, kBlob, header, sizeof header) == 0) return nil;
    if (errno != ERANGE) return nil;
    uint32_t length = ntohl(header[1]);
    if (length < 12 || length > (16u << 20)) return nil;
    NSMutableData *blob = [NSMutableData dataWithLength:length];
    if (csops(pid, kBlob, blob.mutableBytes, blob.length) != 0) return nil;
    return BigEndian(blob, 0) == kSuperBlob && BigEndian(blob, 4) <= blob.length ? blob : nil;
}

// One of the superblob's pieces, by its slot, checked to lie inside it.
static NSData *Piece(NSData *blob, uint32_t slot) {
    uint32_t count = BigEndian(blob, 8);
    for (uint32_t i = 0; i < count && i < 64; i++) {
        if (BigEndian(blob, 12 + i * 8) != slot) continue;
        uint32_t offset = BigEndian(blob, 16 + i * 8), length = BigEndian(blob, offset + 4);
        if (length < 8 || offset > blob.length || blob.length - offset < length) return nil;
        return [blob subdataWithRange:NSMakeRange(offset, length)];
    }
    return nil;
}

// A code directory's hash, as its own hash type says, the way the system takes it: the first 20 bytes are its cdhash.
static NSData *DirectoryHash(NSData *directory) {
    if (BigEndian(directory, 0) != kCodeDirectory || directory.length < 40) return nil;
    uint8_t type = ((const uint8_t *)directory.bytes)[37];
    NSMutableData *hash;
    switch (type) {
        case 1: hash = [NSMutableData dataWithLength:CC_SHA1_DIGEST_LENGTH];
            CC_SHA1(directory.bytes, (CC_LONG)directory.length, hash.mutableBytes); break;
        case 2: case 3: hash = [NSMutableData dataWithLength:CC_SHA256_DIGEST_LENGTH];
            CC_SHA256(directory.bytes, (CC_LONG)directory.length, hash.mutableBytes); break;
        case 4: hash = [NSMutableData dataWithLength:CC_SHA384_DIGEST_LENGTH];
            CC_SHA384(directory.bytes, (CC_LONG)directory.length, hash.mutableBytes); break;
        default: return nil;
    }
    return hash;
}

static NSData *CDHashOf(NSData *directory) {
    NSData *hash = DirectoryHash(directory);
    return hash.length >= 20 ? [hash subdataWithRange:NSMakeRange(0, 20)] : nil;
}

#pragma mark Certificates

// One DER element at `at`: its tag, and where its contents start and end. NO when it doesn't fit.
static BOOL Element(NSData *der, NSUInteger at, uint8_t *tag, NSUInteger *start, NSUInteger *end) {
    const uint8_t *b = der.bytes;
    if (at + 2 > der.length) return NO;
    *tag = b[at];
    NSUInteger length = b[at + 1], next = at + 2;
    if (length & 0x80) {
        NSUInteger bytes = length & 0x7f;
        if (bytes == 0 || bytes > 4 || next + bytes > der.length) return NO;
        length = 0;
        for (NSUInteger i = 0; i < bytes; i++) length = length << 8 | b[next + i];
        next += bytes;
    }
    if (length > der.length - next) return NO;
    *start = next;
    *end = next + length;
    return YES;
}

// What a certificate signs (its "to be signed" part, whole), the algorithm it was signed with, and the signature.
static BOOL CertificateParts(NSData *der, NSData **signedPart, NSData **algorithm, NSData **signature) {
    uint8_t tag;
    NSUInteger start, end, s, e;
    if (!Element(der, 0, &tag, &start, &end) || tag != 0x30) return NO;
    if (!Element(der, start, &tag, &s, &e) || tag != 0x30) return NO;
    *signedPart = [der subdataWithRange:NSMakeRange(start, e - start)];
    NSUInteger at = e;
    if (!Element(der, at, &tag, &s, &e) || tag != 0x30) return NO;
    uint8_t oidTag;
    NSUInteger os, oe;
    if (!Element(der, s, &oidTag, &os, &oe) || oidTag != 0x06) return NO;
    *algorithm = [der subdataWithRange:NSMakeRange(os, oe - os)];
    at = e;
    if (!Element(der, at, &tag, &s, &e) || tag != 0x03 || e - s < 2 || ((const uint8_t *)der.bytes)[s] != 0) return NO;
    *signature = [der subdataWithRange:NSMakeRange(s + 1, e - s - 1)];
    return YES;
}

// The signing algorithms Apple's certificates use, by their DER object identifiers.
static SecKeyAlgorithm AlgorithmFor(NSData *oid) {
    static const struct { uint8_t bytes[9]; NSUInteger length; } rsa[] = {
        {{0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x05}, 9},
        {{0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x0b}, 9},
        {{0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x0c}, 9},
        {{0x2a, 0x86, 0x48, 0xce, 0x3d, 0x04, 0x03, 0x02}, 8},
        {{0x2a, 0x86, 0x48, 0xce, 0x3d, 0x04, 0x03, 0x03}, 8},
    };
    SecKeyAlgorithm algorithms[] = {
        kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA1, kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256,
        kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA384, kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
        kSecKeyAlgorithmECDSASignatureMessageX962SHA384,
    };
    for (size_t i = 0; i < sizeof rsa / sizeof rsa[0]; i++)
        if (oid.length == rsa[i].length && memcmp(oid.bytes, rsa[i].bytes, rsa[i].length) == 0) return algorithms[i];
    return NULL;
}

// Whether `issuer`'s key signed `certificate`.
static BOOL SignedBy(SecCertificateRef certificate, SecCertificateRef issuer) {
    NSData *der = (__bridge_transfer NSData *)SecCertificateCopyData(certificate);
    NSData *signedPart, *oid, *signature;
    if (!CertificateParts(der, &signedPart, &oid, &signature)) return NO;
    SecKeyAlgorithm algorithm = AlgorithmFor(oid);
    SecKeyRef key = SecCertificateCopyKey(issuer);
    if (!algorithm || !key) {
        if (key) CFRelease(key);
        return NO;
    }
    BOOL good = SecKeyVerifySignature(key, algorithm, (__bridge CFDataRef)signedPart, (__bridge CFDataRef)signature,
                                      NULL);
    CFRelease(key);
    return good;
}

static NSString *Fingerprint(SecCertificateRef certificate) {
    NSData *der = (__bridge_transfer NSData *)SecCertificateCopyData(certificate);
    uint8_t hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(der.bytes, (CC_LONG)der.length, hash);
    NSMutableString *hex = [NSMutableString string];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02X", hash[i]];
    return hex;
}

static BOOL SameName(CFDataRef a, CFDataRef b) {
    BOOL same = a && b && CFEqual(a, b);
    if (a) CFRelease(a);
    if (b) CFRelease(b);
    return same;
}

// The certificate among `all` that issued `certificate`, by its name.
static SecCertificateRef IssuerOf(SecCertificateRef certificate, NSArray *all) {
    for (id each in all) {
        SecCertificateRef other = (__bridge SecCertificateRef)each;
        if (CFEqual(other, certificate)) continue;
        if (SameName(SecCertificateCopyNormalizedIssuerSequence(certificate),
                     SecCertificateCopyNormalizedSubjectSequence(other)))
            return other;
    }
    return NULL;
}

// What a certificate says under these object identifiers, read by the system's own parser.
static NSDictionary *ValuesOf(SecCertificateRef certificate, NSArray<NSString *> *keys) {
    return (__bridge_transfer NSDictionary *)SecCertificateCopyValues(certificate, (__bridge CFArrayRef)keys, NULL);
}

static BOOL InDate(SecCertificateRef certificate, NSDate *at) {
    NSDate *from = (__bridge_transfer NSDate *)SecCertificateCopyNotValidBeforeDate(certificate);
    NSDate *until = (__bridge_transfer NSDate *)SecCertificateCopyNotValidAfterDate(certificate);
    return from && until && [at compare:from] != NSOrderedAscending && [at compare:until] != NSOrderedDescending;
}

// The team a Developer ID Application certificate is for: its subject's organizational unit.
static NSString *TeamOf(SecCertificateRef leaf) {
    NSDictionary *subject = ValuesOf(leaf, @[(__bridge NSString *)kSecOIDX509V1SubjectName])
        [(__bridge NSString *)kSecOIDX509V1SubjectName];
    for (NSDictionary *part in subject[(__bridge NSString *)kSecPropertyKeyValue])
        if ([part[(__bridge NSString *)kSecPropertyKeyLabel] isEqual:kOrganizationalUnit])
            return part[(__bridge NSString *)kSecPropertyKeyValue];
    return nil;
}

#pragma mark The check

// Why a signature isn't a Developer ID's for `team` over the code the system runs (`cdhash`), or nil when it is.
static NSString *WhyNotDeveloperID(NSData *blob, NSData *cdhash, NSString *team) {
    NSData *first = Piece(blob, kFirstDirectory), *wrapper = Piece(blob, kSignatureSlot);
    if (!first) return @"it has no code directory";
    if (!wrapper || BigEndian(wrapper, 0) != kBlobWrapper || wrapper.length <= 8) return @"it's signed ad hoc";
    // The CMS message signs the first code directory, so that must be the one the system runs. A program whose first
    // directory has a weak hash runs a stronger alternative instead, which the message covers only through a list of
    // hashes the system's public calls don't give: such a program isn't taken, rather than taken unchecked. Claude
    // Code's has one directory, hashed with SHA-256.
    if (![CDHashOf(first) isEqual:cdhash]) return @"what it signs isn't the code that runs";

    CMSDecoderRef decoder = NULL;
    if (CMSDecoderCreate(&decoder) != errSecSuccess) return @"its signature can't be read";
    NSString *why = nil;
    NSData *message = [wrapper subdataWithRange:NSMakeRange(8, wrapper.length - 8)];
    size_t signers = 0;
    CMSSignerStatus status = kCMSSignerUnsigned;
    SecPolicyRef policy = SecPolicyCreateBasicX509();
    CFArrayRef certificates = NULL;
    CFAbsoluteTime when = 0;
    // The signer's own signature over what it signs, without the system's trust: whose it is, the chain below says.
    if (CMSDecoderUpdateMessage(decoder, message.bytes, message.length) != errSecSuccess
        || CMSDecoderSetDetachedContent(decoder, (__bridge CFDataRef)first) != errSecSuccess
        || CMSDecoderFinalizeMessage(decoder) != errSecSuccess
        || CMSDecoderGetNumSigners(decoder, &signers) != errSecSuccess || signers != 1
        || CMSDecoderCopySignerStatus(decoder, 0, policy, NO, &status, NULL, NULL) != errSecSuccess
        || status != kCMSSignerValid)
        why = @"its signature doesn't hold";
    // When it was signed: Apple's secure timestamp, else the time the signer gives, which its signature covers.
    if (!why && CMSDecoderCopySignerTimestamp(decoder, 0, &when) != errSecSuccess
        && CMSDecoderCopySignerSigningTime(decoder, 0, &when) != errSecSuccess)
        why = @"it says nothing of when it was signed";
    SecCertificateRef leaf = NULL;
    if (!why && (CMSDecoderCopySignerCert(decoder, 0, &leaf) != errSecSuccess || !leaf
                 || CMSDecoderCopyAllCerts(decoder, &certificates) != errSecSuccess || !certificates))
        why = @"it carries no certificates";
    if (!why) {
        NSDate *signedAt = [NSDate dateWithTimeIntervalSinceReferenceDate:when];
        NSArray *all = (__bridge NSArray *)certificates;
        SecCertificateRef at = leaf;
        BOOL rooted = NO;
        // Up from the leaf, each signed by the next, to Apple's root; never more than a few steps.
        for (int step = 0; step < 4 && !rooted; step++) {
            if ([Fingerprint(at) isEqualToString:kAppleRoot]) {
                rooted = step > 0;
                break;
            }
            SecCertificateRef issuer = IssuerOf(at, all);
            if (!issuer || !SignedBy(at, issuer) || !InDate(at, signedAt)) break;
            if (step == 0 && !ValuesOf(issuer, @[kDeveloperIDAuthority])[kDeveloperIDAuthority]) break;
            at = issuer;
        }
        if (!rooted) why = @"its certificate isn't Apple's Developer ID";
        else if (!ValuesOf(leaf, @[kDeveloperIDApplication])[kDeveloperIDApplication])
            why = @"its certificate isn't a Developer ID Application one";
        else if (![TeamOf(leaf) isEqual:team]) why = @"its certificate is another team's";
    }
    if (leaf) CFRelease(leaf);
    if (certificates) CFRelease(certificates);
    if (policy) CFRelease(policy);
    CFRelease(decoder);
    return why;
}

NSDictionary *RunningSignature(pid_t pid) {
    if (pid <= 0) return nil;
    uint32_t status = 0;
    if (csops(pid, kStatus, &status, sizeof status) != 0) return nil;
    NSMutableDictionary *found = [@{@"valid": @((BOOL)(status & kValid)), @"developerID": @NO} mutableCopy];
    NSString *identifier = Text(pid, kIdentity), *team = Text(pid, kTeam);
    if (identifier) found[@"identifier"] = identifier;
    if (team) found[@"team"] = team;
    uint8_t cdhash[20] = {0};
    NSData *blob = WholeSignature(pid);
    if (!(status & kValid)) found[@"why"] = @"the system doesn't hold its code as signed";
    else if (!team) found[@"why"] = @"it names no team";
    else if (csops(pid, kCDHash, cdhash, sizeof cdhash) != 0 || !blob) found[@"why"] = @"its signature can't be read";
    else {
        NSString *why = WhyNotDeveloperID(blob, [NSData dataWithBytes:cdhash length:sizeof cdhash], team);
        if (why) found[@"why"] = why;
        else found[@"developerID"] = @YES;
    }
    return found;
}

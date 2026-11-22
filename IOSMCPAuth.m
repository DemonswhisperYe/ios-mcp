#import "IOSMCPAuth.h"
#import "IOSMCPPreferences.h"
#import <CommonCrypto/CommonCryptoError.h>
#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonKeyDerivation.h>
#import <Security/SecRandom.h>
#import <string.h>
#import <sys/socket.h>

// V1 stores a random salt followed by PBKDF2-HMAC-SHA256 in a single preference.
static CFStringRef const verifierKey = CFSTR("connectionPasswordVerifierV1");
enum { SaltBytes = 16, HashBytes = CC_SHA256_DIGEST_LENGTH, Rounds = 600000 };

static NSData *currentVerifier(void) {
    CFStringRef domain = (__bridge CFStringRef)IOS_MCP_PREFERENCES_DOMAIN;
    if (!CFPreferencesAppSynchronize(domain)) return nil;
    id value = CFBridgingRelease(CFPreferencesCopyAppValue(verifierKey, domain));
    if (![value isKindOfClass:NSData.class] || [value length] != SaltBytes + HashBytes) return nil;
    return value;
}

BOOL IOSMCPHasPassword(void) {
    return currentVerifier() != nil;
}

BOOL IOSMCPPasswordIsValid(NSString *password) {
    NSUInteger bytes = [password lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    return bytes >= 12 && bytes <= 128 &&
           [password rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location == NSNotFound &&
           [password stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length > 0;
}

static BOOL deriveHash(const void *password, size_t length, const uint8_t *salt, uint8_t *hash) {
    return CCKeyDerivationPBKDF(kCCPBKDF2, password, length, salt, SaltBytes,
                                kCCPRFHmacAlgSHA256, Rounds, hash, HashBytes) == kCCSuccess;
}

BOOL IOSMCPSavePassword(NSString *password) {
    if (!IOSMCPPasswordIsValid(password)) return NO;
    NSData *input = [password dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t record[SaltBytes + HashBytes];
    if (!input || SecRandomCopyBytes(kSecRandomDefault, SaltBytes, record) != 0 ||
        !deriveHash(input.bytes, input.length, record, record + SaltBytes)) return NO;

    NSData *verifier = [NSData dataWithBytes:record length:sizeof(record)];
    CFStringRef domain = (__bridge CFStringRef)IOS_MCP_PREFERENCES_DOMAIN;
    CFPreferencesSetAppValue(verifierKey, (__bridge CFDataRef)verifier, domain);
    return CFPreferencesAppSynchronize(domain);
}

BOOL IOSMCPRequestIsAuthorized(NSString *method, NSString *basePath, int clientSocket, NSString *header) {
    if ([method isEqualToString:@"GET"] && [basePath isEqualToString:@"/health"]) {
        // Settings probes the IPv4 listener locally. Trust the socket peer, never a request header.
        struct sockaddr_in peer = {0};
        socklen_t size = sizeof(peer);
        if (getpeername(clientSocket, (struct sockaddr *)&peer, &size) == 0 &&
            size == sizeof(peer) && peer.sin_family == AF_INET &&
            (ntohl(peer.sin_addr.s_addr) >> 24) == 127) return YES;
    }
    if (header.length < 7 || header.length > 200 ||
        [header compare:@"Basic " options:NSCaseInsensitiveSearch range:NSMakeRange(0, 6)] != NSOrderedSame) return NO;
    NSString *token = [[header substringFromIndex:6] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    NSData *decoded = [[NSData alloc] initWithBase64EncodedString:token options:0];
    const size_t prefixLength = sizeof("mcp:") - 1;
    if (decoded.length < prefixLength + 12 || decoded.length > prefixLength + 128 ||
        memcmp(decoded.bytes, "mcp:", prefixLength) != 0) return NO;
    const uint8_t *password = (const uint8_t *)decoded.bytes + prefixLength;
    size_t length = decoded.length - prefixLength;

    // Do the slow derivation only until the first success for a given stored verifier.
    // Keeping the cache under one lock also bounds concurrent CPU use before that success.
    static NSData *verifiedRecord;
    static uint8_t verifiedFingerprint[HashBytes];
    static NSObject *lock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lock = [NSObject new]; });
    @synchronized (lock) {
        NSData *record = currentVerifier();
        if (!record) return NO;
        uint8_t fingerprint[HashBytes];
        CC_SHA256(password, (CC_LONG)length, fingerprint);
        if (verifiedRecord && [record isEqualToData:verifiedRecord]) {
            return timingsafe_bcmp(fingerprint, verifiedFingerprint, HashBytes) == 0;
        }
        uint8_t hash[HashBytes];
        const uint8_t *stored = record.bytes;
        if (!deriveHash(password, length, stored, hash) ||
            timingsafe_bcmp(hash, stored + SaltBytes, HashBytes) != 0) return NO;
        verifiedRecord = record;
        memcpy(verifiedFingerprint, fingerprint, HashBytes);
        return YES;
    }
}

// macOS: clang -fobjc-arc -framework Foundation -framework Security tests/http_auth_tests.m -o /tmp/ios-mcp-auth-test && /tmp/ios-mcp-auth-test
#import "../IOSMCPPreferences.h"
#import <assert.h>
#import <sys/socket.h>
#import <unistd.h>

// Exercise the production verifier with an isolated preferences store.
static id preference;
static Boolean syncOK = true;
static CFPropertyListRef testCopy(CFStringRef key, CFStringRef domain) {
    return CFBridgingRetain(preference);
}
static void testSet(CFStringRef key, CFPropertyListRef value, CFStringRef domain) {
    preference = [(__bridge id)value copy];
}
#define CFPreferencesAppSynchronize(domain) (syncOK)
#define CFPreferencesCopyAppValue testCopy
#define CFPreferencesSetAppValue testSet
#import "../IOSMCPAuth.m"

static NSString *basic(NSString *credentials) {
    NSData *data = [credentials dataUsingEncoding:NSUTF8StringEncoding];
    return [@"bAsIc " stringByAppendingString:[data base64EncodedStringWithOptions:0]];
}

int main(void) {
    @autoreleasepool {
        NSString *password = [@"测试:" stringByAppendingString:NSUUID.UUID.UUIDString];
        NSString *old = basic([@"mcp:" stringByAppendingString:password]);
        NSString *next = NSUUID.UUID.UUIDString;
        NSString *fresh = basic([@"mcp:" stringByAppendingString:next]);
        assert(!IOSMCPHasPassword() && !IOSMCPRequestIsAuthorized(@"POST", @"/mcp", -1, old));
        assert(!IOSMCPSavePassword(@"            "));
        assert(!IOSMCPSavePassword(@"12345678901"));
        assert(!IOSMCPSavePassword([password stringByAppendingString:@"\n"]));
        NSString *max = [@"" stringByPaddingToLength:128 withString:@"x" startingAtIndex:0];
        assert(IOSMCPPasswordIsValid(max) && !IOSMCPPasswordIsValid([max stringByAppendingString:@"x"]));

        assert(IOSMCPSavePassword(password) && IOSMCPHasPassword());
        NSData *firstRecord = preference;
        assert([firstRecord isKindOfClass:NSData.class] && firstRecord.length == 48);
        assert(IOSMCPSavePassword(password) && ![firstRecord isEqual:preference]);
        assert(!IOSMCPRequestIsAuthorized(@"POST", @"/mcp", -1, fresh));
        for (NSString *path in @[@"/mcp", @"/upload_file", @"/download_file", @"/health", @"/future"]) {
            assert(!IOSMCPRequestIsAuthorized(@"GET", path, -1, nil));
            assert(IOSMCPRequestIsAuthorized(@"GET", path, -1, old));
        }
        for (NSString *bad in @[@"Basic !", @"Bearer test", @"Basic bWNwOg==", fresh,
                                 basic([@"other:" stringByAppendingString:password])]) {
            assert(!IOSMCPRequestIsAuthorized(@"POST", @"/mcp", -1, bad));
        }
        assert(IOSMCPSavePassword(next));
        assert(!IOSMCPRequestIsAuthorized(@"POST", @"/mcp", -1, old));
        assert(IOSMCPRequestIsAuthorized(@"POST", @"/mcp", -1, fresh));
        syncOK = false;
        assert(!IOSMCPRequestIsAuthorized(@"POST", @"/mcp", -1, fresh));
        syncOK = true;
        for (id damaged in @[@"invalid", [NSData data]]) {
            preference = damaged;
            assert(!IOSMCPHasPassword() && !IOSMCPRequestIsAuthorized(@"POST", @"/mcp", -1, fresh));
        }
        preference = nil;
        assert(!IOSMCPRequestIsAuthorized(@"POST", @"/mcp", -1, fresh));

        int listener = socket(AF_INET, SOCK_STREAM, 0);
        struct sockaddr_in local = { .sin_family = AF_INET, .sin_addr.s_addr = htonl(INADDR_LOOPBACK) };
        socklen_t size = sizeof(local);
        assert(bind(listener, (struct sockaddr *)&local, size) == 0 && listen(listener, 1) == 0);
        assert(getsockname(listener, (struct sockaddr *)&local, &size) == 0);
        int client = socket(AF_INET, SOCK_STREAM, 0);
        assert(connect(client, (struct sockaddr *)&local, size) == 0);
        int server = accept(listener, NULL, NULL);
        assert(server >= 0 && IOSMCPRequestIsAuthorized(@"GET", @"/health", server, nil));
        assert(!IOSMCPRequestIsAuthorized(@"POST", @"/health", server, nil));
        assert(!IOSMCPRequestIsAuthorized(@"GET", @"/download_file", server, nil));
        assert(!IOSMCPRequestIsAuthorized(@"POST", @"/mcp", server, nil));
        close(server); close(client); close(listener);
        puts("PASS password setup, verifier, credentials, rotation, closed defaults and loopback health");
    }
    return 0;
}

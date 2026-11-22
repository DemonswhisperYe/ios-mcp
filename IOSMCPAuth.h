#import <Foundation/Foundation.h>

BOOL IOSMCPPasswordIsValid(NSString *password);
BOOL IOSMCPSavePassword(NSString *password);
BOOL IOSMCPHasPassword(void);
BOOL IOSMCPRequestIsAuthorized(NSString *method, NSString *basePath, int clientSocket, NSString *header);

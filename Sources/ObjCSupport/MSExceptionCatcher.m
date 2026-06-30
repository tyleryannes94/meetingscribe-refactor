#import "MSExceptionCatcher.h"

NSError *_Nullable MSRunCatchingExceptions(NS_NOESCAPE void (^block)(void)) {
    @try {
        block();
        return nil;
    } @catch (NSException *exception) {
        NSString *reason = exception.reason ?: exception.name ?: @"Objective-C exception";
        return [NSError errorWithDomain:@"MSObjCException"
                                   code:1
                               userInfo:@{
            NSLocalizedDescriptionKey: reason,
            @"ExceptionName": exception.name ?: @"unknown",
        }];
    }
}

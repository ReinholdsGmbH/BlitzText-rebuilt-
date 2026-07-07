#import "ExceptionCatcher.h"

@implementation ExceptionCatcher

+ (nullable NSError *)tryBlock:(NS_NOESCAPE void (^)(void))block {
    @try {
        block();
        return nil;
    } @catch (NSException *exception) {
        NSMutableDictionary *info = [NSMutableDictionary dictionary];
        info[NSLocalizedDescriptionKey] = exception.reason ?: exception.name;
        info[@"ExceptionName"] = exception.name;
        return [NSError errorWithDomain:@"BlitzText.ObjCException" code:0 userInfo:info];
    }
}

@end

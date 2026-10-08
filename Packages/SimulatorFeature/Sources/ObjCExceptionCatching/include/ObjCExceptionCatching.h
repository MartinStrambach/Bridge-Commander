#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block` and returns the Objective-C exception it raised, or nil. Swift cannot catch an
/// `NSException`: one thrown through Swift frames terminates the process.
NSException *_Nullable BCCatchObjCException(NS_NOESCAPE void (^block)(void));

NS_ASSUME_NONNULL_END

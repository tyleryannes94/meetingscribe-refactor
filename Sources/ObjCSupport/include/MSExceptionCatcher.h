#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block` inside an Objective-C `@try/@catch`. If it raises an NSException,
/// returns an NSError (domain "MSObjCException") describing it instead of letting
/// the exception propagate to `objc_terminate` and SIGABRT the whole process.
/// Returns nil on success.
///
/// This exists because a handful of AppKit/AVFoundation APIs (notably
/// `-[AVAudioNode installTapOnBus:bufferSize:format:block:]`) signal failure by
/// *throwing* an Objective-C exception, which Swift `do/catch` cannot intercept.
/// Wrapping the call here turns an unrecoverable crash into a catchable error.
NSError *_Nullable MSRunCatchingExceptions(NS_NOESCAPE void (^block)(void));

NS_ASSUME_NONNULL_END

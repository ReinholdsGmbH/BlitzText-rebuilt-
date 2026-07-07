#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Führt einen Swift-Block aus und fängt eine ggf. geworfene ObjC-`NSException`.
///
/// Hintergrund: `AVAudioEngine` (u. a. `installTap`, `start()`) wirft bei ungültigem/„stale"
/// Hardware-Format eine ObjC-`NSException` („required condition is false…"). Swift-`do/catch`
/// kann diese NICHT fangen. Läuft der Aufruf aus dem AppKit-Event-Dispatch (Hotkey), wird die
/// Exception dort verschluckt und hinterlässt die Main-Queue tot → App-Freeze. Dieser Wrapper
/// fängt sie und liefert sie als `NSError` zurück, sodass Swift sauber reagieren kann.
@interface ExceptionCatcher : NSObject
/// Führt `block` aus. Rückgabe `nil` = erfolgreich; andernfalls ein `NSError`, der die
/// gefangene `NSException` beschreibt.
+ (nullable NSError *)tryBlock:(NS_NOESCAPE void (^)(void))block NS_SWIFT_NAME(run(_:));
@end

NS_ASSUME_NONNULL_END

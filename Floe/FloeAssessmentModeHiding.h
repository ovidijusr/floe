//
//  FloeAssessmentModeHiding.h
//  Project: Floe
//
//  Ported from Thaw (ThawAssessmentModeHiding.h)
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Whether the private MenuBarClientCore assessment-mode classes are present
/// and loadable on this system.
BOOL FloeAssessmentModeHidingAvailable(void);

/// Activates a menu bar visibility restriction that allows only the given
/// bundle identifiers and system items; every other menu bar item is hidden
/// and the bar reflows. Returns an opaque retained assertion handle that must
/// be kept alive for the restriction to remain in effect, or NULL on failure.
/// `onFailure` is invoked on the main queue if activation later reports an
/// asynchronous error.
void *_Nullable FloeAssessmentModeHidingActivate(NSArray<NSString *> *allowedBundleIdentifiers,
                                                 NSArray<NSNumber *> *allowedSystemItems,
                                                 void (^_Nullable onFailure)(void));

/// Invalidates and releases an assertion handle returned by
/// `FloeAssessmentModeHidingActivate`, revealing all items again.
void FloeAssessmentModeHidingInvalidate(void *_Nullable handle);

NS_ASSUME_NONNULL_END

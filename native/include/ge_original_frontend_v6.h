#ifndef GE_ORIGINAL_FRONTEND_V6_NATIVE_COMPAT_H
#define GE_ORIGINAL_FRONTEND_V6_NATIVE_COMPAT_H

/*
 * Legacy standalone C-test compatibility. SwiftPM's GoldenEyeNative umbrella
 * sees this marker with SWIFT_PACKAGE defined; the independent
 * GoldenEyeOriginalFrontend module owns the public API and this header must
 * contribute no declarations there.
 */
#if !defined(SWIFT_PACKAGE)
#include "../source_port/original/ge_original_frontend_v6.h"
#endif

#endif /* GE_ORIGINAL_FRONTEND_V6_NATIVE_COMPAT_H */

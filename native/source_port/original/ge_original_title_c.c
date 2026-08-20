/*
 * SwiftPM-facing title translation unit.  Keep this separate from front.c so
 * the original translation-unit statics and source symbol ownership remain
 * exactly as they are in the checked-in source.
 */
#ifndef _LANGUAGE_C
#define _LANGUAGE_C 1
#endif
#ifndef VERSION_US
#define VERSION_US 1
#endif
#ifndef LANG_US
#define LANG_US 1
#endif
#ifndef REFRESH_NTSC
#define REFRESH_NTSC 1
#endif
#ifndef LEFTOVERDEBUG
#define LEFTOVERDEBUG 1
#endif
#ifndef LEFTOVERSPECTRUM
#define LEFTOVERSPECTRUM 1
#endif
#ifndef BUGFIX_R0
#define BUGFIX_R0 1
#endif
#ifndef BYTEMATCH
#define BYTEMATCH 1
#endif

#define GE_ORIGINAL_UNIT_PREFIX ge_title_
#include "ge_original_host_compat.h"

/* Deliberately no F3DEX_GBI_2: this checkout uses classic GE/F3D opcodes. */
#include "../../../src/game/title.c"

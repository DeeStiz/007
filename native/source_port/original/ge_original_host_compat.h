#ifndef GE_ORIGINAL_HOST_COMPAT_H
#define GE_ORIGINAL_HOST_COMPAT_H

/*
 * Host-only include bridge for compiling the checked-in frontend translation
 * units.  This header is intentionally small: it fixes include-order and
 * compiler dialect differences before front.c/title.c are included.  It does
 * not provide a game implementation or an N64 scheduler.
 */

#include <stdint.h>
#include <stddef.h>

/* SwiftPM defines DEBUG for its Debug configuration. The original headers
 * emit external *_ToString arrays when DEBUG is set, which creates one
 * definition per unchanged translation unit. The canonical source-oracle
 * build does not define DEBUG, so keep this isolated module consistent. */
#ifdef DEBUG
#undef DEBUG
#endif

/* bondconstants.h intentionally emits debug lookup arrays when AIPARSE is
 * enabled. The hosted compatibility include needs AIPARSE to avoid the N64
 * chrobjdata include-order cycle, so namespace those arrays per translation
 * unit instead of relying on the N64 linker's dead stripping. */
#ifndef GE_ORIGINAL_UNIT_PREFIX
#define GE_ORIGINAL_UNIT_PREFIX ge_original_
#endif
#define GE_ORIGINAL_CONCAT_INNER(a, b) a##b
#define GE_ORIGINAL_CONCAT(a, b) GE_ORIGINAL_CONCAT_INNER(a, b)
#define GE_ORIGINAL_UNIT_SYMBOL(name) GE_ORIGINAL_CONCAT(GE_ORIGINAL_UNIT_PREFIX, name)
#define ANIMATIONS_ToString GE_ORIGINAL_UNIT_SYMBOL(ANIMATIONS_ToString)
#define AIRCRAFT_ANIMATION_ToString GE_ORIGINAL_UNIT_SYMBOL(AIRCRAFT_ANIMATION_ToString)
#define CUFF_TYPES_ToString GE_ORIGINAL_UNIT_SYMBOL(CUFF_TYPES_ToString)
#define DIFFICULTY_ToString GE_ORIGINAL_UNIT_SYMBOL(DIFFICULTY_ToString)
#define HIT_TYPE_ToString GE_ORIGINAL_UNIT_SYMBOL(HIT_TYPE_ToString)
#define LEVELID_ToString GE_ORIGINAL_UNIT_SYMBOL(LEVELID_ToString)
#define MUSIC_TRACK_ToString GE_ORIGINAL_UNIT_SYMBOL(MUSIC_TRACK_ToString)
#define SFX_ID_ToString GE_ORIGINAL_UNIT_SYMBOL(SFX_ID_ToString)
#define TEXTBANK_LEVEL_INDEX_ToString GE_ORIGINAL_UNIT_SYMBOL(TEXTBANK_LEVEL_INDEX_ToString)
#define PROP_ToString GE_ORIGINAL_UNIT_SYMBOL(PROP_ToString)
#define PROP_TYPE_ToString GE_ORIGINAL_UNIT_SYMBOL(PROP_TYPE_ToString)
#define ACT_STATUS_ToString GE_ORIGINAL_UNIT_SYMBOL(ACT_STATUS_ToString)
#define ACT_TYPE_ToString GE_ORIGINAL_UNIT_SYMBOL(ACT_TYPE_ToString)
#define AMMOTYPE_ToString GE_ORIGINAL_UNIT_SYMBOL(AMMOTYPE_ToString)
#define ITEM_IDS_ToString GE_ORIGINAL_UNIT_SYMBOL(ITEM_IDS_ToString)
#define PROPDEF_TYPE_ToString GE_ORIGINAL_UNIT_SYMBOL(PROPDEF_TYPE_ToString)
#define CAMERAMODE_ToString GE_ORIGINAL_UNIT_SYMBOL(CAMERAMODE_ToString)
#define INTRO_TYPE_ToString GE_ORIGINAL_UNIT_SYMBOL(INTRO_TYPE_ToString)
#define MISSION_STATE_IDS_ToString GE_ORIGINAL_UNIT_SYMBOL(MISSION_STATE_IDS_ToString)
#define OBJECTIVESTATUS_ToString GE_ORIGINAL_UNIT_SYMBOL(OBJECTIVESTATUS_ToString)
#define CHR_ToString GE_ORIGINAL_UNIT_SYMBOL(CHR_ToString)

/* The repository's intentionally empty include/stddef.h masks the hosted
 * declaration while ultratypes.h still needs ptrdiff_t. */
#ifndef GE_ORIGINAL_HOST_COMPAT_PTRDIFF_T
#define GE_ORIGINAL_HOST_COMPAT_PTRDIFF_T 1
typedef long ptrdiff_t;
#endif
#ifndef GE_ORIGINAL_HOST_COMPAT_SIZE_T
#define GE_ORIGINAL_HOST_COMPAT_SIZE_T 1
typedef unsigned long size_t;
#endif

/* Hosted libc declarations hidden by the repository's SDK compatibility
 * headers.  These are used only by the adapter/stub translation units. */
extern void *memset(void *destination, int value, size_t size);
extern void *memcpy(void *destination, const void *source, size_t size);

/* bondtypes.h includes chrobjdata.h before its model-record definitions when
 * compiled by a hosted C compiler.  Prime bondtypes with its AIPARSE path so
 * the later source include sees complete record types. */
#ifndef AIPARSE
#define AIPARSE 1
#define GE_ORIGINAL_HOST_COMPAT_UNDEFINE_AIPARSE 1
#endif

/* The source's __sgi BITFLAG macro is a no-op on hosted compilers. */
typedef enum PLAYERFLAG {
    PLAYERFLAG_NONE = 0,
    PLAYERFLAG_LOCKCONTROLS = 1 << 0,
    PLAYERFLAG_NOCONTROL = 1 << 1,
    PLAYERFLAG_NOTIMER = 1 << 2
} PLAYERFLAG;

/* image_externs.h keeps its generated declarations disabled on hosted builds,
 * but front.c still names the source enum entry in a dead-strippable helper. */
#ifndef IMAGE_CHECK
#define IMAGE_CHECK 4
#endif

#include <bondtypes.h>

/* The N64 macro subtracts the K0 virtual base from a pointer.  That is a
 * valid 32-bit address operation on the source target but is undefined when
 * a hosted arm64 sanitizer evaluates a deliberately inert sink value.  Keep
 * the source command emission while making the host conversion value-only. */
#ifdef OS_K0_TO_PHYSICAL
#undef OS_K0_TO_PHYSICAL
#endif
extern u32 ge_original_host_virtual_to_physical(void *value);
#define OS_K0_TO_PHYSICAL(value) \
    ge_original_host_virtual_to_physical((void *)(uintptr_t)(value))

/* A few source files intentionally rely on the original project's broad
 * translation-unit include order.  Preserve the real return types for the
 * title functions whose hosted implicit declarations would truncate a
 * pointer before it reaches the adapter. */
extern Gfx *retrieve_display_rareware_logo(Gfx *gdl);
extern Gfx *renderGunbarrelEyeIntroSequence(Gfx *gdl);
extern void setupRarewareLogoData(s32 address, s32 size);
extern void initializeGunBarrelIntro(u8 *gfxBuffer, s32 bufferSize);
extern void clearChrGunModelInstances(void);
extern s32 isGunBarrelInMode2(void);
extern s32 isGunBarrelInMode9(void);
extern void sub_GAME_7F008DE4(u8 **addr, s32 *size);
extern void *dynAllocate(s32 size);
extern void rle_expand_8bit(u8 *src, u8 *dst);

#ifdef GE_ORIGINAL_HOST_COMPAT_UNDEFINE_AIPARSE
#undef AIPARSE
#undef GE_ORIGINAL_HOST_COMPAT_UNDEFINE_AIPARSE
#endif

#endif /* GE_ORIGINAL_HOST_COMPAT_H */

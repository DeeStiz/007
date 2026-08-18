#ifndef GE_NATIVE_FOUNDATION_H
#define GE_NATIVE_FOUNDATION_H

#include <stdint.h>

#define GE_NATIVE_ABI_VERSION ((uint32_t)1u)

typedef uint32_t GEStatusV1;

#define GE_STATUS_OK ((GEStatusV1)0u)
#define GE_STATUS_INVALID_VERSION ((GEStatusV1)1u)
#define GE_STATUS_INVALID_SIZE ((GEStatusV1)2u)
#define GE_STATUS_INVALID_ARGUMENT ((GEStatusV1)3u)
#define GE_STATUS_INVALID_STATE ((GEStatusV1)4u)
#define GE_STATUS_WRONG_OWNER_THREAD ((GEStatusV1)5u)
#define GE_STATUS_THREAD_ID_UNAVAILABLE ((GEStatusV1)6u)
#define GE_STATUS_RESERVED_BITS ((GEStatusV1)7u)
#define GE_STATUS_INTERNAL_ERROR ((GEStatusV1)8u)
#define GE_STATUS_UNSUPPORTED_COMMAND ((GEStatusV1)9u)
#define GE_STATUS_MALFORMED_STREAM ((GEStatusV1)10u)
#define GE_STATUS_RESOURCE_NOT_FOUND ((GEStatusV1)11u)
#define GE_STATUS_VERTEX_OUT_OF_RANGE ((GEStatusV1)12u)
#define GE_STATUS_REPLAY_DEPTH ((GEStatusV1)13u)
#define GE_STATUS_REPLAY_BUDGET ((GEStatusV1)14u)
#define GE_STATUS_REPLAY_CYCLE ((GEStatusV1)15u)
#define GE_STATUS_ASSET_MISMATCH ((GEStatusV1)16u)
#define GE_STATUS_MATRIX_STACK ((GEStatusV1)17u)
#define GE_STATUS_TEXTURE_FORMAT ((GEStatusV1)18u)
#define GE_STATUS_TEXTURE_COMPRESSION ((GEStatusV1)19u)
#define GE_STATUS_TEXTURE_OVERFLOW ((GEStatusV1)20u)
#define GE_STATUS_TMEM_OVERFLOW ((GEStatusV1)21u)
#define GE_STATUS_TLUT_OVERFLOW ((GEStatusV1)22u)

typedef struct GEAbiHeaderV1 {
    uint32_t abi_version;
    uint32_t struct_size;
} GEAbiHeaderV1;

typedef struct GEVertexV1 {
    int16_t x;
    int16_t y;
    int16_t z;
    uint16_t reserved0;
    int16_t s;
    int16_t t;
    uint8_t r;
    uint8_t g;
    uint8_t b;
    uint8_t a;
    uint32_t reserved1;
} GEVertexV1;

#if defined(__cplusplus)
static_assert(sizeof(GEAbiHeaderV1) == 8u, "GEAbiHeaderV1 layout drift");
static_assert(sizeof(GEVertexV1) == 20u, "GEVertexV1 layout drift");
#else
_Static_assert(sizeof(GEAbiHeaderV1) == 8u, "GEAbiHeaderV1 layout drift");
_Static_assert(sizeof(GEVertexV1) == 20u, "GEVertexV1 layout drift");
#endif

#endif /* GE_NATIVE_FOUNDATION_H */

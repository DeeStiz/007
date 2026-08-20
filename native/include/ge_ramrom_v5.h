#ifndef GE_RAMROM_V5_H
#define GE_RAMROM_V5_H

/*
 * Native RAMROM recording contract.
 *
 * The US NTSC recording files are source-derived, big-endian byte streams.
 * This sidecar decodes their value-only header and bounded packet stream.  It
 * deliberately does not expose a ROM address, file path, pointer retained in
 * a record, or a gameplay/runtime object.  The parser takes bytes only for
 * the duration of a call and returns fixed-width observations.
 *
 * Source format facts retained here:
 *   - ramromfilestructure is 0xe8 bytes after natural 64-bit tail padding.
 *   - each packet is [speedframes,count,randseed,check] followed by
 *     count * controller_count four-byte input samples.
 *   - a four-byte all-zero packet header is the terminal packet.
 *   - the source checksum is the low byte of speedframes + count + randseed
 *     plus every input byte in the packet.
 */

#include <stdint.h>

#include "ge_native_foundation.h"
#include "ge_native_runtime_v5.h"

#ifdef __cplusplus
extern "C" {
#endif

#define GE_RAMROM_V5_CONTRACT_VERSION ((uint32_t)5u)
#define GE_RAMROM_V5_RECORD_VERSION ((uint32_t)1u)

#define GE_RAMROM_V5_HEADER_BYTES ((uint32_t)232u)
#define GE_RAMROM_V5_SAVE_BYTES ((uint32_t)96u)
#define GE_RAMROM_V5_PACKET_HEADER_BYTES ((uint32_t)4u)
#define GE_RAMROM_V5_SAMPLE_BYTES ((uint32_t)4u)
#define GE_RAMROM_V5_TERMINAL_BYTES ((uint32_t)4u)
#define GE_RAMROM_V5_MAX_CONTROLLERS ((uint32_t)4u)
#define GE_RAMROM_V5_MAX_PACKETS ((uint32_t)4096u)
#define GE_RAMROM_V5_MAX_PACKET_RECORDS ((uint32_t)255u)
#define GE_RAMROM_V5_MAX_TRAILING_BYTES ((uint32_t)15u)

#define GE_RAMROM_V5_DEMO_COUNT ((uint32_t)14u)

/* Source demo-table order in src/game/ramromreplay.c. */
#define GE_RAMROM_V5_DEMO_DAM_1 ((uint32_t)1u)
#define GE_RAMROM_V5_DEMO_DAM_2 ((uint32_t)2u)
#define GE_RAMROM_V5_DEMO_FACILITY_1 ((uint32_t)3u)
#define GE_RAMROM_V5_DEMO_FACILITY_2 ((uint32_t)4u)
#define GE_RAMROM_V5_DEMO_FACILITY_3 ((uint32_t)5u)
#define GE_RAMROM_V5_DEMO_RUNWAY_1 ((uint32_t)6u)
#define GE_RAMROM_V5_DEMO_RUNWAY_2 ((uint32_t)7u)
#define GE_RAMROM_V5_DEMO_BUNKER_I_1 ((uint32_t)8u)
#define GE_RAMROM_V5_DEMO_BUNKER_I_2 ((uint32_t)9u)
#define GE_RAMROM_V5_DEMO_SILO_1 ((uint32_t)10u)
#define GE_RAMROM_V5_DEMO_SILO_2 ((uint32_t)11u)
#define GE_RAMROM_V5_DEMO_FRIGATE_1 ((uint32_t)12u)
#define GE_RAMROM_V5_DEMO_FRIGATE_2 ((uint32_t)13u)
#define GE_RAMROM_V5_DEMO_TRAIN ((uint32_t)14u)

/* LEVELID values used by the NTSC-US recording headers. */
#define GE_RAMROM_V5_STAGE_BUNKER_I ((uint32_t)9u)
#define GE_RAMROM_V5_STAGE_SILO ((uint32_t)20u)
#define GE_RAMROM_V5_STAGE_TRAIN ((uint32_t)25u)
#define GE_RAMROM_V5_STAGE_FRIGATE ((uint32_t)26u)
#define GE_RAMROM_V5_STAGE_DAM ((uint32_t)33u)
#define GE_RAMROM_V5_STAGE_FACILITY ((uint32_t)34u)
#define GE_RAMROM_V5_STAGE_RUNWAY ((uint32_t)35u)

#define GE_RAMROM_V5_PARSE_FLAG_HEADER_VALID ((uint32_t)1u << 0)
#define GE_RAMROM_V5_PARSE_FLAG_TERMINAL_VALID ((uint32_t)1u << 1)
#define GE_RAMROM_V5_PARSE_FLAG_CHECKSUMS_VALID ((uint32_t)1u << 2)
#define GE_RAMROM_V5_PARSE_FLAG_RNG_CHECKPOINTS ((uint32_t)1u << 3)
#define GE_RAMROM_V5_PARSE_FLAG_SPEEDFRAMES_VALID ((uint32_t)1u << 4)
#define GE_RAMROM_V5_PARSE_FLAG_MASK ((uint32_t)0x1fu)

#define GE_RAMROM_V5_PACKET_FLAG_CHECKSUM_VALID ((uint32_t)1u << 0)
#define GE_RAMROM_V5_PACKET_FLAG_RNG_CHECKPOINT ((uint32_t)1u << 1)
#define GE_RAMROM_V5_PACKET_FLAG_SPEEDFRAMES_VALID ((uint32_t)1u << 2)
#define GE_RAMROM_V5_PACKET_FLAG_TERMINAL ((uint32_t)1u << 3)
#define GE_RAMROM_V5_PACKET_FLAG_MASK ((uint32_t)0x0fu)

/*
 * Host-order semantic view of the first 0xe8 bytes.  The source save bytes
 * remain available through ge_ramrom_v5_copy_save; only their two checksums
 * and deterministic hash are carried here.
 */
typedef struct GERamRomHeaderV5 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t source_header_bytes;
    uint64_t random_seed;
    uint64_t randomizer_seed;
    uint32_t stage_id;
    uint32_t difficulty;
    uint32_t controller_count;
    uint32_t total_time_ms;
    uint32_t declared_file_bytes;
    uint32_t mode;
    uint32_t slot_number;
    uint32_t player_count;
    uint32_t scenario;
    uint32_t multiplayer_stage;
    uint32_t game_length;
    uint32_t weapon_set;
    uint32_t aim_option;
    uint32_t character_ids[4];
    uint32_t handicaps[4];
    uint32_t controller_styles[4];
    uint32_t player_flags[4];
    uint32_t save_checksum1;
    uint32_t save_checksum2;
    uint64_t save_hash;
    uint64_t header_hash;
    uint32_t reserved0;
    uint32_t reserved1;
} GERamRomHeaderV5;

typedef struct GERamRomPacketV5 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t packet_index;
    uint32_t byte_offset;
    uint32_t record_count;
    uint32_t controller_count;
    uint32_t speedframes;
    uint32_t rng_seed;
    uint32_t checksum;
    uint32_t computed_checksum;
    uint32_t payload_bytes;
    uint32_t flags;
    uint64_t packet_hash;
    uint64_t payload_hash;
    uint32_t reserved0;
    uint32_t reserved1;
} GERamRomPacketV5;

typedef struct GERamRomSampleV5 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t packet_index;
    uint32_t frame_index;
    uint32_t controller_index;
    int8_t stick_x;
    int8_t stick_y;
    uint8_t button_low;
    uint8_t button_high;
    uint32_t buttons;
    uint32_t reserved0;
} GERamRomSampleV5;

typedef struct GERamRomParseSummaryV5 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t flags;
    uint32_t packet_count;
    uint32_t record_count;
    uint32_t checksum_valid_count;
    uint32_t rng_checkpoint_count;
    uint32_t terminal_offset;
    uint32_t terminal_bytes;
    uint32_t parsed_bytes;
    uint32_t trailing_bytes;
    uint32_t first_invalid_packet;
    uint32_t reserved0;
    uint32_t reserved1;
    uint64_t header_hash;
    uint64_t recording_hash;
    uint64_t packet_hash;
    uint64_t rng_hash;
    uint64_t input_hash;
} GERamRomParseSummaryV5;

/* Static catalog values are a source-order guard, not a runtime path list. */
typedef struct GERamRomCatalogEntryV5 {
    GEAbiHeaderV1 header;
    uint32_t record_version;
    uint32_t demo_id;
    uint32_t stage_id;
    uint32_t variant;
    uint32_t controller_count;
    uint32_t declared_file_bytes;
    uint32_t asset_file_bytes;
    uint32_t total_time_ms;
    uint64_t recording_hash;
} GERamRomCatalogEntryV5;

/* A bounded source-derived hash.  The byte stream remains externally owned. */
uint64_t ge_ramrom_v5_hash_bytes(const uint8_t *bytes, uint32_t byte_count);

GEStatusV1 ge_ramrom_v5_validate_header(const GERamRomHeaderV5 *value);
GEStatusV1 ge_ramrom_v5_validate_packet(const GERamRomPacketV5 *value);
GEStatusV1 ge_ramrom_v5_validate_sample(const GERamRomSampleV5 *value);
GEStatusV1 ge_ramrom_v5_validate_summary(const GERamRomParseSummaryV5 *value);
GEStatusV1 ge_ramrom_v5_validate_catalog_entry(const GERamRomCatalogEntryV5 *value);

GEStatusV1 ge_ramrom_v5_read_header(const uint8_t *bytes,
                                    uint32_t byte_count,
                                    GERamRomHeaderV5 *out_header);

GEStatusV1 ge_ramrom_v5_copy_save(const uint8_t *bytes,
                                  uint32_t byte_count,
                                  uint8_t *out_save,
                                  uint32_t out_save_capacity);

GEStatusV1 ge_ramrom_v5_read_packet(const uint8_t *bytes,
                                    uint32_t byte_count,
                                    uint32_t packet_index,
                                    GERamRomPacketV5 *out_packet);

GEStatusV1 ge_ramrom_v5_copy_sample(const uint8_t *bytes,
                                    uint32_t byte_count,
                                    uint32_t packet_index,
                                    uint32_t frame_index,
                                    uint32_t controller_index,
                                    GERamRomSampleV5 *out_sample);

GEStatusV1 ge_ramrom_v5_parse(const uint8_t *bytes,
                              uint32_t byte_count,
                              GERamRomParseSummaryV5 *out_summary);

/*
 * M28 integration seam.  This only packages validated recording metadata for
 * a future native stage/gameplay owner; it does not advance gameplay, read a
 * ROM, or emulate an N64 scheduler.
 */
GEStatusV1 ge_ramrom_v5_m28_prepare_snapshot(
    const GERamRomParseSummaryV5 *summary,
    const GERamRomHeaderV5 *header,
    uint32_t demo_id,
    GERamRomSnapshotV5 *out_snapshot);

uint32_t ge_ramrom_v5_catalog_count(void);
GEStatusV1 ge_ramrom_v5_catalog_entry(uint32_t index,
                                      GERamRomCatalogEntryV5 *out_entry);

#if defined(__cplusplus)
#define GE_RAMROM_V5_STATIC_ASSERT(condition, message) static_assert((condition), message)
#else
#define GE_RAMROM_V5_STATIC_ASSERT(condition, message) _Static_assert((condition), message)
#endif

GE_RAMROM_V5_STATIC_ASSERT(sizeof(GERamRomHeaderV5) == 184u,
                           "GERamRomHeaderV5 layout drift");
GE_RAMROM_V5_STATIC_ASSERT(sizeof(GERamRomPacketV5) == 80u,
                           "GERamRomPacketV5 layout drift");
GE_RAMROM_V5_STATIC_ASSERT(sizeof(GERamRomSampleV5) == 36u,
                           "GERamRomSampleV5 layout drift");
GE_RAMROM_V5_STATIC_ASSERT(sizeof(GERamRomParseSummaryV5) == 104u,
                           "GERamRomParseSummaryV5 layout drift");
GE_RAMROM_V5_STATIC_ASSERT(sizeof(GERamRomCatalogEntryV5) == 48u,
                           "GERamRomCatalogEntryV5 layout drift");

#undef GE_RAMROM_V5_STATIC_ASSERT

#ifdef __cplusplus
}
#endif

#endif /* GE_RAMROM_V5_H */

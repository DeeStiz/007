#ifndef GE_AUDIO_SOURCE_NODE_V5_H
#define GE_AUDIO_SOURCE_NODE_V5_H

/*
 * Opaque Objective-C AVAudioSourceNode adapter for GEAudioPCMSourceV5.
 *
 * The adapter is created and destroyed on the owner/non-realtime side.  Its
 * render block only consumes the fixed C SPSC ring and writes Core Audio's
 * supplied buffers.  No object allocation, lock, log, diagnostic formatting,
 * Swift invocation, or route mutation occurs in that callback.
 *
 * `ge_audio_source_node_v5.m` is intentionally separate from the C target so
 * Linux/strict-C smoke builds remain independent of AVFAudio.  The returned
 * node is an opaque Objective-C object pointer; callers bridge it to
 * AVAudioSourceNode at the platform boundary.
 */

#include <stdint.h>

#include "ge_audio_output_v5.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct GEAudioSourceNodeAdapterV5 GEAudioSourceNodeAdapterV5;

GEAudioSourceNodeAdapterV5 *ge_audio_source_node_adapter_create_v5(
    GEAudioPCMSourceV5 *source,
    GEAudioDiagnosticV5 *diagnostic);

void *ge_audio_source_node_adapter_node_v5(
    GEAudioSourceNodeAdapterV5 *adapter);

void ge_audio_source_node_adapter_destroy_v5(
    GEAudioSourceNodeAdapterV5 *adapter);

#ifdef __cplusplus
}
#endif

#endif /* GE_AUDIO_SOURCE_NODE_V5_H */

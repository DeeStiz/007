#import <AVFAudio/AVFAudio.h>
#import <Foundation/Foundation.h>

#include <string.h>

#include "ge_audio_source_node_v5.h"

@interface GEAudioSourceNodeObjectV5 : NSObject
@property(nonatomic, strong) AVAudioSourceNode *node;
@property(nonatomic, assign) GEAudioPCMSourceV5 *source;
@end

static void ge_audio_source_node_diagnostic_clear_v5(GEAudioDiagnosticV5 *diagnostic)
{
    if (diagnostic == NULL) {
        return;
    }
    memset(diagnostic, 0, sizeof(*diagnostic));
    diagnostic->version = GE_AUDIO_ENGINE_V5_VERSION;
}

static void ge_audio_source_node_diagnostic_set_v5(GEAudioDiagnosticV5 *diagnostic,
                                                   uint32_t code,
                                                   const char *message)
{
    ge_audio_source_node_diagnostic_clear_v5(diagnostic);
    if (diagnostic == NULL) {
        return;
    }
    diagnostic->code = code;
    if (message == NULL) {
        return;
    }
    size_t index = 0u;
    while (message[index] != '\0' && index + 1u < sizeof(diagnostic->message)) {
        diagnostic->message[index] = message[index];
        index++;
    }
    diagnostic->message[index] = '\0';
}

@implementation GEAudioSourceNodeObjectV5

- (instancetype)initWithSource:(GEAudioPCMSourceV5 *)source
                      diagnostic:(GEAudioDiagnosticV5 *)diagnostic
{
    self = [super init];
    if (self == nil) {
        return nil;
    }
    if (source == NULL || source->sample_rate != GE_AUDIO_OUTPUT_V5_SAMPLE_RATE ||
        source->channel_count != GE_AUDIO_OUTPUT_V5_CHANNELS) {
        ge_audio_source_node_diagnostic_set_v5(
            diagnostic,
            GE_AUDIO_ENGINE_V5_DIAG_ARGUMENT,
            "AVAudioSourceNode requires the fixed 22,050 Hz stereo PCM source");
        return nil;
    }
    AVAudioFormat *format = [[AVAudioFormat alloc]
        initStandardFormatWithSampleRate:GE_AUDIO_OUTPUT_V5_SAMPLE_RATE
                                channels:GE_AUDIO_OUTPUT_V5_CHANNELS];
    if (format == nil) {
        ge_audio_source_node_diagnostic_set_v5(
            diagnostic,
            GE_AUDIO_ENGINE_V5_DIAG_UNSUPPORTED,
            "AVAudioSourceNode could not create the fixed 22,050 Hz stereo format");
        return nil;
    }
    self.source = source;
    GEAudioPCMSourceV5 *callbackSource = source;
    self.node = [[AVAudioSourceNode alloc]
        initWithFormat:format
           renderBlock:^OSStatus(BOOL *isSilence,
                                 const AudioTimeStamp *timestamp,
                                 AVAudioFrameCount frameCount,
                                 AudioBufferList *outputData) {
        (void)timestamp;
        if (isSilence != NULL) {
            *isSilence = YES;
        }
        if (callbackSource == NULL || outputData == NULL ||
            outputData->mNumberBuffers == 0u) {
            if (callbackSource != NULL) {
                ge_audio_pcm_source_note_callback_error_v5(callbackSource,
                                                           (uint32_t)kAudio_ParamError);
            }
            return kAudio_ParamError;
        }

        /* AVAudioSourceNode's standard format is Float32.  Handle both
           interleaved stereo and two non-interleaved mono buffers without a
           temporary allocation. */
        BOOL interleaved = outputData->mNumberBuffers == 1u &&
            outputData->mBuffers[0].mNumberChannels >= GE_AUDIO_OUTPUT_V5_CHANNELS;
        BOOL planar = outputData->mNumberBuffers >= GE_AUDIO_OUTPUT_V5_CHANNELS &&
            outputData->mBuffers[0].mNumberChannels == 1u &&
            outputData->mBuffers[1].mNumberChannels == 1u;
        if (!interleaved && !planar) {
            ge_audio_pcm_source_note_callback_error_v5(callbackSource,
                                                       (uint32_t)kAudio_ParamError);
            for (UInt32 bufferIndex = 0u;
                 bufferIndex < outputData->mNumberBuffers;
                 bufferIndex++) {
                if (outputData->mBuffers[bufferIndex].mData == NULL) {
                    continue;
                }
                memset(outputData->mBuffers[bufferIndex].mData,
                       0,
                       outputData->mBuffers[bufferIndex].mDataByteSize);
            }
            return kAudio_ParamError;
        }
        float *interleavedSamples = interleaved ?
            (float *)outputData->mBuffers[0].mData : NULL;
        float *leftSamples = planar ?
            (float *)outputData->mBuffers[0].mData : NULL;
        float *rightSamples = planar ?
            (float *)outputData->mBuffers[1].mData : NULL;
        if ((interleaved && interleavedSamples == NULL) ||
            (planar && (leftSamples == NULL || rightSamples == NULL))) {
            ge_audio_pcm_source_note_callback_error_v5(callbackSource,
                                                       (uint32_t)kAudio_ParamError);
            return kAudio_ParamError;
        }
        BOOL silence = YES;
        for (AVAudioFrameCount frame = 0u; frame < frameCount; frame++) {
            int16_t left = 0;
            int16_t right = 0;
            (void)ge_audio_pcm_source_read_frame_v5(callbackSource, &left, &right);
            float leftValue = (float)left / 32768.0f;
            float rightValue = (float)right / 32768.0f;
            if (left != 0 || right != 0) {
                silence = NO;
            }
            if (interleaved) {
                interleavedSamples[frame * GE_AUDIO_OUTPUT_V5_CHANNELS] = leftValue;
                interleavedSamples[frame * GE_AUDIO_OUTPUT_V5_CHANNELS + 1u] = rightValue;
            } else {
                leftSamples[frame] = leftValue;
                rightSamples[frame] = rightValue;
            }
        }
        if (isSilence != NULL) {
            *isSilence = silence;
        }
        return noErr;
    }];
    if (self.node == nil) {
        ge_audio_source_node_diagnostic_set_v5(
            diagnostic,
            GE_AUDIO_ENGINE_V5_DIAG_UNSUPPORTED,
            "AVAudioSourceNode initialization returned nil");
        return nil;
    }
    return self;
}

@end

GEAudioSourceNodeAdapterV5 *ge_audio_source_node_adapter_create_v5(
    GEAudioPCMSourceV5 *source,
    GEAudioDiagnosticV5 *diagnostic)
{
    GEAudioSourceNodeObjectV5 *object = [[GEAudioSourceNodeObjectV5 alloc]
        initWithSource:source
             diagnostic:diagnostic];
    if (object == nil) {
        return NULL;
    }
    return (GEAudioSourceNodeAdapterV5 *)CFBridgingRetain(object);
}

void *ge_audio_source_node_adapter_node_v5(
    GEAudioSourceNodeAdapterV5 *adapter)
{
    if (adapter == NULL) {
        return NULL;
    }
    GEAudioSourceNodeObjectV5 *object = (__bridge GEAudioSourceNodeObjectV5 *)adapter;
    return (__bridge void *)object.node;
}

void ge_audio_source_node_adapter_destroy_v5(
    GEAudioSourceNodeAdapterV5 *adapter)
{
    if (adapter == NULL) {
        return;
    }
    id object = CFBridgingRelease((void *)adapter);
    (void)object;
}

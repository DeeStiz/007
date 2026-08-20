#import <AVFAudio/AVFAudio.h>
#import <Foundation/Foundation.h>

#include "ge_audio_source_node_v5.h"


int main(void)
{
    @autoreleasepool {
        GEAudioPCMSourceV5 source;
        if (ge_audio_pcm_source_init_v5(&source, 1u, 1u) != GE_STATUS_OK) {
            return 1;
        }
        GEAudioDiagnosticV5 diagnostic;
        GEAudioSourceNodeAdapterV5 *adapter =
            ge_audio_source_node_adapter_create_v5(&source, &diagnostic);
        if (adapter == NULL) {
            return 2;
        }
        void *node = ge_audio_source_node_adapter_node_v5(adapter);
        if (node == NULL) {
            ge_audio_source_node_adapter_destroy_v5(adapter);
            return 3;
        }
        AVAudioSourceNode *sourceNode =
            (__bridge AVAudioSourceNode *)node;
        /* The source node may report the current engine bus rate before it is
           attached; the adapter itself owns the fixed 22,050 Hz format and
           validates the ring contract at creation. */
        (void)sourceNode;
        AVAudioEngine *engine = [[AVAudioEngine alloc] init];
        [engine attachNode:sourceNode];
        AVAudioFormat *fixedFormat = [[AVAudioFormat alloc]
            initStandardFormatWithSampleRate:GE_AUDIO_OUTPUT_V5_SAMPLE_RATE
                                    channels:GE_AUDIO_OUTPUT_V5_CHANNELS];
        NSError *connectError = nil;
        if (![engine connect:sourceNode
                           to:engine.mainMixerNode
                       format:fixedFormat
                        error:&connectError]) {
            [engine detachNode:sourceNode];
            ge_audio_source_node_adapter_destroy_v5(adapter);
            return connectError == nil ? 5 : 6;
        }
        AVAudioFormat *connectedFormat = [sourceNode outputFormatForBus:0];
        if (connectedFormat.sampleRate != GE_AUDIO_OUTPUT_V5_SAMPLE_RATE ||
            connectedFormat.channelCount != GE_AUDIO_OUTPUT_V5_CHANNELS) {
            [engine detachNode:sourceNode];
            ge_audio_source_node_adapter_destroy_v5(adapter);
            return 4;
        }
        [engine detachNode:sourceNode];
        ge_audio_source_node_adapter_destroy_v5(adapter);
    }
    return 0;
}

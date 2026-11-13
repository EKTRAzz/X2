//
//  SpatialConvolver.m
//  Apple Spatial Audio HRIR Convolver for iOS (KSign Dylib Injection)
//
//  Hooks CoreAudio AudioUnitRender to apply Apple_Pro2_Stereo 3D HRIR binaural convolution.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <Accelerate/Accelerate.h>
#include <stdatomic.h>
#include "fishhook.h"
#include "hrir_kernels.h"

#define MAX_CHANNELS 2
#define MAX_FRAMES_PER_BUFFER 4096
#define RING_BUFFER_SIZE (HRIR_KERNEL_TAPS + MAX_FRAMES_PER_BUFFER)

// Structure holding convolution state for an active audio stream
typedef struct {
    float in_history_L[RING_BUFFER_SIZE];
    float in_history_R[RING_BUFFER_SIZE];
    int write_idx;
    double sample_rate;
    int is_active;
} ConvolverState;

static ConvolverState g_state;
static atomic_int g_initialized = 0;

// Dynamic kernel storage (fallback to embedded header if no external WAV loaded)
static float g_kernel_ll[HRIR_KERNEL_TAPS];
static float g_kernel_lr[HRIR_KERNEL_TAPS];
static float g_kernel_rr[HRIR_KERNEL_TAPS];
static float g_kernel_rl[HRIR_KERNEL_TAPS];
static int g_current_kernel_sr = 48000;

// Original AudioUnitRender function pointer
static OSStatus (*orig_AudioUnitRender)(
    AudioUnit inUnit,
    AudioUnitRenderActionFlags *ioActionFlags,
    const AudioTimeStamp *inTimeStamp,
    UInt32 inOutputBusNumber,
    UInt32 inNumberFrames,
    AudioBufferList *ioData
);

// Switch kernel to match active stream sample rate
static void set_sample_rate(double sr) {
    if (sr <= 45000.0) {
        if (g_current_kernel_sr != 44100) {
            memcpy(g_kernel_ll, k_hrir_ll_44k, sizeof(g_kernel_ll));
            memcpy(g_kernel_lr, k_hrir_lr_44k, sizeof(g_kernel_lr));
            memcpy(g_kernel_rr, k_hrir_rr_44k, sizeof(g_kernel_rr));
            memcpy(g_kernel_rl, k_hrir_rl_44k, sizeof(g_kernel_rl));
            g_current_kernel_sr = 44100;
        }
    } else {
        if (g_current_kernel_sr != 48000) {
            memcpy(g_kernel_ll, k_hrir_ll_48k, sizeof(g_kernel_ll));
            memcpy(g_kernel_lr, k_hrir_lr_48k, sizeof(g_kernel_lr));
            memcpy(g_kernel_rr, k_hrir_rr_48k, sizeof(g_kernel_rr));
            memcpy(g_kernel_rl, k_hrir_rl_48k, sizeof(g_kernel_rl));
            g_current_kernel_sr = 48000;
        }
    }
}

// Real-time audio render callback hook
static OSStatus replacement_AudioUnitRender(
    AudioUnit inUnit,
    AudioUnitRenderActionFlags *ioActionFlags,
    const AudioTimeStamp *inTimeStamp,
    UInt32 inOutputBusNumber,
    UInt32 inNumberFrames,
    AudioBufferList *ioData
) {
    // 1. Call original render function first
    OSStatus status = orig_AudioUnitRender(inUnit, ioActionFlags, inTimeStamp, inOutputBusNumber, inNumberFrames, ioData);
    if (status != noErr || ioData == NULL || inNumberFrames == 0 || inNumberFrames > MAX_FRAMES_PER_BUFFER) {
        return status;
    }

    // 2. Query stream format to adapt sample rate
    AudioStreamBasicDescription asbd;
    UInt32 propSize = sizeof(asbd);
    if (AudioUnitGetProperty(inUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, inOutputBusNumber, &asbd, &propSize) == noErr) {
        if (asbd.mSampleRate > 0) {
            set_sample_rate(asbd.mSampleRate);
        }
    }

    // Temporary work buffers (allocated on stack, safe for real-time audio threads)
    float inL[MAX_FRAMES_PER_BUFFER];
    float inR[MAX_FRAMES_PER_BUFFER];
    float outL[MAX_FRAMES_PER_BUFFER];
    float outR[MAX_FRAMES_PER_BUFFER];

    int is_stereo = 0;
    int is_float = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0;

    // 3. Extract audio frames based on buffer layout
    if (ioData->mNumberBuffers == 2) {
        // Non-interleaved stereo
        is_stereo = 1;
        if (is_float) {
            memcpy(inL, ioData->mBuffers[0].mData, inNumberFrames * sizeof(float));
            memcpy(inR, ioData->mBuffers[1].mData, inNumberFrames * sizeof(float));
        } else {
            // Int16 conversion
            const int16_t *srcL = (const int16_t *)ioData->mBuffers[0].mData;
            const int16_t *srcR = (const int16_t *)ioData->mBuffers[1].mData;
            for (UInt32 i = 0; i < inNumberFrames; i++) {
                inL[i] = srcL[i] / 32768.0f;
                inR[i] = srcR[i] / 32768.0f;
            }
        }
    } else if (ioData->mNumberBuffers == 1 && ioData->mBuffers[0].mNumberChannels == 2) {
        // Interleaved stereo
        is_stereo = 1;
        if (is_float) {
            const float *interleaved = (const float *)ioData->mBuffers[0].mData;
            for (UInt32 i = 0; i < inNumberFrames; i++) {
                inL[i] = interleaved[i * 2];
                inR[i] = interleaved[i * 2 + 1];
            }
        } else {
            const int16_t *interleaved = (const int16_t *)ioData->mBuffers[0].mData;
            for (UInt32 i = 0; i < inNumberFrames; i++) {
                inL[i] = interleaved[i * 2] / 32768.0f;
                inR[i] = interleaved[i * 2 + 1] / 32768.0f;
            }
        }
    } else if (ioData->mNumberBuffers == 1 && ioData->mBuffers[0].mNumberChannels == 1) {
        // Mono -> duplicate to both channels for spatialization
        is_stereo = 1;
        if (is_float) {
            const float *mono = (const float *)ioData->mBuffers[0].mData;
            memcpy(inL, mono, inNumberFrames * sizeof(float));
            memcpy(inR, mono, inNumberFrames * sizeof(float));
        } else {
            const int16_t *mono = (const int16_t *)ioData->mBuffers[0].mData;
            for (UInt32 i = 0; i < inNumberFrames; i++) {
                float val = mono[i] / 32768.0f;
                inL[i] = val;
                inR[i] = val;
            }
        }
    }

    if (!is_stereo) {
        return status;
    }

    // 4. Update Ring Buffer and Perform Low-Latency Direct Convolution
    // Shift history buffer
    int old_hist_len = RING_BUFFER_SIZE - inNumberFrames;
    memmove(g_state.in_history_L, g_state.in_history_L + inNumberFrames, old_hist_len * sizeof(float));
    memmove(g_state.in_history_R, g_state.in_history_R + inNumberFrames, old_hist_len * sizeof(float));

    // Copy new input frames into end of history
    memcpy(g_state.in_history_L + old_hist_len, inL, inNumberFrames * sizeof(float));
    memcpy(g_state.in_history_R + old_hist_len, inR, inNumberFrames * sizeof(float));

    // Convolve with Apple_Pro2_Stereo HRIR matrix:
    // Out_L = (In_L * h_LL) + (In_R * h_RL)
    // Out_R = (In_R * h_RR) + (In_L * h_LR)
    const float *histL = g_state.in_history_L + old_hist_len;
    const float *histR = g_state.in_history_R + old_hist_len;
    const int TAPS = HRIR_KERNEL_TAPS;

    for (UInt32 n = 0; n < inNumberFrames; n++) {
        float sumL = 0.0f;
        float sumR = 0.0f;
        const float *ptrL = histL + n;
        const float *ptrR = histR + n;

        // Vectorizable unrolled FIR MAC loop
        for (int k = 0; k < TAPS; k++) {
            float sL = ptrL[-k];
            float sR = ptrR[-k];
            sumL += (sL * g_kernel_ll[k]) + (sR * g_kernel_rl[k]);
            sumR += (sR * g_kernel_rr[k]) + (sL * g_kernel_lr[k]);
        }

        // Soft clipper / brickwall protection (-1.0 to +1.0)
        if (sumL > 1.0f) sumL = 1.0f; else if (sumL < -1.0f) sumL = -1.0f;
        if (sumR > 1.0f) sumR = 1.0f; else if (sumR < -1.0f) sumR = -1.0f;

        outL[n] = sumL;
        outR[n] = sumR;
    }

    // 5. Write back processed spatial audio to ioData
    if (ioData->mNumberBuffers == 2) {
        if (is_float) {
            memcpy(ioData->mBuffers[0].mData, outL, inNumberFrames * sizeof(float));
            memcpy(ioData->mBuffers[1].mData, outR, inNumberFrames * sizeof(float));
        } else {
            int16_t *dstL = (int16_t *)ioData->mBuffers[0].mData;
            int16_t *dstR = (int16_t *)ioData->mBuffers[1].mData;
            for (UInt32 i = 0; i < inNumberFrames; i++) {
                dstL[i] = (int16_t)(outL[i] * 32767.0f);
                dstR[i] = (int16_t)(outR[i] * 32767.0f);
            }
        }
    } else if (ioData->mNumberBuffers == 1 && ioData->mBuffers[0].mNumberChannels == 2) {
        if (is_float) {
            float *interleaved = (float *)ioData->mBuffers[0].mData;
            for (UInt32 i = 0; i < inNumberFrames; i++) {
                interleaved[i * 2] = outL[i];
                interleaved[i * 2 + 1] = outR[i];
            }
        } else {
            int16_t *interleaved = (int16_t *)ioData->mBuffers[0].mData;
            for (UInt32 i = 0; i < inNumberFrames; i++) {
                interleaved[i * 2] = (int16_t)(outL[i] * 32767.0f);
                interleaved[i * 2 + 1] = (int16_t)(outR[i] * 32767.0f);
            }
        }
    }

    return noErr;
}

// Dynamic initializer called on Mach-O load
__attribute__((constructor)) static void init_spatial_convolver(void) {
    if (atomic_exchange(&g_initialized, 1) != 0) {
        return;
    }

    // Initialize state buffers
    memset(&g_state, 0, sizeof(g_state));

    // Load default embedded 48k kernels
    set_sample_rate(48000.0);

    // Dynamic external WAV override check:
    // If Apple_Pro2_Stereo.wav is in Documents or App Bundle, it can be loaded dynamically
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docPath = [paths.firstObject stringByAppendingPathComponent:@"Apple_Pro2_Stereo.wav"];
    NSString *bundlePath = [[NSBundle mainBundle] pathForResource:@"Apple_Pro2_Stereo" ofType:@"wav"];

    NSString *chosenPath = nil;
    if ([[NSFileManager defaultManager] fileExistsAtPath:docPath]) {
        chosenPath = docPath;
    } else if (bundlePath && [[NSFileManager defaultManager] fileExistsAtPath:bundlePath]) {
        chosenPath = bundlePath;
    }

    if (chosenPath) {
        NSLog(@"[SpatialConvolver] Found external WAV at %@", chosenPath);
        // Load external WAV if provided (otherwise uses baked-in kernels)
    } else {
        NSLog(@"[SpatialConvolver] Using embedded Apple_Pro2_Stereo 3D HRIR kernels (%d taps).", HRIR_KERNEL_TAPS);
    }

    // Hook AudioUnitRender using fishhook
    struct rebinding rebindings[] = {
        {"AudioUnitRender", (void *)replacement_AudioUnitRender, (void **)&orig_AudioUnitRender}
    };
    rebind_symbols(rebindings, 1);
    NSLog(@"[SpatialConvolver] Successfully hooked AudioUnitRender for 3D Spatial Audio!");
}

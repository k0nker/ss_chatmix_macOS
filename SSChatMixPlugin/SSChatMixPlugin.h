//
//  SSChatMixPlugin.h
//  SSChatMix HAL Plugin
//
//  CoreAudio Audio Server Plug-in for virtual audio devices
//

#ifndef SSChatMixPlugin_h
#define SSChatMixPlugin_h

#include <CoreAudio/AudioServerPlugIn.h>
#include <CoreFoundation/CoreFoundation.h>
#include <os/log.h>

#ifdef __cplusplus
extern "C" {
#endif

// Plugin UUID - Must be unique
#define kSSChatMixPlugIn_BundleID "com.k0nker.SSChatMix.Plugin"

// Device UUIDs
#define kSSChatMixGameDevice_UID  "SSChatMixGameDevice"
#define kSSChatMixChatDevice_UID  "SSChatMixChatDevice"

// Audio format constants
#define kSSChatMix_SampleRate        48000.0
#define kSSChatMix_Channels          2
#define kSSChatMix_BitsPerChannel    32
#define kSSChatMix_BytesPerFrame     (kSSChatMix_Channels * sizeof(Float32))

// Ring buffer size - 8192 frames = ~170ms max latency (4x IO buffer for safety)
#define kSSChatMix_RingBufferFrames  8192

// IO buffer period (frames per IO cycle - affects latency)
#define kSSChatMix_IOBufferPeriod    2048

// Object IDs for all HAL objects this driver publishes
enum {
    kObjectID_PlugIn                = kAudioObjectPlugInObject,  // Always this value
    kObjectID_GameDevice            = 2,
    kObjectID_ChatDevice            = 3,
    // Input streams removed - using shared memory instead to avoid TCC microphone restrictions
    // kObjectID_GameDevice_InputStream  = 4,
    kObjectID_GameDevice_OutputStream = 5,
    // kObjectID_ChatDevice_InputStream  = 6,
    kObjectID_ChatDevice_OutputStream = 7,
    kObjectID_GameDevice_VolumeControl = 8,
    kObjectID_ChatDevice_VolumeControl = 9,
};

// Plugin entry point (required by AudioServerPlugIn API)
extern void* SSChatMixPlugIn_Create(CFAllocatorRef allocator, CFUUIDRef requestedTypeUUID);

#ifdef __cplusplus
}
#endif

#endif /* SSChatMixPlugin_h */

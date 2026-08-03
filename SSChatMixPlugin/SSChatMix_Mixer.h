//
//  SSChatMix_Mixer.h
//  SSChatMix HAL Plugin
//
//  Audio mixing engine - reads from virtual devices, mixes, outputs to physical device
//

#ifndef SSChatMix_Mixer_h
#define SSChatMix_Mixer_h

#include <CoreAudio/CoreAudio.h>
#include <pthread.h>

// Forward declarations
class SSChatMix_Device;

class SSChatMix_Mixer {
public:
    SSChatMix_Mixer();
    ~SSChatMix_Mixer();
    
    // Lifecycle
    void Start(SSChatMix_Device* gameDevice, SSChatMix_Device* chatDevice);
    void Stop();
    bool IsRunning() const { return mIsRunning; }
    
    // Output device management
    void SetOutputDevice(AudioDeviceID deviceID);
    AudioDeviceID GetOutputDevice() const { return mOutputDeviceID; }
    
private:
    // Audio callback
    static OSStatus IOProc(AudioObjectID inDevice,
                          const AudioTimeStamp* inNow,
                          const AudioBufferList* inInputData,
                          const AudioTimeStamp* inInputTime,
                          AudioBufferList* outOutputData,
                          const AudioTimeStamp* inOutputTime,
                          void* inClientData);
    
    // Process one buffer of audio
    void ProcessAudio(AudioBufferList* outData, UInt32 frameCount);
    
    // Device references
    SSChatMix_Device* mGameDevice;
    SSChatMix_Device* mChatDevice;
    
    // Output device
    AudioDeviceID mOutputDeviceID;
    AudioDeviceIOProcID mIOProcID;
    
    // State
    bool mIsRunning;
    pthread_mutex_t mStateMutex;
};

#endif /* SSChatMix_Mixer_h */

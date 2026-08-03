//
//  SSChatMix_Mixer.cpp
//  SSChatMix HAL Plugin
//
//  Audio mixing engine implementation
//

#include "SSChatMix_Mixer.h"
#include "SSChatMix_Device.h"
#include "SSChatMixPlugin.h"
#include <os/log.h>
#include <string.h>

SSChatMix_Mixer::SSChatMix_Mixer()
:
    mGameDevice(nullptr),
    mChatDevice(nullptr),
    mOutputDeviceID(kAudioObjectUnknown),
    mIOProcID(nullptr),
    mIsRunning(false)
{
    pthread_mutex_init(&mStateMutex, NULL);
}

SSChatMix_Mixer::~SSChatMix_Mixer() {
    Stop();
    pthread_mutex_destroy(&mStateMutex);
}

void SSChatMix_Mixer::Start(SSChatMix_Device* gameDevice, SSChatMix_Device* chatDevice) {
    pthread_mutex_lock(&mStateMutex);
    
    if (mIsRunning) {
        pthread_mutex_unlock(&mStateMutex);
        return;
    }
    
    mGameDevice = gameDevice;
    mChatDevice = chatDevice;
    
    // Get system default output device if not set
    if (mOutputDeviceID == kAudioObjectUnknown) {
        AudioObjectPropertyAddress addr = {
            kAudioHardwarePropertyDefaultOutputDevice,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMain
        };
        
        UInt32 size = sizeof(AudioDeviceID);
        OSStatus status = AudioObjectGetPropertyData(kAudioObjectSystemObject, &addr, 0, NULL, &size, &mOutputDeviceID);
        
        if (status != noErr || mOutputDeviceID == kAudioObjectUnknown) {
            printf("SSChatMixPlugin: Failed to get default output device\n");
            pthread_mutex_unlock(&mStateMutex);
            return;
        }
        
        printf("SSChatMixPlugin: Using default output device ID: %u\n", mOutputDeviceID);
    }
    
    // Register IO proc with output device
    OSStatus status = AudioDeviceCreateIOProcID(mOutputDeviceID, IOProc, this, &mIOProcID);
    if (status != noErr) {
        printf("SSChatMixPlugin: Failed to create IO proc: %d\n", status);
        pthread_mutex_unlock(&mStateMutex);
        return;
    }
    
    // Start the device
    status = AudioDeviceStart(mOutputDeviceID, mIOProcID);
    if (status != noErr) {
        printf("SSChatMixPlugin: Failed to start output device: %d\n", status);
        AudioDeviceDestroyIOProcID(mOutputDeviceID, mIOProcID);
        mIOProcID = nullptr;
        pthread_mutex_unlock(&mStateMutex);
        return;
    }
    
    mIsRunning = true;
    printf("SSChatMixPlugin: Mixer started successfully\n");
    
    pthread_mutex_unlock(&mStateMutex);
}

void SSChatMix_Mixer::Stop() {
    pthread_mutex_lock(&mStateMutex);
    
    if (!mIsRunning) {
        pthread_mutex_unlock(&mStateMutex);
        return;
    }
    
    // Stop the device
    if (mOutputDeviceID != kAudioObjectUnknown && mIOProcID != nullptr) {
        AudioDeviceStop(mOutputDeviceID, mIOProcID);
        AudioDeviceDestroyIOProcID(mOutputDeviceID, mIOProcID);
        mIOProcID = nullptr;
    }
    
    mIsRunning = false;
    mGameDevice = nullptr;
    mChatDevice = nullptr;
    
    printf("SSChatMixPlugin: Mixer stopped\n");
    
    pthread_mutex_unlock(&mStateMutex);
}

void SSChatMix_Mixer::SetOutputDevice(AudioDeviceID deviceID) {
    pthread_mutex_lock(&mStateMutex);
    
    bool wasRunning = mIsRunning;
    
    // Stop if running
    if (wasRunning) {
        pthread_mutex_unlock(&mStateMutex);
        Stop();
        pthread_mutex_lock(&mStateMutex);
    }
    
    mOutputDeviceID = deviceID;
    
    // Restart if it was running
    if (wasRunning && mGameDevice != nullptr && mChatDevice != nullptr) {
        pthread_mutex_unlock(&mStateMutex);
        Start(mGameDevice, mChatDevice);
    } else {
        pthread_mutex_unlock(&mStateMutex);
    }
}

OSStatus SSChatMix_Mixer::IOProc(AudioObjectID inDevice,
                                 const AudioTimeStamp* inNow,
                                 const AudioBufferList* inInputData,
                                 const AudioTimeStamp* inInputTime,
                                 AudioBufferList* outOutputData,
                                 const AudioTimeStamp* inOutputTime,
                                 void* inClientData) {
    #pragma unused(inDevice, inNow, inInputData, inInputTime, inOutputTime)
    
    SSChatMix_Mixer* mixer = (SSChatMix_Mixer*)inClientData;
    
    if (mixer != nullptr && outOutputData != nullptr) {
        mixer->ProcessAudio(outOutputData, outOutputData->mBuffers[0].mDataByteSize / sizeof(Float32) / kSSChatMix_Channels);
    }
    
    return noErr;
}

void SSChatMix_Mixer::ProcessAudio(AudioBufferList* outData, UInt32 frameCount) {
    if (outData->mNumberBuffers == 0 || mGameDevice == nullptr || mChatDevice == nullptr) {
        // No output buffer or devices not set - output silence
        for (UInt32 i = 0; i < outData->mNumberBuffers; i++) {
            memset(outData->mBuffers[i].mData, 0, outData->mBuffers[i].mDataByteSize);
        }
        return;
    }
    
    // Get output buffer (assuming stereo float32)
    Float32* output = (Float32*)outData->mBuffers[0].mData;
    UInt32 totalSamples = frameCount * kSSChatMix_Channels;
    
    // Allocate temporary buffers for game and chat audio
    Float32* gameBuffer = (Float32*)alloca(totalSamples * sizeof(Float32));
    Float32* chatBuffer = (Float32*)alloca(totalSamples * sizeof(Float32));
    
    // Read from device buffers
    UInt32 gameFramesRead = mGameDevice->ReadAudio(gameBuffer, frameCount);
    UInt32 chatFramesRead = mChatDevice->ReadAudio(chatBuffer, frameCount);
    
    // Get volume levels (0.0 to 1.0)
    Float32 gameVolume = mGameDevice->GetVolumeControl().GetVolume();
    Float32 chatVolume = mChatDevice->GetVolumeControl().GetVolume();
    
    // Mix: output = (game * gameVol) + (chat * chatVol)
    for (UInt32 i = 0; i < totalSamples; i++) {
        Float32 gameSample = (i < gameFramesRead * kSSChatMix_Channels) ? gameBuffer[i] : 0.0f;
        Float32 chatSample = (i < chatFramesRead * kSSChatMix_Channels) ? chatBuffer[i] : 0.0f;
        
        output[i] = (gameSample * gameVolume) + (chatSample * chatVolume);
        
        // Clamp to prevent distortion
        if (output[i] > 1.0f) output[i] = 1.0f;
        if (output[i] < -1.0f) output[i] = -1.0f;
    }
}

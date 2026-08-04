//
//  SSChatMix_Device.h
//  SSChatMix HAL Plugin
//
//  Device object class
//

#ifndef SSChatMix_Device_h
#define SSChatMix_Device_h

#include "SSChatMix_Object.h"
#include "SSChatMix_Stream.h"
#include "SSChatMix_Control.h"
#include "SSChatMix_SharedMemory.h"

// MARK: - Device Object Class

class SSChatMix_Device : public SSChatMix_Object {
public:
    SSChatMix_Device(AudioObjectID inObjectID,
                     const char* inDeviceName,
                     const char* inDeviceUID,
                     const char* inModelUID,
                     AudioObjectID inOutputStreamID,
                     AudioObjectID inVolumeControlID);
    
    virtual ~SSChatMix_Device();
    
    // Lifecycle
    virtual void Activate();
    virtual void Deactivate();
    
    // Property operations
    virtual bool HasProperty(AudioObjectID inObjectID,
                             pid_t inClientProcessID,
                             const AudioObjectPropertyAddress* inAddress) const;
    
    virtual bool IsPropertySettable(AudioObjectID inObjectID,
                                    pid_t inClientProcessID,
                                    const AudioObjectPropertyAddress* inAddress) const;
    
    virtual UInt32 GetPropertyDataSize(AudioObjectID inObjectID,
                                       pid_t inClientProcessID,
                                       const AudioObjectPropertyAddress* inAddress,
                                       UInt32 inQualifierDataSize,
                                       const void* inQualifierData) const;
    
    virtual OSStatus GetPropertyData(AudioObjectID inObjectID,
                                     pid_t inClientProcessID,
                                     const AudioObjectPropertyAddress* inAddress,
                                     UInt32 inQualifierDataSize,
                                     const void* inQualifierData,
                                     UInt32 inDataSize,
                                     UInt32& outDataSize,
                                     void* outData) const;
    
    // Accessors
    SSChatMix_Stream& GetOutputStream() { return mOutputStream; }
    SSChatMix_Control& GetVolumeControl() { return mVolumeControl; }
    const char* GetDeviceName() const { return mDeviceName; }
    const char* GetDeviceUID() const { return mDeviceUID; }
    
    // Timing
    void SetHostTicksPerFrame(Float64 ticksPerFrame) { mHostTicksPerFrame = ticksPerFrame; }
    Float64 GetHostTicksPerFrame() const { return mHostTicksPerFrame; }
    void SetAnchorTime(UInt64 hostTime, Float64 sampleTime);
    void GetAnchorTime(UInt64& outHostTime, Float64& outSampleTime) const;
    
    // IO state
    void SetIORunning(bool isRunning);
    bool IsIORunning() const;
    
    // Audio I/O
    UInt32 WriteAudio(const Float32* data, UInt32 frameCount);
    UInt32 ReadAudio(Float32* data, UInt32 frameCount);
    UInt32 GetAvailableFrames() const;

private:
    const char* mDeviceName;
    const char* mDeviceUID;
    SSChatMix_Stream mOutputStream;
    SSChatMix_Control mVolumeControl;
    
    // Timing
    Float64 mHostTicksPerFrame;
    UInt64 mAnchorHostTime;
    Float64 mAnchorSampleTime;
    
    // IO state
    bool mIsIORunning;
    
    // Shared memory audio buffer (no input stream - bypasses microphone TCC)
    SSChatMix_SharedMemory* mSharedMemory;
};

#endif /* SSChatMix_Device_h */

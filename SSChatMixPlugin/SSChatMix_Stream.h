//
//  SSChatMix_Stream.h
//  SSChatMix HAL Plugin
//
//  Stream object class
//

#ifndef SSChatMix_Stream_h
#define SSChatMix_Stream_h

#include "SSChatMix_Object.h"

// MARK: - Stream Object Class

class SSChatMix_Stream : public SSChatMix_Object {
public:
    SSChatMix_Stream(AudioObjectID inObjectID,
                     AudioObjectID inOwnerDeviceID,
                     bool inIsInput,
                     Float64 inSampleRate);
    
    virtual ~SSChatMix_Stream();
    
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
    bool IsInput() const { return mIsInput; }
    Float64 GetSampleRate() const { return mSampleRate; }

private:
    bool mIsInput;
    Float64 mSampleRate;
};

#endif /* SSChatMix_Stream_h */

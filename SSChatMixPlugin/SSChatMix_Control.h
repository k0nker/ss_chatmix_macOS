//
//  SSChatMix_Control.h
//  SSChatMix HAL Plugin
//
//  Control object class (volume/mute)
//

#ifndef SSChatMix_Control_h
#define SSChatMix_Control_h

#include "SSChatMix_Object.h"

// MARK: - Control Object Class

class SSChatMix_Control : public SSChatMix_Object {
public:
    SSChatMix_Control(AudioObjectID inObjectID,
                      AudioObjectID inOwnerDeviceID,
                      AudioObjectPropertyScope inScope,
                      AudioObjectPropertyElement inElement);
    
    virtual ~SSChatMix_Control();
    
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
    
    virtual void SetPropertyData(AudioObjectID inObjectID,
                                 pid_t inClientProcessID,
                                 const AudioObjectPropertyAddress* inAddress,
                                 UInt32 inQualifierDataSize,
                                 const void* inQualifierData,
                                 UInt32 inDataSize,
                                 const void* inData);
    
    // Volume control
    void SetVolume(Float32 volume);
    Float32 GetVolume() const;

private:
    Float32 mVolume;
    AudioObjectPropertyScope mScope;
    AudioObjectPropertyElement mElement;
};

#endif /* SSChatMix_Control_h */

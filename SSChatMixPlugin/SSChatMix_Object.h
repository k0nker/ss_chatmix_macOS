//
//  SSChatMix_Object.h
//  SSChatMix HAL Plugin
//
//  Base object class for the HAL plugin OOP architecture
//

#ifndef SSChatMix_Object_h
#define SSChatMix_Object_h

#include <CoreAudio/AudioServerPlugIn.h>
#include <CoreFoundation/CoreFoundation.h>

// MARK: - Base Object Class

class SSChatMix_Object {
public:
    SSChatMix_Object(AudioObjectID inObjectID,
                     AudioClassID inClassID,
                     AudioClassID inBaseClassID,
                     AudioObjectID inOwnerObjectID);
    
    virtual ~SSChatMix_Object();
    
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
    
    virtual void SetPropertyData(AudioObjectID inObjectID,
                                 pid_t inClientProcessID,
                                 const AudioObjectPropertyAddress* inAddress,
                                 UInt32 inQualifierDataSize,
                                 const void* inQualifierData,
                                 UInt32 inDataSize,
                                 const void* inData);
    
    // Accessors
    AudioObjectID GetObjectID() const { return mObjectID; }
    AudioClassID GetClassID() const { return mClassID; }
    AudioClassID GetBaseClassID() const { return mBaseClassID; }
    AudioObjectID GetOwnerObjectID() const { return mOwnerObjectID; }
    bool IsActive() const { return mIsActive; }

protected:
    AudioObjectID mObjectID;
    AudioClassID mClassID;
    AudioClassID mBaseClassID;
    AudioObjectID mOwnerObjectID;
    bool mIsActive;
};

#endif /* SSChatMix_Object_h */

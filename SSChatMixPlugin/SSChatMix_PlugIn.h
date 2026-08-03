//
//  SSChatMix_PlugIn.h
//  SSChatMix HAL Plugin
//
//  Plugin object class
//

#ifndef SSChatMix_PlugIn_h
#define SSChatMix_PlugIn_h

#include "SSChatMix_Object.h"
#include "SSChatMix_Device.h"

// MARK: - Plugin Object Class

class SSChatMix_PlugIn : public SSChatMix_Object {
public:
    SSChatMix_PlugIn();
    virtual ~SSChatMix_PlugIn();
    
    // Static initialization (thread-safe singleton)
    static void StaticInitialize(AudioServerPlugInHostRef inHost);
    static SSChatMix_PlugIn& GetInstance();
    
    // Accessors
    AudioServerPlugInHostRef GetHost() const { return mHost; }
    SSChatMix_Device& GetGameDevice() { return mGameDevice; }
    SSChatMix_Device& GetChatDevice() { return mChatDevice; }
    
    // Lifecycle overrides
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

private:
    AudioServerPlugInHostRef mHost;
    SSChatMix_Device mGameDevice;
    SSChatMix_Device mChatDevice;
};

#endif /* SSChatMix_PlugIn_h */

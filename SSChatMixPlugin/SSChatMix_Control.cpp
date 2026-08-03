//
//  SSChatMix_Control.cpp
//  SSChatMix HAL Plugin
//
//  Control object implementation
//

#include "SSChatMix_Control.h"
#include <CoreAudio/AudioHardwareBase.h>
#include <os/log.h>

// MARK: - Constructor/Destructor

SSChatMix_Control::SSChatMix_Control(AudioObjectID inObjectID,
                                     AudioObjectID inOwnerDeviceID,
                                     AudioObjectPropertyScope inScope,
                                     AudioObjectPropertyElement inElement)
:
    SSChatMix_Object(inObjectID, kAudioVolumeControlClassID, kAudioLevelControlClassID, inOwnerDeviceID),
    mVolume(1.0f),
    mScope(inScope),
    mElement(inElement)
{
}

SSChatMix_Control::~SSChatMix_Control() {
}

// MARK: - Volume Control

void SSChatMix_Control::SetVolume(Float32 volume) {
    if (volume < 0.0f) volume = 0.0f;
    if (volume > 1.0f) volume = 1.0f;
    mVolume = volume;
}

Float32 SSChatMix_Control::GetVolume() const {
    return mVolume;
}

// MARK: - Property Operations

bool SSChatMix_Control::HasProperty(AudioObjectID inObjectID,
                                    pid_t inClientProcessID,
                                    const AudioObjectPropertyAddress* inAddress) const {
    #pragma unused(inObjectID, inClientProcessID)
    
    bool theAnswer = false;
    
    switch (inAddress->mSelector) {
        case kAudioControlPropertyScope:
        case kAudioControlPropertyElement:
        case kAudioLevelControlPropertyScalarValue:
            theAnswer = true;
            break;
            
        default:
            theAnswer = SSChatMix_Object::HasProperty(inObjectID, inClientProcessID, inAddress);
            break;
    }
    
    return theAnswer;
}

bool SSChatMix_Control::IsPropertySettable(AudioObjectID inObjectID,
                                           pid_t inClientProcessID,
                                           const AudioObjectPropertyAddress* inAddress) const {
    #pragma unused(inObjectID, inClientProcessID)
    
    bool theAnswer = false;
    
    switch (inAddress->mSelector) {
        case kAudioControlPropertyScope:
        case kAudioControlPropertyElement:
            theAnswer = false;
            break;
            
        case kAudioLevelControlPropertyScalarValue:
            theAnswer = true;
            break;
            
        default:
            theAnswer = SSChatMix_Object::IsPropertySettable(inObjectID, inClientProcessID, inAddress);
            break;
    }
    
    return theAnswer;
}

UInt32 SSChatMix_Control::GetPropertyDataSize(AudioObjectID inObjectID,
                                              pid_t inClientProcessID,
                                              const AudioObjectPropertyAddress* inAddress,
                                              UInt32 inQualifierDataSize,
                                              const void* inQualifierData) const {
    #pragma unused(inObjectID, inClientProcessID, inQualifierDataSize, inQualifierData)
    
    UInt32 theAnswer = 0;
    
    switch (inAddress->mSelector) {
        case kAudioControlPropertyScope:
            theAnswer = sizeof(AudioObjectPropertyScope);
            break;
            
        case kAudioControlPropertyElement:
            theAnswer = sizeof(AudioObjectPropertyElement);
            break;
            
        case kAudioLevelControlPropertyScalarValue:
            theAnswer = sizeof(Float32);
            break;
            
        default:
            theAnswer = SSChatMix_Object::GetPropertyDataSize(inObjectID, inClientProcessID, inAddress,
                                                              inQualifierDataSize, inQualifierData);
            break;
    }
    
    return theAnswer;
}

OSStatus SSChatMix_Control::GetPropertyData(AudioObjectID inObjectID,
                                            pid_t inClientProcessID,
                                            const AudioObjectPropertyAddress* inAddress,
                                            UInt32 inQualifierDataSize,
                                            const void* inQualifierData,
                                            UInt32 inDataSize,
                                            UInt32& outDataSize,
                                            void* outData) const {
    #pragma unused(inObjectID, inClientProcessID, inQualifierDataSize, inQualifierData, inDataSize)
    
    OSStatus result = kAudioHardwareNoError;
    
    switch (inAddress->mSelector) {
        case kAudioControlPropertyScope:
            *reinterpret_cast<AudioObjectPropertyScope*>(outData) = mScope;
            outDataSize = sizeof(AudioObjectPropertyScope);
            break;
            
        case kAudioControlPropertyElement:
            *reinterpret_cast<AudioObjectPropertyElement*>(outData) = mElement;
            outDataSize = sizeof(AudioObjectPropertyElement);
            break;
            
        case kAudioLevelControlPropertyScalarValue:
            *reinterpret_cast<Float32*>(outData) = mVolume;
            outDataSize = sizeof(Float32);
            break;
            
        default:
            result = SSChatMix_Object::GetPropertyData(inObjectID, inClientProcessID, inAddress,
                                                       inQualifierDataSize, inQualifierData,
                                                       inDataSize, outDataSize, outData);
            break;
    }
    
    return result;
}

void SSChatMix_Control::SetPropertyData(AudioObjectID inObjectID,
                                        pid_t inClientProcessID,
                                        const AudioObjectPropertyAddress* inAddress,
                                        UInt32 inQualifierDataSize,
                                        const void* inQualifierData,
                                        UInt32 inDataSize,
                                        const void* inData) {
    #pragma unused(inObjectID, inClientProcessID, inQualifierDataSize, inQualifierData, inDataSize)
    
    switch (inAddress->mSelector) {
        case kAudioLevelControlPropertyScalarValue:
            if (inDataSize >= sizeof(Float32)) {
                SetVolume(*reinterpret_cast<const Float32*>(inData));
            }
            break;
            
        default:
            SSChatMix_Object::SetPropertyData(inObjectID, inClientProcessID, inAddress,
                                              inQualifierDataSize, inQualifierData,
                                              inDataSize, inData);
            break;
    }
}

//
//  SSChatMix_Control.cpp
//  SSChatMix HAL Plugin
//
//  Control object implementation
//

#include "SSChatMix_Control.h"
#include <os/log.h>

// MARK: - Constructor/Destructor

SSChatMix_Control::SSChatMix_Control(AudioObjectID inObjectID,
                                     AudioObjectID inOwnerDeviceID)
:
    SSChatMix_Object(inObjectID, kAudioControlClassID, kAudioObjectClassID, inOwnerDeviceID),
    mVolume(1.0f)
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
        case kAudioVolumeControlPropertyIsOwnedByDevice:
        case kAudioVolumeControlPropertyChannel:
        case kAudioVolumeControlPropertyScalarValue:
        case kAudioVolumeControlPropertyNumericValue:
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
        case kAudioVolumeControlPropertyChannel:
            theAnswer = false;
            break;
            
        case kAudioVolumeControlPropertyScalarValue:
        case kAudioVolumeControlPropertyNumericValue:
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
        case kAudioVolumeControlPropertyIsOwnedByDevice:
            theAnswer = sizeof(UInt32);
            break;
            
        case kAudioVolumeControlPropertyChannel:
            theAnswer = sizeof(AudioVolumeControlChannelInfo);
            break;
            
        case kAudioVolumeControlPropertyScalarValue:
            theAnswer = sizeof(Float32);
            break;
            
        case kAudioVolumeControlPropertyNumericValue:
            theAnswer = sizeof(AudioValueRange);
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
        case kAudioVolumeControlPropertyIsOwnedByDevice:
            *reinterpret_cast<UInt32*>(outData) = 1;
            outDataSize = sizeof(UInt32);
            break;
            
        case kAudioVolumeControlPropertyChannel: {
            AudioVolumeControlChannelInfo* channelInfo = reinterpret_cast<AudioVolumeControlChannelInfo*>(outData);
            channelInfo->mChannel = 0;
            channelInfo->mFlags = kAudioVolumeControlChannelFlagsHiFi;
            outDataSize = sizeof(AudioVolumeControlChannelInfo);
            break;
        }
            
        case kAudioVolumeControlPropertyScalarValue:
            *reinterpret_cast<Float32*>(outData) = mVolume;
            outDataSize = sizeof(Float32);
            break;
            
        case kAudioVolumeControlPropertyNumericValue:
            reinterpret_cast<AudioValueRange*>(outData)->mMinimum = 0.0f;
            reinterpret_cast<AudioValueRange*>(outData)->mMaximum = 1.0f;
            outDataSize = sizeof(AudioValueRange);
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
        case kAudioVolumeControlPropertyScalarValue:
            if (inDataSize >= sizeof(Float32)) {
                SetVolume(*reinterpret_cast<const Float32*>(inData));
            }
            break;
            
        case kAudioVolumeControlPropertyNumericValue:
            if (inDataSize >= sizeof(AudioValueRange)) {
                Float32 numericValue = *reinterpret_cast<const Float32*>(inData);
                AudioValueRange range;
                range.mMinimum = 0.0f;
                range.mMaximum = 1.0f;
                // Convert numeric value to scalar
                Float32 scalar = (numericValue - range.mMinimum) / (range.mMaximum - range.mMinimum);
                SetVolume(scalar);
            }
            break;
            
        default:
            SSChatMix_Object::SetPropertyData(inObjectID, inClientProcessID, inAddress,
                                              inQualifierDataSize, inQualifierData,
                                              inDataSize, inData);
            break;
    }
}

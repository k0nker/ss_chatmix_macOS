//
//  SSChatMix_Object.cpp
//  SSChatMix HAL Plugin
//
//  Base object class implementation
//

#include "SSChatMix_Object.h"

// MARK: - Constructor/Destructor

SSChatMix_Object::SSChatMix_Object(AudioObjectID inObjectID,
                                   AudioClassID inClassID,
                                   AudioClassID inBaseClassID,
                                   AudioObjectID inOwnerObjectID)
:
    mObjectID(inObjectID),
    mClassID(inClassID),
    mBaseClassID(inBaseClassID),
    mOwnerObjectID(inOwnerObjectID),
    mIsActive(false)
{
}

void SSChatMix_Object::Activate() {
    mIsActive = true;
}

void SSChatMix_Object::Deactivate() {
    mIsActive = false;
}

SSChatMix_Object::~SSChatMix_Object() {
}

// MARK: - Property Operations

bool SSChatMix_Object::HasProperty(AudioObjectID inObjectID,
                                   pid_t inClientProcessID,
                                   const AudioObjectPropertyAddress* inAddress) const {
    #pragma unused(inObjectID, inClientProcessID)
    
    bool theAnswer = false;
    switch (inAddress->mSelector) {
        case kAudioObjectPropertyBaseClass:
        case kAudioObjectPropertyClass:
        case kAudioObjectPropertyOwner:
        case kAudioObjectPropertyOwnedObjects:
            theAnswer = true;
            break;
    }
    return theAnswer;
}

bool SSChatMix_Object::IsPropertySettable(AudioObjectID inObjectID,
                                          pid_t inClientProcessID,
                                          const AudioObjectPropertyAddress* inAddress) const {
    #pragma unused(inObjectID, inClientProcessID)
    
    bool theAnswer = false;
    switch (inAddress->mSelector) {
        case kAudioObjectPropertyBaseClass:
        case kAudioObjectPropertyClass:
        case kAudioObjectPropertyOwner:
        case kAudioObjectPropertyOwnedObjects:
            theAnswer = false;
            break;
    }
    return theAnswer;
}

UInt32 SSChatMix_Object::GetPropertyDataSize(AudioObjectID inObjectID,
                                             pid_t inClientProcessID,
                                             const AudioObjectPropertyAddress* inAddress,
                                             UInt32 inQualifierDataSize,
                                             const void* inQualifierData) const {
    #pragma unused(inObjectID, inClientProcessID, inQualifierDataSize, inQualifierData)
    
    UInt32 theAnswer = 0;
    switch (inAddress->mSelector) {
        case kAudioObjectPropertyBaseClass:
        case kAudioObjectPropertyClass:
            theAnswer = sizeof(AudioClassID);
            break;
            
        case kAudioObjectPropertyOwner:
            theAnswer = sizeof(AudioObjectID);
            break;
            
        case kAudioObjectPropertyOwnedObjects:
            theAnswer = 0;
            break;
    }
    return theAnswer;
}

OSStatus SSChatMix_Object::GetPropertyData(AudioObjectID inObjectID,
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
        case kAudioObjectPropertyBaseClass:
            if (inDataSize < sizeof(AudioClassID)) {
                result = kAudioHardwareBadPropertySizeError;
            } else {
                *reinterpret_cast<AudioClassID*>(outData) = mBaseClassID;
                outDataSize = sizeof(AudioClassID);
            }
            break;
            
        case kAudioObjectPropertyClass:
            if (inDataSize < sizeof(AudioClassID)) {
                result = kAudioHardwareBadPropertySizeError;
            } else {
                *reinterpret_cast<AudioClassID*>(outData) = mClassID;
                outDataSize = sizeof(AudioClassID);
            }
            break;
            
        case kAudioObjectPropertyOwner:
            if (inDataSize < sizeof(AudioObjectID)) {
                result = kAudioHardwareBadPropertySizeError;
            } else {
                *reinterpret_cast<AudioObjectID*>(outData) = mOwnerObjectID;
                outDataSize = sizeof(AudioObjectID);
            }
            break;
            
        case kAudioObjectPropertyOwnedObjects:
            outDataSize = 0;
            break;
            
        default:
            result = kAudioHardwareUnknownPropertyError;
            break;
    }
    
    return result;
}

void SSChatMix_Object::SetPropertyData(AudioObjectID inObjectID,
                                       pid_t inClientProcessID,
                                       const AudioObjectPropertyAddress* inAddress,
                                       UInt32 inQualifierDataSize,
                                       const void* inQualifierData,
                                       UInt32 inDataSize,
                                       const void* inData) {
    #pragma unused(inObjectID, inClientProcessID, inAddress, inQualifierDataSize, inQualifierData, inDataSize, inData)
    // Base class doesn't support property setting
}

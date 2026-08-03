//
//  SSChatMix_Stream.cpp
//  SSChatMix HAL Plugin
//
//  Stream object implementation
//

#include "SSChatMix_Stream.h"
#include "SSChatMixPlugin.h"
#include <os/log.h>

// MARK: - Constructor/Destructor

SSChatMix_Stream::SSChatMix_Stream(AudioObjectID inObjectID,
                                   AudioObjectID inOwnerDeviceID,
                                   bool inIsInput,
                                   Float64 inSampleRate)
:
    SSChatMix_Object(inObjectID, kAudioStreamClassID, kAudioObjectClassID, inOwnerDeviceID),
    mIsInput(inIsInput),
    mSampleRate(inSampleRate)
{
}

SSChatMix_Stream::~SSChatMix_Stream() {
}

// MARK: - Property Operations

bool SSChatMix_Stream::HasProperty(AudioObjectID inObjectID,
                                   pid_t inClientProcessID,
                                   const AudioObjectPropertyAddress* inAddress) const {
    #pragma unused(inObjectID, inClientProcessID)
    
    bool theAnswer = false;
    
    switch (inAddress->mSelector) {
        case kAudioStreamPropertyIsActive:
        case kAudioStreamPropertyDirection:
        case kAudioStreamPropertyTerminalType:
        case kAudioStreamPropertyStartingChannel:
        case kAudioStreamPropertyLatency:
        case kAudioStreamPropertyVirtualFormat:
        case kAudioStreamPropertyPhysicalFormat:
        case kAudioStreamPropertyAvailableVirtualFormats:
        case kAudioStreamPropertyAvailablePhysicalFormats:
            theAnswer = true;
            break;
            
        default:
            theAnswer = SSChatMix_Object::HasProperty(inObjectID, inClientProcessID, inAddress);
            break;
    }
    
    return theAnswer;
}

bool SSChatMix_Stream::IsPropertySettable(AudioObjectID inObjectID,
                                          pid_t inClientProcessID,
                                          const AudioObjectPropertyAddress* inAddress) const {
    #pragma unused(inObjectID, inClientProcessID)
    
    bool theAnswer = false;
    
    switch (inAddress->mSelector) {
        case kAudioStreamPropertyDirection:
        case kAudioStreamPropertyTerminalType:
        case kAudioStreamPropertyStartingChannel:
        case kAudioStreamPropertyLatency:
        case kAudioStreamPropertyAvailableVirtualFormats:
        case kAudioStreamPropertyAvailablePhysicalFormats:
            theAnswer = false;
            break;
            
        case kAudioStreamPropertyIsActive:
        case kAudioStreamPropertyVirtualFormat:
        case kAudioStreamPropertyPhysicalFormat:
            theAnswer = true;
            break;
            
        default:
            theAnswer = SSChatMix_Object::IsPropertySettable(inObjectID, inClientProcessID, inAddress);
            break;
    }
    
    return theAnswer;
}

UInt32 SSChatMix_Stream::GetPropertyDataSize(AudioObjectID inObjectID,
                                             pid_t inClientProcessID,
                                             const AudioObjectPropertyAddress* inAddress,
                                             UInt32 inQualifierDataSize,
                                             const void* inQualifierData) const {
    #pragma unused(inObjectID, inClientProcessID, inQualifierDataSize, inQualifierData)
    
    UInt32 theAnswer = 0;
    
    switch (inAddress->mSelector) {
        case kAudioStreamPropertyIsActive:
        case kAudioStreamPropertyDirection:
        case kAudioStreamPropertyTerminalType:
        case kAudioStreamPropertyStartingChannel:
        case kAudioStreamPropertyLatency:
            theAnswer = sizeof(UInt32);
            break;
            
        case kAudioStreamPropertyVirtualFormat:
        case kAudioStreamPropertyPhysicalFormat:
            theAnswer = sizeof(AudioStreamBasicDescription);
            break;
            
        case kAudioStreamPropertyAvailableVirtualFormats:
        case kAudioStreamPropertyAvailablePhysicalFormats:
            theAnswer = sizeof(AudioStreamRangedDescription);
            break;
            
        default:
            theAnswer = SSChatMix_Object::GetPropertyDataSize(inObjectID, inClientProcessID, inAddress,
                                                              inQualifierDataSize, inQualifierData);
            break;
    }
    
    return theAnswer;
}

OSStatus SSChatMix_Stream::GetPropertyData(AudioObjectID inObjectID,
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
        case kAudioStreamPropertyIsActive:
            *reinterpret_cast<UInt32*>(outData) = 1;
            outDataSize = sizeof(UInt32);
            break;
            
        case kAudioStreamPropertyDirection:
            *reinterpret_cast<UInt32*>(outData) = mIsInput ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput;
            outDataSize = sizeof(UInt32);
            break;
            
        case kAudioStreamPropertyTerminalType:
            *reinterpret_cast<UInt32*>(outData) = 0;
            outDataSize = sizeof(UInt32);
            break;
            
        case kAudioStreamPropertyStartingChannel:
            *reinterpret_cast<UInt32*>(outData) = 1;
            outDataSize = sizeof(UInt32);
            break;
            
        case kAudioStreamPropertyLatency:
            *reinterpret_cast<UInt32*>(outData) = 0;
            outDataSize = sizeof(UInt32);
            break;
            
        case kAudioStreamPropertyVirtualFormat:
        case kAudioStreamPropertyPhysicalFormat: {
            AudioStreamBasicDescription* desc = reinterpret_cast<AudioStreamBasicDescription*>(outData);
            desc->mSampleRate = mSampleRate;
            desc->mFormatID = kAudioFormatLinearPCM;
            desc->mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagsNativeEndian;
            desc->mBytesPerPacket = kSSChatMix_Channels * sizeof(Float32);
            desc->mFramesPerPacket = 1;
            desc->mBytesPerFrame = kSSChatMix_Channels * sizeof(Float32);
            desc->mChannelsPerFrame = kSSChatMix_Channels;
            desc->mBitsPerChannel = 32;
            outDataSize = sizeof(AudioStreamBasicDescription);
            break;
        }
            
        case kAudioStreamPropertyAvailableVirtualFormats:
        case kAudioStreamPropertyAvailablePhysicalFormats: {
            AudioStreamRangedDescription* rangedDesc = reinterpret_cast<AudioStreamRangedDescription*>(outData);
            rangedDesc->mFormat.mSampleRate = mSampleRate;
            rangedDesc->mFormat.mFormatID = kAudioFormatLinearPCM;
            rangedDesc->mFormat.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagsNativeEndian;
            rangedDesc->mFormat.mBytesPerPacket = kSSChatMix_Channels * sizeof(Float32);
            rangedDesc->mFormat.mFramesPerPacket = 1;
            rangedDesc->mFormat.mBytesPerFrame = kSSChatMix_Channels * sizeof(Float32);
            rangedDesc->mFormat.mChannelsPerFrame = kSSChatMix_Channels;
            rangedDesc->mFormat.mBitsPerChannel = 32;
            rangedDesc->mSampleRateRange.mMinimum = mSampleRate;
            rangedDesc->mSampleRateRange.mMaximum = mSampleRate;
            outDataSize = sizeof(AudioStreamRangedDescription);
            break;
        }
            
        default:
            result = SSChatMix_Object::GetPropertyData(inObjectID, inClientProcessID, inAddress,
                                                       inQualifierDataSize, inQualifierData,
                                                       inDataSize, outDataSize, outData);
            break;
    }
    
    return result;
}

//
//  SSChatMix_Device.cpp
//  SSChatMix HAL Plugin
//
//  Device object implementation
//

#include "SSChatMix_Device.h"
#include "SSChatMixPlugin.h"
#include <os/log.h>

// MARK: - Constructor/Destructor

SSChatMix_Device::SSChatMix_Device(AudioObjectID inObjectID,
                                   const char* inDeviceName,
                                   const char* inDeviceUID,
                                   const char* inModelUID,
                                   AudioObjectID inOutputStreamID,
                                   AudioObjectID inVolumeControlID)
:
    SSChatMix_Object(inObjectID, kAudioDeviceClassID, kAudioObjectClassID, kAudioObjectPlugInObject),
    mDeviceName(inDeviceName),
    mDeviceUID(inDeviceUID),
    mOutputStream(inOutputStreamID, inObjectID, false, kSSChatMix_SampleRate),  // false = output stream
    mVolumeControl(inVolumeControlID, inObjectID, kAudioObjectPropertyScopeOutput, kAudioObjectPropertyElementMain),
    mHostTicksPerFrame(0.0),
    mAnchorHostTime(0),
    mAnchorSampleTime(0.0),
    mIsIORunning(false),
    mSharedMemory(nullptr)
{
    // FIRST LINE: Verify constructor runs
    FILE* log = fopen("/tmp/sschatmix_plugin.log", "a");
    if (log) {
        fprintf(log, "=== SSChatMix_Device constructor START: %s\n", inDeviceUID);
        fclose(log);
    }
    
    // Create shared memory buffer with unique name based on device type
    // Format: "/ssc.game" or "/ssc.chat" (must be ≤31 chars for macOS PSEMNAMLEN)
    const char* shortName = (strcmp(inDeviceUID, "SSChatMixGameDevice") == 0) ? "/ssc.game" : "/ssc.chat";
    
    log = fopen("/tmp/sschatmix_plugin.log", "a");
    if (log) {
        fprintf(log, "Creating SSChatMix_SharedMemory: %s\n", shortName);
        fclose(log);
    }
    mSharedMemory = new SSChatMix_SharedMemory(shortName, kSSChatMix_RingBufferFrames, kSSChatMix_Channels);
    
    // DEBUG: Write to file to confirm this code runs
    FILE* debugFile = fopen("/tmp/sschatmix_device_created.txt", "a");
    if (debugFile) {
        fprintf(debugFile, "Device constructor called: %s -> %s\n", inDeviceUID, shortName);
        fclose(debugFile);
    }
    
    log = fopen("/tmp/sschatmix_plugin.log", "a");
    if (log) {
        fprintf(log, "Calling InitializeAsWriter()\n");
        fclose(log);
    }
    // Initialize as writer (plugin side)
    if (!mSharedMemory->InitializeAsWriter()) {
        log = fopen("/tmp/sschatmix_plugin.log", "a");
        if (log) {
            fprintf(log, "InitializeAsWriter() FAILED for %s\n", shortName);
            fclose(log);
        }
        os_log_error(OS_LOG_DEFAULT, "Failed to initialize shared memory for device %s", inDeviceName);
        delete mSharedMemory;
        mSharedMemory = nullptr;
    } else {
        log = fopen("/tmp/sschatmix_plugin.log", "a");
        if (log) {
            fprintf(log, "InitializeAsWriter() SUCCESS for %s\n", shortName);
            fclose(log);
        }
    }
}

SSChatMix_Device::~SSChatMix_Device() {
    if (mSharedMemory != nullptr) {
        delete mSharedMemory;
        mSharedMemory = nullptr;
    }
}

// MARK: - Lifecycle

void SSChatMix_Device::Activate() {
    mOutputStream.Activate();
    mVolumeControl.Activate();
    SSChatMix_Object::Activate();
}

void SSChatMix_Device::Deactivate() {
    mOutputStream.Deactivate();
    mVolumeControl.Deactivate();
    SSChatMix_Object::Deactivate();
}

// MARK: - Timing

void SSChatMix_Device::SetAnchorTime(UInt64 hostTime, Float64 sampleTime) {
    mAnchorHostTime = hostTime;
    mAnchorSampleTime = sampleTime;
}

void SSChatMix_Device::GetAnchorTime(UInt64& outHostTime, Float64& outSampleTime) const {
    outHostTime = mAnchorHostTime;
    outSampleTime = mAnchorSampleTime;
}

void SSChatMix_Device::SetIORunning(bool isRunning) {
    mIsIORunning = isRunning;
}

bool SSChatMix_Device::IsIORunning() const {
    return mIsIORunning;
}

// MARK: - Audio I/O

UInt32 SSChatMix_Device::WriteAudio(const Float32* data, UInt32 frameCount) {
    if (mSharedMemory != nullptr) {
        return mSharedMemory->Write(data, frameCount);
    }
    return 0;
}

UInt32 SSChatMix_Device::ReadAudio(Float32* data, UInt32 frameCount) {
    if (mSharedMemory != nullptr) {
        return mSharedMemory->Read(data, frameCount);
    }
    // Fill with silence if no shared memory
    memset(data, 0, frameCount * kSSChatMix_Channels * sizeof(Float32));
    return 0;
}

UInt32 SSChatMix_Device::GetAvailableFrames() const {
    if (mSharedMemory != nullptr) {
        return mSharedMemory->GetAvailableFrames();
    }
    return 0;
}

// MARK: - Property Operations

bool SSChatMix_Device::HasProperty(AudioObjectID inObjectID,
                                   pid_t inClientProcessID,
                                   const AudioObjectPropertyAddress* inAddress) const {
    #pragma unused(inClientProcessID)
    
    // Delegate to child objects (streams, controls)
    if (inObjectID == mOutputStream.GetObjectID()) {
        return mOutputStream.HasProperty(inObjectID, inClientProcessID, inAddress);
    } else if (inObjectID == mVolumeControl.GetObjectID()) {
        return mVolumeControl.HasProperty(inObjectID, inClientProcessID, inAddress);
    }
    
    bool theAnswer = false;
    
    switch (inAddress->mSelector) {
        case kAudioObjectPropertyBaseClass:
        case kAudioObjectPropertyClass:
        case kAudioObjectPropertyOwner:
        case kAudioObjectPropertyOwnedObjects:
        case kAudioObjectPropertyName:
        case kAudioObjectPropertyManufacturer:
        case kAudioDevicePropertyDeviceUID:
        case kAudioDevicePropertyModelUID:
        case kAudioDevicePropertyTransportType:
        case kAudioDevicePropertyRelatedDevices:
        case kAudioDevicePropertyClockDomain:
        case kAudioDevicePropertyDeviceIsAlive:
        case kAudioDevicePropertyDeviceIsRunning:
        case kAudioObjectPropertyControlList:
        case kAudioDevicePropertyDeviceCanBeDefaultDevice:
        case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice:
        case kAudioDevicePropertyLatency:
        case kAudioDevicePropertyStreams:
        case kAudioDevicePropertySafetyOffset:
        case kAudioDevicePropertyNominalSampleRate:
        case kAudioDevicePropertyAvailableNominalSampleRates:
        case kAudioDevicePropertyIsHidden:
        case kAudioDevicePropertyZeroTimeStampPeriod:
        case kAudioDevicePropertyPreferredChannelsForStereo:
            theAnswer = true;
            break;
            
        default:
            theAnswer = SSChatMix_Object::HasProperty(inObjectID, inClientProcessID, inAddress);
            break;
    }
    
    return theAnswer;
}

bool SSChatMix_Device::IsPropertySettable(AudioObjectID inObjectID,
                                          pid_t inClientProcessID,
                                          const AudioObjectPropertyAddress* inAddress) const {
    #pragma unused(inClientProcessID)
    
    // Delegate to child objects (streams, controls)
    if (inObjectID == mOutputStream.GetObjectID()) {
        return mOutputStream.IsPropertySettable(inObjectID, inClientProcessID, inAddress);
    } else if (inObjectID == mVolumeControl.GetObjectID()) {
        return mVolumeControl.IsPropertySettable(inObjectID, inClientProcessID, inAddress);
    }
    
    bool theAnswer = false;
    
    switch (inAddress->mSelector) {
        case kAudioObjectPropertyBaseClass:
        case kAudioObjectPropertyClass:
        case kAudioObjectPropertyOwner:
        case kAudioObjectPropertyOwnedObjects:
        case kAudioObjectPropertyName:
        case kAudioObjectPropertyManufacturer:
        case kAudioDevicePropertyDeviceUID:
        case kAudioDevicePropertyModelUID:
        case kAudioDevicePropertyTransportType:
        case kAudioDevicePropertyRelatedDevices:
        case kAudioDevicePropertyClockDomain:
        case kAudioDevicePropertyDeviceIsAlive:
        case kAudioDevicePropertyDeviceIsRunning:
        case kAudioObjectPropertyControlList:
        case kAudioDevicePropertyDeviceCanBeDefaultDevice:
        case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice:
        case kAudioDevicePropertyLatency:
        case kAudioDevicePropertyStreams:
        case kAudioDevicePropertySafetyOffset:
        case kAudioDevicePropertyIsHidden:
        case kAudioDevicePropertyZeroTimeStampPeriod:
        case kAudioDevicePropertyPreferredChannelsForStereo:
            theAnswer = false;
            break;
            
        case kAudioDevicePropertyNominalSampleRate:
        case kAudioDevicePropertyAvailableNominalSampleRates:
            theAnswer = false;
            break;
            
        default:
            theAnswer = SSChatMix_Object::IsPropertySettable(inObjectID, inClientProcessID, inAddress);
            break;
    }
    
    return theAnswer;
}

UInt32 SSChatMix_Device::GetPropertyDataSize(AudioObjectID inObjectID,
                                             pid_t inClientProcessID,
                                             const AudioObjectPropertyAddress* inAddress,
                                             UInt32 inQualifierDataSize,
                                             const void* inQualifierData) const {
    #pragma unused(inClientProcessID, inQualifierDataSize, inQualifierData)
    
    // Delegate to child objects (streams, controls)
    if (inObjectID == mOutputStream.GetObjectID()) {
        return mOutputStream.GetPropertyDataSize(inObjectID, inClientProcessID, inAddress,
                                                  inQualifierDataSize, inQualifierData);
    } else if (inObjectID == mVolumeControl.GetObjectID()) {
        return mVolumeControl.GetPropertyDataSize(inObjectID, inClientProcessID, inAddress,
                                                   inQualifierDataSize, inQualifierData);
    }
    
    UInt32 theAnswer = 0;
    
    switch (inAddress->mSelector) {
        case kAudioObjectPropertyBaseClass:
        case kAudioObjectPropertyClass:
            theAnswer = sizeof(AudioClassID);
            break;
            
        case kAudioObjectPropertyOwner:
            theAnswer = sizeof(AudioObjectID);
            break;
            
        case kAudioObjectPropertyName:
        case kAudioObjectPropertyManufacturer:
        case kAudioDevicePropertyDeviceUID:
        case kAudioDevicePropertyModelUID:
            theAnswer = sizeof(CFStringRef);
            break;
            
        case kAudioDevicePropertyTransportType:
        case kAudioDevicePropertyRelatedDevices:
        case kAudioDevicePropertyClockDomain:
        case kAudioDevicePropertyDeviceIsAlive:
        case kAudioDevicePropertyDeviceIsRunning:
        case kAudioDevicePropertyDeviceCanBeDefaultDevice:
        case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice:
        case kAudioDevicePropertyLatency:
        case kAudioDevicePropertySafetyOffset:
        case kAudioDevicePropertyIsHidden:
        case kAudioDevicePropertyZeroTimeStampPeriod:
            theAnswer = sizeof(UInt32);
            break;
            
        case kAudioObjectPropertyControlList:
            theAnswer = sizeof(AudioObjectID);
            break;
            
        case kAudioObjectPropertyOwnedObjects:
            if (inAddress->mScope == kAudioObjectPropertyScopeGlobal) {
                theAnswer = 2 * sizeof(AudioObjectID);  // output stream + volume control
            } else if (inAddress->mScope == kAudioObjectPropertyScopeOutput) {
                theAnswer = 2 * sizeof(AudioObjectID);
            } else {
                theAnswer = 0;  // no input stream
            }
            break;
            
        case kAudioDevicePropertyStreams:
            if (inAddress->mScope == kAudioObjectPropertyScopeInput) {
                theAnswer = 0;  // no input stream
            } else {
                theAnswer = sizeof(AudioObjectID);  // only output stream
            }
            break;
            
        case kAudioDevicePropertyNominalSampleRate:
            theAnswer = sizeof(Float64);
            break;
            
        case kAudioDevicePropertyAvailableNominalSampleRates:
            theAnswer = sizeof(AudioValueRange);
            break;
            
        case kAudioDevicePropertyPreferredChannelsForStereo:
            theAnswer = 2 * sizeof(UInt32);
            break;
            
        default:
            theAnswer = SSChatMix_Object::GetPropertyDataSize(inObjectID, inClientProcessID, inAddress,
                                                              inQualifierDataSize, inQualifierData);
            break;
    }
    
    return theAnswer;
}

OSStatus SSChatMix_Device::GetPropertyData(AudioObjectID inObjectID,
                                           pid_t inClientProcessID,
                                           const AudioObjectPropertyAddress* inAddress,
                                           UInt32 inQualifierDataSize,
                                           const void* inQualifierData,
                                           UInt32 inDataSize,
                                           UInt32& outDataSize,
                                           void* outData) const {
    #pragma unused(inClientProcessID, inQualifierDataSize, inQualifierData, inDataSize)
    
    // Delegate to child objects (streams, controls)
    if (inObjectID == mOutputStream.GetObjectID()) {
        return mOutputStream.GetPropertyData(inObjectID, inClientProcessID, inAddress,
                                              inQualifierDataSize, inQualifierData,
                                              inDataSize, outDataSize, outData);
    } else if (inObjectID == mVolumeControl.GetObjectID()) {
        return mVolumeControl.GetPropertyData(inObjectID, inClientProcessID, inAddress,
                                               inQualifierDataSize, inQualifierData,
                                               inDataSize, outDataSize, outData);
    }
    
    // Log property queries to help debug
    char selectorStr[5];
    *((UInt32*)selectorStr) = CFSwapInt32HostToBig(inAddress->mSelector);
    selectorStr[4] = '\0';
    os_log(OS_LOG_DEFAULT, "SSChatMix_Device::GetPropertyData: %s scope=%u elem=%u", 
           selectorStr, inAddress->mScope, inAddress->mElement);
    
    OSStatus result = kAudioHardwareNoError;
    
    switch (inAddress->mSelector) {
        case kAudioObjectPropertyBaseClass:
            *reinterpret_cast<AudioClassID*>(outData) = mBaseClassID;
            outDataSize = sizeof(AudioClassID);
            break;
            
        case kAudioObjectPropertyClass:
            *reinterpret_cast<AudioClassID*>(outData) = mClassID;
            outDataSize = sizeof(AudioClassID);
            break;
            
        case kAudioObjectPropertyOwner:
            *reinterpret_cast<AudioObjectID*>(outData) = mOwnerObjectID;
            outDataSize = sizeof(AudioObjectID);
            break;
            
        case kAudioObjectPropertyName:
            {
                CFStringRef nameRef = CFStringCreateWithCString(NULL, mDeviceName, kCFStringEncodingUTF8);
                *reinterpret_cast<CFStringRef*>(outData) = nameRef;
                outDataSize = sizeof(CFStringRef);
                CFRetain(nameRef); // Retain because HAL owns the reference
                CFRelease(nameRef);
            }
            break;
            
        case kAudioObjectPropertyManufacturer:
            *reinterpret_cast<CFStringRef*>(outData) = CFSTR("k0nker");
            outDataSize = sizeof(CFStringRef);
            break;
            
        case kAudioDevicePropertyDeviceUID:
            {
                CFStringRef uidRef = CFStringCreateWithCString(NULL, mDeviceUID, kCFStringEncodingUTF8);
                *reinterpret_cast<CFStringRef*>(outData) = uidRef;
                outDataSize = sizeof(CFStringRef);
                CFRetain(uidRef); // Retain because HAL owns the reference
                CFRelease(uidRef);
            }
            break;
            
        case kAudioDevicePropertyModelUID:
            *reinterpret_cast<CFStringRef*>(outData) = CFSTR("SSChatMixDevice");
            outDataSize = sizeof(CFStringRef);
            break;
            
        case kAudioDevicePropertyTransportType:
            *reinterpret_cast<UInt32*>(outData) = kAudioDeviceTransportTypeVirtual;
            outDataSize = sizeof(UInt32);
            break;
            
        case kAudioDevicePropertyRelatedDevices:
            *reinterpret_cast<AudioObjectID*>(outData) = mObjectID;
            outDataSize = sizeof(AudioObjectID);
            break;
            
        case kAudioDevicePropertyClockDomain:
            *reinterpret_cast<UInt32*>(outData) = 0;
            outDataSize = sizeof(UInt32);
            break;
            
        case kAudioDevicePropertyDeviceIsAlive:
            *reinterpret_cast<UInt32*>(outData) = 1;
            outDataSize = sizeof(UInt32);
            break;
            
        case kAudioDevicePropertyDeviceIsRunning:
            *reinterpret_cast<UInt32*>(outData) = mIsIORunning ? 1 : 0;
            outDataSize = sizeof(UInt32);
            break;
            
        case kAudioDevicePropertyDeviceCanBeDefaultDevice:
        case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice:
            *reinterpret_cast<UInt32*>(outData) = 1;
            outDataSize = sizeof(UInt32);
            break;
            
        case kAudioObjectPropertyControlList:
            *reinterpret_cast<AudioObjectID*>(outData) = mVolumeControl.GetObjectID();
            outDataSize = sizeof(AudioObjectID);
            break;
            
        case kAudioObjectPropertyOwnedObjects:
            if (inAddress->mScope == kAudioObjectPropertyScopeGlobal) {
                // Only output stream + volume control (no input stream)
                reinterpret_cast<AudioObjectID*>(outData)[0] = mOutputStream.GetObjectID();
                reinterpret_cast<AudioObjectID*>(outData)[1] = mVolumeControl.GetObjectID();
                outDataSize = 2 * sizeof(AudioObjectID);
            } else if (inAddress->mScope == kAudioObjectPropertyScopeInput) {
                // No input stream
                outDataSize = 0;
            } else if (inAddress->mScope == kAudioObjectPropertyScopeOutput) {
                reinterpret_cast<AudioObjectID*>(outData)[0] = mOutputStream.GetObjectID();
                reinterpret_cast<AudioObjectID*>(outData)[1] = mVolumeControl.GetObjectID();
                outDataSize = 2 * sizeof(AudioObjectID);
            } else {
                outDataSize = 0;
            }
            break;
            
        case kAudioDevicePropertyStreams:
            if (inAddress->mScope == kAudioObjectPropertyScopeInput) {
                // No input stream
                outDataSize = 0;
            } else if (inAddress->mScope == kAudioObjectPropertyScopeOutput || inAddress->mScope == kAudioObjectPropertyScopeGlobal) {
                // Only output stream
                *reinterpret_cast<AudioObjectID*>(outData) = mOutputStream.GetObjectID();
                outDataSize = sizeof(AudioObjectID);
            } else {
                outDataSize = 0;
            }
            break;
            
        case kAudioDevicePropertyLatency:
        case kAudioDevicePropertySafetyOffset:
            *reinterpret_cast<UInt32*>(outData) = 0;
            outDataSize = sizeof(UInt32);
            break;
            
        case kAudioDevicePropertyNominalSampleRate:
            *reinterpret_cast<Float64*>(outData) = kSSChatMix_SampleRate;
            outDataSize = sizeof(Float64);
            break;
            
        case kAudioDevicePropertyAvailableNominalSampleRates:
            reinterpret_cast<AudioValueRange*>(outData)->mMinimum = kSSChatMix_SampleRate;
            reinterpret_cast<AudioValueRange*>(outData)->mMaximum = kSSChatMix_SampleRate;
            outDataSize = sizeof(AudioValueRange);
            break;
            
        case kAudioDevicePropertyIsHidden:
            *reinterpret_cast<UInt32*>(outData) = 0;
            outDataSize = sizeof(UInt32);
            break;
            
        case kAudioDevicePropertyZeroTimeStampPeriod:
            *reinterpret_cast<UInt32*>(outData) = kSSChatMix_RingBufferFrames;
            outDataSize = sizeof(UInt32);
            break;
            
        case kAudioDevicePropertyPreferredChannelsForStereo:
            reinterpret_cast<UInt32*>(outData)[0] = 1;
            reinterpret_cast<UInt32*>(outData)[1] = 2;
            outDataSize = 2 * sizeof(UInt32);
            break;
            
        default:
            result = SSChatMix_Object::GetPropertyData(inObjectID, inClientProcessID, inAddress,
                                                       inQualifierDataSize, inQualifierData,
                                                       inDataSize, outDataSize, outData);
            break;
    }
    
    return result;
}

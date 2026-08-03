//
//  SSChatMix_PlugIn.cpp
//  SSChatMix HAL Plugin
//
//  Plugin object implementation
//

#include "SSChatMix_PlugIn.h"
#include "SSChatMixPlugin.h"
#include <pthread.h>
#include <mach/mach_time.h>
#include <os/log.h>

// MARK: - Static Members

static pthread_once_t sStaticInitializer = PTHREAD_ONCE_INIT;
static SSChatMix_PlugIn* sInstance = NULL;
static AudioServerPlugInHostRef sHost = NULL;

// MARK: - Constructor/Destructor

SSChatMix_PlugIn::SSChatMix_PlugIn()
:
    SSChatMix_Object(kAudioObjectPlugInObject, kAudioPlugInClassID, kAudioObjectClassID, kAudioObjectUnknown),
    mHost(NULL),
    mGameDevice(kObjectID_GameDevice, "SSChatMix Game", kSSChatMixGameDevice_UID, "SSChatMixDevice",
                kObjectID_GameDevice_OutputStream, kObjectID_GameDevice_VolumeControl),
    mChatDevice(kObjectID_ChatDevice, "SSChatMix Chat", kSSChatMixChatDevice_UID, "SSChatMixDevice",
                kObjectID_ChatDevice_OutputStream, kObjectID_ChatDevice_VolumeControl)
{
    FILE* log = fopen("/tmp/sschatmix_plugin.log", "a");
    if (log) {
        fprintf(log, "SSChatMix_PlugIn constructor finished\n");
        fclose(log);
    }
}

SSChatMix_PlugIn::~SSChatMix_PlugIn() {
}

// MARK: - Static Methods

void SSChatMix_PlugIn::SetHost(AudioServerPlugInHostRef inHost) {
    sHost = inHost;
}

SSChatMix_PlugIn& SSChatMix_PlugIn::GetInstance() {
    FILE* log = fopen("/tmp/sschatmix_plugin.log", "a");
    if (log) {
        fprintf(log, "GetInstance() called\n");
        fclose(log);
    }
    pthread_once(&sStaticInitializer, []() {
        FILE* log = fopen("/tmp/sschatmix_plugin.log", "a");
        if (log) {
            fprintf(log, "pthread_once block executing - creating SSChatMix_PlugIn\n");
            fclose(log);
        }
        sInstance = new SSChatMix_PlugIn;
        log = fopen("/tmp/sschatmix_plugin.log", "a");
        if (log) {
            fprintf(log, "SSChatMix_PlugIn created, calling Activate()\n");
            fclose(log);
        }
        sInstance->Activate();
        
        // Initialize timing
        struct mach_timebase_info timeBaseInfo;
        mach_timebase_info(&timeBaseInfo);
        Float64 hostClockFrequency = (Float64)timeBaseInfo.denom / (Float64)timeBaseInfo.numer;
        hostClockFrequency *= 1000000000.0;
        sInstance->mGameDevice.SetHostTicksPerFrame(hostClockFrequency / kSSChatMix_SampleRate);
        sInstance->mChatDevice.SetHostTicksPerFrame(hostClockFrequency / kSSChatMix_SampleRate);
        
        // Initialize anchor times
        UInt64 anchorHostTime = mach_absolute_time();
        sInstance->mGameDevice.SetAnchorTime(anchorHostTime, 0.0);
        sInstance->mChatDevice.SetAnchorTime(anchorHostTime, 0.0);
        
        log = fopen("/tmp/sschatmix_plugin.log", "a");
        if (log) {
            fprintf(log, "Plugin initialization complete\n");
            fclose(log);
        }
        os_log(OS_LOG_DEFAULT, "SSChatMix_PlugIn::GetInstance: hostTicksPerFrame=%f",
               sInstance->mGameDevice.GetHostTicksPerFrame());
    });
    log = fopen("/tmp/sschatmix_plugin.log", "a");
    if (log) {
        fprintf(log, "GetInstance() returning\n");
        fclose(log);
    }
    return *sInstance;
}

// MARK: - Lifecycle

void SSChatMix_PlugIn::Activate() {
    mGameDevice.Activate();
    mChatDevice.Activate();
    SSChatMix_Object::Activate();
}

void SSChatMix_PlugIn::Deactivate() {
    mGameDevice.Deactivate();
    mChatDevice.Deactivate();
    SSChatMix_Object::Deactivate();
}

// MARK: - Property Operations

bool SSChatMix_PlugIn::HasProperty(AudioObjectID inObjectID,
                                   pid_t inClientProcessID,
                                   const AudioObjectPropertyAddress* inAddress) const {
    bool theAnswer = false;
    
    switch (inAddress->mSelector) {
        case kAudioObjectPropertyManufacturer:
        case kAudioPlugInPropertyDeviceList:
        case kAudioPlugInPropertyTranslateUIDToDevice:
        case kAudioPlugInPropertyResourceBundle:
            theAnswer = true;
            break;
            
        default:
            theAnswer = SSChatMix_Object::HasProperty(inObjectID, inClientProcessID, inAddress);
            break;
    }
    
    return theAnswer;
}

bool SSChatMix_PlugIn::IsPropertySettable(AudioObjectID inObjectID,
                                          pid_t inClientProcessID,
                                          const AudioObjectPropertyAddress* inAddress) const {
    bool theAnswer = false;
    
    switch (inAddress->mSelector) {
        case kAudioObjectPropertyManufacturer:
        case kAudioPlugInPropertyDeviceList:
        case kAudioPlugInPropertyTranslateUIDToDevice:
        case kAudioPlugInPropertyResourceBundle:
            theAnswer = false;
            break;
            
        default:
            theAnswer = SSChatMix_Object::IsPropertySettable(inObjectID, inClientProcessID, inAddress);
            break;
    }
    
    return theAnswer;
}

UInt32 SSChatMix_PlugIn::GetPropertyDataSize(AudioObjectID inObjectID,
                                             pid_t inClientProcessID,
                                             const AudioObjectPropertyAddress* inAddress,
                                             UInt32 inQualifierDataSize,
                                             const void* inQualifierData) const {
    UInt32 theAnswer = 0;
    
    switch (inAddress->mSelector) {
        case kAudioObjectPropertyManufacturer:
            theAnswer = sizeof(CFStringRef);
            break;
            
        case kAudioObjectPropertyOwnedObjects:
        case kAudioPlugInPropertyDeviceList:
            theAnswer = 2 * sizeof(AudioObjectID);
            break;
            
        case kAudioPlugInPropertyTranslateUIDToDevice:
            theAnswer = sizeof(AudioObjectID);
            break;
            
        case kAudioPlugInPropertyResourceBundle:
            theAnswer = sizeof(CFStringRef);
            break;
            
        default:
            theAnswer = SSChatMix_Object::GetPropertyDataSize(inObjectID, inClientProcessID, inAddress,
                                                              inQualifierDataSize, inQualifierData);
            break;
    }
    
    return theAnswer;
}

OSStatus SSChatMix_PlugIn::GetPropertyData(AudioObjectID inObjectID,
                                           pid_t inClientProcessID,
                                           const AudioObjectPropertyAddress* inAddress,
                                           UInt32 inQualifierDataSize,
                                           const void* inQualifierData,
                                           UInt32 inDataSize,
                                           UInt32& outDataSize,
                                           void* outData) const {
    OSStatus result = kAudioHardwareNoError;
    
    switch (inAddress->mSelector) {
        case kAudioObjectPropertyManufacturer:
            if (inDataSize < sizeof(CFStringRef)) {
                result = kAudioHardwareBadPropertySizeError;
            } else {
                *reinterpret_cast<CFStringRef*>(outData) = CFSTR("k0nker");
                outDataSize = sizeof(CFStringRef);
            }
            break;
            
        case kAudioObjectPropertyOwnedObjects:
        case kAudioPlugInPropertyDeviceList: {
            AudioObjectID* theReturnedDeviceList = reinterpret_cast<AudioObjectID*>(outData);
            if (inDataSize >= 2 * sizeof(AudioObjectID)) {
                theReturnedDeviceList[0] = kObjectID_GameDevice;
                theReturnedDeviceList[1] = kObjectID_ChatDevice;
                outDataSize = 2 * sizeof(AudioObjectID);
            } else {
                outDataSize = 0;
            }
            break;
        }
            
        case kAudioPlugInPropertyTranslateUIDToDevice:
            if (inDataSize >= sizeof(AudioObjectID) && inQualifierDataSize == sizeof(CFStringRef)) {
                const CFStringRef* uidPtr = reinterpret_cast<const CFStringRef*>(inQualifierData);
                CFStringRef uid = *uidPtr;
                if (CFStringCompare(uid, CFSTR(kSSChatMixGameDevice_UID), 0) == kCFCompareEqualTo) {
                    *reinterpret_cast<AudioObjectID*>(outData) = kObjectID_GameDevice;
                } else if (CFStringCompare(uid, CFSTR(kSSChatMixChatDevice_UID), 0) == kCFCompareEqualTo) {
                    *reinterpret_cast<AudioObjectID*>(outData) = kObjectID_ChatDevice;
                } else {
                    *reinterpret_cast<AudioObjectID*>(outData) = kAudioObjectUnknown;
                }
                outDataSize = sizeof(AudioObjectID);
            } else {
                outDataSize = 0;
            }
            break;
            
        case kAudioPlugInPropertyResourceBundle:
            if (inDataSize < sizeof(CFStringRef)) {
                result = kAudioHardwareBadPropertySizeError;
            } else {
                *reinterpret_cast<CFStringRef*>(outData) = CFSTR("");
                outDataSize = sizeof(CFStringRef);
            }
            break;
            
        default:
            result = SSChatMix_Object::GetPropertyData(inObjectID, inClientProcessID, inAddress,
                                                       inQualifierDataSize, inQualifierData,
                                                       inDataSize, outDataSize, outData);
            break;
    }
    
    return result;
}

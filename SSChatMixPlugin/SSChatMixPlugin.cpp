//
//  SSChatMixPlugin.cpp
//  SSChatMix HAL Plugin
//
//  CoreAudio Audio Server Plug-in implementation
//  ! pattern - AudioServerPlugInDriver COM-style vtable
//

#include "SSChatMixPlugin.h"
#include "SSChatMix_PlugIn.h"
#include "SSChatMix_Device.h"
#include "SSChatMix_Stream.h"
#include "SSChatMix_Control.h"
#include "SSChatMix_Object.h"
#include "CAException.h"

#include <CoreAudio/AudioServerPlugIn.h>
#include <mach/mach_time.h>

// MARK: - Logging

#define LOG_DEBUG(fmt, ...) os_log(OS_LOG_DEFAULT, "SSChatMixPlugin: " fmt, ##__VA_ARGS__)
#define LOG_ERROR(fmt, ...) os_log(OS_LOG_DEFAULT, "SSChatMixPlugin ERROR: " fmt, ##__VA_ARGS__)

// MARK: - COM Prototypes

extern "C" void*	SSChatMixPlugIn_Create(CFAllocatorRef inAllocator, CFUUIDRef inRequestedTypeUUID);
static HRESULT		SSChatMixPlugIn_QueryInterface(void* inDriver, REFIID inUUID, LPVOID* outInterface);
static ULONG		SSChatMixPlugIn_AddRef(void* inDriver);
static ULONG		SSChatMixPlugIn_Release(void* inDriver);
static OSStatus		SSChatMixPlugIn_Initialize(AudioServerPlugInDriverRef inDriver, AudioServerPlugInHostRef inHost);
static OSStatus		SSChatMixPlugIn_CreateDevice(AudioServerPlugInDriverRef inDriver, CFDictionaryRef inDescription, const AudioServerPlugInClientInfo* inClientInfo, AudioObjectID* outDeviceObjectID);
static OSStatus		SSChatMixPlugIn_DestroyDevice(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID);
static OSStatus		SSChatMixPlugIn_AddDeviceClient(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, const AudioServerPlugInClientInfo* inClientInfo);
static OSStatus		SSChatMixPlugIn_RemoveDeviceClient(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, const AudioServerPlugInClientInfo* inClientInfo);
static OSStatus		SSChatMixPlugIn_PerformDeviceConfigurationChange(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt64 inChangeAction, void* inChangeInfo);
static OSStatus		SSChatMixPlugIn_AbortDeviceConfigurationChange(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt64 inChangeAction, void* inChangeInfo);
static Boolean		SSChatMixPlugIn_HasProperty(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress* inAddress);
static OSStatus		SSChatMixPlugIn_IsPropertySettable(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress* inAddress, Boolean* outIsSettable);
static OSStatus		SSChatMixPlugIn_GetPropertyDataSize(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress* inAddress, UInt32 inQualifierDataSize, const void* inQualifierData, UInt32* outDataSize);
static OSStatus		SSChatMixPlugIn_GetPropertyData(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress* inAddress, UInt32 inQualifierDataSize, const void* inQualifierData, UInt32 inDataSize, UInt32* outDataSize, void* outData);
static OSStatus		SSChatMixPlugIn_SetPropertyData(AudioServerPlugInDriverRef inDriver, AudioObjectID inObjectID, pid_t inClientProcessID, const AudioObjectPropertyAddress* inAddress, UInt32 inQualifierDataSize, const void* inQualifierData, UInt32 inDataSize, const void* inData);
static OSStatus		SSChatMixPlugIn_StartIO(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID);
static OSStatus		SSChatMixPlugIn_StopIO(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID);
static OSStatus		SSChatMixPlugIn_GetZeroTimeStamp(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID, Float64* outSampleTime, UInt64* outHostTime, UInt64* outSeed);
static OSStatus		SSChatMixPlugIn_WillDoIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID, UInt32 inOperationID, Boolean* outWillDo, Boolean* outWillDoInPlace);
static OSStatus		SSChatMixPlugIn_BeginIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID, UInt32 inOperationID, UInt32 inIOBufferFrameSize, const AudioServerPlugInIOCycleInfo* inIOCycleInfo);
static OSStatus		SSChatMixPlugIn_DoIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, AudioObjectID inStreamObjectID, UInt32 inClientID, UInt32 inOperationID, UInt32 inIOBufferFrameSize, const AudioServerPlugInIOCycleInfo* inIOCycleInfo, void* ioMainBuffer, void* ioSecondaryBuffer);
static OSStatus		SSChatMixPlugIn_EndIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID, UInt32 inOperationID, UInt32 inIOBufferFrameSize, const AudioServerPlugInIOCycleInfo* inIOCycleInfo);

#pragma mark - Interface Table

static AudioServerPlugInDriverInterface gAudioServerPlugInDriverInterface =
{
	NULL,
	SSChatMixPlugIn_QueryInterface,
	SSChatMixPlugIn_AddRef,
	SSChatMixPlugIn_Release,
	SSChatMixPlugIn_Initialize,
	SSChatMixPlugIn_CreateDevice,
	SSChatMixPlugIn_DestroyDevice,
	SSChatMixPlugIn_AddDeviceClient,
	SSChatMixPlugIn_RemoveDeviceClient,
	SSChatMixPlugIn_PerformDeviceConfigurationChange,
	SSChatMixPlugIn_AbortDeviceConfigurationChange,
	SSChatMixPlugIn_HasProperty,
	SSChatMixPlugIn_IsPropertySettable,
	SSChatMixPlugIn_GetPropertyDataSize,
	SSChatMixPlugIn_GetPropertyData,
	SSChatMixPlugIn_SetPropertyData,
	SSChatMixPlugIn_StartIO,
	SSChatMixPlugIn_StopIO,
	SSChatMixPlugIn_GetZeroTimeStamp,
	SSChatMixPlugIn_WillDoIOOperation,
	SSChatMixPlugIn_BeginIOOperation,
	SSChatMixPlugIn_DoIOOperation,
	SSChatMixPlugIn_EndIOOperation
};

static AudioServerPlugInDriverInterface* gAudioServerPlugInDriverInterfacePtr = &gAudioServerPlugInDriverInterface;
static AudioServerPlugInDriverRef gAudioServerPlugInDriverRef = &gAudioServerPlugInDriverInterfacePtr;
static UInt32 gAudioServerPlugInDriverRefCount = 1;

// MARK: - Helper Function: Get Object by ObjectID

static SSChatMix_Object* GetObjectByObjectID(AudioObjectID inObjectID) {
    SSChatMix_Object* obj = NULL;
    SSChatMix_PlugIn& plugin = SSChatMix_PlugIn::GetInstance();
    
    if (inObjectID == kObjectID_PlugIn) {
        obj = &plugin;
    } else if (inObjectID == kObjectID_GameDevice) {
        obj = &plugin.GetGameDevice();
    } else if (inObjectID == kObjectID_ChatDevice) {
        obj = &plugin.GetChatDevice();
    } else if (inObjectID == kObjectID_GameDevice_InputStream ||
               inObjectID == kObjectID_GameDevice_OutputStream ||
               inObjectID == kObjectID_GameDevice_VolumeControl) {
        obj = &plugin.GetGameDevice();
    } else if (inObjectID == kObjectID_ChatDevice_InputStream ||
               inObjectID == kObjectID_ChatDevice_OutputStream ||
               inObjectID == kObjectID_ChatDevice_VolumeControl) {
        obj = &plugin.GetChatDevice();
    }
    
    return obj;
}

#pragma mark - Factory

extern "C"
void* SSChatMixPlugIn_Create(CFAllocatorRef inAllocator, CFUUIDRef inRequestedTypeUUID) {
    // This is the CFPlugIn factory function.
    // Returns the AudioServerPlugInDriverRef that points to the driver's interface.
    
    #pragma unused(inAllocator)
    
    void* theAnswer = NULL;
    
    if (CFEqual(inRequestedTypeUUID, kAudioServerPlugInTypeUUID)) {
        theAnswer = gAudioServerPlugInDriverRef;
        
        // Initialize the plugin singleton
        SSChatMix_PlugIn::GetInstance();
    }
    
    return theAnswer;
}

#pragma mark - COM Interface

static HRESULT SSChatMixPlugIn_QueryInterface(void* inDriver, REFIID inUUID, LPVOID* outInterface) {
    // This function is called by the HAL to get the interface to talk to the plug-in through.
    // AudioServerPlugIns must support IUnknown and AudioServerPlugInDriverInterface.
    
    HRESULT theAnswer = 0;
    CFUUIDRef theRequestedUUID = NULL;
    
    try {
        // Validate the arguments
        if (inDriver != gAudioServerPlugInDriverRef) {
            throw CAException(kAudioHardwareBadObjectError);
        }
        
        if (outInterface == NULL) {
            throw CAException(kAudioHardwareIllegalOperationError);
        }
        
        // Make a CFUUIDRef from inUUID
        theRequestedUUID = CFUUIDCreateFromUUIDBytes(NULL, inUUID);
        if (theRequestedUUID == NULL) {
            throw CAException(kAudioHardwareIllegalOperationError);
        }
        
        // AudioServerPlugIns support IUnknown and AudioServerPlugInDriverInterface
        if (!CFEqual(theRequestedUUID, IUnknownUUID) && !CFEqual(theRequestedUUID, kAudioServerPlugInDriverInterfaceUUID)) {
            throw CAException(E_NOINTERFACE);
        }
        
        if (gAudioServerPlugInDriverRefCount == UINT32_MAX) {
            throw CAException(E_NOINTERFACE);
        }
        
        // Return the interface
        ++gAudioServerPlugInDriverRefCount;
        *outInterface = gAudioServerPlugInDriverRef;
    }
    catch(const CAException& inException) {
        theAnswer = inException.GetError();
    }
    catch(...) {
        theAnswer = kAudioHardwareUnspecifiedError;
    }
    
    if (theRequestedUUID != NULL) {
        CFRelease(theRequestedUUID);
    }
    
    return theAnswer;
}

static ULONG SSChatMixPlugIn_AddRef(void* inDriver) {
    // Returns the resulting reference count after the increment.
    
    ULONG theAnswer = 0;
    
    if (inDriver != gAudioServerPlugInDriverRef) {
        // Bad driver reference
        return 0;
    }
    
    if (gAudioServerPlugInDriverRefCount == UINT32_MAX) {
        return 0;
    }
    
    ++gAudioServerPlugInDriverRefCount;
    theAnswer = gAudioServerPlugInDriverRefCount;
    
    return theAnswer;
}

static ULONG SSChatMixPlugIn_Release(void* inDriver) {
    // Returns the resulting reference count after the decrement.
    
    ULONG theAnswer = 0;
    
    if (inDriver != gAudioServerPlugInDriverRef) {
        // Bad driver reference
        return 0;
    }
    
    if (gAudioServerPlugInDriverRefCount == UINT32_MAX) {
        return 0;
    }
    
    // Decrement the refcount
    // Note: We don't do anything special if the refcount goes to zero as the HAL
    // will never fully release a plug-in it opens.
    --gAudioServerPlugInDriverRefCount;
    theAnswer = gAudioServerPlugInDriverRefCount;
    
    return theAnswer;
}

#pragma mark - Basic Operations

static OSStatus SSChatMixPlugIn_Initialize(AudioServerPlugInDriverRef inDriver, AudioServerPlugInHostRef inHost) {
    // Get the driver initialized. Store the AudioServerPlugInHostRef.
    
    OSStatus theAnswer = 0;
    
    try {
        // Check the arguments
        if (inDriver != gAudioServerPlugInDriverRef) {
            throw CAException(kAudioHardwareBadObjectError);
        }
        
        // Store the AudioServerPlugInHostRef
        SSChatMix_PlugIn::SetHost(inHost);
        
        // Init/activate the devices
        SSChatMix_PlugIn::GetInstance();
        
    } catch(const CAException& inException) {
        theAnswer = inException.GetError();
    } catch(...) {
        theAnswer = kAudioHardwareUnspecifiedError;
    }
    
    return theAnswer;
}

static OSStatus SSChatMixPlugIn_CreateDevice(AudioServerPlugInDriverRef inDriver, CFDictionaryRef inDescription, const AudioServerPlugInClientInfo* inClientInfo, AudioObjectID* outDeviceObjectID) {
    // Not supported - devices are statically defined
    
    #pragma unused(inDriver, inDescription, inClientInfo, outDeviceObjectID)
    
    return kAudioHardwareUnsupportedOperationError;
}

static OSStatus SSChatMixPlugIn_DestroyDevice(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID) {
    // Not supported - devices are statically defined
    
    #pragma unused(inDriver, inDeviceObjectID)
    
    return kAudioHardwareUnsupportedOperationError;
}

static OSStatus SSChatMixPlugIn_AddDeviceClient(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, const AudioServerPlugInClientInfo* inClientInfo) {
    #pragma unused(inDriver, inDeviceObjectID, inClientInfo)
    
    return kAudioHardwareUnsupportedOperationError;
}

static OSStatus SSChatMixPlugIn_RemoveDeviceClient(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, const AudioServerPlugInClientInfo* inClientInfo) {
    #pragma unused(inDriver, inDeviceObjectID, inClientInfo)
    
    return kAudioHardwareUnsupportedOperationError;
}

static OSStatus SSChatMixPlugIn_PerformDeviceConfigurationChange(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt64 inChangeAction, void* inChangeInfo) {
    #pragma unused(inDriver, inDeviceObjectID, inChangeAction, inChangeInfo)
    
    return kAudioHardwareUnsupportedOperationError;
}

static OSStatus SSChatMixPlugIn_AbortDeviceConfigurationChange(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt64 inChangeAction, void* inChangeInfo) {
    #pragma unused(inDriver, inDeviceObjectID, inChangeAction, inChangeInfo)
    
    return kAudioHardwareUnsupportedOperationError;
}

#pragma mark - Property Operations

static Boolean SSChatMixPlugIn_HasProperty(AudioServerPlugInDriverRef inDriver,
                                           AudioObjectID inObjectID,
                                           pid_t inClientProcessID,
                                           const AudioObjectPropertyAddress* inAddress) {
    #pragma unused(inDriver)
    
    Boolean theAnswer = false;
    
    SSChatMix_Object* obj = GetObjectByObjectID(inObjectID);
    
    if (obj) {
        theAnswer = obj->HasProperty(inObjectID, inClientProcessID, inAddress);
    } else {
        LOG_DEBUG("HasProperty: Unknown ObjectID %d", inObjectID);
        theAnswer = false;
    }
    
    return theAnswer;
}

static OSStatus SSChatMixPlugIn_IsPropertySettable(AudioServerPlugInDriverRef inDriver,
                                                   AudioObjectID inObjectID,
                                                   pid_t inClientProcessID,
                                                   const AudioObjectPropertyAddress* inAddress,
                                                   Boolean* outIsSettable) {
    #pragma unused(inDriver)
    
    OSStatus theAnswer = kAudioHardwareNoError;
    
    try {
        SSChatMix_Object* obj = GetObjectByObjectID(inObjectID);
        
        if (obj) {
            *outIsSettable = obj->IsPropertySettable(inObjectID, inClientProcessID, inAddress);
        } else {
            *outIsSettable = false;
        }
    } catch(const CAException& inException) {
        theAnswer = inException.GetError();
    } catch(...) {
        theAnswer = kAudioHardwareUnspecifiedError;
    }
    
    return theAnswer;
}

static OSStatus SSChatMixPlugIn_GetPropertyDataSize(AudioServerPlugInDriverRef inDriver,
                                                    AudioObjectID inObjectID,
                                                    pid_t inClientProcessID,
                                                    const AudioObjectPropertyAddress* inAddress,
                                                    UInt32 inQualifierDataSize,
                                                    const void* inQualifierData,
                                                    UInt32* outDataSize) {
    #pragma unused(inDriver)
    
    OSStatus theAnswer = kAudioHardwareNoError;
    
    try {
        SSChatMix_Object* obj = GetObjectByObjectID(inObjectID);
        
        if (obj) {
            *outDataSize = obj->GetPropertyDataSize(inObjectID, inClientProcessID, inAddress,
                                                    inQualifierDataSize, inQualifierData);
        } else {
            LOG_ERROR("GetPropertyDataSize: Unknown ObjectID %d", inObjectID);
            *outDataSize = 0;
            throw CAException(kAudioHardwareBadObjectError);
        }
    } catch(const CAException& inException) {
        theAnswer = inException.GetError();
    } catch(...) {
        theAnswer = kAudioHardwareUnspecifiedError;
    }
    
    return theAnswer;
}

static OSStatus SSChatMixPlugIn_GetPropertyData(AudioServerPlugInDriverRef inDriver,
                                                AudioObjectID inObjectID,
                                                pid_t inClientProcessID,
                                                const AudioObjectPropertyAddress* inAddress,
                                                UInt32 inQualifierDataSize,
                                                const void* inQualifierData,
                                                UInt32 inDataSize,
                                                UInt32* outDataSize,
                                                void* outData) {
    #pragma unused(inDriver)
    
    OSStatus theAnswer = kAudioHardwareNoError;
    
    try {
        SSChatMix_Object* obj = GetObjectByObjectID(inObjectID);
        
        if (obj) {
            theAnswer = obj->GetPropertyData(inObjectID, inClientProcessID, inAddress,
                                             inQualifierDataSize, inQualifierData,
                                             inDataSize, *outDataSize, outData);
        } else {
            LOG_ERROR("GetPropertyData: Unknown ObjectID %d", inObjectID);
            *outDataSize = 0;
            throw CAException(kAudioHardwareBadObjectError);
        }
    } catch(const CAException& inException) {
        theAnswer = inException.GetError();
    } catch(...) {
        theAnswer = kAudioHardwareUnspecifiedError;
    }
    
    return theAnswer;
}

static OSStatus SSChatMixPlugIn_SetPropertyData(AudioServerPlugInDriverRef inDriver,
                                                AudioObjectID inObjectID,
                                                pid_t inClientProcessID,
                                                const AudioObjectPropertyAddress* inAddress,
                                                UInt32 inQualifierDataSize,
                                                const void* inQualifierData,
                                                UInt32 inDataSize,
                                                const void* inData) {
    #pragma unused(inDriver)
    
    OSStatus theAnswer = kAudioHardwareNoError;
    
    try {
        SSChatMix_Object* obj = GetObjectByObjectID(inObjectID);
        
        if (obj) {
            obj->SetPropertyData(inObjectID, inClientProcessID, inAddress,
                                 inQualifierDataSize, inQualifierData,
                                 inDataSize, inData);
        } else {
            LOG_ERROR("SetPropertyData: Unknown ObjectID %d", inObjectID);
        }
    } catch(const CAException& inException) {
        theAnswer = inException.GetError();
    } catch(...) {
        theAnswer = kAudioHardwareUnspecifiedError;
    }
    
    return theAnswer;
}

#pragma mark - IO Operations (Not Supported - Return Unsupported)

static OSStatus SSChatMixPlugIn_StartIO(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID) {
    #pragma unused(inDriver, inDeviceObjectID, inClientID)
    
    return kAudioHardwareUnsupportedOperationError;
}

static OSStatus SSChatMixPlugIn_StopIO(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID) {
    #pragma unused(inDriver, inDeviceObjectID, inClientID)
    
    return kAudioHardwareUnsupportedOperationError;
}

static OSStatus SSChatMixPlugIn_GetZeroTimeStamp(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID, Float64* outSampleTime, UInt64* outHostTime, UInt64* outSeed) {
    #pragma unused(inDriver, inDeviceObjectID, inClientID, outSampleTime, outHostTime, outSeed)
    
    return kAudioHardwareUnsupportedOperationError;
}

static OSStatus SSChatMixPlugIn_WillDoIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID, UInt32 inOperationID, Boolean* outWillDo, Boolean* outWillDoInPlace) {
    #pragma unused(inDriver, inDeviceObjectID, inClientID, inOperationID, outWillDo, outWillDoInPlace)
    
    return kAudioHardwareUnsupportedOperationError;
}

static OSStatus SSChatMixPlugIn_BeginIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID, UInt32 inOperationID, UInt32 inIOBufferFrameSize, const AudioServerPlugInIOCycleInfo* inIOCycleInfo) {
    #pragma unused(inDriver, inDeviceObjectID, inClientID, inOperationID, inIOBufferFrameSize, inIOCycleInfo)
    
    return kAudioHardwareUnsupportedOperationError;
}

static OSStatus SSChatMixPlugIn_DoIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, AudioObjectID inStreamObjectID, UInt32 inClientID, UInt32 inOperationID, UInt32 inIOBufferFrameSize, const AudioServerPlugInIOCycleInfo* inIOCycleInfo, void* ioMainBuffer, void* ioSecondaryBuffer) {
    #pragma unused(inDriver, inDeviceObjectID, inStreamObjectID, inClientID, inOperationID, inIOBufferFrameSize, inIOCycleInfo, ioMainBuffer, ioSecondaryBuffer)
    
    return kAudioHardwareUnsupportedOperationError;
}

static OSStatus SSChatMixPlugIn_EndIOOperation(AudioServerPlugInDriverRef inDriver, AudioObjectID inDeviceObjectID, UInt32 inClientID, UInt32 inOperationID, UInt32 inIOBufferFrameSize, const AudioServerPlugInIOCycleInfo* inIOCycleInfo) {
    #pragma unused(inDriver, inDeviceObjectID, inClientID, inOperationID, inIOBufferFrameSize, inIOCycleInfo)
    
    return kAudioHardwareUnsupportedOperationError;
}

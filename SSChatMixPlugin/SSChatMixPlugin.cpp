//
//  SSChatMixPlugin.cpp
//  SSChatMix HAL Plugin
//
//  CoreAudio Audio Server Plug-in implementation
//  Wraps OOP object hierarchy with AudioServerPlugIn interface
//

#include "SSChatMixPlugin.h"
#include "SSChatMix_PlugIn.h"
#include "SSChatMix_Device.h"
#include "SSChatMix_Stream.h"
#include "SSChatMix_Control.h"
#include "SSChatMix_Object.h"

#include <mach/mach_time.h>

// MARK: - Logging

#define LOG_DEBUG(fmt, ...) os_log(OS_LOG_DEFAULT, "SSChatMixPlugin: " fmt, ##__VA_ARGS__)
#define LOG_ERROR(fmt, ...) os_log(OS_LOG_DEFAULT, "SSChatMixPlugin ERROR: " fmt, ##__VA_ARGS__)

// MARK: - Helper Functions

static AudioServerPlugInRef CreateInterface(AudioServerPlugInHostRef inHost) {
    #pragma unused(inHost)
    
    AudioServerPlugInRef outInterface = NULL;
    
    // Allocate memory for the interface
    outInterface = (AudioServerPlugInRef)malloc(sizeof(AudioServerPlugInInterface));
    
    if (outInterface != NULL) {
        // Initialize the interface table
        outInterface->mInterfaceTable = NULL;
        outInterface->mHost = inHost;
        outInterface->mRefCon = NULL;
        
        // Fill in the function pointers
        outInterface->Initialize = SSChatMixPlugIn_Initialize;
        outInterface->Teardown = SSChatMixPlugIn_Teardown;
        outInterface->IsPropertyObject = NULL;
        outInterface->HasProperty = SSChatMixPlugIn_HasProperty;
        outInterface->IsPropertySettable = SSChatMixPlugIn_IsPropertySettable;
        outInterface->GetPropertyDataSize = SSChatMixPlugIn_GetPropertyDataSize;
        outInterface->GetPropertyData = SSChatMixPlugIn_GetPropertyData;
        outInterface->SetPropertyData = SSChatMixPlugIn_SetPropertyData;
        outInterface->AllocateActionListEntry = NULL;
        outInterface->AppendActionsToRun = NULL;
        outInterface->CreateDevice = NULL;
        outInterface->DestroyDevice = NULL;
        outInterface->AddDeviceMember = NULL;
        outInterface->RemoveDeviceMember = NULL;
        outInterface->WillDoIOOperation = NULL;
        outInterface->BeginIOOperation = NULL;
        outInterface->DoIOOperation = NULL;
        outInterface->EndIOOperation = NULL;
        outInterface->StartIO = NULL;
        outInterface->StopIO = NULL;
        outInterface->GetZeroTimeStamp = NULL;
        outInterface->ReadInput = NULL;
        outInterface->WriteOutput = NULL;
        outInterface->DeviceHasChanged = NULL;
        outInterface->ReconfigureIO = NULL;
        outInterface->CanDoIOOperation = NULL;
    }
    
    return outInterface;
}

// MARK: - AudioServerPlugIn Interface Functions

static OSStatus SSChatMixPlugIn_Initialize(AudioServerPlugInRef inThis,
                                           AudioServerPlugInHostRef inHost) {
    #pragma unused(inThis)
    
    LOG_DEBUG("SSChatMixPlugIn_Initialize");
    
    // Initialize the plugin singleton
    OSStatus result = SSChatMix_PlugIn::StaticInitialize(inHost);
    
    if (result == kAudioHardwareNoError) {
        LOG_DEBUG("Plugin initialized successfully");
    } else {
        LOG_ERROR("Plugin initialization failed: %d", result);
    }
    
    return result;
}

static OSStatus SSChatMixPlugIn_Teardown(AudioServerPlugInRef inThis) {
    #pragma unused(inThis)
    
    LOG_DEBUG("SSChatMixPlugIn_Teardown");
    
    // Clean up the plugin singleton
    SSChatMix_PlugIn::GetInstance();
    
    return kAudioHardwareNoError;
}

static OSStatus SSChatMixPlugIn_IsPropertyObject(AudioServerPlugInRef inThis,
                                                 AudioObjectID inObjectID,
                                                 pid_t inClientProcessID,
                                                 const AudioObjectPropertyAddress* inAddress,
                                                 Boolean* outIsPropertyObject) {
    #pragma unused(inThis, inObjectID, inClientProcessID, inAddress, outIsPropertyObject)
    
    // Not implemented - return false
    *outIsPropertyObject = false;
    return kAudioHardwareUnsupportedOperationError;
}

static OSStatus SSChatMixPlugIn_HasProperty(AudioServerPlugInRef inThis,
                                            AudioObjectID inObjectID,
                                            pid_t inClientProcessID,
                                            const AudioObjectPropertyAddress* inAddress,
                                            Boolean* outAnswer) {
    #pragma unused(inThis)
    
    // Dispatch to the appropriate OOP object
    SSChatMix_Object* obj = NULL;
    
    // Determine which object this ObjectID belongs to
    if (inObjectID == kObjectID_PlugIn) {
        obj = SSChatMix_PlugIn::GetInstance();
    } else if (inObjectID == kObjectID_GameDevice || inObjectID == kObjectID_ChatDevice) {
        SSChatMix_PlugIn* plugin = SSChatMix_PlugIn::GetInstance();
        if (inObjectID == kObjectID_GameDevice) {
            obj = plugin->GetGameDevice();
        } else {
            obj = plugin->GetChatDevice();
        }
    } else if (inObjectID == kObjectID_GameDevice_InputStream ||
               inObjectID == kObjectID_GameDevice_OutputStream ||
               inObjectID == kObjectID_ChatDevice_InputStream ||
               inObjectID == kObjectID_ChatDevice_OutputStream) {
        // Get the parent device and find the stream
        AudioObjectID deviceID = (inObjectID == kObjectID_GameDevice_InputStream ||
                                  inObjectID == kObjectID_GameDevice_OutputStream)
                                 ? kObjectID_GameDevice : kObjectID_ChatDevice;
        SSChatMix_PlugIn* plugin = SSChatMix_PlugIn::GetInstance();
        SSChatMix_Device* device = (deviceID == kObjectID_GameDevice)
                                   ? plugin->GetGameDevice() : plugin->GetChatDevice();
        if (device) {
            obj = device->GetStream(inObjectID);
        }
    } else if (inObjectID == kObjectID_VolumeControl) {
        // Volume control belongs to the game device
        SSChatMix_PlugIn* plugin = SSChatMix_PlugIn::GetInstance();
        SSChatMix_Device* device = plugin->GetGameDevice();
        if (device) {
            obj = device->GetVolumeControl();
        }
    }
    
    if (obj) {
        *outAnswer = obj->HasProperty(inObjectID, inClientProcessID, inAddress);
    } else {
        LOG_ERROR("HasProperty: Unknown ObjectID %d", inObjectID);
        *outAnswer = false;
    }
    
    return kAudioHardwareNoError;
}

static OSStatus SSChatMixPlugIn_IsPropertySettable(AudioServerPlugInRef inThis,
                                                   AudioObjectID inObjectID,
                                                   pid_t inClientProcessID,
                                                   const AudioObjectPropertyAddress* inAddress,
                                                   Boolean* outAnswer) {
    #pragma unused(inThis)
    
    SSChatMix_Object* obj = NULL;
    
    if (inObjectID == kObjectID_PlugIn) {
        obj = SSChatMix_PlugIn::GetInstance();
    } else if (inObjectID == kObjectID_GameDevice || inObjectID == kObjectID_ChatDevice) {
        SSChatMix_PlugIn* plugin = SSChatMix_PlugIn::GetInstance();
        if (inObjectID == kObjectID_GameDevice) {
            obj = plugin->GetGameDevice();
        } else {
            obj = plugin->GetChatDevice();
        }
    } else if (inObjectID == kObjectID_GameDevice_InputStream ||
               inObjectID == kObjectID_GameDevice_OutputStream ||
               inObjectID == kObjectID_ChatDevice_InputStream ||
               inObjectID == kObjectID_ChatDevice_OutputStream) {
        AudioObjectID deviceID = (inObjectID == kObjectID_GameDevice_InputStream ||
                                  inObjectID == kObjectID_GameDevice_OutputStream)
                                 ? kObjectID_GameDevice : kObjectID_ChatDevice;
        SSChatMix_PlugIn* plugin = SSChatMix_PlugIn::GetInstance();
        SSChatMix_Device* device = (deviceID == kObjectID_GameDevice)
                                   ? plugin->GetGameDevice() : plugin->GetChatDevice();
        if (device) {
            obj = device->GetStream(inObjectID);
        }
    } else if (inObjectID == kObjectID_VolumeControl) {
        SSChatMix_PlugIn* plugin = SSChatMix_PlugIn::GetInstance();
        SSChatMix_Device* device = plugin->GetGameDevice();
        if (device) {
            obj = device->GetVolumeControl();
        }
    }
    
    if (obj) {
        *outAnswer = obj->IsPropertySettable(inObjectID, inClientProcessID, inAddress);
    } else {
        *outAnswer = false;
    }
    
    return kAudioHardwareNoError;
}

static OSStatus SSChatMixPlugIn_GetPropertyDataSize(AudioServerPlugInRef inThis,
                                                    AudioObjectID inObjectID,
                                                    pid_t inClientProcessID,
                                                    const AudioObjectPropertyAddress* inAddress,
                                                    UInt32 inQualifierDataSize,
                                                    const void* inQualifierData,
                                                    UInt32* outDataSize) {
    #pragma unused(inThis)
    
    SSChatMix_Object* obj = NULL;
    
    if (inObjectID == kObjectID_PlugIn) {
        obj = SSChatMix_PlugIn::GetInstance();
    } else if (inObjectID == kObjectID_GameDevice || inObjectID == kObjectID_ChatDevice) {
        SSChatMix_PlugIn* plugin = SSChatMix_PlugIn::GetInstance();
        if (inObjectID == kObjectID_GameDevice) {
            obj = plugin->GetGameDevice();
        } else {
            obj = plugin->GetChatDevice();
        }
    } else if (inObjectID == kObjectID_GameDevice_InputStream ||
               inObjectID == kObjectID_GameDevice_OutputStream ||
               inObjectID == kObjectID_ChatDevice_InputStream ||
               inObjectID == kObjectID_ChatDevice_OutputStream) {
        AudioObjectID deviceID = (inObjectID == kObjectID_GameDevice_InputStream ||
                                  inObjectID == kObjectID_GameDevice_OutputStream)
                                 ? kObjectID_GameDevice : kObjectID_ChatDevice;
        SSChatMix_PlugIn* plugin = SSChatMix_PlugIn::GetInstance();
        SSChatMix_Device* device = (deviceID == kObjectID_GameDevice)
                                   ? plugin->GetGameDevice() : plugin->GetChatDevice();
        if (device) {
            obj = device->GetStream(inObjectID);
        }
    } else if (inObjectID == kObjectID_VolumeControl) {
        SSChatMix_PlugIn* plugin = SSChatMix_PlugIn::GetInstance();
        SSChatMix_Device* device = plugin->GetGameDevice();
        if (device) {
            obj = device->GetVolumeControl();
        }
    }
    
    if (obj) {
        *outDataSize = obj->GetPropertyDataSize(inObjectID, inClientProcessID, inAddress,
                                                inQualifierDataSize, inQualifierData);
    } else {
        LOG_ERROR("GetPropertyDataSize: Unknown ObjectID %d", inObjectID);
        *outDataSize = 0;
        return kAudioHardwareBadObjectError;
    }
    
    return kAudioHardwareNoError;
}

static OSStatus SSChatMixPlugIn_GetPropertyData(AudioServerPlugInRef inThis,
                                                AudioObjectID inObjectID,
                                                pid_t inClientProcessID,
                                                const AudioObjectPropertyAddress* inAddress,
                                                UInt32 inQualifierDataSize,
                                                const void* inQualifierData,
                                                UInt32 inDataSize,
                                                UInt32* outDataSize,
                                                void* outData) {
    #pragma unused(inThis)
    
    SSChatMix_Object* obj = NULL;
    
    if (inObjectID == kObjectID_PlugIn) {
        obj = SSChatMix_PlugIn::GetInstance();
    } else if (inObjectID == kObjectID_GameDevice || inObjectID == kObjectID_ChatDevice) {
        SSChatMix_PlugIn* plugin = SSChatMix_PlugIn::GetInstance();
        if (inObjectID == kObjectID_GameDevice) {
            obj = plugin->GetGameDevice();
        } else {
            obj = plugin->GetChatDevice();
        }
    } else if (inObjectID == kObjectID_GameDevice_InputStream ||
               inObjectID == kObjectID_GameDevice_OutputStream ||
               inObjectID == kObjectID_ChatDevice_InputStream ||
               inObjectID == kObjectID_ChatDevice_OutputStream) {
        AudioObjectID deviceID = (inObjectID == kObjectID_GameDevice_InputStream ||
                                  inObjectID == kObjectID_GameDevice_OutputStream)
                                 ? kObjectID_GameDevice : kObjectID_ChatDevice;
        SSChatMix_PlugIn* plugin = SSChatMix_PlugIn::GetInstance();
        SSChatMix_Device* device = (deviceID == kObjectID_GameDevice)
                                   ? plugin->GetGameDevice() : plugin->GetChatDevice();
        if (device) {
            obj = device->GetStream(inObjectID);
        }
    } else if (inObjectID == kObjectID_VolumeControl) {
        SSChatMix_PlugIn* plugin = SSChatMix_PlugIn::GetInstance();
        SSChatMix_Device* device = plugin->GetGameDevice();
        if (device) {
            obj = device->GetVolumeControl();
        }
    }
    
    if (obj) {
        return obj->GetPropertyData(inObjectID, inClientProcessID, inAddress,
                                    inQualifierDataSize, inQualifierData,
                                    inDataSize, *outDataSize, outData);
    } else {
        LOG_ERROR("GetPropertyData: Unknown ObjectID %d", inObjectID);
        *outDataSize = 0;
        return kAudioHardwareBadObjectError;
    }
}

static OSStatus SSChatMixPlugIn_SetPropertyData(AudioServerPlugInRef inThis,
                                                AudioObjectID inObjectID,
                                                pid_t inClientProcessID,
                                                const AudioObjectPropertyAddress* inAddress,
                                                UInt32 inQualifierDataSize,
                                                const void* inQualifierData,
                                                UInt32 inDataSize,
                                                const void* inData,
                                                UInt32* outDataSize) {
    #pragma unused(inThis, outDataSize)
    
    SSChatMix_Object* obj = NULL;
    
    if (inObjectID == kObjectID_PlugIn) {
        obj = SSChatMix_PlugIn::GetInstance();
    } else if (inObjectID == kObjectID_GameDevice || inObjectID == kObjectID_ChatDevice) {
        SSChatMix_PlugIn* plugin = SSChatMix_PlugIn::GetInstance();
        if (inObjectID == kObjectID_GameDevice) {
            obj = plugin->GetGameDevice();
        } else {
            obj = plugin->GetChatDevice();
        }
    } else if (inObjectID == kObjectID_GameDevice_InputStream ||
               inObjectID == kObjectID_GameDevice_OutputStream ||
               inObjectID == kObjectID_ChatDevice_InputStream ||
               inObjectID == kObjectID_ChatDevice_OutputStream) {
        AudioObjectID deviceID = (inObjectID == kObjectID_GameDevice_InputStream ||
                                  inObjectID == kObjectID_GameDevice_OutputStream)
                                 ? kObjectID_GameDevice : kObjectID_ChatDevice;
        SSChatMix_PlugIn* plugin = SSChatMix_PlugIn::GetInstance();
        SSChatMix_Device* device = (deviceID == kObjectID_GameDevice)
                                   ? plugin->GetGameDevice() : plugin->GetChatDevice();
        if (device) {
            obj = device->GetStream(inObjectID);
        }
    } else if (inObjectID == kObjectID_VolumeControl) {
        SSChatMix_PlugIn* plugin = SSChatMix_PlugIn::GetInstance();
        SSChatMix_Device* device = plugin->GetGameDevice();
        if (device) {
            obj = device->GetVolumeControl();
        }
    }
    
    if (obj) {
        obj->SetPropertyData(inObjectID, inClientProcessID, inAddress,
                             inQualifierDataSize, inQualifierData,
                             inDataSize, inData);
    } else {
        LOG_ERROR("SetPropertyData: Unknown ObjectID %d", inObjectID);
    }
    
    return kAudioHardwareNoError;
}

// MARK: - Device Management (Not Supported - Return Unsupported)

static OSStatus SSChatMixPlugIn_CreateDevice(AudioServerPlugInRef inThis,
                                             UInt32 inAddressSize,
                                             const void* inAddressData,
                                             AudioObjectID* outDeviceID) {
    #pragma unused(inThis, inAddressSize, inAddressData, outDeviceID)
    
    LOG_DEBUG("CreateDevice called - not supported");
    return kAudioHardwareUnsupportedOperationError;
}

static OSStatus SSChatMixPlugIn_DestroyDevice(AudioServerPlugInRef inThis,
                                              AudioObjectID inDeviceID) {
    #pragma unused(inThis, inDeviceID)
    
    LOG_DEBUG("DestroyDevice called - not supported");
    return kAudioHardwareUnsupportedOperationError;
}

static OSStatus SSChatMixPlugIn_AddDeviceMember(AudioServerPlugInRef inThis,
                                                AudioObjectID inDeviceID,
                                                AudioObjectID inMemberID) {
    #pragma unused(inThis, inDeviceID, inMemberID)
    
    return kAudioHardwareUnsupportedOperationError;
}

static OSStatus SSChatMixPlugIn_RemoveDeviceMember(AudioServerPlugInRef inThis,
                                                   AudioObjectID inDeviceID,
                                                   AudioObjectID inMemberID) {
    #pragma unused(inThis, inDeviceID, inMemberID)
    
    return kAudioHardwareUnsupportedOperationError;
}

// MARK: - IO Operations (Not Supported - Return Unsupported)

static OSStatus SSChatMixPlugIn_WillDoIOOperation(AudioServerPlugInRef inThis,
                                                  AudioObjectID inDeviceID,
                                                  Boolean inForInput,
                                                  UInt32 inClientProcessID) {
    #pragma unused(inThis, inDeviceID, inForInput, inClientProcessID)
    
    return kAudioHardwareUnsupportedOperationError;
}

static OSStatus SSChatMixPlugIn_BeginIOOperation(AudioServerPlugInRef inThis,
                                                 AudioObjectID inDeviceID,
                                                 Boolean inForInput,
                                                 UInt32 inClientProcessID,
                                                 AudioServerPlugInIOProcID inIOProc,
                                                 void* inContext,
                                                 AudioServerPlugInIOActionRecord* inActionRecords) {
    #pragma unused(inThis, inDeviceID, inForInput, inClientProcessID, inIOProc, inContext, inActionRecords)
    
    return kAudioHardwareUnsupportedOperationError;
}

static OSStatus SSChatMixPlugIn_DoIOOperation(AudioServerPlugInRef inThis,
                                              AudioObjectID inDeviceID,
                                              Boolean inForInput,
                                              UInt32 inClientProcessID,
                                              AudioServerPlugInIOProcID inIOProc,
                                              void* inContext,
                                              UInt32 inNumRecords,
                                              AudioServerPlugInIOActionRecord* inActionRecords) {
    #pragma unused(inThis, inDeviceID, inForInput, inClientProcessID, inIOProc, inContext, inNumRecords, inActionRecords)
    
    return kAudioHardwareUnsupportedOperationError;
}

static OSStatus SSChatMixPlugIn_EndIOOperation(AudioServerPlugInRef inThis,
                                               AudioObjectID inDeviceID,
                                               Boolean inForInput,
                                               UInt32 inClientProcessID,
                                               AudioServerPlugInIOProcID inIOProc,
                                               void* inContext,
                                               UInt32 inNumRecords,
                                               AudioServerPlugInIOActionRecord* inActionRecords) {
    #pragma unused(inThis, inDeviceID, inForInput, inClientProcessID, inIOProc, inContext, inNumRecords, inActionRecords)
    
    return kAudioHardwareUnsupportedOperationError;
}

static OSStatus SSChatMixPlugIn_StartIO(AudioServerPlugInRef inThis,
                                        AudioObjectID inDeviceID,
                                        Float64 inSampleRate) {
    #pragma unused(inThis, inDeviceID, inSampleRate)
    
    LOG_DEBUG("StartIO called - not supported");
    return kAudioHardwareUnsupportedOperationError;
}

static OSStatus SSChatMixPlugIn_StopIO(AudioServerPlugInRef inThis,
                                       AudioObjectID inDeviceID) {
    #pragma unused(inThis, inDeviceID)
    
    LOG_DEBUG("StopIO called - not supported");
    return kAudioHardwareUnsupportedOperationError;
}

static OSStatus SSChatMixPlugIn_GetZeroTimeStamp(AudioServerPlugInRef inThis,
                                                 AudioObjectID inDeviceID,
                                                 Float64* outSampleTime,
                                                 Float64* outHostTime,
                                                 Float64* outTimeStamp) {
    #pragma unused(inThis, inDeviceID, outSampleTime, outHostTime, outTimeStamp)
    
    return kAudioHardwareUnsupportedOperationError;
}

static OSStatus SSChatMixPlugIn_ReadInput(AudioServerPlugInRef inThis,
                                          AudioObjectID inDeviceID,
                                          AudioServerPlugInBufferDescription* inBufferDescriptions,
                                          UInt32 inNumBuffers,
                                          AudioTimeStamp* inTimeStamp,
                                          UInt32* outNumPackages,
                                          UInt8* outPacketDescriptions) {
    #pragma unused(inThis, inDeviceID, inBufferDescriptions, inNumBuffers, inTimeStamp, outNumPackages, outPacketDescriptions)
    
    return kAudioHardwareUnsupportedOperationError;
}

static OSStatus SSChatMixPlugIn_WriteOutput(AudioServerPlugInRef inThis,
                                            AudioObjectID inDeviceID,
                                            AudioServerPlugInBufferDescription* inBufferDescriptions,
                                            UInt32 inNumBuffers,
                                            AudioTimeStamp* inTimeStamp,
                                            UInt32 inNumPackages,
                                            const UInt8* inPacketDescriptions) {
    #pragma unused(inThis, inDeviceID, inBufferDescriptions, inNumBuffers, inTimeStamp, inNumPackages, inPacketDescriptions)
    
    return kAudioHardwareUnsupportedOperationError;
}

static OSStatus SSChatMixPlugIn_DeviceHasChanged(AudioServerPlugInRef inThis,
                                                 AudioObjectID inDeviceID) {
    #pragma unused(inThis, inDeviceID)
    
    return kAudioHardwareUnsupportedOperationError;
}

static OSStatus SSChatMixPlugIn_ReconfigureIO(AudioServerPlugInRef inThis,
                                              AudioObjectID inDeviceID,
                                              UInt32 inClientProcessID) {
    #pragma unused(inThis, inDeviceID, inClientProcessID)
    
    return kAudioHardwareUnsupportedOperationError;
}

static OSStatus SSChatMixPlugIn_CanDoIOOperation(AudioServerPlugInRef inThis,
                                                 AudioObjectID inDeviceID,
                                                 Boolean inForInput,
                                                 UInt32 inClientProcessID) {
    #pragma unused(inThis, inDeviceID, inForInput, inClientProcessID)
    
    return kAudioHardwareUnsupportedOperationError;
}

// MARK: - Interface Table

static AudioServerPlugInInterface gPlugInInterface = {
    NULL,  // mInterfaceTable (set dynamically)
    NULL,  // mHost (set dynamically)
    NULL,  // mRefCon (set dynamically)
    SSChatMixPlugIn_Initialize,
    SSChatMixPlugIn_Teardown,
    SSChatMixPlugIn_IsPropertyObject,
    SSChatMixPlugIn_HasProperty,
    SSChatMixPlugIn_IsPropertySettable,
    SSChatMixPlugIn_GetPropertyDataSize,
    SSChatMixPlugIn_GetPropertyData,
    SSChatMixPlugIn_SetPropertyData,
    NULL,  // AllocateActionListEntry
    NULL,  // AppendActionsToRun
    SSChatMixPlugIn_CreateDevice,
    SSChatMixPlugIn_DestroyDevice,
    SSChatMixPlugIn_AddDeviceMember,
    SSChatMixPlugIn_RemoveDeviceMember,
    SSChatMixPlugIn_WillDoIOOperation,
    SSChatMixPlugIn_BeginIOOperation,
    SSChatMixPlugIn_DoIOOperation,
    SSChatMixPlugIn_EndIOOperation,
    SSChatMixPlugIn_StartIO,
    SSChatMixPlugIn_StopIO,
    SSChatMixPlugIn_GetZeroTimeStamp,
    SSChatMixPlugIn_ReadInput,
    SSChatMixPlugIn_WriteOutput,
    NULL,  // DeviceHasChanged
    NULL,  // ReconfigureIO
    NULL,  // CanDoIOOperation
};

// MARK: - Plugin Entry Point

void* SSChatMixPlugIn_Create(CFAllocatorRef allocator, CFUUIDRef requestedTypeUUID) {
    #pragma unused(allocator)
    
    static CFUUIDRef sAudioServerPlugInTypeUUID = NULL;
    
    if (sAudioServerPlugInTypeUUID == NULL) {
        sAudioServerPlugInTypeUUID = CFUUIDCreateFromUUIDBytes(kCFAllocatorDefault,
                                                               *reinterpret_cast<CFUUIDBytes*>(
                                                                   "\x44\x3A\xBA\xB8\xE7\xB3\x49\x1A\xB9\x85\xBE\xB9\x18\x70\x30\xDB"));
    }
    
    void* result = NULL;
    
    if (CFEqual(requestedTypeUUID, sAudioServerPlugInTypeUUID)) {
        // Create the interface
        AudioServerPlugInRef interface = CreateInterface(NULL);
        
        if (interface != NULL) {
            // Copy the interface table
            memcpy(interface, &gPlugInInterface, sizeof(AudioServerPlugInInterface));
            result = interface;
        }
    }
    
    return result;
}

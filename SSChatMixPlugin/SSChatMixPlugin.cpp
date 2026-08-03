//
//  SSChatMixPlugin.cpp
//  SSChatMix HAL Plugin
//
//  Based on AudioServerPlugIn API
//

#include "SSChatMixPlugin.h"
#include <pthread.h>
#include <mach/mach_time.h>
#include <sys/syslog.h>

// MARK: - Ring Buffer (Thread-safe circular buffer for audio)

struct RingBuffer {
    Float32* buffer;
    UInt32 capacity;        // Total frames
    UInt32 writeIndex;
    UInt32 readIndex;
    pthread_mutex_t lock;
    
    RingBuffer(UInt32 frames) : capacity(frames), writeIndex(0), readIndex(0) {
        buffer = (Float32*)calloc(frames * kSSChatMix_Channels, sizeof(Float32));
        pthread_mutex_init(&lock, NULL);
    }
    
    ~RingBuffer() {
        free(buffer);
        pthread_mutex_destroy(&lock);
    }
    
    void Write(const Float32* data, UInt32 frames) {
        pthread_mutex_lock(&lock);
        
        for (UInt32 i = 0; i < frames * kSSChatMix_Channels; i++) {
            buffer[writeIndex * kSSChatMix_Channels + (i % kSSChatMix_Channels)] = data[i];
            writeIndex = (writeIndex + 1) % capacity;
        }
        
        pthread_mutex_unlock(&lock);
    }
    
    void Read(Float32* data, UInt32 frames) {
        pthread_mutex_lock(&lock);
        
        for (UInt32 i = 0; i < frames * kSSChatMix_Channels; i++) {
            data[i] = buffer[readIndex * kSSChatMix_Channels + (i % kSSChatMix_Channels)];
            readIndex = (readIndex + 1) % capacity;
        }
        
        pthread_mutex_unlock(&lock);
    }
    
    UInt32 AvailableFrames() {
        pthread_mutex_lock(&lock);
        UInt32 available = (writeIndex >= readIndex) 
            ? (writeIndex - readIndex) 
            : (capacity - readIndex + writeIndex);
        pthread_mutex_unlock(&lock);
        return available;
    }
};

// MARK: - Plugin State

struct SSChatMixPlugInState {
    AudioServerPlugInHostRef host;
    
    // Timing for audio clock
    Float64 hostTicksPerFrame;
    UInt64 numberTimeStamps;
    Float64 anchorSampleTime;
    UInt64 anchorHostTime;
    
    // IO state
    UInt64 gameDeviceIORunning;
    UInt64 chatDeviceIORunning;
    
    // Ring buffers for audio routing
    RingBuffer* gameBuffer;
    RingBuffer* chatBuffer;
    
    // Volume control (0.0 - 1.0)
    Float32 gameVolume;
    Float32 chatVolume;
    
    // Mutexes
    pthread_mutex_t stateMutex;
    pthread_mutex_t ioMutex;
    
    SSChatMixPlugInState() 
        : host(NULL)
        , hostTicksPerFrame(0.0)
        , numberTimeStamps(0)
        , anchorSampleTime(0.0)
        , anchorHostTime(0)
        , gameDeviceIORunning(0)
        , chatDeviceIORunning(0)
        , gameVolume(1.0f)
        , chatVolume(1.0f) 
    {
        pthread_mutex_init(&stateMutex, NULL);
        pthread_mutex_init(&ioMutex, NULL);
        gameBuffer = new RingBuffer(kSSChatMix_RingBufferFrames);
        chatBuffer = new RingBuffer(kSSChatMix_RingBufferFrames);
    }
    
    ~SSChatMixPlugInState() {
        delete gameBuffer;
        delete chatBuffer;
        pthread_mutex_destroy(&stateMutex);
        pthread_mutex_destroy(&ioMutex);
    }
};

static SSChatMixPlugInState* gPlugInState = NULL;

// MARK: - AudioServerPlugIn Interface Implementation

static OSStatus SSChatMixPlugIn_Initialize(AudioServerPlugInDriverRef inDriver, AudioServerPlugInHostRef inHost) {
    os_log(OS_LOG_DEFAULT, "SSChatMixPlugIn_Initialize");
    
    if (gPlugInState == NULL) {
        gPlugInState = new SSChatMixPlugInState();
    }
    
    gPlugInState->host = inHost;
    
    // Calculate host ticks per frame for audio timing
    struct mach_timebase_info timeBaseInfo;
    mach_timebase_info(&timeBaseInfo);
    Float64 hostClockFrequency = (Float64)timeBaseInfo.denom / (Float64)timeBaseInfo.numer;
    hostClockFrequency *= 1000000000.0;  // Convert to nanoseconds
    gPlugInState->hostTicksPerFrame = hostClockFrequency / kSSChatMix_SampleRate;
    
    // Initialize anchor times
    gPlugInState->anchorHostTime = mach_absolute_time();
    gPlugInState->anchorSampleTime = 0.0;
    gPlugInState->numberTimeStamps = 0;
    
    os_log(OS_LOG_DEFAULT, "SSChatMixPlugIn_Initialize: hostTicksPerFrame=%f", gPlugInState->hostTicksPerFrame);
    
    return kAudioHardwareNoError;
}

static OSStatus SSChatMixPlugIn_Teardown(AudioServerPlugInDriverRef inDriver) {
    os_log(OS_LOG_DEFAULT, "SSChatMixPlugIn_Teardown");
    
    if (gPlugInState != NULL) {
        delete gPlugInState;
        gPlugInState = NULL;
    }
    
    return kAudioHardwareNoError;
}

static HRESULT SSChatMixPlugIn_QueryInterface(void* inDriver, REFIID inUUID, LPVOID* outInterface) {
    // Standard QueryInterface implementation
    CFUUIDRef interfaceUUID = CFUUIDCreateFromUUIDBytes(NULL, inUUID);
    
    if (CFEqual(interfaceUUID, IUnknownUUID) || CFEqual(interfaceUUID, kAudioServerPlugInDriverInterfaceUUID)) {
        *outInterface = inDriver;
        CFRelease(interfaceUUID);
        return S_OK;
    }
    
    CFRelease(interfaceUUID);
    return E_NOINTERFACE;
}

static ULONG SSChatMixPlugIn_AddRef(void* inDriver) {
    return 1;
}

static ULONG SSChatMixPlugIn_Release(void* inDriver) {
    return 1;
}

// MARK: - Property Handlers

static Boolean SSChatMixPlugIn_HasProperty(
    AudioServerPlugInDriverRef inDriver,
    AudioObjectID inObjectID,
    pid_t inClientProcessID,
    const AudioObjectPropertyAddress* inAddress)
{
    Boolean hasProperty = false;
    
    // Log all property queries to see what HAL is asking for
    UInt32 selector = CFSwapInt32HostToBig(inAddress->mSelector);
    os_log(OS_LOG_DEFAULT, "SSChatMixPlugIn_HasProperty: object=%u, selector='%c%c%c%c' (0x%x), scope=0x%x",
           inObjectID,
           (char)((selector >> 24) & 0xFF),
           (char)((selector >> 16) & 0xFF),
           (char)((selector >> 8) & 0xFF),
           (char)(selector & 0xFF),
           inAddress->mSelector,
           inAddress->mScope);
    
    switch (inObjectID) {
        case kObjectID_PlugIn:
            // Plugin object properties
            switch (inAddress->mSelector) {
                case kAudioObjectPropertyBaseClass:
                case kAudioObjectPropertyClass:
                case kAudioObjectPropertyOwner:
                case kAudioObjectPropertyManufacturer:
                case kAudioObjectPropertyOwnedObjects:
                case kAudioPlugInPropertyDeviceList:
                case kAudioPlugInPropertyTranslateUIDToDevice:
                case kAudioPlugInPropertyResourceBundle:
                    hasProperty = true;
                    break;
            }
            break;
            
        case kObjectID_GameDevice:
        case kObjectID_ChatDevice:
            // Device properties
            switch (inAddress->mSelector) {
                case kAudioObjectPropertyBaseClass:
                case kAudioObjectPropertyClass:
                case kAudioObjectPropertyOwner:
                case kAudioObjectPropertyName:
                case kAudioObjectPropertyManufacturer:
                case kAudioObjectPropertyOwnedObjects:
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
                    hasProperty = true;
                    break;
            }
            break;
            
        case kObjectID_GameDevice_InputStream:
        case kObjectID_GameDevice_OutputStream:
        case kObjectID_ChatDevice_InputStream:
        case kObjectID_ChatDevice_OutputStream:
            // Stream properties
            switch (inAddress->mSelector) {
                case kAudioObjectPropertyBaseClass:
                case kAudioObjectPropertyClass:
                case kAudioObjectPropertyOwner:
                case kAudioStreamPropertyIsActive:
                case kAudioStreamPropertyDirection:
                case kAudioStreamPropertyTerminalType:
                case kAudioStreamPropertyStartingChannel:
                case kAudioStreamPropertyLatency:
                case kAudioStreamPropertyVirtualFormat:
                case kAudioStreamPropertyPhysicalFormat:
                case kAudioStreamPropertyAvailableVirtualFormats:
                case kAudioStreamPropertyAvailablePhysicalFormats:
                    hasProperty = true;
                    break;
            }
            break;
    }
    
    os_log(OS_LOG_DEFAULT, "SSChatMixPlugIn_HasProperty: object=%u, selector=0x%x -> %s",
           inObjectID, inAddress->mSelector, hasProperty ? "YES" : "NO");
    
    return hasProperty;
}

static OSStatus SSChatMixPlugIn_IsPropertySettable(
    AudioServerPlugInDriverRef inDriver,
    AudioObjectID inObjectID,
    pid_t inClientProcessID,
    const AudioObjectPropertyAddress* inAddress,
    Boolean* outIsSettable)
{
    OSStatus result = kAudioHardwareNoError;
    
    switch (inObjectID) {
        case kObjectID_PlugIn:
            switch (inAddress->mSelector) {
                case kAudioObjectPropertyBaseClass:
                case kAudioObjectPropertyClass:
                case kAudioObjectPropertyOwner:
                case kAudioObjectPropertyManufacturer:
                case kAudioObjectPropertyOwnedObjects:
                case kAudioPlugInPropertyBoxList:
                case kAudioPlugInPropertyDeviceList:
                case kAudioPlugInPropertyTranslateUIDToDevice:
                case kAudioPlugInPropertyResourceBundle:
                    *outIsSettable = false;
                    break;
                default:
                    result = kAudioHardwareUnknownPropertyError;
                    break;
            }
            break;
            
        case kObjectID_GameDevice:
        case kObjectID_ChatDevice:
            switch (inAddress->mSelector) {
                case kAudioDevicePropertyNominalSampleRate:
                    *outIsSettable = false;  // We only support 48kHz
                    break;
                default:
                    *outIsSettable = false;
                    break;
            }
            break;
            
        case kObjectID_GameDevice_InputStream:
        case kObjectID_GameDevice_OutputStream:
        case kObjectID_ChatDevice_InputStream:
        case kObjectID_ChatDevice_OutputStream:
            *outIsSettable = false;
            break;
            
        default:
            result = kAudioHardwareBadObjectError;
            break;
    }
    
    return result;
}

static OSStatus SSChatMixPlugIn_GetPropertyDataSize(
    AudioServerPlugInDriverRef inDriver,
    AudioObjectID inObjectID,
    pid_t inClientProcessID,
    const AudioObjectPropertyAddress* inAddress,
    UInt32 inQualifierDataSize,
    const void* inQualifierData,
    UInt32* outDataSize)
{
    OSStatus result = kAudioHardwareNoError;
    
    switch (inObjectID) {
        case kObjectID_PlugIn:
            switch (inAddress->mSelector) {
                case kAudioObjectPropertyBaseClass:
                case kAudioObjectPropertyClass:
                    *outDataSize = sizeof(AudioClassID);
                    break;
                case kAudioObjectPropertyOwner:
                    *outDataSize = sizeof(AudioObjectID);
                    break;
                case kAudioObjectPropertyManufacturer:
                case kAudioPlugInPropertyResourceBundle:
                    *outDataSize = sizeof(CFStringRef);
                    break;
                case kAudioObjectPropertyOwnedObjects:
                    *outDataSize = 2 * sizeof(AudioObjectID);  // Game and Chat devices
                    break;
                case kAudioPlugInPropertyDeviceList:
                    *outDataSize = 2 * sizeof(AudioObjectID);  // Game and Chat devices
                    break;
                case kAudioPlugInPropertyTranslateUIDToDevice:
                    *outDataSize = sizeof(AudioObjectID);
                    break;
                default:
                    result = kAudioHardwareUnknownPropertyError;
                    break;
            }
            break;
            
        case kObjectID_GameDevice:
        case kObjectID_ChatDevice:
            switch (inAddress->mSelector) {
                case kAudioObjectPropertyBaseClass:
                case kAudioObjectPropertyClass:
                    *outDataSize = sizeof(AudioClassID);
                    break;
                case kAudioObjectPropertyOwner:
                    *outDataSize = sizeof(AudioObjectID);
                    break;
                case kAudioObjectPropertyName:
                case kAudioObjectPropertyManufacturer:
                case kAudioDevicePropertyDeviceUID:
                case kAudioDevicePropertyModelUID:
                    *outDataSize = sizeof(CFStringRef);
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
                    *outDataSize = sizeof(UInt32);
                    break;
                case kAudioObjectPropertyControlList:
                    *outDataSize = 0;  // No controls for now
                    break;
                case kAudioObjectPropertyOwnedObjects:
                case kAudioDevicePropertyStreams:
                    // Return size based on scope - 1 stream for input/output, 2 for global
                    *outDataSize = 0;
                    if (inAddress->mScope == kAudioObjectPropertyScopeGlobal) {
                        *outDataSize = 2 * sizeof(AudioObjectID);
                    } else {
                        *outDataSize = sizeof(AudioObjectID);
                    }
                    break;
                case kAudioDevicePropertyNominalSampleRate:
                    *outDataSize = sizeof(Float64);
                    break;
                case kAudioDevicePropertyAvailableNominalSampleRates:
                    *outDataSize = sizeof(AudioValueRange);
                    break;
                case kAudioDevicePropertyPreferredChannelsForStereo:
                    *outDataSize = 2 * sizeof(UInt32);
                    break;
                default:
                    result = kAudioHardwareUnknownPropertyError;
                    break;
            }
            break;
            
        case kObjectID_GameDevice_InputStream:
        case kObjectID_GameDevice_OutputStream:
        case kObjectID_ChatDevice_InputStream:
        case kObjectID_ChatDevice_OutputStream:
            switch (inAddress->mSelector) {
                case kAudioObjectPropertyBaseClass:
                case kAudioObjectPropertyClass:
                    *outDataSize = sizeof(AudioClassID);
                    break;
                case kAudioObjectPropertyOwner:
                    *outDataSize = sizeof(AudioObjectID);
                    break;
                case kAudioStreamPropertyIsActive:
                case kAudioStreamPropertyDirection:
                case kAudioStreamPropertyTerminalType:
                case kAudioStreamPropertyStartingChannel:
                case kAudioStreamPropertyLatency:
                    *outDataSize = sizeof(UInt32);
                    break;
                case kAudioStreamPropertyVirtualFormat:
                case kAudioStreamPropertyPhysicalFormat:
                    *outDataSize = sizeof(AudioStreamBasicDescription);
                    break;
                default:
                    result = kAudioHardwareUnknownPropertyError;
                    break;
            }
            break;
            
        default:
            result = kAudioHardwareBadObjectError;
            break;
    }
    
    return result;
}

static OSStatus SSChatMixPlugIn_GetPropertyData(
    AudioServerPlugInDriverRef inDriver,
    AudioObjectID inObjectID,
    pid_t inClientProcessID,
    const AudioObjectPropertyAddress* inAddress,
    UInt32 inQualifierDataSize,
    const void* inQualifierData,
    UInt32 inDataSize,
    UInt32* outDataSize,
    void* outData)
{
    OSStatus result = kAudioHardwareNoError;
    
    // Debug logging for property queries
    char selectorStr[5] = {0};
    *((UInt32*)selectorStr) = CFSwapInt32HostToBig(inAddress->mSelector);
    os_log(OS_LOG_DEFAULT, "SSChatMixPlugIn_GetPropertyData: object=%u, selector='%s' (0x%x), scope=0x%x", 
           inObjectID, selectorStr, inAddress->mSelector, inAddress->mScope);
    
    switch (inObjectID) {
        case kObjectID_PlugIn:
            switch (inAddress->mSelector) {
                case kAudioObjectPropertyBaseClass:
                    *((AudioClassID*)outData) = kAudioObjectClassID;
                    *outDataSize = sizeof(AudioClassID);
                    break;
                case kAudioObjectPropertyClass:
                    *((AudioClassID*)outData) = kAudioPlugInClassID;
                    *outDataSize = sizeof(AudioClassID);
                    break;
                case kAudioObjectPropertyOwner:
                    *((AudioObjectID*)outData) = kAudioObjectUnknown;
                    *outDataSize = sizeof(AudioObjectID);
                    break;
                case kAudioObjectPropertyManufacturer:
                    *((CFStringRef*)outData) = CFSTR("k0nker");
                    *outDataSize = sizeof(CFStringRef);
                    break;
                case kAudioObjectPropertyOwnedObjects:
                    ((AudioObjectID*)outData)[0] = kObjectID_GameDevice;
                    ((AudioObjectID*)outData)[1] = kObjectID_ChatDevice;
                    *outDataSize = 2 * sizeof(AudioObjectID);
                    break;
                case kAudioPlugInPropertyDeviceList:
                    ((AudioObjectID*)outData)[0] = kObjectID_GameDevice;
                    ((AudioObjectID*)outData)[1] = kObjectID_ChatDevice;
                    *outDataSize = 2 * sizeof(AudioObjectID);
                    os_log(OS_LOG_DEFAULT, "SSChatMixPlugIn: Returning device list: Game=%u, Chat=%u",
                           kObjectID_GameDevice, kObjectID_ChatDevice);
                    break;
                case kAudioPlugInPropertyTranslateUIDToDevice:
                    if (inQualifierDataSize == sizeof(CFStringRef)) {
                        CFStringRef uid = *((CFStringRef*)inQualifierData);
                        if (CFStringCompare(uid, CFSTR(kSSChatMixGameDevice_UID), 0) == kCFCompareEqualTo) {
                            *((AudioObjectID*)outData) = kObjectID_GameDevice;
                        } else if (CFStringCompare(uid, CFSTR(kSSChatMixChatDevice_UID), 0) == kCFCompareEqualTo) {
                            *((AudioObjectID*)outData) = kObjectID_ChatDevice;
                        } else {
                            *((AudioObjectID*)outData) = kAudioObjectUnknown;
                        }
                        *outDataSize = sizeof(AudioObjectID);
                    }
                    break;
                case kAudioPlugInPropertyResourceBundle:
                    *((CFStringRef*)outData) = CFSTR("");
                    *outDataSize = sizeof(CFStringRef);
                    break;
                default:
                    result = kAudioHardwareUnknownPropertyError;
                    break;
            }
            break;
            
        case kObjectID_GameDevice:
        case kObjectID_ChatDevice:
            {
                bool isGame = (inObjectID == kObjectID_GameDevice);
                switch (inAddress->mSelector) {
                    case kAudioObjectPropertyBaseClass:
                        *((AudioClassID*)outData) = kAudioObjectClassID;
                        *outDataSize = sizeof(AudioClassID);
                        break;
                    case kAudioObjectPropertyClass:
                        *((AudioClassID*)outData) = kAudioDeviceClassID;
                        *outDataSize = sizeof(AudioClassID);
                        os_log(OS_LOG_DEFAULT, "SSChatMixPlugIn: Returning device %u class = 0x%x ('adev')", inObjectID, kAudioDeviceClassID);
                        break;
                    case kAudioObjectPropertyOwner:
                        *((AudioObjectID*)outData) = kObjectID_PlugIn;
                        *outDataSize = sizeof(AudioObjectID);
                        break;
                    case kAudioObjectPropertyName:
                        *((CFStringRef*)outData) = isGame ? CFSTR("SSChatMix Game") : CFSTR("SSChatMix Chat");
                        *outDataSize = sizeof(CFStringRef);
                        break;
                    case kAudioObjectPropertyManufacturer:
                        *((CFStringRef*)outData) = CFSTR("k0nker");
                        *outDataSize = sizeof(CFStringRef);
                        break;
                    case kAudioDevicePropertyDeviceUID:
                        *((CFStringRef*)outData) = isGame ? CFSTR(kSSChatMixGameDevice_UID) : CFSTR(kSSChatMixChatDevice_UID);
                        *outDataSize = sizeof(CFStringRef);
                        os_log(OS_LOG_DEFAULT, "SSChatMixPlugIn: Returning device %u UID = %{public}@", 
                               inObjectID, isGame ? CFSTR(kSSChatMixGameDevice_UID) : CFSTR(kSSChatMixChatDevice_UID));
                        break;
                    case kAudioDevicePropertyModelUID:
                        *((CFStringRef*)outData) = CFSTR("SSChatMixDevice");
                        *outDataSize = sizeof(CFStringRef);
                        break;
                    case kAudioDevicePropertyTransportType:
                        *((UInt32*)outData) = kAudioDeviceTransportTypeVirtual;
                        *outDataSize = sizeof(UInt32);
                        break;
                    case kAudioDevicePropertyRelatedDevices:
                        *((AudioObjectID*)outData) = inObjectID;
                        *outDataSize = sizeof(AudioObjectID);
                        break;
                    case kAudioDevicePropertyClockDomain:
                        *((UInt32*)outData) = 0;
                        *outDataSize = sizeof(UInt32);
                        break;
                    case kAudioDevicePropertyDeviceIsAlive:
                        *((UInt32*)outData) = 1;
                        *outDataSize = sizeof(UInt32);
                        break;
                    case kAudioDevicePropertyDeviceIsRunning:
                        pthread_mutex_lock(&gPlugInState->stateMutex);
                        *((UInt32*)outData) = isGame ? (gPlugInState->gameDeviceIORunning > 0 ? 1 : 0)
                                                     : (gPlugInState->chatDeviceIORunning > 0 ? 1 : 0);
                        pthread_mutex_unlock(&gPlugInState->stateMutex);
                        *outDataSize = sizeof(UInt32);
                        break;
                    case kAudioDevicePropertyDeviceCanBeDefaultDevice:
                    case kAudioDevicePropertyDeviceCanBeDefaultSystemDevice:
                        *((UInt32*)outData) = 1;
                        *outDataSize = sizeof(UInt32);
                        break;
                    case kAudioObjectPropertyControlList:
                        // No controls yet - empty list
                        *outDataSize = 0;
                        break;
                    case kAudioDevicePropertyLatency:
                    case kAudioDevicePropertySafetyOffset:
                        *((UInt32*)outData) = 0;
                        *outDataSize = sizeof(UInt32);
                        break;
                    case kAudioObjectPropertyOwnedObjects:
                    case kAudioDevicePropertyStreams:
                        if (inAddress->mScope == kAudioObjectPropertyScopeInput || inAddress->mScope == kAudioObjectPropertyScopeGlobal) {
                            ((AudioObjectID*)outData)[0] = isGame ? kObjectID_GameDevice_InputStream : kObjectID_ChatDevice_InputStream;
                            if (inAddress->mScope == kAudioObjectPropertyScopeGlobal) {
                                ((AudioObjectID*)outData)[1] = isGame ? kObjectID_GameDevice_OutputStream : kObjectID_ChatDevice_OutputStream;
                                *outDataSize = 2 * sizeof(AudioObjectID);
                                os_log(OS_LOG_DEFAULT, "SSChatMixPlugIn: Device %u streams (global) = [%u, %u]", 
                                       inObjectID, ((AudioObjectID*)outData)[0], ((AudioObjectID*)outData)[1]);
                            } else {
                                *outDataSize = sizeof(AudioObjectID);
                                os_log(OS_LOG_DEFAULT, "SSChatMixPlugIn: Device %u streams (input) = [%u]", 
                                       inObjectID, ((AudioObjectID*)outData)[0]);
                            }
                        } else if (inAddress->mScope == kAudioObjectPropertyScopeOutput) {
                            ((AudioObjectID*)outData)[0] = isGame ? kObjectID_GameDevice_OutputStream : kObjectID_ChatDevice_OutputStream;
                            *outDataSize = sizeof(AudioObjectID);
                            os_log(OS_LOG_DEFAULT, "SSChatMixPlugIn: Device %u streams (output) = [%u]", 
                                   inObjectID, ((AudioObjectID*)outData)[0]);
                        }
                        break;
                    case kAudioDevicePropertyNominalSampleRate:
                        *((Float64*)outData) = kSSChatMix_SampleRate;
                        *outDataSize = sizeof(Float64);
                        break;
                    case kAudioDevicePropertyAvailableNominalSampleRates:
                        ((AudioValueRange*)outData)->mMinimum = kSSChatMix_SampleRate;
                        ((AudioValueRange*)outData)->mMaximum = kSSChatMix_SampleRate;
                        *outDataSize = sizeof(AudioValueRange);
                        break;
                    case kAudioDevicePropertyIsHidden:
                        *((UInt32*)outData) = 0;
                        *outDataSize = sizeof(UInt32);
                        break;
                    case kAudioDevicePropertyZeroTimeStampPeriod:
                        *((UInt32*)outData) = kSSChatMix_RingBufferFrames;
                        *outDataSize = sizeof(UInt32);
                        break;
                    case kAudioDevicePropertyPreferredChannelsForStereo:
                        ((UInt32*)outData)[0] = 1;
                        ((UInt32*)outData)[1] = 2;
                        *outDataSize = 2 * sizeof(UInt32);
                        break;
                    default:
                        result = kAudioHardwareUnknownPropertyError;
                        break;
                }
            }
            break;
            
        case kObjectID_GameDevice_InputStream:
        case kObjectID_GameDevice_OutputStream:
        case kObjectID_ChatDevice_InputStream:
        case kObjectID_ChatDevice_OutputStream:
            {
                bool isInputStream = (inObjectID == kObjectID_GameDevice_InputStream || inObjectID == kObjectID_ChatDevice_InputStream);
                bool isGameDevice = (inObjectID == kObjectID_GameDevice_InputStream || inObjectID == kObjectID_GameDevice_OutputStream);
                
                switch (inAddress->mSelector) {
                    case kAudioObjectPropertyBaseClass:
                        *((AudioClassID*)outData) = kAudioObjectClassID;
                        *outDataSize = sizeof(AudioClassID);
                        break;
                    case kAudioObjectPropertyClass:
                        *((AudioClassID*)outData) = kAudioStreamClassID;
                        *outDataSize = sizeof(AudioClassID);
                        break;
                    case kAudioObjectPropertyOwner:
                        *((AudioObjectID*)outData) = isGameDevice ? kObjectID_GameDevice : kObjectID_ChatDevice;
                        *outDataSize = sizeof(AudioObjectID);
                        break;
                    case kAudioStreamPropertyIsActive:
                        *((UInt32*)outData) = 1;
                        *outDataSize = sizeof(UInt32);
                        break;
                    case kAudioStreamPropertyDirection:
                        *((UInt32*)outData) = isInputStream ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput;
                        *outDataSize = sizeof(UInt32);
                        break;
                    case kAudioStreamPropertyTerminalType:
                        *((UInt32*)outData) = 0;
                        *outDataSize = sizeof(UInt32);
                        break;
                    case kAudioStreamPropertyStartingChannel:
                        *((UInt32*)outData) = 1;
                        *outDataSize = sizeof(UInt32);
                        break;
                    case kAudioStreamPropertyLatency:
                        *((UInt32*)outData) = 0;
                        *outDataSize = sizeof(UInt32);
                        break;
                    case kAudioStreamPropertyVirtualFormat:
                    case kAudioStreamPropertyPhysicalFormat:
                        {
                            AudioStreamBasicDescription* desc = (AudioStreamBasicDescription*)outData;
                            desc->mSampleRate = kSSChatMix_SampleRate;
                            desc->mFormatID = kAudioFormatLinearPCM;
                            desc->mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagsNativeEndian;
                            desc->mBytesPerPacket = kSSChatMix_Channels * sizeof(Float32);
                            desc->mFramesPerPacket = 1;
                            desc->mBytesPerFrame = kSSChatMix_Channels * sizeof(Float32);
                            desc->mChannelsPerFrame = kSSChatMix_Channels;
                            desc->mBitsPerChannel = 32;
                            *outDataSize = sizeof(AudioStreamBasicDescription);
                        }
                        break;
                    case kAudioStreamPropertyAvailableVirtualFormats:
                    case kAudioStreamPropertyAvailablePhysicalFormats:
                        {
                            AudioStreamRangedDescription* rangedDesc = (AudioStreamRangedDescription*)outData;
                            rangedDesc->mFormat.mSampleRate = kSSChatMix_SampleRate;
                            rangedDesc->mFormat.mFormatID = kAudioFormatLinearPCM;
                            rangedDesc->mFormat.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagsNativeEndian;
                            rangedDesc->mFormat.mBytesPerPacket = kSSChatMix_Channels * sizeof(Float32);
                            rangedDesc->mFormat.mFramesPerPacket = 1;
                            rangedDesc->mFormat.mBytesPerFrame = kSSChatMix_Channels * sizeof(Float32);
                            rangedDesc->mFormat.mChannelsPerFrame = kSSChatMix_Channels;
                            rangedDesc->mFormat.mBitsPerChannel = 32;
                            rangedDesc->mSampleRateRange.mMinimum = kSSChatMix_SampleRate;
                            rangedDesc->mSampleRateRange.mMaximum = kSSChatMix_SampleRate;
                            *outDataSize = sizeof(AudioStreamRangedDescription);
                        }
                        break;
                    default:
                        result = kAudioHardwareUnknownPropertyError;
                        break;
                }
            }
            break;
            
        default:
            result = kAudioHardwareBadObjectError;
            break;
    }
    
    if (result != kAudioHardwareNoError) {
        os_log(OS_LOG_DEFAULT, "SSChatMixPlugIn_GetPropertyData: FAILED object=%u, selector=0x%x, result=0x%x", 
               inObjectID, inAddress->mSelector, result);
    }
    
    return result;
}

static OSStatus SSChatMixPlugIn_SetPropertyData(
    AudioServerPlugInDriverRef inDriver,
    AudioObjectID inObjectID,
    pid_t inClientProcessID,
    const AudioObjectPropertyAddress* inAddress,
    UInt32 inQualifierDataSize,
    const void* inQualifierData,
    UInt32 inDataSize,
    const void* inData)
{
    // Handle volume control property writes here
    return kAudioHardwareNoError;
}

// MARK: - Device Management

static OSStatus SSChatMixPlugIn_CreateDevice(
    AudioServerPlugInDriverRef inDriver,
    CFDictionaryRef inDescription,
    const AudioServerPlugInClientInfo* inClientInfo,
    AudioObjectID* outDeviceObjectID)
{
    // Not a Transport Manager - devices are created at plugin initialization
    return kAudioHardwareUnsupportedOperationError;
}

static OSStatus SSChatMixPlugIn_DestroyDevice(
    AudioServerPlugInDriverRef inDriver,
    AudioObjectID inDeviceObjectID)
{
    // Not a Transport Manager - devices persist for plugin lifetime
    return kAudioHardwareUnsupportedOperationError;
}

static OSStatus SSChatMixPlugIn_AddDeviceClient(
    AudioServerPlugInDriverRef inDriver,
    AudioObjectID inDeviceObjectID,
    const AudioServerPlugInClientInfo* inClientInfo)
{
    // Inform driver about new client using device
    os_log(OS_LOG_DEFAULT, "SSChatMixPlugIn_AddDeviceClient: device=%u", inDeviceObjectID);
    return kAudioHardwareNoError;
}

static OSStatus SSChatMixPlugIn_RemoveDeviceClient(
    AudioServerPlugInDriverRef inDriver,
    AudioObjectID inDeviceObjectID,
    const AudioServerPlugInClientInfo* inClientInfo)
{
    // Inform driver about client no longer using device
    os_log(OS_LOG_DEFAULT, "SSChatMixPlugIn_RemoveDeviceClient: device=%u", inDeviceObjectID);
    return kAudioHardwareNoError;
}

static OSStatus SSChatMixPlugIn_PerformDeviceConfigurationChange(
    AudioServerPlugInDriverRef inDriver,
    AudioObjectID inDeviceObjectID,
    UInt64 inChangeAction,
    void* inChangeInfo)
{
    // Configuration changes not supported
    return kAudioHardwareUnsupportedOperationError;
}

static OSStatus SSChatMixPlugIn_AbortDeviceConfigurationChange(
    AudioServerPlugInDriverRef inDriver,
    AudioObjectID inDeviceObjectID,
    UInt64 inChangeAction,
    void* inChangeInfo)
{
    // Configuration changes not supported
    return kAudioHardwareUnsupportedOperationError;
}

// MARK: - IO Operations

static OSStatus SSChatMixPlugIn_StartIO(
    AudioServerPlugInDriverRef inDriver,
    AudioObjectID inDeviceObjectID,
    UInt32 inClientID)
{
    os_log(OS_LOG_DEFAULT, "SSChatMixPlugIn_StartIO: device=%u", inDeviceObjectID);
    return kAudioHardwareNoError;
}

static OSStatus SSChatMixPlugIn_StopIO(
    AudioServerPlugInDriverRef inDriver,
    AudioObjectID inDeviceObjectID,
    UInt32 inClientID)
{
    os_log(OS_LOG_DEFAULT, "SSChatMixPlugIn_StopIO: device=%u", inDeviceObjectID);
    return kAudioHardwareNoError;
}

static OSStatus SSChatMixPlugIn_GetZeroTimeStamp(
    AudioServerPlugInDriverRef inDriver,
    AudioObjectID inDeviceObjectID,
    UInt32 inClientID,
    Float64* outSampleTime,
    UInt64* outHostTime,
    UInt64* outSeed)
{
    if (gPlugInState == NULL) {
        return kAudioHardwareIllegalOperationError;
    }
    
    pthread_mutex_lock(&gPlugInState->stateMutex);
    *outSampleTime = gPlugInState->anchorSampleTime;
    *outHostTime = gPlugInState->anchorHostTime;
    *outSeed = 1;
    pthread_mutex_unlock(&gPlugInState->stateMutex);
    
    return kAudioHardwareNoError;
}

static OSStatus SSChatMixPlugIn_WillDoIOOperation(
    AudioServerPlugInDriverRef inDriver,
    AudioObjectID inDeviceObjectID,
    UInt32 inClientID,
    UInt32 inOperationID,
    Boolean* outWillDo,
    Boolean* outWillDoInPlace)
{
    // Declare which IO operations we support
    Boolean willDo = false;
    Boolean willDoInPlace = true;
    
    switch (inOperationID) {
        case kAudioServerPlugInIOOperationReadInput:
            willDo = true;
            willDoInPlace = true;
            break;
        case kAudioServerPlugInIOOperationWriteMix:
            willDo = true;
            willDoInPlace = true;
            break;
    }
    
    if (outWillDo != NULL) {
        *outWillDo = willDo;
    }
    if (outWillDoInPlace != NULL) {
        *outWillDoInPlace = willDoInPlace;
    }
    
    return kAudioHardwareNoError;
}

static OSStatus SSChatMixPlugIn_BeginIOOperation(
    AudioServerPlugInDriverRef inDriver,
    AudioObjectID inDeviceObjectID,
    UInt32 inClientID,
    UInt32 inOperationID,
    UInt32 inIOBufferFrameSize,
    const AudioServerPlugInIOCycleInfo* inIOCycleInfo)
{
    // Called at the beginning of an IO operation
    return kAudioHardwareNoError;
}

static OSStatus SSChatMixPlugIn_DoIOOperation(
    AudioServerPlugInDriverRef inDriver,
    AudioObjectID inDeviceObjectID,
    AudioObjectID inStreamObjectID,
    UInt32 inClientID,
    UInt32 inOperationID,
    UInt32 inIOBufferFrameSize,
    const AudioServerPlugInIOCycleInfo* inIOCycleInfo,
    void* ioMainBuffer,
    void* ioSecondaryBuffer)
{
    // Perform the actual IO operation
    // This is where audio data moves through our device
    return kAudioHardwareNoError;
}

static OSStatus SSChatMixPlugIn_EndIOOperation(
    AudioServerPlugInDriverRef inDriver,
    AudioObjectID inDeviceObjectID,
    UInt32 inClientID,
    UInt32 inOperationID,
    UInt32 inIOBufferFrameSize,
    const AudioServerPlugInIOCycleInfo* inIOCycleInfo)
{
    // Called at the end of an IO operation
    return kAudioHardwareNoError;
}

static OSStatus SSChatMixPlugIn_ReadInput(
    AudioServerPlugInDriverRef inDriver,
    AudioObjectID inDeviceObjectID,
    UInt32 inClientID,
    const AudioTimeStamp* inStartTime,
    UInt32 inFrameCount,
    void* outData)
{
    // Read audio from ring buffer
    // This is called when apps record from our virtual device
    return kAudioHardwareNoError;
}

static OSStatus SSChatMixPlugIn_WriteOutput(
    AudioServerPlugInDriverRef inDriver,
    AudioObjectID inDeviceObjectID,
    UInt32 inClientID,
    const AudioTimeStamp* inStartTime,
    UInt32 inFrameCount,
    const void* inData)
{
    // Write audio to ring buffer
    // This is called when apps play audio to our virtual device
    
    if (gPlugInState == NULL) return kAudioHardwareIllegalOperationError;
    
    const Float32* audioData = (const Float32*)inData;
    
    if (inDeviceObjectID == kObjectID_GameDevice) {
        gPlugInState->gameBuffer->Write(audioData, inFrameCount);
    } else if (inDeviceObjectID == kObjectID_ChatDevice) {
        gPlugInState->chatBuffer->Write(audioData, inFrameCount);
    }
    
    return kAudioHardwareNoError;
}

// MARK: - Plugin Interface Table

static AudioServerPlugInDriverInterface gPlugInInterface = {
    NULL,                                           // _reserved
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

static AudioServerPlugInDriverInterface* gPlugInInterfacePtr = &gPlugInInterface;
static AudioServerPlugInDriverRef gPlugInDriverRef = &gPlugInInterfacePtr;

// MARK: - Plugin Entry Point

extern "C" void* SSChatMixPlugIn_Create(CFAllocatorRef allocator, CFUUIDRef requestedTypeUUID) {
    os_log(OS_LOG_DEFAULT, "SSChatMixPlugIn_Create");
    
    if (!CFEqual(requestedTypeUUID, kAudioServerPlugInTypeUUID)) {
        os_log(OS_LOG_DEFAULT, "SSChatMixPlugIn_Create: Wrong UUID requested");
        return NULL;
    }
    
    os_log(OS_LOG_DEFAULT, "SSChatMixPlugIn_Create: Returning gPlugInDriverRef");
    return gPlugInDriverRef;
}

//
//  SSChatMix_SharedMemory.h
//  SSChatMix HAL Plugin
//
//  Shared memory ring buffer for bypassing CoreAudio input stream restrictions
//  Based on BackgroundMusic's approach to avoid microphone permissions
//

#ifndef SSChatMix_SharedMemory_h
#define SSChatMix_SharedMemory_h

#include <CoreAudio/AudioServerPlugIn.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <atomic>

// Shared memory ring buffer structure (must be POD for shared memory)
struct SSChatMix_SharedRingBuffer {
    // Ring buffer metadata
    UInt32 capacityFrames;
    UInt32 channelCount;
    UInt32 bytesPerFrame;
    
    // Atomic indices for lock-free access
    std::atomic<UInt32> writePosition;
    std::atomic<UInt32> readPosition;
    
    // Audio data follows this structure in memory
    // Float32 data[capacityFrames * channelCount];
};

// Shared memory ring buffer manager
class SSChatMix_SharedMemory {
public:
    SSChatMix_SharedMemory(const char* name, UInt32 capacityFrames, UInt32 channelCount);
    ~SSChatMix_SharedMemory();
    
    // Initialize shared memory (plugin side - creates memory)
    bool InitializeAsWriter();
    
    // Attach to existing shared memory (app side - opens existing)
    bool AttachAsReader();
    
    // Write audio data to the buffer
    UInt32 Write(const Float32* data, UInt32 frameCount);
    
    // Read audio data from the buffer
    UInt32 Read(Float32* data, UInt32 frameCount);
    
    // Get number of frames available to read
    UInt32 GetAvailableFrames() const;
    
    // Get free space in frames
    UInt32 GetFreeSpace() const;
    
    // Clear the buffer
    void Reset();
    
    // Get shared memory name (for app to connect)
    const char* GetName() const { return mName; }
    
private:
    char mName[256];
    UInt32 mCapacityFrames;
    UInt32 mCapacityMask;  // For fast modulo: (mCapacityFrames - 1) when capacity is power of 2
    UInt32 mChannelCount;
    UInt32 mBytesPerFrame;
    
    // Shared memory mapping (POSIX shared memory)
    void* mMemoryAddress;
    size_t mMemorySize;
    
    // Pointer to shared ring buffer structure
    SSChatMix_SharedRingBuffer* mRingBuffer;
    Float32* mAudioData;
    
    bool mIsWriter;
    bool mIsAttached;
};

#endif /* SSChatMix_SharedMemory_h */

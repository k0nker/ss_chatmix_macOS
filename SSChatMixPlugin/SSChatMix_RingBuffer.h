//
//  SSChatMix_RingBuffer.h
//  SSChatMix HAL Plugin
//
//  Simple ring buffer for audio data
//

#ifndef SSChatMix_RingBuffer_h
#define SSChatMix_RingBuffer_h

#include <CoreAudio/AudioServerPlugIn.h>
#include <pthread.h>
#include <atomic>
#include <memory.h>

// Simple lock-free ring buffer for float audio data
class SSChatMix_RingBuffer {
public:
    SSChatMix_RingBuffer(UInt32 capacityFrames, UInt32 channelCount);
    ~SSChatMix_RingBuffer();
    
    // Write audio data to the buffer
    // Returns number of frames actually written
    UInt32 Write(const Float32* data, UInt32 frameCount);
    
    // Read audio data from the buffer
    // Returns number of frames actually read
    UInt32 Read(Float32* data, UInt32 frameCount);
    
    // Get number of frames available to read
    UInt32 GetAvailableFrames() const;
    
    // Get free space in frames
    UInt32 GetFreeSpace() const;
    
    // Clear the buffer
    void Reset();
    
private:
    Float32* mBuffer;
    UInt32 mCapacityFrames;
    UInt32 mChannelCount;
    UInt32 mBytesPerFrame;
    
    std::atomic<UInt32> mWritePosition;
    std::atomic<UInt32> mReadPosition;
};

#endif /* SSChatMix_RingBuffer_h */

//
//  SSChatMix_RingBuffer.cpp
//  SSChatMix HAL Plugin
//
//  Simple ring buffer implementation
//

#include "SSChatMix_RingBuffer.h"
#include <algorithm>

SSChatMix_RingBuffer::SSChatMix_RingBuffer(UInt32 capacityFrames, UInt32 channelCount)
:
    mCapacityFrames(capacityFrames),
    mChannelCount(channelCount),
    mBytesPerFrame(channelCount * sizeof(Float32)),
    mWritePosition(0),
    mReadPosition(0)
{
    // Allocate buffer for audio data
    UInt32 bufferSize = capacityFrames * mBytesPerFrame;
    mBuffer = (Float32*)calloc(1, bufferSize);
}

SSChatMix_RingBuffer::~SSChatMix_RingBuffer() {
    if (mBuffer != nullptr) {
        free(mBuffer);
        mBuffer = nullptr;
    }
}

UInt32 SSChatMix_RingBuffer::Write(const Float32* data, UInt32 frameCount) {
    if (data == nullptr || frameCount == 0) {
        return 0;
    }
    
    // Get current positions
    UInt32 writePos = mWritePosition.load(std::memory_order_acquire);
    UInt32 readPos = mReadPosition.load(std::memory_order_acquire);
    
    // Calculate available space
    UInt32 freeSpace = (readPos - writePos - 1 + mCapacityFrames) % mCapacityFrames;
    
    // Limit to available space
    UInt32 framesToWrite = std::min(frameCount, freeSpace);
    if (framesToWrite == 0) {
        return 0;
    }
    
    // Write in two chunks if wrapping around
    UInt32 contiguousFrames = mCapacityFrames - writePos;
    
    if (framesToWrite <= contiguousFrames) {
        // Single contiguous write
        memcpy(mBuffer + (writePos * mChannelCount), data, framesToWrite * mBytesPerFrame);
    } else {
        // Write wraps around buffer
        UInt32 firstChunkFrames = contiguousFrames;
        UInt32 secondChunkFrames = framesToWrite - firstChunkFrames;
        
        memcpy(mBuffer + (writePos * mChannelCount), data, firstChunkFrames * mBytesPerFrame);
        memcpy(mBuffer, data + (firstChunkFrames * mChannelCount), secondChunkFrames * mBytesPerFrame);
    }
    
    // Update write position
    UInt32 newWritePos = (writePos + framesToWrite) % mCapacityFrames;
    mWritePosition.store(newWritePos, std::memory_order_release);
    
    return framesToWrite;
}

UInt32 SSChatMix_RingBuffer::Read(Float32* data, UInt32 frameCount) {
    if (data == nullptr || frameCount == 0) {
        return 0;
    }
    
    // Get current positions
    UInt32 writePos = mWritePosition.load(std::memory_order_acquire);
    UInt32 readPos = mReadPosition.load(std::memory_order_acquire);
    
    // Calculate available data
    UInt32 availableFrames = (writePos - readPos + mCapacityFrames) % mCapacityFrames;
    
    // Limit to available data
    UInt32 framesToRead = std::min(frameCount, availableFrames);
    if (framesToRead == 0) {
        // No data available, return silence
        memset(data, 0, frameCount * mBytesPerFrame);
        return 0;
    }
    
    // Read in two chunks if wrapping around
    UInt32 contiguousFrames = mCapacityFrames - readPos;
    
    if (framesToRead <= contiguousFrames) {
        // Single contiguous read
        memcpy(data, mBuffer + (readPos * mChannelCount), framesToRead * mBytesPerFrame);
    } else {
        // Read wraps around buffer
        UInt32 firstChunkFrames = contiguousFrames;
        UInt32 secondChunkFrames = framesToRead - firstChunkFrames;
        
        memcpy(data, mBuffer + (readPos * mChannelCount), firstChunkFrames * mBytesPerFrame);
        memcpy(data + (firstChunkFrames * mChannelCount), mBuffer, secondChunkFrames * mBytesPerFrame);
    }
    
    // If we read less than requested, fill remaining with silence
    if (framesToRead < frameCount) {
        memset(data + (framesToRead * mChannelCount), 0, (frameCount - framesToRead) * mBytesPerFrame);
    }
    
    // Update read position
    UInt32 newReadPos = (readPos + framesToRead) % mCapacityFrames;
    mReadPosition.store(newReadPos, std::memory_order_release);
    
    return framesToRead;
}

UInt32 SSChatMix_RingBuffer::GetAvailableFrames() const {
    UInt32 writePos = mWritePosition.load(std::memory_order_acquire);
    UInt32 readPos = mReadPosition.load(std::memory_order_acquire);
    return (writePos - readPos + mCapacityFrames) % mCapacityFrames;
}

UInt32 SSChatMix_RingBuffer::GetFreeSpace() const {
    UInt32 writePos = mWritePosition.load(std::memory_order_acquire);
    UInt32 readPos = mReadPosition.load(std::memory_order_acquire);
    return (readPos - writePos - 1 + mCapacityFrames) % mCapacityFrames;
}

void SSChatMix_RingBuffer::Reset() {
    mWritePosition.store(0, std::memory_order_release);
    mReadPosition.store(0, std::memory_order_release);
    
    // Clear buffer data
    if (mBuffer != nullptr) {
        memset(mBuffer, 0, mCapacityFrames * mBytesPerFrame);
    }
}

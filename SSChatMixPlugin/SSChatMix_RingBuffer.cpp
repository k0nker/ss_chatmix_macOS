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
    mCapacityMask(capacityFrames - 1),  // For power-of-2: 8192 - 1 = 8191 = 0x1FFF
    mChannelCount(channelCount),
    mBytesPerFrame(channelCount * sizeof(Float32)),
    mWritePosition(0),
    mReadPosition(0)
{
    // Verify capacity is a power of 2 (required for bit masking optimization)
    // 8192 = 2^13, so (8192 & 8191) = 0
    if ((capacityFrames & (capacityFrames - 1)) != 0) {
        // Not a power of 2 - this should never happen with kSSChatMix_RingBufferFrames = 8192
        fprintf(stderr, "[SSChatMix] WARNING: Ring buffer capacity %u is not a power of 2!\n", capacityFrames);
    }
    
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
    
    // Calculate available space (use bit masking for fast modulo since capacity is power of 2)
    UInt32 freeSpace = (readPos - writePos - 1 + mCapacityFrames) & mCapacityMask;
    
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
    
    // Update write position (bit masking for fast modulo)
    UInt32 newWritePos = (writePos + framesToWrite) & mCapacityMask;
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
    
    // Calculate available data (use bit masking for fast modulo since capacity is power of 2)
    UInt32 availableFrames = (writePos - readPos + mCapacityFrames) & mCapacityMask;
    
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
    
    // Update read position (bit masking for fast modulo)
    UInt32 newReadPos = (readPos + framesToRead) & mCapacityMask;
    mReadPosition.store(newReadPos, std::memory_order_release);
    
    return framesToRead;
}

UInt32 SSChatMix_RingBuffer::GetAvailableFrames() const {
    UInt32 writePos = mWritePosition.load(std::memory_order_acquire);
    UInt32 readPos = mReadPosition.load(std::memory_order_acquire);
    return (writePos - readPos + mCapacityFrames) & mCapacityMask;  // Bit masking for fast modulo
}

UInt32 SSChatMix_RingBuffer::GetFreeSpace() const {
    UInt32 writePos = mWritePosition.load(std::memory_order_acquire);
    UInt32 readPos = mReadPosition.load(std::memory_order_acquire);
    return (readPos - writePos - 1 + mCapacityFrames) & mCapacityMask;  // Bit masking for fast modulo
}

void SSChatMix_RingBuffer::Reset() {
    mWritePosition.store(0, std::memory_order_release);
    mReadPosition.store(0, std::memory_order_release);
    
    // Clear buffer data
    if (mBuffer != nullptr) {
        memset(mBuffer, 0, mCapacityFrames * mBytesPerFrame);
    }
}

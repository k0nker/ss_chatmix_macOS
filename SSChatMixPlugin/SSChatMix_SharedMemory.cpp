//
//  SSChatMix_SharedMemory.cpp
//  SSChatMix HAL Plugin
//
//  Shared memory ring buffer implementation
//

#include "SSChatMix_SharedMemory.h"
#include <algorithm>
#include <string.h>
#include <stdio.h>
#include <os/log.h>

SSChatMix_SharedMemory::SSChatMix_SharedMemory(const char* name, UInt32 capacityFrames, UInt32 channelCount)
:
    mCapacityFrames(capacityFrames),
    mChannelCount(channelCount),
    mBytesPerFrame(channelCount * sizeof(Float32)),
    mMemoryAddress(nullptr),
    mMemorySize(0),
    mRingBuffer(nullptr),
    mAudioData(nullptr),
    mIsWriter(false),
    mIsAttached(false)
{
    strncpy(mName, name, sizeof(mName) - 1);
    mName[sizeof(mName) - 1] = '\0';
    
    // Calculate total memory size
    mMemorySize = sizeof(SSChatMix_SharedRingBuffer) + (capacityFrames * mBytesPerFrame);
}

SSChatMix_SharedMemory::~SSChatMix_SharedMemory() {
    if (mIsAttached && mMemoryAddress != nullptr) {
        // Unmap memory
        munmap(mMemoryAddress, mMemorySize);
        mMemoryAddress = nullptr;
    }
    
    if (mIsWriter) {
        // Unlink shared memory object (writer/creator only)
        shm_unlink(mName);
    }
}

bool SSChatMix_SharedMemory::InitializeAsWriter() {
    if (mIsAttached) {
        fprintf(stderr, "[SSChatMix] InitializeAsWriter: already attached\n");
        os_log_error(OS_LOG_DEFAULT, "[SSChatMix] InitializeAsWriter: already attached");
        return false;
    }
    
    fprintf(stderr, "[SSChatMix] InitializeAsWriter: creating shared memory '%s' size=%zu\n", mName, mMemorySize);
    os_log(OS_LOG_DEFAULT, "[SSChatMix] InitializeAsWriter: creating shared memory '%{public}s' size=%zu", mName, mMemorySize);
    
    // Use POSIX shared memory (more compatible with sandboxed environments)
    // Unlink any existing shared memory first
    shm_unlink(mName);
    
    // Create new shared memory object
    int fd = shm_open(mName, O_CREAT | O_RDWR, 0600);
    if (fd < 0) {
        fprintf(stderr, "[SSChatMix] InitializeAsWriter: shm_open failed: %d (%s)\n", errno, strerror(errno));
        os_log_error(OS_LOG_DEFAULT, "[SSChatMix] InitializeAsWriter: shm_open failed: %d (%{public}s)", errno, strerror(errno));
        return false;
    }
    
    // Set size
    if (ftruncate(fd, mMemorySize) != 0) {
        close(fd);
        shm_unlink(mName);
        return false;
    }
    
    // Map memory
    mMemoryAddress = mmap(NULL, mMemorySize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    close(fd);  // Can close fd after mmap
    
    if (mMemoryAddress == MAP_FAILED) {
        shm_unlink(mName);
        mMemoryAddress = nullptr;
        return false;
    }
    
    // Set up pointers
    mRingBuffer = reinterpret_cast<SSChatMix_SharedRingBuffer*>(mMemoryAddress);
    mAudioData = reinterpret_cast<Float32*>(static_cast<char*>(mMemoryAddress) + sizeof(SSChatMix_SharedRingBuffer));
    
    // Initialize ring buffer metadata
    mRingBuffer->capacityFrames = mCapacityFrames;
    mRingBuffer->channelCount = mChannelCount;
    mRingBuffer->bytesPerFrame = mBytesPerFrame;
    mRingBuffer->writePosition.store(0, std::memory_order_release);
    mRingBuffer->readPosition.store(0, std::memory_order_release);
    
    // Zero out audio data
    memset(mAudioData, 0, mCapacityFrames * mBytesPerFrame);
    
    mIsWriter = true;
    mIsAttached = true;
    
    fprintf(stderr, "[SSChatMix] InitializeAsWriter: SUCCESS - shared memory '%s' created\n", mName);
    os_log(OS_LOG_DEFAULT, "[SSChatMix] InitializeAsWriter: SUCCESS - shared memory '%{public}s' created", mName);
    return true;
}

bool SSChatMix_SharedMemory::AttachAsReader() {
    if (mIsAttached) {
        return false;
    }
    
    // Open existing shared memory object
    int fd = shm_open(mName, O_RDWR, 0600);
    if (fd < 0) {
        return false;
    }
    
    // Map memory
    mMemoryAddress = mmap(NULL, mMemorySize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    close(fd);  // Can close fd after mmap
    
    if (mMemoryAddress == MAP_FAILED) {
        mMemoryAddress = nullptr;
        return false;
    }
    
    // Set up pointers
    mRingBuffer = reinterpret_cast<SSChatMix_SharedRingBuffer*>(mMemoryAddress);
    mAudioData = reinterpret_cast<Float32*>(static_cast<char*>(mMemoryAddress) + sizeof(SSChatMix_SharedRingBuffer));
    
    mIsWriter = false;
    mIsAttached = true;
    return true;
}

UInt32 SSChatMix_SharedMemory::Write(const Float32* data, UInt32 frameCount) {
    if (!mIsAttached || !mIsWriter || data == nullptr || frameCount == 0) {
        return 0;
    }
    
    // Get current positions
    UInt32 writePos = mRingBuffer->writePosition.load(std::memory_order_acquire);
    UInt32 readPos = mRingBuffer->readPosition.load(std::memory_order_acquire);
    
    // Calculate available space
    UInt32 freeSpace = (readPos - writePos - 1 + mCapacityFrames) % mCapacityFrames;
    
    // Limit to available space
    UInt32 framesToWrite = std::min(frameCount, freeSpace);
    if (framesToWrite == 0) {
        return 0;
    }
    
    // Write in two chunks if wrapping around
    UInt32 contiguousFrames = mCapacityFrames - writePos;
    UInt32 firstChunk = std::min(framesToWrite, contiguousFrames);
    UInt32 secondChunk = framesToWrite - firstChunk;
    
    // Copy first chunk
    UInt32 samplesToCopy = firstChunk * mChannelCount;
    memcpy(mAudioData + (writePos * mChannelCount), data, samplesToCopy * sizeof(Float32));
    
    // Copy second chunk if needed
    if (secondChunk > 0) {
        UInt32 secondSamples = secondChunk * mChannelCount;
        memcpy(mAudioData, data + samplesToCopy, secondSamples * sizeof(Float32));
    }
    
    // Update write position
    UInt32 newWritePos = (writePos + framesToWrite) % mCapacityFrames;
    mRingBuffer->writePosition.store(newWritePos, std::memory_order_release);
    
    return framesToWrite;
}

UInt32 SSChatMix_SharedMemory::Read(Float32* data, UInt32 frameCount) {
    if (!mIsAttached || data == nullptr || frameCount == 0) {
        return 0;
    }
    
    // Get current positions
    UInt32 readPos = mRingBuffer->readPosition.load(std::memory_order_acquire);
    UInt32 writePos = mRingBuffer->writePosition.load(std::memory_order_acquire);
    
    // Calculate available data
    UInt32 availableFrames = (writePos - readPos + mCapacityFrames) % mCapacityFrames;
    
    // Limit to available data
    UInt32 framesToRead = std::min(frameCount, availableFrames);
    if (framesToRead == 0) {
        // No data available - fill with silence
        memset(data, 0, frameCount * mChannelCount * sizeof(Float32));
        return 0;
    }
    
    // Read in two chunks if wrapping around
    UInt32 contiguousFrames = mCapacityFrames - readPos;
    UInt32 firstChunk = std::min(framesToRead, contiguousFrames);
    UInt32 secondChunk = framesToRead - firstChunk;
    
    // Copy first chunk
    UInt32 samplesToCopy = firstChunk * mChannelCount;
    memcpy(data, mAudioData + (readPos * mChannelCount), samplesToCopy * sizeof(Float32));
    
    // Copy second chunk if needed
    if (secondChunk > 0) {
        UInt32 secondSamples = secondChunk * mChannelCount;
        memcpy(data + samplesToCopy, mAudioData, secondSamples * sizeof(Float32));
    }
    
    // Fill remaining with silence if we read less than requested
    if (framesToRead < frameCount) {
        UInt32 silenceFrames = frameCount - framesToRead;
        memset(data + (framesToRead * mChannelCount), 0, silenceFrames * mChannelCount * sizeof(Float32));
    }
    
    // Update read position
    UInt32 newReadPos = (readPos + framesToRead) % mCapacityFrames;
    mRingBuffer->readPosition.store(newReadPos, std::memory_order_release);
    
    return framesToRead;
}

UInt32 SSChatMix_SharedMemory::GetAvailableFrames() const {
    if (!mIsAttached) {
        return 0;
    }
    
    UInt32 readPos = mRingBuffer->readPosition.load(std::memory_order_acquire);
    UInt32 writePos = mRingBuffer->writePosition.load(std::memory_order_acquire);
    
    return (writePos - readPos + mCapacityFrames) % mCapacityFrames;
}

UInt32 SSChatMix_SharedMemory::GetFreeSpace() const {
    if (!mIsAttached) {
        return 0;
    }
    
    UInt32 readPos = mRingBuffer->readPosition.load(std::memory_order_acquire);
    UInt32 writePos = mRingBuffer->writePosition.load(std::memory_order_acquire);
    
    return (readPos - writePos - 1 + mCapacityFrames) % mCapacityFrames;
}

void SSChatMix_SharedMemory::Reset() {
    if (!mIsAttached || !mIsWriter) {
        return;
    }
    
    mRingBuffer->writePosition.store(0, std::memory_order_release);
    mRingBuffer->readPosition.store(0, std::memory_order_release);
    memset(mAudioData, 0, mCapacityFrames * mBytesPerFrame);
}

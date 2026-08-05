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
    mCapacityMask(capacityFrames - 1),  // For power-of-2: 8192 - 1 = 8191 = 0x1FFF
    mChannelCount(channelCount),
    mBytesPerFrame(channelCount * sizeof(Float32)),
    mMemoryAddress(nullptr),
    mMemorySize(0),
    mRingBuffer(nullptr),
    mAudioData(nullptr),
    mIsWriter(false),
    mIsAttached(false)
{
    // Verify capacity is a power of 2 (required for bit masking optimization)
    if ((capacityFrames & (capacityFrames - 1)) != 0) {
        fprintf(stderr, "[SSChatMix] WARNING: Shared memory buffer capacity %u is not a power of 2!\n", capacityFrames);
    }
    
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
    FILE* logFile = fopen("/tmp/sschatmix_plugin.log", "a");
    if (logFile) fprintf(logFile, "=== InitializeAsWriter START for %s (size %zu) ===\n", mName, mMemorySize);
    
    if (mIsAttached) {
        fprintf(stderr, "[SSChatMix] InitializeAsWriter: already attached\n");
        os_log_error(OS_LOG_DEFAULT, "[SSChatMix] InitializeAsWriter: already attached");
        if (logFile) { fprintf(logFile, "Already attached, returning false\n"); fclose(logFile); }
        return false;
    }
    
    fprintf(stderr, "[SSChatMix] InitializeAsWriter: creating shared memory '%s' size=%zu\n", mName, mMemorySize);
    os_log(OS_LOG_DEFAULT, "[SSChatMix] InitializeAsWriter: creating shared memory '%{public}s' size=%zu", mName, mMemorySize);
    if (logFile) fprintf(logFile, "Unlinking old shm: %s\n", mName);
    
    // Use POSIX shared memory (more compatible with sandboxed environments)
    // Unlink any existing shared memory first
    shm_unlink(mName);
    if (logFile) fprintf(logFile, "Calling shm_open with O_CREAT|O_RDWR mode 0666\n");
    
    // Create new shared memory object with permissive mode (0666) so app can access it
    // Plugin runs as root, app runs as user - need world-readable/writable permissions
    int fd = shm_open(mName, O_CREAT | O_RDWR, 0666);
    if (logFile) fprintf(logFile, "shm_open returned fd=%d (errno=%d if negative)\n", fd, errno);
    
    if (fd < 0) {
        fprintf(stderr, "[SSChatMix] InitializeAsWriter: shm_open failed: %d (%s)\n", errno, strerror(errno));
        os_log_error(OS_LOG_DEFAULT, "[SSChatMix] InitializeAsWriter: shm_open failed: %d (%{public}s)", errno, strerror(errno));
        if (logFile) { fprintf(logFile, "shm_open FAILED, returning false\n"); fclose(logFile); }
        return false;
    }
    
    // Set size
    if (logFile) fprintf(logFile, "Calling ftruncate(%d, %zu)\n", fd, mMemorySize);
    if (ftruncate(fd, mMemorySize) != 0) {
        if (logFile) fprintf(logFile, "ftruncate FAILED errno=%d\n", errno);
        close(fd);
        shm_unlink(mName);
        if (logFile) { fprintf(logFile, "Returning false\n"); fclose(logFile); }
        return false;
    }
    if (logFile) fprintf(logFile, "ftruncate succeeded\n");
    
    // Map memory
    if (logFile) fprintf(logFile, "Calling mmap for %zu bytes\n", mMemorySize);
    mMemoryAddress = mmap(NULL, mMemorySize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    close(fd);  // Can close fd after mmap
    
    if (logFile) fprintf(logFile, "mmap returned %p\n", mMemoryAddress);
    
    if (mMemoryAddress == MAP_FAILED) {
        fprintf(stderr, "[SSChatMix] InitializeAsWriter: mmap failed\n");
        shm_unlink(mName);
        mMemoryAddress = nullptr;
        if (logFile) { fprintf(logFile, "mmap FAILED, returning false\n"); fclose(logFile); }
        return false;
    }
    
    // Set up pointers
    mRingBuffer = reinterpret_cast<SSChatMix_SharedRingBuffer*>(mMemoryAddress);
    mAudioData = reinterpret_cast<Float32*>(static_cast<char*>(mMemoryAddress) + sizeof(SSChatMix_SharedRingBuffer));
    
    if (logFile) fprintf(logFile, "Initializing ring buffer metadata\n");
    
    // Initialize ring buffer metadata
    mRingBuffer->capacityFrames = mCapacityFrames;
    mRingBuffer->channelCount = mChannelCount;
    mRingBuffer->bytesPerFrame = mBytesPerFrame;
    mRingBuffer->writePosition.store(0, std::memory_order_release);
    mRingBuffer->readPosition.store(0, std::memory_order_release);
    
    // Zero out audio data
    memset(mAudioData, 0, mCapacityFrames * mBytesPerFrame);
    if (logFile) fprintf(logFile, "Zeroed audio data\n");
    
    mIsWriter = true;
    mIsAttached = true;
    
    fprintf(stderr, "[SSChatMix] InitializeAsWriter: SUCCESS - shared memory '%s' created\n", mName);
    os_log(OS_LOG_DEFAULT, "[SSChatMix] InitializeAsWriter: SUCCESS - shared memory '%{public}s' created", mName);
    if (logFile) {
        fprintf(logFile, "=== InitializeAsWriter SUCCESS for %s ===\n", mName);
        fclose(logFile);
    }
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
    
    // Calculate available space (use bit masking for fast modulo since capacity is power of 2)
    UInt32 freeSpace = (readPos - writePos - 1 + mCapacityFrames) & mCapacityMask;
    
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
    
    // Update write position (bit masking for fast modulo)
    UInt32 newWritePos = (writePos + framesToWrite) & mCapacityMask;
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
    
    // Calculate available data (use bit masking for fast modulo since capacity is power of 2)
    UInt32 availableFrames = (writePos - readPos + mCapacityFrames) & mCapacityMask;
    
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
    
    // Update read position (bit masking for fast modulo)
    UInt32 newReadPos = (readPos + framesToRead) & mCapacityMask;
    mRingBuffer->readPosition.store(newReadPos, std::memory_order_release);
    
    return framesToRead;
}

UInt32 SSChatMix_SharedMemory::GetAvailableFrames() const {
    if (!mIsAttached) {
        return 0;
    }
    
    UInt32 readPos = mRingBuffer->readPosition.load(std::memory_order_acquire);
    UInt32 writePos = mRingBuffer->writePosition.load(std::memory_order_acquire);
    
    return (writePos - readPos + mCapacityFrames) & mCapacityMask;  // Bit masking for fast modulo
}

UInt32 SSChatMix_SharedMemory::GetFreeSpace() const {
    if (!mIsAttached) {
        return 0;
    }
    
    UInt32 readPos = mRingBuffer->readPosition.load(std::memory_order_acquire);
    UInt32 writePos = mRingBuffer->writePosition.load(std::memory_order_acquire);
    
    return (readPos - writePos - 1 + mCapacityFrames) & mCapacityMask;  // Bit masking for fast modulo
}

void SSChatMix_SharedMemory::Reset() {
    if (!mIsAttached || !mIsWriter) {
        return;
    }
    
    mRingBuffer->writePosition.store(0, std::memory_order_release);
    mRingBuffer->readPosition.store(0, std::memory_order_release);
    memset(mAudioData, 0, mCapacityFrames * mBytesPerFrame);
}

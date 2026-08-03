//
//  SSChatMix_SharedMemory.cpp
//  SSChatMix HAL Plugin
//
//  Shared memory ring buffer implementation
//

#include "SSChatMix_SharedMemory.h"
#include <servers/bootstrap.h>
#include <mach/mach_vm.h>
#include <algorithm>
#include <string.h>

SSChatMix_SharedMemory::SSChatMix_SharedMemory(const char* name, UInt32 capacityFrames, UInt32 channelCount)
:
    mCapacityFrames(capacityFrames),
    mChannelCount(channelCount),
    mBytesPerFrame(channelCount * sizeof(Float32)),
    mMemoryPort(MACH_PORT_NULL),
    mMemoryAddress(0),
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
    if (mIsAttached && mMemoryAddress != 0) {
        // Unmap memory
        mach_vm_deallocate(mach_task_self(), mMemoryAddress, mMemorySize);
        mMemoryAddress = 0;
    }
    
    if (mIsWriter && mMemoryPort != MACH_PORT_NULL) {
        // Destroy memory object (writer only)
        mach_port_deallocate(mach_task_self(), mMemoryPort);
        mMemoryPort = MACH_PORT_NULL;
    }
}

bool SSChatMix_SharedMemory::InitializeAsWriter() {
    if (mIsAttached) {
        return false;
    }
    
    // Allocate shared memory
    kern_return_t kr = mach_vm_allocate(
        mach_task_self(),
        &mMemoryAddress,
        mMemorySize,
        VM_FLAGS_ANYWHERE
    );
    
    if (kr != KERN_SUCCESS) {
        return false;
    }
    
    // Make memory region shared
    kr = mach_make_memory_entry_64(
        mach_task_self(),
        &mMemorySize,
        mMemoryAddress,
        VM_PROT_READ | VM_PROT_WRITE,
        &mMemoryPort,
        MACH_PORT_NULL
    );
    
    if (kr != KERN_SUCCESS) {
        mach_vm_deallocate(mach_task_self(), mMemoryAddress, mMemorySize);
        mMemoryAddress = 0;
        return false;
    }
    
    // Register memory port with bootstrap server so app can find it
    kr = bootstrap_register(bootstrap_port, mName, mMemoryPort);
    if (kr != KERN_SUCCESS) {
        // Try to check out first (in case old instance exists)
        mach_port_t oldPort = MACH_PORT_NULL;
        bootstrap_check_in(bootstrap_port, mName, &oldPort);
        if (oldPort != MACH_PORT_NULL) {
            mach_port_deallocate(mach_task_self(), oldPort);
        }
        
        // Try register again
        kr = bootstrap_register(bootstrap_port, mName, mMemoryPort);
        if (kr != KERN_SUCCESS) {
            mach_port_deallocate(mach_task_self(), mMemoryPort);
            mach_vm_deallocate(mach_task_self(), mMemoryAddress, mMemorySize);
            mMemoryPort = MACH_PORT_NULL;
            mMemoryAddress = 0;
            return false;
        }
    }
    
    // Set up pointers
    mRingBuffer = reinterpret_cast<SSChatMix_SharedRingBuffer*>(mMemoryAddress);
    mAudioData = reinterpret_cast<Float32*>(mMemoryAddress + sizeof(SSChatMix_SharedRingBuffer));
    
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
    return true;
}

bool SSChatMix_SharedMemory::AttachAsReader() {
    if (mIsAttached) {
        return false;
    }
    
    // Look up memory port from bootstrap server
    kern_return_t kr = bootstrap_look_up(bootstrap_port, mName, &mMemoryPort);
    if (kr != KERN_SUCCESS) {
        return false;
    }
    
    // Map memory into our address space
    kr = mach_vm_map(
        mach_task_self(),
        &mMemoryAddress,
        mMemorySize,
        0,  // mask
        VM_FLAGS_ANYWHERE,
        mMemoryPort,
        0,  // offset
        FALSE,  // copy
        VM_PROT_READ,
        VM_PROT_READ,
        VM_INHERIT_NONE
    );
    
    if (kr != KERN_SUCCESS) {
        mach_port_deallocate(mach_task_self(), mMemoryPort);
        mMemoryPort = MACH_PORT_NULL;
        return false;
    }
    
    // Set up pointers
    mRingBuffer = reinterpret_cast<SSChatMix_SharedRingBuffer*>(mMemoryAddress);
    mAudioData = reinterpret_cast<Float32*>(mMemoryAddress + sizeof(SSChatMix_SharedRingBuffer));
    
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

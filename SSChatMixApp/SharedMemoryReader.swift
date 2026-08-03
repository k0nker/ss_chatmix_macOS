//
//  SharedMemoryReader.swift
//  SSChatMix
//
//  Reads audio from HAL plugin shared memory using POSIX shared memory
//

import Foundation
import Darwin.C
import os.log

// Shared ring buffer structure (must match C++ definition)
struct SharedRingBuffer {
    var capacityFrames: UInt32
    var channelCount: UInt32
    var bytesPerFrame: UInt32
    var writePosition: UInt32
    var readPosition: UInt32
}

class SharedMemoryReader {
    private let sharedMemoryName: String
    private var memoryPointer: UnsafeMutableRawPointer?
    private var memorySize: Int = 0
    private var ringBuffer: UnsafeMutablePointer<SharedRingBuffer>?
    private var audioData: UnsafeMutablePointer<Float32>?
    
    init(deviceUID: String) {
        // POSIX shared memory names: max 31 chars on macOS (PSEMNAMLEN)
        // Use short names: /ssc.game or /ssc.chat
        self.sharedMemoryName = deviceUID.contains("Game") ? "/ssc.game" : "/ssc.chat"
    }
    
    deinit {
        detach()
    }
    
    // Attach to shared memory created by plugin
    func attach() -> Bool {
        // Calculate memory size: header + audio data
        // Capacity is 96000 frames (2 seconds at 48kHz), 2 channels, 4 bytes per float
        memorySize = MemoryLayout<SharedRingBuffer>.stride + (96000 * 2 * 4)
        
        os_log("Attempting to attach to shared memory: %{public}s (size: %d bytes)", sharedMemoryName, memorySize)
        
        // Open existing POSIX shared memory object
        let fd = shm_open_helper(sharedMemoryName, O_RDWR, 0o600)
        guard fd >= 0 else {
            let err = errno
            let errStr = String(cString: strerror(err))
            os_log("Failed to open shared memory '%{public}s': errno=%d (%{public}s)", 
                   sharedMemoryName, err, errStr)
            return false
        }
        
        os_log("Successfully opened shared memory fd=%d", fd)
        
        // Map memory
        memoryPointer = mmap(nil, memorySize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0)
        let mapResult = memoryPointer
        close(fd)  // Can close fd after mmap
        
        guard mapResult != MAP_FAILED else {
            let err = errno
            let errStr = String(cString: strerror(err))
            os_log("Failed to mmap shared memory: errno=%d (%{public}s)", err, errStr)
            memoryPointer = nil
            return false
        }
        
        // Set up pointers
        ringBuffer = memoryPointer?.assumingMemoryBound(to: SharedRingBuffer.self)
        audioData = (memoryPointer! + MemoryLayout<SharedRingBuffer>.stride).assumingMemoryBound(to: Float32.self)
        
        os_log("Successfully attached to shared memory: %{public}s", sharedMemoryName)
        return true
    }
    
    // Detach from shared memory
    func detach() {
        if let ptr = memoryPointer {
            munmap(ptr, memorySize)
            memoryPointer = nil
            ringBuffer = nil
            audioData = nil
        }
    }
    
    // Read audio frames from the ring buffer
    func read(into buffer: UnsafeMutablePointer<Float32>, frameCount: UInt32) -> UInt32 {
        guard let rb = ringBuffer, let audio = audioData else {
            return 0
        }
        
        // Get current positions (atomic loads)
        let writePos = rb.pointee.writePosition
        let readPos = rb.pointee.readPosition
        
        // Calculate available frames
        let available = (writePos - readPos + rb.pointee.capacityFrames) % rb.pointee.capacityFrames
        let framesToRead = min(frameCount, available)
        
        if framesToRead == 0 {
            return 0
        }
        
        // Read in two chunks if wrapping around
        let contiguousFrames = rb.pointee.capacityFrames - readPos
        let firstChunk = min(framesToRead, contiguousFrames)
        let secondChunk = framesToRead - firstChunk
        
        // Copy first chunk
        let samplesToCopy = firstChunk * rb.pointee.channelCount
        buffer.update(from: audio + Int(readPos * rb.pointee.channelCount), count: Int(samplesToCopy))
        
        // Copy second chunk if needed (wrap around)
        if secondChunk > 0 {
            let samplesToCopy2 = secondChunk * rb.pointee.channelCount
            (buffer + Int(firstChunk * rb.pointee.channelCount)).update(from: audio, count: Int(samplesToCopy2))
        }
        
        // Update read position
        let newReadPos = (readPos + framesToRead) % rb.pointee.capacityFrames
        rb.pointee.readPosition = newReadPos
        
        return framesToRead
    }
    
    // Get number of frames available to read
    func availableFrames() -> UInt32 {
        guard let rb = ringBuffer else {
            return 0
        }
        
        let writePos = rb.pointee.writePosition
        let readPos = rb.pointee.readPosition
        
        return (writePos - readPos + rb.pointee.capacityFrames) % rb.pointee.capacityFrames
    }
}

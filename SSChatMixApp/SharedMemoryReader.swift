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
        // Capacity is 8192 frames (~170ms at 48kHz), 2 channels, 4 bytes per float
        memorySize = MemoryLayout<SharedRingBuffer>.stride + (8192 * 2 * 4)
        
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
        
        // On startup, check if buffer has stale data from previous session
        // Only skip ahead if there's more than half the buffer size (definitely stale)
        // Buffer is now 8192 frames (~170ms), so check for > 4096 frames (~85ms)
        if let rb = ringBuffer {
            let writePos = UInt64(rb.pointee.writePosition)
            let readPos = UInt64(rb.pointee.readPosition)
            let capacity = UInt64(rb.pointee.capacityFrames)
            let available = (writePos &- readPos) % capacity
            
            // If more than half the buffer is filled, it's likely stale - catch up but keep tiny buffer
            if available > (capacity / 2) {
                // Keep 512 frames (~10ms) for smooth startup - ensure positive value with modulo math
                let newReadPos = (writePos + capacity - 512) % capacity
                rb.pointee.readPosition = UInt32(newReadPos & 0xFFFFFFFF)
                os_log("Skipped stale buffer data (%d frames), now at 10ms latency", available)
            }
        }
        
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
            // Zero buffer if not attached
            buffer.assign(repeating: 0.0, count: Int(frameCount) * 2)
            return 0
        }
        
        // Get current positions (atomic loads) - convert to UInt64 for ring buffer math
        let writePos = UInt64(rb.pointee.writePosition)
        let readPos = UInt64(rb.pointee.readPosition)
        let capacity = UInt64(rb.pointee.capacityFrames)
        
        // Calculate available frames using wrapping arithmetic for ring buffer
        let available = (writePos &- readPos) % capacity
        let framesToRead = min(UInt64(frameCount), available)
        
        if framesToRead == 0 {
            // Zero buffer if no data available (prevents stale data artifacts)
            buffer.assign(repeating: 0.0, count: Int(frameCount) * 2)
            return 0
        }
        
        // Read in two chunks if wrapping around
        let contiguousFrames = capacity &- readPos
        let firstChunk = min(framesToRead, contiguousFrames)
        let secondChunk = framesToRead &- firstChunk
        
        // Copy first chunk
        let channelCount = UInt64(rb.pointee.channelCount)
        let samplesToCopy = firstChunk * channelCount
        buffer.update(from: audio + Int(readPos * channelCount), count: Int(samplesToCopy))
        
        // Copy second chunk if needed (wrap around)
        if secondChunk > 0 {
            let samplesToCopy2 = secondChunk * channelCount
            (buffer + Int(firstChunk * channelCount)).update(from: audio, count: Int(samplesToCopy2))
        }
        
        // If we read fewer frames than requested, zero the remainder
        if framesToRead < UInt64(frameCount) {
            let samplesRead = Int(framesToRead * channelCount)
            let remainingSamples = Int(UInt64(frameCount) * channelCount - framesToRead * channelCount)
            (buffer + samplesRead).assign(repeating: 0.0, count: remainingSamples)
        }
        
        // Update read position
        let newReadPos = (readPos &+ framesToRead) % capacity
        rb.pointee.readPosition = UInt32(newReadPos & 0xFFFFFFFF)
        
        return UInt32(framesToRead)
    }
    
    // Get number of frames available to read
    func availableFrames() -> UInt32 {
        guard let rb = ringBuffer else {
            return 0
        }
        
        let writePos = UInt64(rb.pointee.writePosition)
        let readPos = UInt64(rb.pointee.readPosition)
        let capacity = UInt64(rb.pointee.capacityFrames)
        
        let available = (writePos &- readPos) % capacity
        return UInt32(min(available, UInt64(UInt32.max)))
    }
}

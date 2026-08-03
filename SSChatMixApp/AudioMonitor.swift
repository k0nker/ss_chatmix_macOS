import Foundation
import CoreAudio
import AudioToolbox
import AVFoundation

/// Real-time audio monitoring that reads from two virtual devices,
/// applies volume control, mixes them, and outputs to a physical device.
public class AudioMonitor {
    private var gameInputUnit: AudioUnit?
    private var chatInputUnit: AudioUnit?
    private var outputUnit: AudioUnit?
    
    private var gameDeviceID: AudioDeviceID
    private var chatDeviceID: AudioDeviceID
    private var outputDeviceID: AudioDeviceID
    
    private var gameVolume: Float = 1.0
    private var chatVolume: Float = 1.0
    
    private var isRunning = false
    
    // Audio format (we'll standardize on this)
    private let sampleRate: Float64 = 48000.0
    private let channels: UInt32 = 2
    
    // Ring buffers to store input audio
    private var gameBuffer: RingBuffer
    private var chatBuffer: RingBuffer
    
    // Persistent audio buffers for input callbacks
    private var gameAudioBuffer: [Float]
    private var chatAudioBuffer: [Float]
    private let maxFrames: Int = 4096
    
    public init(gameDeviceID: AudioDeviceID, chatDeviceID: AudioDeviceID, outputDeviceID: AudioDeviceID) {
        self.gameDeviceID = gameDeviceID
        self.chatDeviceID = chatDeviceID
        self.outputDeviceID = outputDeviceID
        
        // Create ring buffers (2 seconds capacity)
        let bufferSize = Int(sampleRate) * Int(channels) * 2
        self.gameBuffer = RingBuffer(capacity: bufferSize)
        self.chatBuffer = RingBuffer(capacity: bufferSize)
        
        // Create persistent audio buffers
        let audioBufferSize = maxFrames * Int(channels)
        self.gameAudioBuffer = Array(repeating: 0.0, count: audioBufferSize)
        self.chatAudioBuffer = Array(repeating: 0.0, count: audioBufferSize)
    }
    
    deinit {
        stop()
    }
    
    // MARK: - Public Interface
    
    public func start() throws {
        guard !isRunning else { return }
        
        print("Starting audio monitoring...")
        print("   Game input: Device \(gameDeviceID)")
        print("   Chat input: Device \(chatDeviceID)")
        print("   Output: Device \(outputDeviceID)")
        
        // Check microphone permission (NON-BLOCKING - just verify it's granted)
        // Permission should have been requested early at app launch
        #if os(macOS)
        if #available(macOS 14.0, *) {
            let status = AVCaptureDevice.authorizationStatus(for: .audio)
            
            if status != .authorized {
                print("Microphone permission not granted!")
                print("   Go to System Settings > Privacy & Security > Microphone")
                print("   Then restart the app")
                throw AudioMonitorError.permissionDenied
            } else {
                print("Microphone permission verified")
            }
        }
        #endif
        
        // Create and configure audio units
        try setupGameInput()
        try setupChatInput()
        try setupOutput()
        
        // Start audio units
        try startAudioUnit(gameInputUnit!)
        try startAudioUnit(chatInputUnit!)
        try startAudioUnit(outputUnit!)
        
        isRunning = true
        print("Audio monitoring started\n")
    }
    
    public func stop() {
        guard isRunning else { return }
        
        if let unit = gameInputUnit {
            AudioOutputUnitStop(unit)
            AudioComponentInstanceDispose(unit)
        }
        if let unit = chatInputUnit {
            AudioOutputUnitStop(unit)
            AudioComponentInstanceDispose(unit)
        }
        if let unit = outputUnit {
            AudioOutputUnitStop(unit)
            AudioComponentInstanceDispose(unit)
        }
        
        gameInputUnit = nil
        chatInputUnit = nil
        outputUnit = nil
        isRunning = false
        
        print("🔇 Audio monitoring stopped")
    }
    
    public func updateVolumes(game: Float, chat: Float) {
        // Clamp to 0.0-1.0 range
        self.gameVolume = min(max(game, 0.0), 1.0)
        self.chatVolume = min(max(chat, 0.0), 1.0)
    }
    
    // MARK: - Audio Unit Setup
    
    private func setupGameInput() throws {
        gameInputUnit = try createInputUnit(deviceID: gameDeviceID, isGame: true)
    }
    
    private func setupChatInput() throws {
        chatInputUnit = try createInputUnit(deviceID: chatDeviceID, isGame: false)
    }
    
    private func setupOutput() throws {
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        
        guard let component = AudioComponentFindNext(nil, &description) else {
            throw AudioMonitorError.componentNotFound
        }
        
        var unit: AudioUnit?
        var status = AudioComponentInstanceNew(component, &unit)
        guard status == noErr, let outputUnit = unit else {
            throw AudioMonitorError.audioUnitCreationFailed(status)
        }
        
        // Enable output
        var enableIO: UInt32 = 1
        status = AudioUnitSetProperty(
            outputUnit,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Output,
            0,
            &enableIO,
            UInt32(MemoryLayout<UInt32>.size)
        )
        guard status == noErr else {
            throw AudioMonitorError.propertySetFailed(status)
        }
        
        // Set output device
        var deviceID = outputDeviceID
        status = AudioUnitSetProperty(
            outputUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            throw AudioMonitorError.propertySetFailed(status)
        }
        
        // Set format
        var format = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(channels * 4),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(channels * 4),
            mChannelsPerFrame: channels,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        
        status = AudioUnitSetProperty(
            outputUnit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input,
            0,
            &format,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )
        guard status == noErr else {
            throw AudioMonitorError.formatSetFailed(status)
        }
        
        // Set render callback
        let context = Unmanaged.passUnretained(self).toOpaque()
        var callback = AURenderCallbackStruct(
            inputProc: outputRenderCallback,
            inputProcRefCon: context
        )
        
        status = AudioUnitSetProperty(
            outputUnit,
            kAudioUnitProperty_SetRenderCallback,
            kAudioUnitScope_Input,
            0,
            &callback,
            UInt32(MemoryLayout<AURenderCallbackStruct>.size)
        )
        guard status == noErr else {
            throw AudioMonitorError.callbackSetFailed(status)
        }
        
        // Initialize
        status = AudioUnitInitialize(outputUnit)
        guard status == noErr else {
            throw AudioMonitorError.initializeFailed(status)
        }
        
        self.outputUnit = outputUnit
    }
    
    private func createInputUnit(deviceID: AudioDeviceID, isGame: Bool) throws -> AudioUnit {
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        
        guard let component = AudioComponentFindNext(nil, &description) else {
            throw AudioMonitorError.componentNotFound
        }
        
        var unit: AudioUnit?
        var status = AudioComponentInstanceNew(component, &unit)
        guard status == noErr, let inputUnit = unit else {
            throw AudioMonitorError.audioUnitCreationFailed(status)
        }
        
        // Enable input, disable output
        var enableIO: UInt32 = 1
        status = AudioUnitSetProperty(
            inputUnit,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Input,
            1,
            &enableIO,
            UInt32(MemoryLayout<UInt32>.size)
        )
        guard status == noErr else {
            throw AudioMonitorError.propertySetFailed(status)
        }
        
        enableIO = 0
        status = AudioUnitSetProperty(
            inputUnit,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Output,
            0,
            &enableIO,
            UInt32(MemoryLayout<UInt32>.size)
        )
        guard status == noErr else {
            throw AudioMonitorError.propertySetFailed(status)
        }
        
        // Set input device
        var devID = deviceID
        status = AudioUnitSetProperty(
            inputUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &devID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            throw AudioMonitorError.propertySetFailed(status)
        }
        
        // Set format
        var format = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(channels * 4),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(channels * 4),
            mChannelsPerFrame: channels,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        
        status = AudioUnitSetProperty(
            inputUnit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Output,
            1,
            &format,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )
        guard status == noErr else {
            throw AudioMonitorError.formatSetFailed(status)
        }
        
        // Allocate buffer for input
        var bufferList = AudioBufferList()
        bufferList.mNumberBuffers = 1
        bufferList.mBuffers.mNumberChannels = channels
        bufferList.mBuffers.mDataByteSize = 0
        bufferList.mBuffers.mData = nil
        
        // Set input callback
        let context = Unmanaged.passUnretained(self).toOpaque()
        var callback: AURenderCallbackStruct
        
        if isGame {
            callback = AURenderCallbackStruct(
                inputProc: gameInputCallback,
                inputProcRefCon: context
            )
        } else {
            callback = AURenderCallbackStruct(
                inputProc: chatInputCallback,
                inputProcRefCon: context
            )
        }
        
        status = AudioUnitSetProperty(
            inputUnit,
            kAudioOutputUnitProperty_SetInputCallback,
            kAudioUnitScope_Global,
            0,
            &callback,
            UInt32(MemoryLayout<AURenderCallbackStruct>.size)
        )
        guard status == noErr else {
            throw AudioMonitorError.callbackSetFailed(status)
        }
        
        // Initialize
        status = AudioUnitInitialize(inputUnit)
        guard status == noErr else {
            throw AudioMonitorError.initializeFailed(status)
        }
        
        return inputUnit
    }
    
    private func startAudioUnit(_ unit: AudioUnit) throws {
        let status = AudioOutputUnitStart(unit)
        guard status == noErr else {
            throw AudioMonitorError.startFailed(status)
        }
    }
    
    // MARK: - Audio Callbacks (C callbacks that call Swift methods)
    
    fileprivate func handleGameInput(
        inNumberFrames: UInt32,
        inTimeStamp: UnsafePointer<AudioTimeStamp>
    ) -> OSStatus {
        // Use persistent buffer
        let bufferSize = Int(inNumberFrames * channels)
        guard bufferSize <= gameAudioBuffer.count else {
            return kAudioUnitErr_TooManyFramesToProcess
        }
        
        let status = gameAudioBuffer.withUnsafeMutableBytes { bufferPointer in
            var bufferList = AudioBufferList()
            bufferList.mNumberBuffers = 1
            bufferList.mBuffers.mNumberChannels = channels
            bufferList.mBuffers.mDataByteSize = UInt32(bufferSize * MemoryLayout<Float>.size)
            bufferList.mBuffers.mData = bufferPointer.baseAddress
            
            // Render audio from the input unit
            return AudioUnitRender(
                gameInputUnit!,
                nil,
                inTimeStamp,
                1,
                inNumberFrames,
                &bufferList
            )
        }
        
        if status == noErr {
            // Write to ring buffer using pointer (no array allocation!)
            gameAudioBuffer.withUnsafeBufferPointer { bufferPointer in
                gameBuffer.write(bufferPointer.baseAddress!, count: bufferSize)
            }
        }
        
        return status
    }
    
    fileprivate func handleChatInput(
        inNumberFrames: UInt32,
        inTimeStamp: UnsafePointer<AudioTimeStamp>
    ) -> OSStatus {
        // Use persistent buffer
        let bufferSize = Int(inNumberFrames * channels)
        guard bufferSize <= chatAudioBuffer.count else {
            return kAudioUnitErr_TooManyFramesToProcess
        }
        
        let status = chatAudioBuffer.withUnsafeMutableBytes { bufferPointer in
            var bufferList = AudioBufferList()
            bufferList.mNumberBuffers = 1
            bufferList.mBuffers.mNumberChannels = channels
            bufferList.mBuffers.mDataByteSize = UInt32(bufferSize * MemoryLayout<Float>.size)
            bufferList.mBuffers.mData = bufferPointer.baseAddress
            
            // Render audio from the input unit
            return AudioUnitRender(
                chatInputUnit!,
                nil,
                inTimeStamp,
                1,
                inNumberFrames,
                &bufferList
            )
        }
        
        if status == noErr {
            // Write to ring buffer using pointer (no array allocation!)
            chatAudioBuffer.withUnsafeBufferPointer { bufferPointer in
                chatBuffer.write(bufferPointer.baseAddress!, count: bufferSize)
            }
        }
        
        return status
    }
    
    fileprivate func handleOutput(
        inNumberFrames: UInt32,
        ioData: UnsafeMutablePointer<AudioBufferList>
    ) -> OSStatus {
        let frameCount = Int(inNumberFrames * channels)
        
        // Get output buffer
        guard let outputBuffer = ioData.pointee.mBuffers.mData?.assumingMemoryBound(to: Float.self) else {
            return kAudioUnitErr_InvalidProperty
        }
        
        // Use the persistent audio buffers as temp storage
        gameAudioBuffer.withUnsafeMutableBufferPointer { gamePtr in
            chatAudioBuffer.withUnsafeMutableBufferPointer { chatPtr in
                // Read from ring buffers directly into temp buffers
                gameBuffer.read(gamePtr.baseAddress!, count: frameCount)
                chatBuffer.read(chatPtr.baseAddress!, count: frameCount)
                
                // Mix directly to output buffer (no intermediate arrays!)
                for i in 0..<frameCount {
                    outputBuffer[i] = gamePtr[i] * gameVolume + chatPtr[i] * chatVolume
                }
            }
        }
        
        return noErr
    }
}

// MARK: - C Callback Functions

private func gameInputCallback(
    inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {
    let monitor = Unmanaged<AudioMonitor>.fromOpaque(inRefCon).takeUnretainedValue()
    return monitor.handleGameInput(inNumberFrames: inNumberFrames, inTimeStamp: inTimeStamp)
}

private func chatInputCallback(
    inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {
    let monitor = Unmanaged<AudioMonitor>.fromOpaque(inRefCon).takeUnretainedValue()
    return monitor.handleChatInput(inNumberFrames: inNumberFrames, inTimeStamp: inTimeStamp)
}

private func outputRenderCallback(
    inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {
    let monitor = Unmanaged<AudioMonitor>.fromOpaque(inRefCon).takeUnretainedValue()
    return monitor.handleOutput(inNumberFrames: inNumberFrames, ioData: ioData!)
}

// MARK: - Ring Buffer

/// Lock-free ring buffer for real-time audio (single-reader, single-writer)
/// Based on the approach used by REDACTED and other pro audio apps
private class RingBuffer {
    private var buffer: UnsafeMutablePointer<Float>
    private var writeIndex: UnsafeMutablePointer<Int32>
    private var readIndex: UnsafeMutablePointer<Int32>
    private let capacity: Int
    
    init(capacity: Int) {
        self.capacity = capacity
        self.buffer = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
        self.buffer.initialize(repeating: 0.0, count: capacity)
        
        // Allocate atomic indices
        self.writeIndex = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
        self.readIndex = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
        self.writeIndex.initialize(to: 0)
        self.readIndex.initialize(to: 0)
    }
    
    deinit {
        buffer.deallocate()
        writeIndex.deallocate()
        readIndex.deallocate()
    }
    
    /// Lock-free write for real-time thread
    func write(_ data: UnsafePointer<Float>, count: Int) {
        guard count <= capacity else { return } // Safety check
        
        let write = Int(writeIndex.pointee)
        
        // Fast path: no wrap-around
        if write + count <= capacity {
            buffer.advanced(by: write).update(from: data, count: count)
            OSAtomicAdd32Barrier(Int32(count), writeIndex)
        } else {
            // Wrap-around: split into two copies
            let firstChunk = capacity - write
            buffer.advanced(by: write).update(from: data, count: firstChunk)
            buffer.update(from: data.advanced(by: firstChunk), count: count - firstChunk)
            
            // Update write index atomically
            let newWrite = (write + count) % capacity
            OSMemoryBarrier()
            writeIndex.pointee = Int32(newWrite)
        }
    }
    
    /// Lock-free read for real-time thread
    func read(_ data: UnsafeMutablePointer<Float>, count: Int) {
        guard count <= capacity else { return } // Safety check
        
        let read = Int(readIndex.pointee)
        
        // Fast path: no wrap-around
        if read + count <= capacity {
            data.update(from: buffer.advanced(by: read), count: count)
            OSAtomicAdd32Barrier(Int32(count), readIndex)
        } else {
            // Wrap-around: split into two copies
            let firstChunk = capacity - read
            data.update(from: buffer.advanced(by: read), count: firstChunk)
            data.advanced(by: firstChunk).update(from: buffer, count: count - firstChunk)
            
            // Update read index atomically
            let newRead = (read + count) % capacity
            OSMemoryBarrier()
            readIndex.pointee = Int32(newRead)
        }
    }
}

// MARK: - Errors

public enum AudioMonitorError: Error {
    case componentNotFound
    case audioUnitCreationFailed(OSStatus)
    case propertySetFailed(OSStatus)
    case formatSetFailed(OSStatus)
    case callbackSetFailed(OSStatus)
    case initializeFailed(OSStatus)
    case startFailed(OSStatus)
    case permissionDenied
}

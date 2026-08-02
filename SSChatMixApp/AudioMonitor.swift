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
    
    // Debug counters
    private var gameInputCallbackCount = 0
    private var chatInputCallbackCount = 0
    private var outputCallbackCount = 0
    private var lastDebugTime = Date()
    
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
        
        print("🎚️  Starting audio monitoring...")
        print("   Game input: Device \(gameDeviceID)")
        print("   Chat input: Device \(chatDeviceID)")
        print("   Output: Device \(outputDeviceID)")
        
        // Check microphone permission
        #if os(macOS)
        if #available(macOS 14.0, *) {
            let status = AVCaptureDevice.authorizationStatus(for: .audio)
            print("🎤 Microphone permission status: \(status.rawValue)")
            if status != .authorized {
                print("⚠️  WARNING: Microphone permission not granted!")
                print("   Menu bar apps need this even for virtual devices")
                print("   Go to System Settings > Privacy & Security > Microphone")
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
        print("✅ Audio monitoring started\n")
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
        print("🔊 AudioMonitor volumes updated: Game=\(Int(self.gameVolume * 100))% Chat=\(Int(self.chatVolume * 100))%")
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
        gameInputCallbackCount += 1
        
        // Log every 500 callbacks (about once per 5 seconds)
        if gameInputCallbackCount % 500 == 0 {
            print("🎮 Game input callback #\(gameInputCallbackCount) - \(inNumberFrames) frames")
        }
        
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
            // Write to ring buffer
            gameBuffer.write(Array(gameAudioBuffer.prefix(bufferSize)))
        } else {
            print("❌ Game input AudioUnitRender failed: \(status)")
        }
        
        return status
    }
    
    fileprivate func handleChatInput(
        inNumberFrames: UInt32,
        inTimeStamp: UnsafePointer<AudioTimeStamp>
    ) -> OSStatus {
        chatInputCallbackCount += 1
        
        // Log every 500 callbacks
        if chatInputCallbackCount % 500 == 0 {
            print("💬 Chat input callback #\(chatInputCallbackCount) - \(inNumberFrames) frames")
        }
        
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
            // Write to ring buffer
            chatBuffer.write(Array(chatAudioBuffer.prefix(bufferSize)))
        } else {
            print("❌ Chat input AudioUnitRender failed: \(status)")
        }
        
        return status
    }
    
    fileprivate func handleOutput(
        inNumberFrames: UInt32,
        ioData: UnsafeMutablePointer<AudioBufferList>
    ) -> OSStatus {
        outputCallbackCount += 1
        
        let frameCount = Int(inNumberFrames * channels)
        
        // Read from ring buffers
        let gameData = gameBuffer.read(frameCount)
        let chatData = chatBuffer.read(frameCount)
        
        // Log every 500 callbacks with audio level info (about once per 5 seconds)
        if outputCallbackCount % 500 == 0 {
            let gamePeak = gameData.map(abs).max() ?? 0.0
            let chatPeak = chatData.map(abs).max() ?? 0.0
            print("🔊 Output callback #\(outputCallbackCount) - \(inNumberFrames) frames")
            print("   Game peak: \(String(format: "%.3f", gamePeak)) (vol: \(Int(gameVolume * 100))%)")
            print("   Chat peak: \(String(format: "%.3f", chatPeak)) (vol: \(Int(chatVolume * 100))%)")
        }
        
        // Get output buffer
        guard let outputBuffer = ioData.pointee.mBuffers.mData?.assumingMemoryBound(to: Float.self) else {
            return kAudioUnitErr_InvalidProperty
        }
        
        // Mix audio with volume applied
        for i in 0..<frameCount {
            let gameSample = i < gameData.count ? gameData[i] * gameVolume : 0.0
            let chatSample = i < chatData.count ? chatData[i] * chatVolume : 0.0
            outputBuffer[i] = gameSample + chatSample
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

private class RingBuffer {
    private var buffer: [Float]
    private var writeIndex = 0
    private var readIndex = 0
    private let capacity: Int
    private let lock = NSLock()
    
    init(capacity: Int) {
        self.capacity = capacity
        self.buffer = Array(repeating: 0.0, count: capacity)
    }
    
    func write(_ data: [Float]) {
        lock.lock()
        defer { lock.unlock() }
        
        for sample in data {
            buffer[writeIndex] = sample
            writeIndex = (writeIndex + 1) % capacity
        }
    }
    
    func read(_ count: Int) -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        
        var result = [Float]()
        result.reserveCapacity(count)
        
        for _ in 0..<count {
            result.append(buffer[readIndex])
            readIndex = (readIndex + 1) % capacity
        }
        
        return result
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
}

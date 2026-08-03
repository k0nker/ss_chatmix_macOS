import Foundation
import CoreAudio
import os.log

/// Audio router that reads from SSChatMix virtual device input streams (loopback),
/// mixes them with volume control, and outputs to a physical device.
///
/// Architecture:
/// 1. Apps write to SSChatMix virtual output streams
/// 2. Plugin stores audio in ring buffers
/// 3. This router reads from SSChatMix input streams (loopback from ring buffers)
/// 4. Router applies volume control and mixes Game + Chat
/// 5. Router writes mixed audio to physical output device
public class AudioRouter {
    private var gameDeviceID: AudioDeviceID
    private var chatDeviceID: AudioDeviceID
    private var outputDeviceID: AudioDeviceID
    
    private var gameProcID: AudioDeviceIOProcID?
    private var chatProcID: AudioDeviceIOProcID?
    private var outputProcID: AudioDeviceIOProcID?
    
    // Volume controls (0.0 - 1.0)
    public var gameVolume: Float = 1.0
    public var chatVolume: Float = 1.0
    
    // Buffers for audio data - using raw pointers for real-time safety
    private var gameBuffer: UnsafeMutablePointer<Float32>
    private var chatBuffer: UnsafeMutablePointer<Float32>
    private let maxFrames: Int = 4096
    private let channels: Int = 2
    private var bufferSize: Int {
        return maxFrames * channels
    }
    
    // Thread safety
    private let queue = DispatchQueue(label: "com.k0nker.sschatmix.audiorouter", qos: .userInteractive)
    
    private let logger = Logger(subsystem: "com.k0nker.sschatmix", category: "AudioRouter")
    
    public init(gameDeviceID: AudioDeviceID, chatDeviceID: AudioDeviceID, outputDeviceID: AudioDeviceID) {
        self.gameDeviceID = gameDeviceID
        self.chatDeviceID = chatDeviceID
        self.outputDeviceID = outputDeviceID
        
        // Allocate raw C-style buffers for real-time safety
        let size = maxFrames * channels
        self.gameBuffer = UnsafeMutablePointer<Float32>.allocate(capacity: size)
        self.chatBuffer = UnsafeMutablePointer<Float32>.allocate(capacity: size)
        
        // Zero out buffers
        self.gameBuffer.initialize(repeating: 0.0, count: size)
        self.chatBuffer.initialize(repeating: 0.0, count: size)
    }
    
    deinit {
        stop()
        
        // Deallocate buffers
        gameBuffer.deinitialize(count: bufferSize)
        gameBuffer.deallocate()
        chatBuffer.deinitialize(count: bufferSize)
        chatBuffer.deallocate()
    }
    
    /// Start audio routing
    public func start() throws {
        logger.info("Starting audio router...")
        logger.info("  Game device: \(self.gameDeviceID)")
        logger.info("  Chat device: \(self.chatDeviceID)")
        logger.info("  Output device: \(self.outputDeviceID)")
        
        // Create IOProc for Game device input stream
        let gameIOProc: AudioDeviceIOProc = { (
            inDevice,
            inNow,
            inInputData,
            inInputTime,
            outOutputData,
            inOutputTime,
            inClientData
        ) -> OSStatus in
            guard let clientData = inClientData else {
                return kAudioHardwareNoError
            }
            
            let router = Unmanaged<AudioRouter>.fromOpaque(clientData).takeUnretainedValue()
            
            // Read from input stream (loopback)
            let buffer = inInputData.pointee.mBuffers
            guard let data = buffer.mData else {
                return kAudioHardwareNoError
            }
            
            let frameCount = Int(buffer.mDataByteSize) / (MemoryLayout<Float32>.size * router.channels)
            let frames = min(frameCount, router.maxFrames)
            
            // Copy input data to game buffer
            let audioData = data.assumingMemoryBound(to: Float32.self)
            for i in 0..<(frames * router.channels) {
                router.gameBuffer[i] = audioData[i]
            }
            
            return kAudioHardwareNoError
        }
        
        var status = AudioDeviceCreateIOProcID(
            gameDeviceID,
            gameIOProc,
            Unmanaged.passUnretained(self).toOpaque(),
            &gameProcID
        )
        
        guard status == kAudioHardwareNoError else {
            throw AudioRouterError.failedToCreateIOProc("Game device", status)
        }
        
        // Create IOProc for Chat device input stream
        let chatIOProc: AudioDeviceIOProc = { (
            inDevice,
            inNow,
            inInputData,
            inInputTime,
            outOutputData,
            inOutputTime,
            inClientData
        ) -> OSStatus in
            guard let clientData = inClientData else {
                return kAudioHardwareNoError
            }
            
            let router = Unmanaged<AudioRouter>.fromOpaque(clientData).takeUnretainedValue()
            
            // Read from input stream (loopback)
            let buffer = inInputData.pointee.mBuffers
            guard let data = buffer.mData else {
                return kAudioHardwareNoError
            }
            
            let frameCount = Int(buffer.mDataByteSize) / (MemoryLayout<Float32>.size * router.channels)
            let frames = min(frameCount, router.maxFrames)
            
            // Copy input data to chat buffer
            let audioData = data.assumingMemoryBound(to: Float32.self)
            for i in 0..<(frames * router.channels) {
                router.chatBuffer[i] = audioData[i]
            }
            
            return kAudioHardwareNoError
        }
        
        status = AudioDeviceCreateIOProcID(
            chatDeviceID,
            chatIOProc,
            Unmanaged.passUnretained(self).toOpaque(),
            &chatProcID
        )
        
        guard status == kAudioHardwareNoError else {
            throw AudioRouterError.failedToCreateIOProc("Chat device", status)
        }
        
        // Create IOProc for output device
        let outputIOProc: AudioDeviceIOProc = { (
            inDevice,
            inNow,
            inInputData,
            inInputTime,
            outOutputData,
            inOutputTime,
            inClientData
        ) -> OSStatus in
            guard let clientData = inClientData else {
                return kAudioHardwareNoError
            }
            
            let router = Unmanaged<AudioRouter>.fromOpaque(clientData).takeUnretainedValue()
            
            // Write mixed audio to output stream
            let buffer = outOutputData.pointee.mBuffers
            guard let data = buffer.mData else {
                return kAudioHardwareNoError
            }
            
            let frameCount = Int(buffer.mDataByteSize) / (MemoryLayout<Float32>.size * router.channels)
            let frames = min(frameCount, router.maxFrames)
            
            let audioData = data.assumingMemoryBound(to: Float32.self)
            
            // Mix Game + Chat with volume control
            for i in 0..<(frames * router.channels) {
                let gameSample = router.gameBuffer[i] * router.gameVolume
                let chatSample = router.chatBuffer[i] * router.chatVolume
                var mixedSample = gameSample + chatSample
                
                // Clipping prevention
                if mixedSample > 1.0 {
                    mixedSample = 1.0
                } else if mixedSample < -1.0 {
                    mixedSample = -1.0
                }
                
                audioData[i] = mixedSample
            }
            
            return kAudioHardwareNoError
        }
        
        status = AudioDeviceCreateIOProcID(
            outputDeviceID,
            outputIOProc,
            Unmanaged.passUnretained(self).toOpaque(),
            &outputProcID
        )
        
        guard status == kAudioHardwareNoError else {
            throw AudioRouterError.failedToCreateIOProc("Output device", status)
        }
        
        // Start all IOProcs
        if let procID = gameProcID {
            status = AudioDeviceStart(gameDeviceID, procID)
            guard status == kAudioHardwareNoError else {
                throw AudioRouterError.failedToStartDevice("Game device", status)
            }
            logger.info("Started Game device IO")
        }
        
        if let procID = chatProcID {
            status = AudioDeviceStart(chatDeviceID, procID)
            guard status == kAudioHardwareNoError else {
                throw AudioRouterError.failedToStartDevice("Chat device", status)
            }
            logger.info("Started Chat device IO")
        }
        
        if let procID = outputProcID {
            status = AudioDeviceStart(outputDeviceID, procID)
            guard status == kAudioHardwareNoError else {
                throw AudioRouterError.failedToStartDevice("Output device", status)
            }
            logger.info("Started Output device IO")
        }
        
        logger.info("✅ Audio router started successfully")
    }
    
    /// Stop audio routing
    public func stop() {
        logger.info("Stopping audio router...")
        
        // Stop and destroy IOProcs
        if let procID = gameProcID {
            AudioDeviceStop(gameDeviceID, procID)
            AudioDeviceDestroyIOProcID(gameDeviceID, procID)
            gameProcID = nil
            logger.info("Stopped Game device IO")
        }
        
        if let procID = chatProcID {
            AudioDeviceStop(chatDeviceID, procID)
            AudioDeviceDestroyIOProcID(chatDeviceID, procID)
            chatProcID = nil
            logger.info("Stopped Chat device IO")
        }
        
        if let procID = outputProcID {
            AudioDeviceStop(outputDeviceID, procID)
            AudioDeviceDestroyIOProcID(outputDeviceID, procID)
            outputProcID = nil
            logger.info("Stopped Output device IO")
        }
        
        logger.info("✅ Audio router stopped")
    }
    
    /// Update volumes in real-time
    public func updateVolumes(game: Float, chat: Float) {
        // Normalize 0-100 to 0.0-1.0
        gameVolume = max(0.0, min(1.0, game / 100.0))
        chatVolume = max(0.0, min(1.0, chat / 100.0))
    }
}

// MARK: - Errors

enum AudioRouterError: Error, LocalizedError {
    case failedToCreateIOProc(String, OSStatus)
    case failedToStartDevice(String, OSStatus)
    
    var errorDescription: String? {
        switch self {
        case .failedToCreateIOProc(let device, let status):
            return "Failed to create IOProc for \(device): OSStatus \(status)"
        case .failedToStartDevice(let device, let status):
            return "Failed to start \(device): OSStatus \(status)"
        }
    }
}

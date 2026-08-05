import Foundation
import CoreAudio
import Accelerate
import os.log
import Darwin

/// Audio router that reads from SSChatMix virtual device shared memory (bypasses input streams),
/// mixes audio with volume control, and outputs to a physical device.
///
/// Architecture:
/// 1. Apps write to SSChatMix virtual output streams
/// 2. Plugin stores audio in shared memory ring buffers
/// 3. This router reads directly from shared memory (NO input streams, bypasses TCC microphone restrictions)
/// 4. Router applies volume control and mixes Game + Chat
/// 5. Router writes mixed audio to physical output device
public class AudioRouter {
    private var outputDeviceID: AudioDeviceID
    
    private var outputProcID: AudioDeviceIOProcID?
    
    // Shared memory readers (no input streams!)
    private var gameReader: SharedMemoryReader
    private var chatReader: SharedMemoryReader
    
    // Volume controls (0.0 - 1.0)
    public var gameVolume: Float = 1.0
    public var chatVolume: Float = 1.0
    
    // Buffers for reading from shared memory
    private var gameBuffer: UnsafeMutablePointer<Float32>
    private var chatBuffer: UnsafeMutablePointer<Float32>
    private let maxFrames: Int = 4096
    private let channels: Int = 2
    private var bufferSize: Int {
        return maxFrames * channels
    }
    
    // Thread safety
    private let queue = DispatchQueue(label: "com.k0nker.sschatmix.audiorouter", qos: .userInteractive)
    
    // Real-time thread management
    private var hasSetRealtimePriority = false
    
    // Underrun detection
    private var underrunCount: UInt32 = 0
    private let maxUnderrunsBeforeWarning: UInt32 = 5
    
    private let logger = Logger(subsystem: "com.k0nker.sschatmix", category: "AudioRouter")
    
    public init(gameDeviceUID: String, chatDeviceUID: String, outputDeviceID: AudioDeviceID) {
        self.outputDeviceID = outputDeviceID
        
        // Create shared memory readers
        self.gameReader = SharedMemoryReader(deviceUID: gameDeviceUID)
        self.chatReader = SharedMemoryReader(deviceUID: chatDeviceUID)
        
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
    
    /// Set real-time thread priority for the current thread
    /// Based on BackgroundMusic's approach: prevents preemption during audio callbacks
    private func setRealtimePriority() {
        var timeConstraintPolicy = thread_time_constraint_policy()
        
        // Convert nanoseconds to absolute time units (Mach timebase)
        var timebaseInfo = mach_timebase_info_data_t()
        mach_timebase_info(&timebaseInfo)
        
        let nsToAbsolute = { (ns: UInt64) -> UInt32 in
            return UInt32((ns * UInt64(timebaseInfo.denom)) / UInt64(timebaseInfo.numer))
        }
        
        // 50μs nominal computation, 60μs maximum
        // These are conservative values that prevent system lockup while ensuring real-time performance
        timeConstraintPolicy.computation = nsToAbsolute(50_000)  // 50 microseconds
        timeConstraintPolicy.constraint = nsToAbsolute(60_000)   // 60 microseconds  
        timeConstraintPolicy.period = 0                          // No inherent periodicity
        timeConstraintPolicy.preemptible = 1                     // Allow preemption by higher RT threads
        
        let policyCount = mach_msg_type_number_t(
            MemoryLayout<thread_time_constraint_policy>.size / MemoryLayout<integer_t>.size
        )
        
        let result = withUnsafeMutablePointer(to: &timeConstraintPolicy) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(policyCount)) { intPtr in
                thread_policy_set(
                    pthread_mach_thread_np(pthread_self()),
                    thread_policy_flavor_t(THREAD_TIME_CONSTRAINT_POLICY),
                    intPtr,
                    policyCount
                )
            }
        }
        
        if result == KERN_SUCCESS {
            logger.info("✅ Set real-time thread priority for audio callback")
        } else {
            logger.warning("⚠️ Failed to set real-time thread priority: \(result)")
        }
    }
    
    /// Start audio routing
    public func start() throws {
        logger.info("Starting audio router with shared memory...")
        logger.info("  Output device: \(self.outputDeviceID)")
        
        // Attach to shared memory
        guard gameReader.attach() else {
            throw AudioRouterError.failedToAttachSharedMemory("Game")
        }
        logger.info("✅ Attached to game shared memory")
        
        guard chatReader.attach() else {
            throw AudioRouterError.failedToAttachSharedMemory("Chat")
        }
        logger.info("✅ Attached to chat shared memory")
        
        // Create IOProc for output device only
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
            
            // Set real-time thread priority on first invocation
            if !router.hasSetRealtimePriority {
                router.setRealtimePriority()
                router.hasSetRealtimePriority = true
            }
            
            // Write mixed audio to output stream
            let buffer = outOutputData.pointee.mBuffers
            guard let data = buffer.mData else {
                return kAudioHardwareNoError
            }
            
            let frameCount = Int(buffer.mDataByteSize) / (MemoryLayout<Float32>.size * router.channels)
            let frames = min(frameCount, router.maxFrames)
            
            // Read from shared memory (buffers zeroed by reader if no data)
            let gameFramesRead = router.gameReader.read(into: router.gameBuffer, frameCount: UInt32(frames))
            let chatFramesRead = router.chatReader.read(into: router.chatBuffer, frameCount: UInt32(frames))
            
            // Detect underruns (when we can't read enough frames)
            if gameFramesRead < UInt32(frames) || chatFramesRead < UInt32(frames) {
                router.underrunCount += 1
                if router.underrunCount == router.maxUnderrunsBeforeWarning {
                    // Log once when threshold reached (avoid flooding logs)
                    router.logger.error("Buffer underrun: game=\(gameFramesRead)/\(frames) chat=\(chatFramesRead)/\(frames)")
                }
            } else {
                // Reset counter when we have healthy reads
                router.underrunCount = 0
            }
            
            let audioData = data.assumingMemoryBound(to: Float32.self)
            
            // Cache volumes for realtime safety (var for vDSP inout parameters)
            var gVol = router.gameVolume
            var cVol = router.chatVolume
            let totalSamples = vDSP_Length(frames * router.channels)
            
            // Hardware-accelerated mixing using vDSP (Accelerate framework)
            // 1. Scale game buffer by volume: audioData = gameBuffer * gVol
            vDSP_vsmul(router.gameBuffer, 1, &gVol, audioData, 1, totalSamples)
            
            // 2. Scale and add chat buffer: audioData = audioData + (chatBuffer * cVol)
            vDSP_vsma(router.chatBuffer, 1, &cVol, audioData, 1, audioData, 1, totalSamples)
            
            // 3. Clip to prevent distortion: clamp values to [-1.0, 1.0]
            var minusOne: Float = -1.0
            var plusOne: Float = 1.0
            vDSP_vclip(audioData, 1, &minusOne, &plusOne, audioData, 1, totalSamples)
            
            return kAudioHardwareNoError
        }
        
        var status = AudioDeviceCreateIOProcID(
            outputDeviceID,
            outputIOProc,
            Unmanaged.passUnretained(self).toOpaque(),
            &outputProcID
        )
        
        guard status == kAudioHardwareNoError else {
            throw AudioRouterError.failedToCreateIOProc("Output device", status)
        }
        
        // Start output IOProc
        if let procID = outputProcID {
            status = AudioDeviceStart(outputDeviceID, procID)
            guard status == kAudioHardwareNoError else {
                throw AudioRouterError.failedToStartDevice("Output device", status)
            }
            logger.info("Started Output device IO")
        }
        
        logger.info("✅ Audio router started successfully (no input streams, using shared memory)")
    }
    
    /// Stop audio routing
    public func stop() {
        logger.info("Stopping audio router...")
        
        // Stop and destroy output IOProc
        if let procID = outputProcID {
            AudioDeviceStop(outputDeviceID, procID)
            AudioDeviceDestroyIOProcID(outputDeviceID, procID)
            outputProcID = nil
            logger.info("Stopped Output device IO")
        }
        
        // Detach from shared memory
        gameReader.detach()
        chatReader.detach()
        logger.info("Detached from shared memory")
        
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
    case failedToAttachSharedMemory(String)
    
    var errorDescription: String? {
        switch self {
        case .failedToCreateIOProc(let device, let status):
            return "Failed to create IOProc for \(device): OSStatus \(status)"
        case .failedToStartDevice(let device, let status):
            return "Failed to start \(device): OSStatus \(status)"
        case .failedToAttachSharedMemory(let device):
            return "Failed to attach to \(device) shared memory"
        }
    }
}

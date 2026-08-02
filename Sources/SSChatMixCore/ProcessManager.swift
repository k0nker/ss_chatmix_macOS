import Foundation

public class ProcessManager {
    private let pidFilePath: String
    
    public init() {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let appDir = supportDir.appendingPathComponent("com.k0nker.sschatmix")
        self.pidFilePath = appDir.appendingPathComponent("sschatmix.pid").path
    }
    
    // MARK: - PID Management
    
    /// Write current process ID to file
    public func writePID() throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        try String(pid).write(toFile: pidFilePath, atomically: true, encoding: .utf8)
    }
    
    /// Read PID from file
    public func readPID() -> Int32? {
        guard let pidString = try? String(contentsOfFile: pidFilePath, encoding: .utf8),
              let pid = Int32(pidString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return pid
    }
    
    /// Remove PID file
    public func removePID() {
        try? FileManager.default.removeItem(atPath: pidFilePath)
    }
    
    /// Check if a process is running
    public func isProcessRunning(_ pid: Int32) -> Bool {
        return kill(pid, 0) == 0
    }
    
    /// Check if sschatmix is already running
    public func isAlreadyRunning() -> Bool {
        guard let pid = readPID() else {
            return false
        }
        return isProcessRunning(pid)
    }
    
    /// Kill the running process
    public func killRunningProcess() throws {
        guard let pid = readPID() else {
            return
        }
        
        if isProcessRunning(pid) {
            kill(pid, SIGTERM)
            
            // Wait up to 2 seconds for graceful shutdown
            for _ in 0..<20 {
                if !isProcessRunning(pid) {
                    break
                }
                usleep(100_000) // 100ms
            }
            
            // Force kill if still running
            if isProcessRunning(pid) {
                kill(pid, SIGKILL)
            }
        }
        
        removePID()
    }
}

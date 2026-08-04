#!/usr/bin/env swift

import Foundation

let RED = "\u{001B}[0;31m"
let GREEN = "\u{001B}[0;32m"
let YELLOW = "\u{001B}[1;33m"
let NC = "\u{001B}[0m"

let pluginPath = "/Library/Audio/Plug-Ins/HAL/SSChatMixPlugin.driver"
let appPath = "/Applications/SSChatMix.app"

// Check if running as root
if getuid() != 0 {
    print("\(RED)Error: This program must be run as root\(NC)")
    print("Usage: sudo uninstall [--plugin]")
    exit(1)
}

let pluginOnly = CommandLine.arguments.contains("--plugin")

print("==========================================")
print("  SSChatMix Uninstaller")
print("==========================================")
print("")

// Remove plugin
if FileManager.default.fileExists(atPath: pluginPath) {
    print("Removing plugin...")
    do {
        try FileManager.default.removeItem(atPath: pluginPath)
        print("\(GREEN)✓ Plugin removed\(NC)")
    } catch {
        print("\(RED)✗ Failed to remove plugin: \(error)\(NC)")
        exit(1)
    }
} else {
    print("\(YELLOW)⚠ Plugin not found (already removed?)\(NC)")
}

// Remove app (unless --plugin flag)
if !pluginOnly {
    if FileManager.default.fileExists(atPath: appPath) {
        print("Removing app...")
        do {
            try FileManager.default.removeItem(atPath: appPath)
            print("\(GREEN)✓ App removed\(NC)")
        } catch {
            print("\(RED)✗ Failed to remove app: \(error)\(NC)")
            exit(1)
        }
    } else {
        print("\(YELLOW)⚠ App not found (already removed?)\(NC)")
    }
}

// Restart audio services
print("")
print("Restarting audio services...")

let services = [
    "coreaudiod",
    "audioaccessoryd",
    "audiomxd",
    "AirPlayXPCHelper"
]

for service in services {
    let checkProcess = Process()
    checkProcess.launchPath = "/usr/bin/pgrep"
    checkProcess.arguments = ["-x", service]
    
    let pipe = Pipe()
    checkProcess.standardOutput = pipe
    
    do {
        try checkProcess.run()
        checkProcess.waitUntilExit()
        
        if checkProcess.terminationStatus == 0 {
            print("  Restarting \(service)...")
            let killProcess = Process()
            killProcess.launchPath = "/usr/bin/killall"
            killProcess.arguments = [service]
            try? killProcess.run()
        }
    } catch {
        // Ignore errors
    }
}

// Wait for services to restart
sleep(2)

print("")
print("\(GREEN)✓ Uninstall complete!\(NC)")
print("")

if !pluginOnly {
    print("SSChatMix has been completely removed from your system.")
} else {
    print("SSChatMix plugin has been removed.")
    print("The app remains at: \(appPath)")
}
print("")

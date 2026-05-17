import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public final class DaemonLauncher {
    private var process: Process?
    private let stderrPipe = Pipe()
    
    public init() {}
    
    /// Starts the background Python inference daemon.
    /// - Parameters:
    ///   - daemonPath: Optional direct path to compiled daemon binary.
    ///   - socketPath: The UDS path.
    public func launch(daemonPath: String? = nil, socketPath: String) throws {
        guard process == nil else { return }
        
        let path: String
        var isScript = false
        
        if let customPath = daemonPath {
            path = customPath
        } else if let envPath = ProcessInfo.processInfo.environment["SANGEET_DAEMON_PATH"] {
            path = envPath
        } else {
            // Bundled resource lookup via Bundle.module
            // Note: SPM compiles Bundle.module synthesis if resources are declared or in tests.
            // Let's resolve the path with a fallback for SPM testing
            #if SWIFT_PACKAGE
            if let bundleURL = Bundle.module.url(forResource: "sangeet-inference", withExtension: nil) {
                path = bundleURL.path
            } else {
                path = "/Users/rahulchaturvedi/AI_Audio_Restoration/services/inference/sangeet_inference/daemon.py"
                isScript = true
            }
            #else
            path = "/Users/rahulchaturvedi/AI_Audio_Restoration/services/inference/sangeet_inference/daemon.py"
            isScript = true
            #endif
        }
        
        if path.hasSuffix(".py") {
            isScript = true
        }
        
        let newProcess = Process()
        
        if isScript {
            var pythonExecutable = "/usr/bin/env"
            var baseArgs = ["python3"]
            
            let venvPath = "/Users/rahulchaturvedi/AI_Audio_Restoration/services/inference/.venv/bin/python3"
            
            if let envPython = ProcessInfo.processInfo.environment["SANGEET_PYTHON_PATH"] {
                pythonExecutable = envPython
                baseArgs = []
            } else if FileManager.default.fileExists(atPath: venvPath) {
                pythonExecutable = venvPath
                baseArgs = []
            } else if FileManager.default.fileExists(atPath: "/opt/miniconda3/bin/python3") {
                pythonExecutable = "/opt/miniconda3/bin/python3"
                baseArgs = []
            }
            
            newProcess.executableURL = URL(fileURLWithPath: pythonExecutable)
            newProcess.arguments = baseArgs + [path, "--socket", socketPath]
        } else {
            newProcess.executableURL = URL(fileURLWithPath: path)
            newProcess.arguments = [
                "--socket", socketPath
            ]
        }
        
        newProcess.standardOutput = Pipe() // Suppress stdout
        newProcess.standardError = stderrPipe
        
        // Listen to stderr for logging/debugging
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let line = String(data: data, encoding: .utf8), !line.isEmpty {
                // Log stderr line to console
                print("[Daemon STDERR] \(line.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }
        
        try newProcess.run()
        self.process = newProcess
        
        // Wait up to 10 seconds for the socket to become connectable
        let timeout: TimeInterval = 10.0
        let startTime = Date()
        var connectable = false
        
        while Date().timeIntervalSince(startTime) < timeout {
            if isSocketConnectable(path: socketPath) {
                connectable = true
                break
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        
        guard connectable else {
            stop()
            throw AudioEngineError.daemonLaunchFailed(
                "The background audio engine daemon started but the socket did not become connectable within 10 seconds."
            )
        }
    }
    
    /// Polled socket check using raw POSIX sockets for high-precision validation.
    private func isSocketConnectable(path: String) -> Bool {
        guard FileManager.default.fileExists(atPath: path) else { return false }
        
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        
        var addr = sockaddr_un()
        #if os(macOS) || os(iOS)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        #endif
        addr.sun_family = sa_family_t(AF_UNIX)
        
        let pathMax = MemoryLayout.size(ofValue: addr.sun_path)
        _ = path.withCString { cstr in
            withUnsafeMutablePointer(to: &addr.sun_path) { sunPathPtr in
                let rawPtr = UnsafeMutableRawPointer(sunPathPtr)
                let charPtr = rawPtr.assumingMemoryBound(to: CChar.self)
                strncpy(charPtr, cstr, pathMax - 1)
            }
        }
        
        var addrCopy = addr
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        return withUnsafePointer(to: &addrCopy) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                connect(fd, sockaddrPtr, len) == 0
            }
        }
    }
    
    /// Stops the daemon gracefully or terminates after a 5 second wait.
    public func stop() {
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        
        guard let proc = process, proc.isRunning else {
            process = nil
            return
        }
        
        // Wait up to 5 seconds for the daemon to shut down cleanly
        let shutdownTimeout: TimeInterval = 5.0
        let startTime = Date()
        
        while proc.isRunning && Date().timeIntervalSince(startTime) < shutdownTimeout {
            Thread.sleep(forTimeInterval: 0.1)
        }
        
        if proc.isRunning {
            // Force terminate (SIGTERM)
            proc.terminate()
            proc.waitUntilExit()
        }
        
        process = nil
    }
    
    deinit {
        stop()
    }
}

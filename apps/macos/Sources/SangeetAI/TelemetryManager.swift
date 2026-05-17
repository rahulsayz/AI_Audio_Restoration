import Foundation
import SwiftUI

/// Thread-safe, privacy-respecting native telemetry manager for Sangeet AI
public final class TelemetryManager: ObservableObject {
    public static let shared = TelemetryManager()
    
    // Opt-out by default as per AGENTS.md requirements
    @AppStorage("SAITelemetryEnabled") public var isTelemetryEnabled = true
    @AppStorage("SAITelemetryConsentShown") public var isConsentShown = false
    
    // Rolling local buffer of last 20 events for visual inspection in Settings -> Privacy
    @Published public private(set) var localEventsBuffer: [TelemetryEvent] = []
    private let maxBufferSize = 20
    private let queue = DispatchQueue(label: "ai.sangeet.telemetry", qos: .utility)
    
    public struct TelemetryEvent: Identifiable, Codable {
        public let id: UUID
        public let timestamp: Date
        public let eventName: String
        public let properties: [String: String]
        
        public var formattedTimestamp: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
            return formatter.string(from: timestamp)
        }
    }
    
    private init() {}
    
    /// Track a telemetry event with key-value property map
    /// - Parameters:
    ///   - event: The identifier name of the event
    ///   - properties: Payload properties (strictly excluding paths, filenames, or user identifiers)
    public func track(event: String, properties: [String: String] = [:]) {
        // Enforce absolute opt-out checks
        guard isTelemetryEnabled else { return }
        
        queue.async {
            let telemetryEvent = TelemetryEvent(
                id: UUID(),
                timestamp: Date(),
                eventName: event,
                properties: properties
            )
            
            // Format properties into a readable debug line
            let propsString = properties.isEmpty 
                ? "none" 
                : properties.map { "\($0.key): \($0.value)" }.sorted().joined(separator: ", ")
            
            // Write directly to stderr for daemon and developer inspection (standard stub backend)
            let logLine = "[Telemetry] [\(telemetryEvent.formattedTimestamp)] Event: \(event) | Properties: {\(propsString)}"
            fputs("\(logLine)\n", stderr)
            
            // Insert event chronologically at the top of the local inspection rolling queue
            DispatchQueue.main.async {
                self.localEventsBuffer.insert(telemetryEvent, at: 0)
                if self.localEventsBuffer.count > self.maxBufferSize {
                    self.localEventsBuffer.removeLast()
                }
            }
        }
    }
    
    /// Collect non-identifying system hardware profile data
    public func trackHardwareConfig() {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let totalMemoryGB = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
        let modelIdentifier = getMacModelIdentifier()
        
        track(event: "hardware_config", properties: [
            "macos_version": osVersion,
            "mac_model": modelIdentifier,
            "total_ram": "\(totalMemoryGB) GB"
        ])
    }
    
    /// System call to retrieve native Apple Silicon or Intel Mac identifier
    private func getMacModelIdentifier() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }
    
    /// Setup uncaught exception crash interceptor
    public static func registerCrashHandler() {
        NSSetUncaughtExceptionHandler { exception in
            let stack = exception.callStackSymbols.prefix(15).joined(separator: "\n")
            let name = exception.name.rawValue
            let reason = exception.reason ?? "No description"
            
            let crashReport: [String: String] = [
                "name": name,
                "reason": reason,
                "stack": stack,
                "timestamp": "\(Date().timeIntervalSince1970)"
            ]
            
            UserDefaults.standard.set(crashReport, forKey: "SAIPendingCrashReport")
            UserDefaults.standard.synchronize()
        }
    }
    
    /// Check for crashes that occurred during the previous session, report, and flush
    public func checkAndFlushPendingCrash() {
        guard let crashReport = UserDefaults.standard.dictionary(forKey: "SAIPendingCrashReport") as? [String: String] else {
            return
        }
        
        UserDefaults.standard.removeObject(forKey: "SAIPendingCrashReport")
        UserDefaults.standard.synchronize()
        
        track(event: "app_crash", properties: [
            "exception_name": crashReport["name"] ?? "Unknown",
            "exception_reason": crashReport["reason"] ?? "Unknown",
            "stack_trace": crashReport["stack"] ?? "",
            "crash_timestamp": crashReport["timestamp"] ?? ""
        ])
    }
    
    /// Manually clear the transparent local events queue
    public func clearLocalHistory() {
        DispatchQueue.main.async {
            self.localEventsBuffer.removeAll()
        }
    }
}

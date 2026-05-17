import Foundation

public enum AudioEngineError: LocalizedError {
    case decodeFailed(String)
    case encodeFailed(String)
    case connectionFailed(String)
    case restorationFailed(String)
    case daemonLaunchFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .decodeFailed(let reason):
            return "Sangeet couldn't read this audio file: \(reason)"
        case .encodeFailed(let reason):
            return "Sangeet couldn't save this audio file: \(reason)"
        case .connectionFailed(let reason):
            return "Failed to establish a connection with Sangeet's background restoration daemon: \(reason)"
        case .restorationFailed(let reason):
            return "Sangeet's restoration process failed: \(reason)"
        case .daemonLaunchFailed(let reason):
            return "Failed to start the Sangeet audio engine daemon: \(reason)"
        }
    }
}

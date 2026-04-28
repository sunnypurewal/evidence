import Foundation

public enum EvidenceError: Error, Equatable, LocalizedError {
    case anchorTimedOut(scene: String, anchor: String, timeout: TimeInterval)
    case navigationFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .anchorTimedOut(scene, anchor, timeout):
            "Timed out after \(timeout)s waiting for \(anchor) in scene '\(scene)'."
        case let .navigationFailed(message):
            message
        }
    }
}

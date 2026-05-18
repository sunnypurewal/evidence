import Foundation

public enum EvidenceError: Error, Equatable, LocalizedError {
    case anchorTimedOut(scene: String, anchor: String, timeout: TimeInterval)
    case navigationFailed(String)
    case planLoadingFailed(path: String, message: String)
    case unsupportedPlanStep(step: String, kind: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case let .anchorTimedOut(scene, anchor, timeout):
            "Timed out after \(timeout)s waiting for \(anchor) in scene '\(scene)'."
        case let .navigationFailed(message):
            message
        case let .planLoadingFailed(path, message):
            "Invalid evidence plan at \(path): \(message)"
        case let .unsupportedPlanStep(step, kind, reason):
            "Unsupported evidence plan step '\(step)' of kind '\(kind)': \(reason)"
        }
    }
}

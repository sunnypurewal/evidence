import Foundation

public enum CLIError: Error, Equatable, LocalizedError {
    case usage(String)
    case config(String)
    case missingTool(String, installHint: String)
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .usage(message), let .config(message), let .commandFailed(message):
            message
        case let .missingTool(tool, installHint):
            "Missing required tool '\(tool)'. \(installHint)"
        }
    }
}

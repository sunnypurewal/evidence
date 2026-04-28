import Foundation

public enum CLIError: Error, Equatable, LocalizedError {
    case usage(String)
    case config(String)
    case missingTool(String, installHint: String)
    case commandFailed(String)
    /// Surface a specific non-zero exit code without losing the human message.
    /// Used by `evidence diff` to distinguish "diff exceeded threshold" (1)
    /// from "baseline missing" (2), and by future subcommands that need
    /// CI-stable exit codes.
    case exit(Int32, message: String)

    public var errorDescription: String? {
        switch self {
        case let .usage(message), let .config(message), let .commandFailed(message):
            message
        case let .missingTool(tool, installHint):
            "Missing required tool '\(tool)'. \(installHint)"
        case let .exit(_, message):
            message
        }
    }

    /// Exit code the CLI should return when this error reaches `run()`.
    /// Defaults to `1` for legacy cases; `.exit` carries its own code.
    public var exitCode: Int32 {
        switch self {
        case let .exit(code, _):
            return code
        default:
            return 1
        }
    }
}

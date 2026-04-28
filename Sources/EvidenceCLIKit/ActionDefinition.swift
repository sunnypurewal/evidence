import Foundation

/// Lightweight validator for the repository's `action.yml` GitHub Action manifest.
///
/// Avoids pulling in a full YAML parser by inspecting the structural keys the
/// project depends on: `name`, `description`, `branding`, declared inputs/outputs,
/// and the composite-action `runs:` block. The validator is intentionally
/// conservative — it does not attempt to fully validate GitHub's schema, only
/// catches local regressions where a contributor accidentally drops a required
/// key or breaks an input name the example workflows depend on.
public struct ActionDefinitionValidator {
    public struct Requirements: Equatable {
        public var requiredInputNames: [String]
        public var requiredOutputNames: [String]
        public var requiredRunsUsing: String

        public init(
            requiredInputNames: [String],
            requiredOutputNames: [String],
            requiredRunsUsing: String = "composite"
        ) {
            self.requiredInputNames = requiredInputNames
            self.requiredOutputNames = requiredOutputNames
            self.requiredRunsUsing = requiredRunsUsing
        }
    }

    /// The default requirements that this repo's `action.yml` must satisfy.
    /// Mirrors the public input surface promised by the example workflows and
    /// README "Use in CI" section.
    public static let defaultRequirements = Requirements(
        requiredInputNames: [
            "subcommand",
            "config",
            "ticket",
            "baseline-dir",
            "output-dir",
            "extra-args",
            "comment-on-pr",
            "github-token"
        ],
        requiredOutputNames: ["output-dir", "artifact-count"]
    )

    public init() {}

    public func validate(_ source: String, requirements: Requirements = ActionDefinitionValidator.defaultRequirements) throws {
        try requireTopLevelKey("name", in: source)
        try requireTopLevelKey("description", in: source)
        try requireTopLevelKey("branding", in: source)
        try requireTopLevelKey("inputs", in: source)
        try requireTopLevelKey("outputs", in: source)
        try requireTopLevelKey("runs", in: source)

        let inputsBlock = try block(named: "inputs", in: source)
        for inputName in requirements.requiredInputNames {
            guard inputsBlock.contains("\n  \(inputName):") || inputsBlock.hasPrefix("\(inputName):") else {
                throw CLIError.config("action.yml is missing the required input '\(inputName)'.")
            }
        }

        let outputsBlock = try block(named: "outputs", in: source)
        for outputName in requirements.requiredOutputNames {
            guard outputsBlock.contains("\n  \(outputName):") || outputsBlock.hasPrefix("\(outputName):") else {
                throw CLIError.config("action.yml is missing the required output '\(outputName)'.")
            }
        }

        let runsBlock = try block(named: "runs", in: source)
        let usingPattern = "using: '\(requirements.requiredRunsUsing)'"
        let usingPatternUnquoted = "using: \(requirements.requiredRunsUsing)"
        let usingPatternDoubleQuoted = "using: \"\(requirements.requiredRunsUsing)\""
        guard runsBlock.contains(usingPattern)
                || runsBlock.contains(usingPatternUnquoted)
                || runsBlock.contains(usingPatternDoubleQuoted) else {
            throw CLIError.config("action.yml runs.using must be '\(requirements.requiredRunsUsing)'.")
        }
        guard runsBlock.contains("steps:") else {
            throw CLIError.config("action.yml runs block is missing 'steps:'.")
        }
    }

    private func requireTopLevelKey(_ key: String, in source: String) throws {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        let pattern = "\(key):"
        for line in lines {
            // Top-level key is on column 0 (no leading whitespace).
            if line.hasPrefix(pattern) {
                return
            }
        }
        throw CLIError.config("action.yml is missing required top-level key '\(key)'.")
    }

    private func block(named key: String, in source: String) throws -> String {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let startIndex = lines.firstIndex(where: { $0.hasPrefix("\(key):") }) else {
            throw CLIError.config("action.yml is missing block '\(key)'.")
        }

        var collected: [String] = []
        for line in lines[(startIndex + 1)...] {
            if line.isEmpty {
                collected.append(line)
                continue
            }
            // A new top-level key starts when a non-comment line has no leading whitespace.
            let firstChar = line.first!
            if firstChar != " " && firstChar != "\t" && firstChar != "#" {
                break
            }
            collected.append(line)
        }
        return "\n" + collected.joined(separator: "\n")
    }
}

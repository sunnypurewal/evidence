import Foundation

extension Platform: Codable {}

/// Runner mode used to execute a PR change evidence plan.
public enum RunnerCapability: String, Codable, Equatable {
    /// XCTest-backed runner. Can use accessibility labels and XCTest UI APIs.
    case xctest
    /// Simulator-control runner. Limited to simulator/app lifecycle operations.
    case simctl
}

public enum PRChangeEvidencePhase: String, Codable, Equatable, Hashable {
    case before
    case after
}

/// A source revision selected by a PR evidence plan.
///
/// JSON accepts either a bare string (`"main"`) or an object with explicit
/// kind metadata (`{ "kind": "sha", "value": "abc123" }`).
public struct PRRevisionRef: Codable, Equatable {
    public enum Kind: String, Codable, Equatable {
        case sha
        case branch
        case tag
        case ref
    }

    public var kind: Kind?
    public var value: String

    public init(kind: Kind? = nil, value: String) {
        self.kind = kind
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let value = try? single.decode(String.self) {
            self.kind = nil
            self.value = value
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.kind = try container.decodeIfPresent(Kind.self, forKey: .kind)
        self.value = try container.decode(String.self, forKey: .value)
    }

    public func encode(to encoder: Encoder) throws {
        if kind == nil {
            var container = encoder.singleValueContainer()
            try container.encode(value)
            return
        }

        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(kind, forKey: .kind)
        try container.encode(value, forKey: .value)
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case value
    }
}

public struct PRChangeEvidenceLaunch: Codable, Equatable {
    public var arguments: [String]
    public var environment: [String: String]

    public init(arguments: [String] = [], environment: [String: String] = [:]) {
        self.arguments = arguments
        self.environment = environment
    }
}

public struct PRChangeEvidenceVideo: Codable, Equatable {
    public var enabled: Bool
    public var name: String?

    public init(enabled: Bool = false, name: String? = nil) {
        self.enabled = enabled
        self.name = name
    }
}

public struct PRChangeEvidenceIOSSettings: Codable, Equatable {
    public var workspace: String?
    public var project: String?
    public var scheme: String?
    public var bundleID: String?
    public var simulator: String?
    public var simulatorUDID: String?
    public var destination: String?
    public var configuration: String?
    public var derivedDataPath: String?
    public var extraBuildArguments: [String]
    public var preserveSimulatorState: Bool

    public init(
        workspace: String? = nil,
        project: String? = nil,
        scheme: String? = nil,
        bundleID: String? = nil,
        simulator: String? = nil,
        simulatorUDID: String? = nil,
        destination: String? = nil,
        configuration: String? = nil,
        derivedDataPath: String? = nil,
        extraBuildArguments: [String] = [],
        preserveSimulatorState: Bool = false
    ) {
        self.workspace = workspace
        self.project = project
        self.scheme = scheme
        self.bundleID = bundleID
        self.simulator = simulator
        self.simulatorUDID = simulatorUDID
        self.destination = destination
        self.configuration = configuration
        self.derivedDataPath = derivedDataPath
        self.extraBuildArguments = extraBuildArguments
        self.preserveSimulatorState = preserveSimulatorState
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let dynamicContainer = try decoder.container(keyedBy: DynamicCodingKey.self)
        self.workspace = try container.decodeIfPresent(String.self, forKey: .workspace)
            ?? dynamicContainer.decodeIfPresent(String.self, forKey: .legacyWorkspace)
        self.project = try container.decodeIfPresent(String.self, forKey: .project)
            ?? dynamicContainer.decodeIfPresent(String.self, forKey: .legacyProject)
        self.scheme = try container.decodeIfPresent(String.self, forKey: .scheme)
        self.bundleID = try container.decodeIfPresent(String.self, forKey: .bundleID)
        self.simulator = try container.decodeIfPresent(String.self, forKey: .simulator)
        self.simulatorUDID = try container.decodeIfPresent(String.self, forKey: .simulatorUDID)
        self.destination = try container.decodeIfPresent(String.self, forKey: .destination)
        self.configuration = try container.decodeIfPresent(String.self, forKey: .configuration)
        self.derivedDataPath = try container.decodeIfPresent(String.self, forKey: .derivedDataPath)
        self.extraBuildArguments = try container.decodeIfPresent([String].self, forKey: .extraBuildArguments)
            ?? dynamicContainer.decodeIfPresent([String].self, forKey: .legacyExtraBuildArguments)
            ?? []
        self.preserveSimulatorState = try container.decodeIfPresent(Bool.self, forKey: .preserveSimulatorState) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(workspace, forKey: .workspace)
        try container.encodeIfPresent(project, forKey: .project)
        try container.encodeIfPresent(scheme, forKey: .scheme)
        try container.encodeIfPresent(bundleID, forKey: .bundleID)
        try container.encodeIfPresent(simulator, forKey: .simulator)
        try container.encodeIfPresent(simulatorUDID, forKey: .simulatorUDID)
        try container.encodeIfPresent(destination, forKey: .destination)
        try container.encodeIfPresent(configuration, forKey: .configuration)
        try container.encodeIfPresent(derivedDataPath, forKey: .derivedDataPath)
        if !extraBuildArguments.isEmpty {
            try container.encode(extraBuildArguments, forKey: .extraBuildArguments)
        }
        if preserveSimulatorState {
            try container.encode(preserveSimulatorState, forKey: .preserveSimulatorState)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case workspace
        case project
        case scheme
        case bundleID = "bundle_id"
        case simulator
        case simulatorUDID = "simulator_udid"
        case destination
        case configuration
        case derivedDataPath = "derived_data_path"
        case extraBuildArguments = "extra_build_arguments"
        case preserveSimulatorState = "preserve_simulator_state"
    }

    private struct DynamicCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?

        init(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            self.stringValue = "\(intValue)"
            self.intValue = intValue
        }

        static let legacyWorkspace = DynamicCodingKey(stringValue: "xcode_" + "workspace")
        static let legacyProject = DynamicCodingKey(stringValue: "xcode_" + "project")
        static let legacyExtraBuildArguments = DynamicCodingKey(stringValue: "extra_" + "xcode" + "build_arguments")
    }
}

public struct PRChangeEvidenceTarget: Codable, Equatable {
    public var accessibilityLabel: String?
    public var staticText: String?
    public var button: String?
    public var textField: String?

    public init(
        accessibilityLabel: String? = nil,
        staticText: String? = nil,
        button: String? = nil,
        textField: String? = nil
    ) {
        self.accessibilityLabel = accessibilityLabel
        self.staticText = staticText
        self.button = button
        self.textField = textField
    }

    var isEmpty: Bool {
        [accessibilityLabel, staticText, button, textField].allSatisfy { value in
            value?.isEmpty ?? true
        }
    }

    private enum CodingKeys: String, CodingKey {
        case accessibilityLabel
        case staticText
        case button
        case textField
    }
}

public enum PRChangeEvidenceSwipeDirection: String, Codable, Equatable {
    case up
    case down
    case left
    case right
}

public struct PRChangeEvidenceStep: Codable, Equatable {
    public enum Kind: String, Codable, Equatable {
        case launch
        case wait
        case screenshot
        case startVideo
        case stopVideo
        case openURL
        case tap
        case typeText
        case swipe

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)
            guard let kind = Kind(rawValue: rawValue) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "unsupported step kind '\(rawValue)'"
                )
            }
            self = kind
        }

        public var supportedRunners: [RunnerCapability] {
            switch self {
            case .tap, .typeText, .swipe:
                return [.xctest]
            case .launch, .wait, .screenshot, .startVideo, .stopVideo, .openURL:
                return [.xctest, .simctl]
            }
        }
    }

    public var name: String
    public var kind: Kind
    public var phase: PRChangeEvidencePhase?
    public var target: PRChangeEvidenceTarget?
    public var timeoutSeconds: Double?
    public var seconds: Double?
    public var path: String?
    public var url: String?
    public var text: String?
    public var direction: PRChangeEvidenceSwipeDirection?

    public init(
        name: String,
        kind: Kind,
        phase: PRChangeEvidencePhase? = nil,
        target: PRChangeEvidenceTarget? = nil,
        timeoutSeconds: Double? = nil,
        seconds: Double? = nil,
        path: String? = nil,
        url: String? = nil,
        text: String? = nil,
        direction: PRChangeEvidenceSwipeDirection? = nil
    ) {
        self.name = name
        self.kind = kind
        self.phase = phase
        self.target = target
        self.timeoutSeconds = timeoutSeconds
        self.seconds = seconds
        self.path = path
        self.url = url
        self.text = text
        self.direction = direction
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case kind
        case phase
        case target
        case timeoutSeconds = "timeout_seconds"
        case seconds
        case path
        case url
        case text
        case direction
    }
}

/// Codable input contract for a future `CapturePullRequestEvidence` use case.
public struct PRChangeEvidencePlan: Codable, Equatable {
    public var repo: String
    public var pr: Int
    public var beforeRef: PRRevisionRef?
    public var afterRef: PRRevisionRef?
    public var platform: Platform
    public var runner: RunnerCapability
    public var ios: PRChangeEvidenceIOSSettings?
    public var launch: PRChangeEvidenceLaunch
    public var outputDirectory: String
    public var steps: [PRChangeEvidenceStep]
    public var video: PRChangeEvidenceVideo

    public init(
        repo: String,
        pr: Int,
        beforeRef: PRRevisionRef? = nil,
        afterRef: PRRevisionRef? = nil,
        platform: Platform,
        runner: RunnerCapability = .xctest,
        ios: PRChangeEvidenceIOSSettings? = nil,
        launch: PRChangeEvidenceLaunch = PRChangeEvidenceLaunch(),
        outputDirectory: String = "docs/pr-change-evidence",
        steps: [PRChangeEvidenceStep],
        video: PRChangeEvidenceVideo = PRChangeEvidenceVideo()
    ) {
        self.repo = repo
        self.pr = pr
        self.beforeRef = beforeRef
        self.afterRef = afterRef
        self.platform = platform
        self.runner = runner
        self.ios = ios
        self.launch = launch
        self.outputDirectory = outputDirectory
        self.steps = steps
        self.video = video
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.repo = try container.decode(String.self, forKey: .repo)
        self.pr = try container.decode(Int.self, forKey: .pr)
        self.beforeRef = try container.decodeIfPresent(PRRevisionRef.self, forKey: .beforeRef)
        self.afterRef = try container.decodeIfPresent(PRRevisionRef.self, forKey: .afterRef)
        self.platform = try container.decode(Platform.self, forKey: .platform)
        self.runner = try container.decodeIfPresent(RunnerCapability.self, forKey: .runner) ?? .xctest
        self.ios = try container.decodeIfPresent(PRChangeEvidenceIOSSettings.self, forKey: .ios)
        self.launch = try container.decodeIfPresent(PRChangeEvidenceLaunch.self, forKey: .launch) ?? PRChangeEvidenceLaunch()
        self.outputDirectory = try container.decodeIfPresent(String.self, forKey: .outputDirectory) ?? "docs/pr-change-evidence"
        self.steps = try container.decode([PRChangeEvidenceStep].self, forKey: .steps)
        self.video = try container.decodeIfPresent(PRChangeEvidenceVideo.self, forKey: .video) ?? PRChangeEvidenceVideo()
    }

    public static func load(from url: URL) throws -> PRChangeEvidencePlan {
        do {
            let data = try Data(contentsOf: url)
            let plan = try JSONDecoder().decode(PRChangeEvidencePlan.self, from: data)
            try plan.validate(planPath: url.path)
            return plan
        } catch let error as CLIError {
            throw error
        } catch let error as DecodingError {
            throw CLIError.config("Invalid PR change evidence plan at \(url.path): \(decodeMessage(for: error)).")
        } catch {
            throw CLIError.config("Invalid PR change evidence plan at \(url.path): \(error.localizedDescription).")
        }
    }

    public func validate(planPath: String) throws {
        try require(!repo.isEmpty, planPath: planPath, field: "repo", message: "value must not be empty")
        try require(pr > 0, planPath: planPath, field: "pr", message: "expected value >= 1")
        try require(!outputDirectory.isEmpty, planPath: planPath, field: "output_directory", message: "value must not be empty")
        try require(!steps.isEmpty, planPath: planPath, field: "steps", message: "must contain at least one step")

        for (index, step) in steps.enumerated() {
            let field = "steps[\(index)]"
            try require(!step.name.isEmpty, planPath: planPath, field: "\(field).name", message: "value must not be empty")
            if !step.kind.supportedRunners.contains(runner) {
                throw CLIError.config("Invalid PR change evidence plan at \(planPath): invalid field '\(field).kind': runner '\(runner.rawValue)' does not support step kind '\(step.kind.rawValue)'.")
            }

            switch step.kind {
            case .launch:
                break
            case .wait:
                if runner == .simctl, step.target?.isEmpty == false {
                    throw CLIError.config("Invalid PR change evidence plan at \(planPath): invalid field '\(field).target': simctl wait steps cannot use accessibility targets; use 'seconds' for time-based waits or runner 'xctest' for accessibility waits.")
                }
                try require(
                    step.target?.isEmpty == false || step.seconds != nil,
                    planPath: planPath,
                    field: field,
                    message: "wait steps require either 'target' or 'seconds'"
                )
            case .screenshot, .startVideo, .stopVideo:
                try require(
                    step.path?.isEmpty == false,
                    planPath: planPath,
                    field: "\(field).path",
                    message: "value must not be empty"
                )
            case .openURL:
                try require(
                    step.url?.isEmpty == false,
                    planPath: planPath,
                    field: "\(field).url",
                    message: "value must not be empty"
                )
            case .tap:
                try require(
                    step.target?.isEmpty == false,
                    planPath: planPath,
                    field: "\(field).target",
                    message: "tap steps require an accessibility target"
                )
            case .typeText:
                try require(
                    step.target?.isEmpty == false,
                    planPath: planPath,
                    field: "\(field).target",
                    message: "typeText steps require an accessibility target"
                )
                try require(
                    step.text?.isEmpty == false,
                    planPath: planPath,
                    field: "\(field).text",
                    message: "value must not be empty"
                )
            case .swipe:
                try require(
                    step.direction != nil,
                    planPath: planPath,
                    field: "\(field).direction",
                    message: "swipe steps require a direction"
                )
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case repo
        case pr
        case beforeRef = "before_ref"
        case afterRef = "after_ref"
        case platform
        case runner
        case ios
        case launch
        case outputDirectory = "output_directory"
        case steps
        case video
    }

    private static func decodeMessage(for error: DecodingError) -> String {
        switch error {
        case let .keyNotFound(key, context):
            return "missing required field '\(fieldPath(context.codingPath, appending: key))'"
        case let .typeMismatch(type, context):
            return "invalid field '\(fieldPath(context.codingPath))': expected \(type)"
        case let .valueNotFound(type, context):
            return "missing value for field '\(fieldPath(context.codingPath))': expected \(type)"
        case let .dataCorrupted(context):
            return "invalid field '\(fieldPath(context.codingPath))': \(context.debugDescription)"
        @unknown default:
            return "could not decode plan"
        }
    }

    private static func fieldPath(_ codingPath: [CodingKey], appending key: CodingKey? = nil) -> String {
        let fullPath = key.map { codingPath + [$0] } ?? codingPath
        guard !fullPath.isEmpty else { return "root" }

        return fullPath.reduce(into: "") { result, key in
            if let index = key.intValue {
                result += "[\(index)]"
            } else if result.isEmpty {
                result = key.stringValue
            } else {
                result += ".\(key.stringValue)"
            }
        }
    }

    private func require(_ condition: Bool, planPath: String, field: String, message: String) throws {
        guard condition else {
            throw CLIError.config("Invalid PR change evidence plan at \(planPath): invalid field '\(field)': \(message).")
        }
    }
}

public struct PRRevisionMetadata: Codable, Equatable {
    public var repo: String?
    public var ref: String?
    public var sha: String

    public init(repo: String? = nil, ref: String? = nil, sha: String) {
        self.repo = repo
        self.ref = ref
        self.sha = sha
    }
}

public struct PRChangeEvidenceSimulator: Codable, Equatable {
    public var name: String?
    public var udid: String?

    public init(name: String? = nil, udid: String? = nil) {
        self.name = name
        self.udid = udid
    }
}

public struct PRChangeEvidenceBuildResult: Codable, Equatable {
    public enum Status: String, Codable, Equatable {
        case succeeded
        case failed
        case skipped
    }

    public var status: Status
    public var logPath: String?
    public var durationSeconds: Double?

    public init(status: Status, logPath: String? = nil, durationSeconds: Double? = nil) {
        self.status = status
        self.logPath = logPath
        self.durationSeconds = durationSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case status
        case logPath = "log_path"
        case durationSeconds = "duration_seconds"
    }
}

public struct RevisionBuildResult: Codable, Equatable {
    public var phase: PRChangeEvidencePhase
    public var command: [String]
    public var exitCode: Int32
    public var durationSeconds: Double
    public var stdoutExcerpt: String
    public var stderrExcerpt: String
    public var appBundlePath: String
    public var derivedDataPath: String
    public var logPath: String

    public init(
        phase: PRChangeEvidencePhase,
        command: [String],
        exitCode: Int32,
        durationSeconds: Double,
        stdoutExcerpt: String,
        stderrExcerpt: String,
        appBundlePath: String,
        derivedDataPath: String,
        logPath: String
    ) {
        self.phase = phase
        self.command = command
        self.exitCode = exitCode
        self.durationSeconds = durationSeconds
        self.stdoutExcerpt = stdoutExcerpt
        self.stderrExcerpt = stderrExcerpt
        self.appBundlePath = appBundlePath
        self.derivedDataPath = derivedDataPath
        self.logPath = logPath
    }

    private enum CodingKeys: String, CodingKey {
        case phase
        case command
        case exitCode = "exit_code"
        case durationSeconds = "duration_seconds"
        case stdoutExcerpt = "stdout_excerpt"
        case stderrExcerpt = "stderr_excerpt"
        case appBundlePath = "app_bundle_path"
        case derivedDataPath = "derived_data_path"
        case logPath = "log_path"
    }
}

public struct CapturedArtifact: Codable, Equatable {
    public enum Kind: String, Codable, Equatable {
        case screenshot
        case video
        case log
        case manifest
        case other
    }

    public var kind: Kind
    public var phase: PRChangeEvidencePhase?
    public var path: String
    public var stepName: String?
    public var sha256: String?

    public init(kind: Kind, phase: PRChangeEvidencePhase? = nil, path: String, stepName: String? = nil, sha256: String? = nil) {
        self.kind = kind
        self.phase = phase
        self.path = path
        self.stepName = stepName
        self.sha256 = sha256
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case phase
        case path
        case stepName = "step_name"
        case sha256
    }
}

public struct PRChangeEvidenceFailureSummary: Codable, Equatable {
    public var stepName: String?
    public var message: String
    public var artifactPath: String?

    public init(stepName: String? = nil, message: String, artifactPath: String? = nil) {
        self.stepName = stepName
        self.message = message
        self.artifactPath = artifactPath
    }

    private enum CodingKeys: String, CodingKey {
        case stepName = "step_name"
        case message
        case artifactPath = "artifact_path"
    }
}

/// Codable output contract for a completed or failed PR change evidence run.
public struct PRChangeEvidenceManifest: Codable, Equatable {
    public var prNumber: Int
    public var prURL: String?
    public var prTitle: String?
    public var prState: String?
    public var beforeSHA: String
    public var afterSHA: String
    public var beforeRef: String?
    public var afterRef: String?
    public var base: PRRevisionMetadata?
    public var head: PRRevisionMetadata?
    public var merge: PRRevisionMetadata?
    public var planPath: String
    public var command: [String]
    public var runnerMode: RunnerCapability
    public var simulator: PRChangeEvidenceSimulator?
    public var xcodeDestination: String?
    public var buildResult: PRChangeEvidenceBuildResult
    public var revisionBuilds: [RevisionBuildResult]
    public var artifacts: [CapturedArtifact]
    public var startedAt: String
    public var completedAt: String?
    public var failures: [PRChangeEvidenceFailureSummary]
    public var worktrees: [ComparisonWorktree]

    public init(
        prNumber: Int,
        prURL: String? = nil,
        prTitle: String? = nil,
        prState: String? = nil,
        beforeSHA: String,
        afterSHA: String,
        beforeRef: String? = nil,
        afterRef: String? = nil,
        base: PRRevisionMetadata? = nil,
        head: PRRevisionMetadata? = nil,
        merge: PRRevisionMetadata? = nil,
        planPath: String,
        command: [String],
        runnerMode: RunnerCapability,
        simulator: PRChangeEvidenceSimulator? = nil,
        xcodeDestination: String? = nil,
        buildResult: PRChangeEvidenceBuildResult,
        revisionBuilds: [RevisionBuildResult] = [],
        artifacts: [CapturedArtifact],
        startedAt: String,
        completedAt: String? = nil,
        failures: [PRChangeEvidenceFailureSummary] = [],
        worktrees: [ComparisonWorktree] = []
    ) {
        self.prNumber = prNumber
        self.prURL = prURL
        self.prTitle = prTitle
        self.prState = prState
        self.beforeSHA = beforeSHA
        self.afterSHA = afterSHA
        self.beforeRef = beforeRef
        self.afterRef = afterRef
        self.base = base
        self.head = head
        self.merge = merge
        self.planPath = planPath
        self.command = command
        self.runnerMode = runnerMode
        self.simulator = simulator
        self.xcodeDestination = xcodeDestination
        self.buildResult = buildResult
        self.revisionBuilds = revisionBuilds
        self.artifacts = artifacts
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.failures = failures
        self.worktrees = worktrees
    }

    private enum CodingKeys: String, CodingKey {
        case prNumber = "pr_number"
        case prURL = "pr_url"
        case prTitle = "pr_title"
        case prState = "pr_state"
        case beforeSHA = "before_sha"
        case afterSHA = "after_sha"
        case beforeRef = "before_ref"
        case afterRef = "after_ref"
        case base
        case head
        case merge
        case planPath = "plan_path"
        case command
        case runnerMode = "runner_mode"
        case simulator
        case xcodeDestination = "xcode_destination"
        case buildResult = "build_result"
        case revisionBuilds = "revision_builds"
        case artifacts
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case failures
        case worktrees
    }
}

import Foundation

public protocol EvidenceClock {
    func now() -> Date
}

public struct SystemEvidenceClock: EvidenceClock {
    public init() {}

    public func now() -> Date {
        Date()
    }
}

public enum ComparisonWorktreeLabel: String, Codable, Equatable {
    case before
    case after
}

public struct PullRequestMetadata: Codable, Equatable {
    public var number: Int
    public var url: String
    public var title: String
    public var state: String
    public var baseRef: String
    public var headRef: String
    public var baseSHA: String
    public var headSHA: String
    public var mergeSHA: String?

    public init(
        number: Int,
        url: String,
        title: String,
        state: String,
        baseRef: String,
        headRef: String,
        baseSHA: String,
        headSHA: String,
        mergeSHA: String?
    ) {
        self.number = number
        self.url = url
        self.title = title
        self.state = state
        self.baseRef = baseRef
        self.headRef = headRef
        self.baseSHA = baseSHA
        self.headSHA = headSHA
        self.mergeSHA = mergeSHA
    }

    enum CodingKeys: String, CodingKey {
        case number
        case url
        case title
        case state
        case baseRef = "base_ref"
        case headRef = "head_ref"
        case baseSHA = "base_sha"
        case headSHA = "head_sha"
        case mergeSHA = "merge_sha"
    }
}

public struct RevisionSelection: Codable, Equatable {
    public var beforeRef: String?
    public var afterRef: String?
    public var beforeSHA: String
    public var afterSHA: String

    public init(beforeRef: String?, afterRef: String?, beforeSHA: String, afterSHA: String) {
        self.beforeRef = beforeRef
        self.afterRef = afterRef
        self.beforeSHA = beforeSHA
        self.afterSHA = afterSHA
    }

    enum CodingKeys: String, CodingKey {
        case beforeRef = "before_ref"
        case afterRef = "after_ref"
        case beforeSHA = "before_sha"
        case afterSHA = "after_sha"
    }
}

public struct ComparisonWorktree: Codable, Equatable {
    public var label: ComparisonWorktreeLabel
    public var sha: String
    public var path: String

    public init(label: ComparisonWorktreeLabel, sha: String, path: String) {
        self.label = label
        self.sha = sha
        self.path = path
    }
}

public struct PullRequestComparisonResolution: Equatable {
    public var metadata: PullRequestMetadata
    public var selection: RevisionSelection

    public init(metadata: PullRequestMetadata, selection: RevisionSelection) {
        self.metadata = metadata
        self.selection = selection
    }
}

public protocol PullRequestMetadataProviding {
    func metadata(repo: String, pr: Int) throws -> PullRequestMetadata
}

public protocol GitRepositoryPreparing {
    func resolveRevision(_ ref: String) throws -> String
    func firstParent(of mergeSHA: String) throws -> String
    func prepareWorktree(label: ComparisonWorktreeLabel, sha: String, outputDirectory: URL) throws -> ComparisonWorktree
}

public struct ResolvePullRequestComparison {
    public var metadataProvider: any PullRequestMetadataProviding
    public var git: any GitRepositoryPreparing

    public init(metadataProvider: any PullRequestMetadataProviding, git: any GitRepositoryPreparing) {
        self.metadataProvider = metadataProvider
        self.git = git
    }

    public func execute(
        repo: String,
        pr: Int,
        beforeRef: String?,
        afterRef: String?
    ) throws -> PullRequestComparisonResolution {
        let metadata = try metadataProvider.metadata(repo: repo, pr: pr)

        let defaultBeforeSHA: String
        let defaultAfterSHA: String
        if metadata.state.uppercased() == "MERGED", let mergeSHA = metadata.mergeSHA, !mergeSHA.isEmpty {
            defaultBeforeSHA = try git.firstParent(of: mergeSHA)
            defaultAfterSHA = try git.resolveRevision(mergeSHA)
        } else {
            defaultBeforeSHA = metadata.baseSHA
            defaultAfterSHA = metadata.headSHA
        }

        let selectedBeforeSHA = try beforeRef.map { try git.resolveRevision($0) } ?? defaultBeforeSHA
        let selectedAfterSHA = try afterRef.map { try git.resolveRevision($0) } ?? defaultAfterSHA

        return PullRequestComparisonResolution(
            metadata: metadata,
            selection: RevisionSelection(
                beforeRef: beforeRef,
                afterRef: afterRef,
                beforeSHA: selectedBeforeSHA,
                afterSHA: selectedAfterSHA
            )
        )
    }
}

public struct PrepareComparisonWorktrees {
    public var git: any GitRepositoryPreparing

    public init(git: any GitRepositoryPreparing) {
        self.git = git
    }

    public func execute(selection: RevisionSelection, outputDirectory: URL) throws -> [ComparisonWorktree] {
        [
            try git.prepareWorktree(label: .before, sha: selection.beforeSHA, outputDirectory: outputDirectory),
            try git.prepareWorktree(label: .after, sha: selection.afterSHA, outputDirectory: outputDirectory)
        ]
    }
}

public struct CapturePullRequestEvidenceInput {
    public var repo: String
    public var pr: Int
    public var planPath: String
    public var planURL: URL
    public var outputDirectory: URL
    public var beforeRef: String?
    public var afterRef: String?

    public init(
        repo: String,
        pr: Int,
        planPath: String,
        planURL: URL? = nil,
        outputDirectory: URL,
        beforeRef: String?,
        afterRef: String?
    ) {
        self.repo = repo
        self.pr = pr
        self.planPath = planPath
        self.planURL = planURL ?? URL(fileURLWithPath: planPath)
        self.outputDirectory = outputDirectory
        self.beforeRef = beforeRef
        self.afterRef = afterRef
    }
}

public struct CapturePullRequestEvidence {
    public var resolver: ResolvePullRequestComparison
    public var worktreePreparer: PrepareComparisonWorktrees
    public var revisionBuilder: BuildRevisionForEvidence?
    public var simulatorPreparer: PrepareSimulatorForEvidenceRun?
    public var planExecutor: EvidencePlanExecuting?
    public var reporter: (any PullRequestEvidenceReporting)?
    public var fileManager: FileManager
    public var clock: any EvidenceClock

    public init(
        resolver: ResolvePullRequestComparison,
        worktreePreparer: PrepareComparisonWorktrees,
        revisionBuilder: BuildRevisionForEvidence? = nil,
        simulatorPreparer: PrepareSimulatorForEvidenceRun? = nil,
        planExecutor: EvidencePlanExecuting? = nil,
        reporter: (any PullRequestEvidenceReporting)? = nil,
        fileManager: FileManager = .default,
        clock: any EvidenceClock = SystemEvidenceClock()
    ) {
        self.resolver = resolver
        self.worktreePreparer = worktreePreparer
        self.revisionBuilder = revisionBuilder
        self.simulatorPreparer = simulatorPreparer
        self.planExecutor = planExecutor
        self.reporter = reporter
        self.fileManager = fileManager
        self.clock = clock
    }

    @discardableResult
    public func execute(_ input: CapturePullRequestEvidenceInput) throws -> PRChangeEvidenceManifest {
        try fileManager.createDirectory(at: input.outputDirectory, withIntermediateDirectories: true)
        let plan = try loadPlan(from: input.planURL)
        let startedAt = ISO8601DateFormatter().string(from: clock.now())

        let resolution = try resolver.execute(
            repo: input.repo,
            pr: input.pr,
            beforeRef: input.beforeRef,
            afterRef: input.afterRef
        )
        let worktrees: [ComparisonWorktree]
        do {
            worktrees = try worktreePreparer.execute(
                selection: resolution.selection,
                outputDirectory: input.outputDirectory
            )
        } catch {
            _ = try reporter?.writeReportOnlyFailure(
                PullRequestEvidenceReportOnlyFailure(
                    repo: input.repo,
                    pr: input.pr,
                    planPath: input.planPath,
                    prURL: resolution.metadata.url,
                    prTitle: resolution.metadata.title,
                    beforeSHA: resolution.selection.beforeSHA,
                    afterSHA: resolution.selection.afterSHA,
                    runnerMode: plan.runner,
                    simulator: PRChangeEvidenceSimulator(
                        name: plan.ios?.simulator,
                        udid: plan.ios?.simulatorUDID
                    ),
                    command: manifestCommand(for: input),
                    startedAt: startedAt,
                    completedAt: ISO8601DateFormatter().string(from: clock.now()),
                    errorMessage: (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                ),
                outputDirectory: input.outputDirectory
            )
            throw error
        }
        let iosSettings = plan.platform == .ios ? plan.ios : nil
        var revisionBuilds: [RevisionBuildResult] = []
        var simulator: PRChangeEvidenceSimulator?
        var failures: [PRChangeEvidenceFailureSummary] = []
        var terminalError: CLIError?
        var buildStatus: PRChangeEvidenceBuildResult.Status = .skipped
        var buildLogPath: String?
        var buildDuration: Double?
        var artifacts: [CapturedArtifact] = [
            CapturedArtifact(
                kind: .manifest,
                path: input.outputDirectory.appendingPathComponent("manifest.json").path
            )
        ]
        var stepResults: [CaptureStepResult] = []

        if let ios = iosSettings, let revisionBuilder {
            for worktree in worktrees {
                let phase = PRChangeEvidencePhase(worktree.label)
                let result = try revisionBuilder.execute(
                    RevisionBuildRequest(
                        phase: phase,
                        worktree: worktree,
                        ios: ios,
                        outputDirectory: input.outputDirectory
                    )
                )
                revisionBuilds.append(result)

                if result.exitCode != 0 {
                    let message = Self.buildFailureMessage(result)
                    failures.append(PRChangeEvidenceFailureSummary(message: message, artifactPath: result.logPath))
                    terminalError = CLIError.commandFailed(message)
                    break
                }
            }

            buildStatus = revisionBuilds.contains { $0.exitCode != 0 } ? .failed : .succeeded
            buildLogPath = input.outputDirectory.appendingPathComponent("logs", isDirectory: true).path
            buildDuration = revisionBuilds.reduce(0) { $0 + $1.durationSeconds }
            artifacts = revisionBuilds.map {
                CapturedArtifact(kind: .log, phase: $0.phase, path: $0.logPath, stepName: "\($0.phase.rawValue) build")
            } + artifacts

            if terminalError == nil, let planExecutor {
                do {
                    let runResult = try planExecutor.execute(
                        EvidencePlanExecutionRequest(
                            plan: plan,
                            planURL: input.planURL,
                            outputDirectory: input.outputDirectory,
                            worktrees: worktrees,
                            revisionBuilds: revisionBuilds,
                            ios: ios,
                            launch: plan.launch
                        )
                    )
                    if let runSimulator = runResult.simulator {
                        simulator = runSimulator
                    }
                    artifacts = runResult.artifacts + artifacts
                    stepResults = runResult.stepResults
                    failures.append(contentsOf: runResult.failures)
                    if !runResult.succeeded {
                        let message = runResult.failures.first?.message
                            ?? runResult.stepResults.first(where: { $0.status == .failed })?.message
                            ?? "PR evidence plan execution failed."
                        terminalError = CLIError.commandFailed(message)
                    }
                } catch let error as CLIError {
                    let message = error.errorDescription ?? String(describing: error)
                    failures.append(PRChangeEvidenceFailureSummary(message: message))
                    terminalError = error
                } catch {
                    let message = String(describing: error)
                    failures.append(PRChangeEvidenceFailureSummary(message: message))
                    terminalError = CLIError.commandFailed(message)
                }
            } else if terminalError == nil, let simulatorPreparer {
                do {
                    simulator = try simulatorPreparer.execute(
                        ios: ios,
                        launch: plan.launch,
                        builds: revisionBuilds
                    )
                } catch let error as CLIError {
                    let message = error.errorDescription ?? String(describing: error)
                    failures.append(PRChangeEvidenceFailureSummary(message: message))
                    terminalError = error
                } catch {
                    let message = String(describing: error)
                    failures.append(PRChangeEvidenceFailureSummary(message: message))
                    terminalError = CLIError.commandFailed(message)
                }
            }
        } else if plan.platform == .ios, plan.ios == nil {
            terminalError = CLIError.config("Invalid PR change evidence plan at \(input.planURL.path): missing required field 'ios' for platform 'ios'.")
            if let terminalError {
                failures.append(PRChangeEvidenceFailureSummary(message: terminalError.errorDescription ?? String(describing: terminalError)))
            }
        }

        let manifest = PRChangeEvidenceManifest(
            prNumber: input.pr,
            prURL: resolution.metadata.url,
            prTitle: resolution.metadata.title,
            prState: resolution.metadata.state,
            beforeSHA: resolution.selection.beforeSHA,
            afterSHA: resolution.selection.afterSHA,
            beforeRef: resolution.selection.beforeRef,
            afterRef: resolution.selection.afterRef,
            base: PRRevisionMetadata(
                repo: input.repo,
                ref: resolution.metadata.baseRef,
                sha: resolution.metadata.baseSHA
            ),
            head: PRRevisionMetadata(
                repo: input.repo,
                ref: resolution.metadata.headRef,
                sha: resolution.metadata.headSHA
            ),
            merge: resolution.metadata.mergeSHA.map {
                PRRevisionMetadata(repo: input.repo, ref: "refs/pull/\(input.pr)/merge", sha: $0)
            },
            planPath: input.planPath,
            command: manifestCommand(for: input),
            runnerMode: plan.runner,
            simulator: simulator,
            xcodeDestination: iosSettings?.destination,
            buildResult: PRChangeEvidenceBuildResult(
                status: buildStatus,
                logPath: buildLogPath,
                durationSeconds: buildDuration
            ),
            revisionBuilds: revisionBuilds,
            artifacts: artifacts,
            stepResults: stepResults,
            startedAt: startedAt,
            completedAt: ISO8601DateFormatter().string(from: clock.now()),
            failures: failures,
            worktrees: worktrees
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(
            to: input.outputDirectory.appendingPathComponent("manifest.json"),
            options: [.atomic]
        )
        try reporter?.writeReport(
            manifest: manifest,
            plan: plan,
            outputDirectory: input.outputDirectory
        )
        if let terminalError {
            throw terminalError
        }
        return manifest
    }

    private func loadPlan(from url: URL) throws -> PRChangeEvidencePlan {
        guard fileManager.fileExists(atPath: url.path) else {
            throw CLIError.config("Missing PR change evidence plan at \(url.path).")
        }
        return try PRChangeEvidencePlan.load(from: url)
    }

    private static func buildFailureMessage(_ result: RevisionBuildResult) -> String {
        let detail = result.stderrExcerpt.nonEmpty ?? result.stdoutExcerpt.nonEmpty ?? "See \(result.logPath)."
        return "\(result.phase.rawValue) build failed with exit code \(result.exitCode). \(detail)"
    }

    private func manifestCommand(for input: CapturePullRequestEvidenceInput) -> [String] {
        var command = [
            "evidence",
            "capture-pr",
            "--repo", input.repo,
            "--pr", "\(input.pr)",
            "--plan", input.planPath,
            "--output", input.outputDirectory.path
        ]
        if let beforeRef = input.beforeRef {
            command.append(contentsOf: ["--before-ref", beforeRef])
        }
        if let afterRef = input.afterRef {
            command.append(contentsOf: ["--after-ref", afterRef])
        }
        return command
    }
}

public struct GitHubCLIPullRequestMetadataProvider: PullRequestMetadataProviding {
    public var runner: CommandRunning
    public var ghPath: String

    public init(runner: CommandRunning, ghPath: String) {
        self.runner = runner
        self.ghPath = ghPath
    }

    public func metadata(repo: String, pr: Int) throws -> PullRequestMetadata {
        let fields = "url,title,state,baseRefName,headRefName,baseRefOid,headRefOid,mergeCommit"
        let result = try runner.run(
            ghPath,
            ["pr", "view", "\(pr)", "--repo", repo, "--json", fields]
        )
        guard result.exitCode == 0 else {
            throw metadataError(repo: repo, pr: pr, detail: result.stderr.nonEmpty ?? result.stdout)
        }

        do {
            let decoded = try JSONDecoder().decode(GitHubPullRequestView.self, from: Data(result.stdout.utf8))
            return try decoded.metadata(number: pr)
        } catch {
            throw metadataError(repo: repo, pr: pr, detail: String(describing: error))
        }
    }

    private func metadataError(repo: String, pr: Int, detail: String) -> CLIError {
        CLIError.commandFailed("PR metadata resolution failed for \(repo)#\(pr): \(detail)")
    }
}

public struct GitCLIRepositoryPreparer: GitRepositoryPreparing {
    public var fileManager: FileManager
    public var runner: CommandRunning
    public var gitPath: String
    public var repositoryRoot: URL

    public init(
        fileManager: FileManager = .default,
        runner: CommandRunning,
        gitPath: String,
        repositoryRoot: URL
    ) {
        self.fileManager = fileManager
        self.runner = runner
        self.gitPath = gitPath
        self.repositoryRoot = repositoryRoot
    }

    public func resolveRevision(_ ref: String) throws -> String {
        try fetch(ref)
        let result = try git(["rev-parse", "--verify", "\(ref)^{commit}"], at: repositoryRoot)
        let resolved = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.exitCode == 0, !resolved.isEmpty else {
            throw missingRef(ref)
        }
        return resolved
    }

    public func firstParent(of mergeSHA: String) throws -> String {
        try fetch(mergeSHA)
        let parentRef = "\(mergeSHA)^1"
        let result = try git(["rev-parse", "--verify", parentRef], at: repositoryRoot)
        let resolved = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.exitCode == 0, !resolved.isEmpty else {
            throw missingRef(parentRef)
        }
        return resolved
    }

    public func prepareWorktree(
        label: ComparisonWorktreeLabel,
        sha: String,
        outputDirectory: URL
    ) throws -> ComparisonWorktree {
        let resolvedSHA = try resolveRevision(sha)
        let shortSHA = String(resolvedSHA.prefix(12))
        let worktreesDirectory = outputDirectory.appendingPathComponent("worktrees", isDirectory: true)
        let worktreeURL = worktreesDirectory.appendingPathComponent("\(label.rawValue)-\(shortSHA)", isDirectory: true)
        let markerDirectory = worktreesDirectory.appendingPathComponent(".evidence-owned", isDirectory: true)
        let markerURL = markerDirectory.appendingPathComponent("\(label.rawValue)-\(shortSHA).json")

        if fileManager.fileExists(atPath: worktreeURL.path) {
            guard fileManager.fileExists(atPath: markerURL.path) else {
                throw dirtyWorktree(path: worktreeURL.path)
            }
            let status = try git(["status", "--porcelain"], at: worktreeURL)
            guard status.exitCode == 0 else {
                throw gitFailure("checking existing worktree", result: status)
            }
            guard status.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw dirtyWorktree(path: worktreeURL.path)
            }
            let remove = try git(["worktree", "remove", "--force", worktreeURL.path], at: repositoryRoot)
            guard remove.exitCode == 0 else {
                throw gitFailure("removing existing worktree", result: remove)
            }
        }

        try fileManager.createDirectory(at: markerDirectory, withIntermediateDirectories: true)
        let add = try git(["worktree", "add", "--detach", worktreeURL.path, resolvedSHA], at: repositoryRoot)
        guard add.exitCode == 0 else {
            throw gitFailure("creating worktree", result: add)
        }

        let marker = WorktreeMarker(label: label, sha: resolvedSHA, path: worktreeURL.path)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(marker).write(to: markerURL, options: [.atomic])

        return ComparisonWorktree(label: label, sha: resolvedSHA, path: worktreeURL.path)
    }

    private func git(_ arguments: [String], at directory: URL) throws -> CommandResult {
        try runner.run(gitPath, ["-C", directory.path] + arguments)
    }

    private func fetch(_ ref: String) throws {
        let result = try git(["fetch", "origin", ref], at: repositoryRoot)
        guard result.exitCode == 0 else {
            let detail = result.stderr.nonEmpty ?? result.stdout.nonEmpty ?? ""
            if detail.contains("couldn't find remote ref")
                || detail.contains("could not find remote ref")
                || detail.contains("not our ref") {
                return
            }
            throw gitFailure("fetching ref '\(ref)'", result: result)
        }
    }

    private func missingRef(_ ref: String) -> CLIError {
        CLIError.commandFailed("Missing ref '\(ref)'. Fetch it locally or pass an explicit --before-ref/--after-ref that resolves to a commit.")
    }

    private func dirtyWorktree(path: String) -> CLIError {
        CLIError.commandFailed("Dirty pre-existing worktree at \(path). Evidence will not remove it; clean it up or choose a different --output path.")
    }

    private func gitFailure(_ operation: String, result: CommandResult) -> CLIError {
        let detail = result.stderr.nonEmpty ?? result.stdout.nonEmpty ?? "exit code \(result.exitCode)"
        return CLIError.commandFailed("Git command failed while \(operation): \(detail)")
    }
}

private struct GitHubPullRequestView: Decodable {
    var url: String?
    var title: String?
    var state: String?
    var baseRefName: String?
    var headRefName: String?
    var baseRefOid: String?
    var headRefOid: String?
    var mergeCommit: MergeCommit?

    func metadata(number: Int) throws -> PullRequestMetadata {
        guard let url = url?.nonEmpty else {
            throw CLIError.commandFailed("missing url")
        }
        guard let title = title?.nonEmpty else {
            throw CLIError.commandFailed("missing title")
        }
        guard let state = state?.nonEmpty else {
            throw CLIError.commandFailed("missing state")
        }
        guard let baseRef = baseRefName?.nonEmpty else {
            throw CLIError.commandFailed("missing baseRefName")
        }
        guard let headRef = headRefName?.nonEmpty else {
            throw CLIError.commandFailed("missing headRefName")
        }
        guard let baseSHA = baseRefOid?.nonEmpty else {
            throw CLIError.commandFailed("missing baseRefOid")
        }
        guard let headSHA = headRefOid?.nonEmpty else {
            throw CLIError.commandFailed("missing headRefOid")
        }

        return PullRequestMetadata(
            number: number,
            url: url,
            title: title,
            state: state,
            baseRef: baseRef,
            headRef: headRef,
            baseSHA: baseSHA,
            headSHA: headSHA,
            mergeSHA: mergeCommit?.oid.nonEmpty
        )
    }

    struct MergeCommit: Decodable {
        var oid: String
    }
}

private struct WorktreeMarker: Codable {
    var label: ComparisonWorktreeLabel
    var sha: String
    var path: String
}

private extension PRChangeEvidencePhase {
    init(_ label: ComparisonWorktreeLabel) {
        switch label {
        case .before:
            self = .before
        case .after:
            self = .after
        }
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

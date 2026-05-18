import Foundation

public struct EvidencePlanExecutionRequest {
    public var plan: PRChangeEvidencePlan
    public var planURL: URL
    public var outputDirectory: URL
    public var worktrees: [ComparisonWorktree]
    public var revisionBuilds: [RevisionBuildResult]
    public var ios: PRChangeEvidenceIOSSettings
    public var launch: PRChangeEvidenceLaunch

    public init(
        plan: PRChangeEvidencePlan,
        planURL: URL,
        outputDirectory: URL,
        worktrees: [ComparisonWorktree],
        revisionBuilds: [RevisionBuildResult],
        ios: PRChangeEvidenceIOSSettings,
        launch: PRChangeEvidenceLaunch
    ) {
        self.plan = plan
        self.planURL = planURL
        self.outputDirectory = outputDirectory
        self.worktrees = worktrees
        self.revisionBuilds = revisionBuilds
        self.ios = ios
        self.launch = launch
    }
}

public struct EvidenceRunResult: Equatable {
    public var simulator: PRChangeEvidenceSimulator?
    public var artifacts: [CapturedArtifact]
    public var stepResults: [CaptureStepResult]
    public var failures: [PRChangeEvidenceFailureSummary]

    public init(
        simulator: PRChangeEvidenceSimulator? = nil,
        artifacts: [CapturedArtifact] = [],
        stepResults: [CaptureStepResult] = [],
        failures: [PRChangeEvidenceFailureSummary] = []
    ) {
        self.simulator = simulator
        self.artifacts = artifacts
        self.stepResults = stepResults
        self.failures = failures
    }

    public var succeeded: Bool {
        failures.isEmpty && !stepResults.contains { $0.status == .failed }
    }
}

public protocol EvidencePlanExecuting {
    func execute(_ request: EvidencePlanExecutionRequest) throws -> EvidenceRunResult
}

public protocol ArtifactWriting {
    func artifact(
        kind: CapturedArtifact.Kind,
        phase: PRChangeEvidencePhase,
        path: String,
        stepName: String,
        mediaType: String,
        capturedAt: String
    ) -> CapturedArtifact
}

public struct FileArtifactWriter: ArtifactWriting {
    public var fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func artifact(
        kind: CapturedArtifact.Kind,
        phase: PRChangeEvidencePhase,
        path: String,
        stepName: String,
        mediaType: String,
        capturedAt: String
    ) -> CapturedArtifact {
        let size = (try? fileManager.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value
        return CapturedArtifact(
            kind: kind,
            phase: phase,
            path: path,
            stepName: stepName,
            mediaType: mediaType,
            fileSize: size,
            capturedAt: capturedAt
        )
    }
}

public struct XcodeTestPlanExecutor: EvidencePlanExecuting {
    public var runner: CommandRunning
    public var xcrunPath: String
    public var videoRecorder: any VideoRecording
    public var artifactWriter: any ArtifactWriting
    public var fileManager: FileManager
    public var clock: any EvidenceClock

    public init(
        runner: CommandRunning,
        xcrunPath: String,
        artifactWriter: any ArtifactWriting,
        videoRecorder: any VideoRecording = NoopVideoRecorder(),
        fileManager: FileManager = .default,
        clock: any EvidenceClock = SystemEvidenceClock()
    ) {
        self.runner = runner
        self.xcrunPath = xcrunPath
        self.videoRecorder = videoRecorder
        self.artifactWriter = artifactWriter
        self.fileManager = fileManager
        self.clock = clock
    }

    public func execute(_ request: EvidencePlanExecutionRequest) throws -> EvidenceRunResult {
        var result = EvidenceRunResult()

        for build in request.revisionBuilds {
            guard let worktree = request.worktrees.first(where: { PRChangeEvidencePhase($0.label) == build.phase }) else {
                throw CLIError.commandFailed("Missing prepared \(build.phase.rawValue) worktree for XCTest evidence execution.")
            }

            let phaseOutputDirectory = request.outputDirectory.appendingPathComponent(build.phase.rawValue, isDirectory: true)
            try fileManager.createDirectory(at: phaseOutputDirectory, withIntermediateDirectories: true)

            let phaseSteps = steps(in: request.plan, for: build.phase)
            let videoPlan = try videoCapturePlan(
                in: request.plan,
                steps: phaseSteps,
                phase: build.phase,
                outputDirectory: request.outputDirectory
            )
            let videoSession = try startVideoIfNeeded(videoPlan, ios: request.ios)

            let commandResult: CommandResult
            do {
                commandResult = try runner.run(
                    xcrunPath,
                    xcodebuildTestArguments(ios: request.ios, derivedDataPath: build.derivedDataPath),
                    workingDirectory: URL(fileURLWithPath: worktree.path, isDirectory: true),
                    environment: [
                        "EVIDENCE_PLAN_PATH": request.planURL.path,
                        "EVIDENCE_OUTPUT_DIR": phaseOutputDirectory.path,
                        "EVIDENCE_REVISION_ROLE": build.phase.rawValue
                    ]
                )
            } catch {
                if let videoSession {
                    try? videoRecorder.stop(videoSession)
                }
                throw error
            }

            let recordedVideoPath = try finishVideoIfNeeded(
                videoSession,
                videoPlan: videoPlan,
                phase: build.phase,
                result: &result
            )

            if commandResult.exitCode != 0 {
                let timestamp = timestamp()
                let message = "\(build.phase.rawValue) XCTest plan failed with exit code \(commandResult.exitCode). \(detail(from: commandResult))"
                result.failures.append(PRChangeEvidenceFailureSummary(stepName: "\(build.phase.rawValue) xctest", message: message))
                result.stepResults.append(CaptureStepResult(
                    phase: build.phase,
                    stepName: "\(build.phase.rawValue) xctest",
                    kind: .launch,
                    status: .failed,
                    message: message,
                    startedAt: timestamp,
                    completedAt: timestamp
                ))
                break
            }

            for step in phaseSteps {
                let timestamp = timestamp()
                let artifactURL = try artifactURL(
                    for: step,
                    phase: build.phase,
                    outputDirectory: request.outputDirectory,
                    fallbackExtension: fallbackExtension(for: step.kind)
                )
                let artifactPath = artifactPath(
                    for: step,
                    defaultPath: artifactURL?.path,
                    recordedVideoPath: recordedVideoPath
                )
                if step.kind == .screenshot, let artifactPath {
                    result.artifacts.append(artifactWriter.artifact(
                        kind: .screenshot,
                        phase: build.phase,
                        path: artifactPath,
                        stepName: step.name,
                        mediaType: "image/png",
                        capturedAt: timestamp
                    ))
                }
                result.stepResults.append(CaptureStepResult(
                    phase: build.phase,
                    stepName: step.name,
                    kind: step.kind,
                    status: .succeeded,
                    artifactPath: artifactPath,
                    startedAt: timestamp,
                    completedAt: timestamp
                ))
            }
        }

        return result
    }

    private func startVideoIfNeeded(
        _ videoPlan: VideoCapturePlan?,
        ios: PRChangeEvidenceIOSSettings
    ) throws -> VideoRecordingSession? {
        guard let videoPlan else { return nil }
        let udid = try recordingUDID(for: ios)
        return try videoRecorder.start(udid: udid, outputURL: videoPlan.outputURL)
    }

    private func finishVideoIfNeeded(
        _ session: VideoRecordingSession?,
        videoPlan: VideoCapturePlan?,
        phase: PRChangeEvidencePhase,
        result: inout EvidenceRunResult
    ) throws -> String? {
        guard let session, let videoPlan else { return nil }
        try videoRecorder.stop(session)
        let timestamp = timestamp()
        result.artifacts.append(artifactWriter.artifact(
            kind: .video,
            phase: phase,
            path: session.outputPath,
            stepName: videoPlan.artifactStepName,
            mediaType: mediaType(for: URL(fileURLWithPath: session.outputPath)),
            capturedAt: timestamp
        ))
        return session.outputPath
    }

    private func artifactPath(
        for step: PRChangeEvidenceStep,
        defaultPath: String?,
        recordedVideoPath: String?
    ) -> String? {
        switch step.kind {
        case .startVideo, .stopVideo:
            return recordedVideoPath ?? defaultPath
        default:
            return defaultPath
        }
    }

    private func xcodebuildTestArguments(
        ios: PRChangeEvidenceIOSSettings,
        derivedDataPath: String
    ) throws -> [String] {
        let scheme = try required(ios.scheme, field: "ios.scheme")
        if ios.workspace != nil, ios.project != nil {
            throw CLIError.config("Invalid PR change evidence plan: only one of ios.workspace or ios.project may be set.")
        }
        guard ios.workspace != nil || ios.project != nil else {
            throw CLIError.config("Invalid PR change evidence plan: one of ios.workspace or ios.project is required for iOS XCTest evidence execution.")
        }

        var arguments = ["xcodebuild", "test"]
        if let workspace = ios.workspace {
            arguments.append(contentsOf: ["-workspace", workspace])
        } else if let project = ios.project {
            arguments.append(contentsOf: ["-project", project])
        }
        arguments.append(contentsOf: ["-scheme", scheme])
        arguments.append(contentsOf: ["-destination", destination(for: ios)])
        arguments.append(contentsOf: ["-derivedDataPath", derivedDataPath])
        arguments.append(contentsOf: ios.extraBuildArguments)
        return arguments
    }

    private func required(_ value: String?, field: String) throws -> String {
        guard let value = value?.nonEmpty else {
            throw CLIError.config("Invalid PR change evidence plan: missing required field '\(field)'.")
        }
        return value
    }

    private func destination(for ios: PRChangeEvidenceIOSSettings) -> String {
        if let destination = ios.destination?.nonEmpty {
            return destination
        }
        if let udid = ios.simulatorUDID?.nonEmpty {
            return "platform=iOS Simulator,id=\(udid)"
        }
        if let name = ios.simulator?.nonEmpty {
            return "platform=iOS Simulator,name=\(name)"
        }
        return "platform=iOS Simulator"
    }

    private func recordingUDID(for ios: PRChangeEvidenceIOSSettings) throws -> String {
        if let udid = ios.simulatorUDID?.nonEmpty {
            return udid
        }
        if let destination = ios.destination?.nonEmpty,
           let udid = destination
            .split(separator: ",")
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { $0.hasPrefix("id=") })?
            .dropFirst(3),
           !udid.isEmpty {
            return String(udid)
        }
        throw CLIError.config("Invalid PR change evidence plan: XCTest video recording requires 'ios.simulator_udid' or an 'ios.destination' with an id=<UDID> segment.")
    }

    private func detail(from result: CommandResult) -> String {
        result.stderr.nonEmpty ?? result.stdout.nonEmpty ?? "See XCTest logs."
    }

    private func timestamp() -> String {
        ISO8601DateFormatter().string(from: clock.now())
    }
}

public protocol VideoRecording {
    func start(udid: String, outputURL: URL) throws -> VideoRecordingSession
    func stop(_ session: VideoRecordingSession) throws
}

public struct VideoRecordingSession: Equatable {
    public var udid: String
    public var outputPath: String
    fileprivate var process: Process?

    public init(udid: String, outputPath: String) {
        self.udid = udid
        self.outputPath = outputPath
        self.process = nil
    }
}

public final class SimctlVideoRecorder: VideoRecording {
    public var xcrunPath: String

    public init(xcrunPath: String) {
        self.xcrunPath = xcrunPath
    }

    public func start(udid: String, outputURL: URL) throws -> VideoRecordingSession {
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let process = Process()
        process.executableURL = URL(fileURLWithPath: xcrunPath)
        process.arguments = ["simctl", "io", udid, "recordVideo", outputURL.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        var session = VideoRecordingSession(udid: udid, outputPath: outputURL.path)
        session.process = process
        return session
    }

    public func stop(_ session: VideoRecordingSession) throws {
        guard let process = session.process else { return }
        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()
    }
}

public struct NoopVideoRecorder: VideoRecording {
    public init() {}

    public func start(udid: String, outputURL: URL) throws -> VideoRecordingSession {
        VideoRecordingSession(udid: udid, outputPath: outputURL.path)
    }

    public func stop(_ session: VideoRecordingSession) throws {}
}

public struct SimctlPlanExecutor: EvidencePlanExecuting {
    public var simulator: any SimulatorControlling
    public var videoRecorder: any VideoRecording
    public var artifactWriter: any ArtifactWriting
    public var fileManager: FileManager
    public var clock: any EvidenceClock

    public init(
        simulator: any SimulatorControlling,
        videoRecorder: any VideoRecording,
        artifactWriter: any ArtifactWriting,
        fileManager: FileManager = .default,
        clock: any EvidenceClock = SystemEvidenceClock()
    ) {
        self.simulator = simulator
        self.videoRecorder = videoRecorder
        self.artifactWriter = artifactWriter
        self.fileManager = fileManager
        self.clock = clock
    }

    public func execute(_ request: EvidencePlanExecutionRequest) throws -> EvidenceRunResult {
        let bundleID = try required(request.ios.bundleID, field: "ios.bundle_id")
        let selection = try simulator.resolve(request.ios)
        let context = SimulatorRunContext(
            selection: selection,
            bundleID: bundleID,
            launch: request.launch,
            preserveState: request.ios.preserveSimulatorState
        )
        var result = EvidenceRunResult(simulator: PRChangeEvidenceSimulator(name: selection.name, udid: selection.udid))

        try simulator.boot(selection)
        defer {
            try? simulator.shutdown(selection)
        }

        for build in request.revisionBuilds {
            var didLaunch = false
            var activeVideo: VideoRecordingSession?

            func launchIfNeeded() throws {
                if didLaunch { return }
                try simulator.installAndLaunch(
                    phase: build.phase,
                    appBundle: AppBundleLocation(path: build.appBundlePath),
                    context: context
                )
                didLaunch = true
            }

            func finishActiveVideo(recordingStepName: String? = nil, capturedAt: String? = nil) {
                if let session = activeVideo {
                    try? videoRecorder.stop(session)
                    activeVideo = nil
                    if let recordingStepName, let capturedAt {
                        result.artifacts.append(artifactWriter.artifact(
                            kind: .video,
                            phase: build.phase,
                            path: session.outputPath,
                            stepName: recordingStepName,
                            mediaType: mediaType(for: URL(fileURLWithPath: session.outputPath)),
                            capturedAt: capturedAt
                        ))
                    }
                }
            }

            defer {
                finishActiveVideo()
                try? simulator.terminate(bundleID: bundleID, selection: selection)
            }

            let steps = steps(in: request.plan, for: build.phase)
            let shouldRecordWholeFlow = request.plan.video.enabled
                && !steps.contains { $0.kind == .startVideo || $0.kind == .stopVideo }
            if shouldRecordWholeFlow {
                let videoURL = request.outputDirectory
                    .appendingPathComponent(build.phase.rawValue, isDirectory: true)
                    .appendingPathComponent("\(request.plan.video.name?.nonEmpty ?? "flow").mov")
                activeVideo = try videoRecorder.start(udid: selection.udid, outputURL: videoURL)
            }

            for step in steps {
                let startedAt = timestamp()
                do {
                    let artifactPath = try execute(
                        step,
                        build: build,
                        request: request,
                        selection: selection,
                        launchIfNeeded: launchIfNeeded,
                        activeVideo: &activeVideo
                    )
                    let completedAt = timestamp()
                    if shouldRecordWholeFlow, step == steps.last, let session = activeVideo {
                        try videoRecorder.stop(session)
                        activeVideo = nil
                        result.artifacts.append(artifactWriter.artifact(
                            kind: .video,
                            phase: build.phase,
                            path: session.outputPath,
                            stepName: request.plan.video.name?.nonEmpty ?? "flow",
                            mediaType: mediaType(for: URL(fileURLWithPath: session.outputPath)),
                            capturedAt: completedAt
                        ))
                    }
                    result.stepResults.append(CaptureStepResult(
                        phase: build.phase,
                        stepName: step.name,
                        kind: step.kind,
                        status: .succeeded,
                        artifactPath: artifactPath,
                        startedAt: startedAt,
                        completedAt: completedAt
                    ))
                    if step.kind == .screenshot, let artifactPath {
                        result.artifacts.append(artifactWriter.artifact(
                            kind: .screenshot,
                            phase: build.phase,
                            path: artifactPath,
                            stepName: step.name,
                            mediaType: "image/png",
                            capturedAt: completedAt
                        ))
                    } else if step.kind == .stopVideo, let artifactPath {
                        result.artifacts.append(artifactWriter.artifact(
                            kind: .video,
                            phase: build.phase,
                            path: artifactPath,
                            stepName: step.name,
                            mediaType: mediaType(for: URL(fileURLWithPath: artifactPath)),
                            capturedAt: completedAt
                        ))
                    }
                } catch let error as CLIError {
                    let completedAt = timestamp()
                    finishActiveVideo(recordingStepName: step.name, capturedAt: completedAt)
                    let message = "\(build.phase.rawValue) step '\(step.name)' failed. \(error.errorDescription ?? String(describing: error))"
                    result.failures.append(PRChangeEvidenceFailureSummary(stepName: step.name, message: message))
                    result.stepResults.append(CaptureStepResult(
                        phase: build.phase,
                        stepName: step.name,
                        kind: step.kind,
                        status: .failed,
                        message: message,
                        startedAt: startedAt,
                        completedAt: completedAt
                    ))
                    return result
                } catch {
                    let completedAt = timestamp()
                    finishActiveVideo(recordingStepName: step.name, capturedAt: completedAt)
                    let message = "\(build.phase.rawValue) step '\(step.name)' failed. \(String(describing: error))"
                    result.failures.append(PRChangeEvidenceFailureSummary(stepName: step.name, message: message))
                    result.stepResults.append(CaptureStepResult(
                        phase: build.phase,
                        stepName: step.name,
                        kind: step.kind,
                        status: .failed,
                        message: message,
                        startedAt: startedAt,
                        completedAt: completedAt
                    ))
                    return result
                }
            }
        }

        return result
    }

    private func execute(
        _ step: PRChangeEvidenceStep,
        build: RevisionBuildResult,
        request: EvidencePlanExecutionRequest,
        selection: SimulatorSelection,
        launchIfNeeded: () throws -> Void,
        activeVideo: inout VideoRecordingSession?
    ) throws -> String? {
        switch step.kind {
        case .launch:
            try launchIfNeeded()
            return nil
        case .wait:
            try launchIfNeeded()
            if let seconds = step.seconds, seconds > 0 {
                Thread.sleep(forTimeInterval: seconds)
            }
            return nil
        case .screenshot:
            try launchIfNeeded()
            let outputURL = try requiredArtifactURL(
                for: step,
                phase: build.phase,
                outputDirectory: request.outputDirectory,
                fallbackExtension: "png"
            )
            try fileManager.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try simulator.screenshot(selection, outputURL: outputURL)
            return outputURL.path
        case .startVideo:
            try launchIfNeeded()
            let outputURL = try requiredArtifactURL(
                for: step,
                phase: build.phase,
                outputDirectory: request.outputDirectory,
                fallbackExtension: "mov"
            )
            activeVideo = try videoRecorder.start(udid: selection.udid, outputURL: outputURL)
            return outputURL.path
        case .stopVideo:
            if let session = activeVideo {
                try videoRecorder.stop(session)
                activeVideo = nil
                return session.outputPath
            }
            let outputURL = try requiredArtifactURL(
                for: step,
                phase: build.phase,
                outputDirectory: request.outputDirectory,
                fallbackExtension: "mov"
            )
            return outputURL.path
        case .openURL:
            try launchIfNeeded()
            guard let url = step.url?.nonEmpty else {
                throw CLIError.config("Invalid PR change evidence plan: openURL step '\(step.name)' requires a url.")
            }
            try simulator.openURL(url, selection: selection)
            return nil
        case .tap, .typeText, .swipe:
            throw CLIError.config("Invalid PR change evidence plan: simctl runner cannot execute '\(step.kind.rawValue)' step '\(step.name)'.")
        }
    }

    private func required(_ value: String?, field: String) throws -> String {
        guard let value = value?.nonEmpty else {
            throw CLIError.config("Invalid PR change evidence plan: missing required field '\(field)'.")
        }
        return value
    }

    private func requiredArtifactURL(
        for step: PRChangeEvidenceStep,
        phase: PRChangeEvidencePhase,
        outputDirectory: URL,
        fallbackExtension: String
    ) throws -> URL {
        guard let url = try artifactURL(
            for: step,
            phase: phase,
            outputDirectory: outputDirectory,
            fallbackExtension: fallbackExtension
        ) else {
            throw CLIError.config("Invalid PR change evidence plan: step '\(step.name)' requires an artifact path.")
        }
        return url
    }

    private func timestamp() -> String {
        ISO8601DateFormatter().string(from: clock.now())
    }
}

public struct DispatchingPlanExecutor: EvidencePlanExecuting {
    public var xctest: XcodeTestPlanExecutor
    public var simctl: SimctlPlanExecutor

    public init(xctest: XcodeTestPlanExecutor, simctl: SimctlPlanExecutor) {
        self.xctest = xctest
        self.simctl = simctl
    }

    public func execute(_ request: EvidencePlanExecutionRequest) throws -> EvidenceRunResult {
        switch request.plan.runner {
        case .xctest:
            return try xctest.execute(request)
        case .simctl:
            return try simctl.execute(request)
        }
    }
}

private func steps(
    in plan: PRChangeEvidencePlan,
    for phase: PRChangeEvidencePhase
) -> [PRChangeEvidenceStep] {
    plan.steps.filter { step in
        step.phase == nil || step.phase == phase
    }
}

private struct VideoCapturePlan {
    var outputURL: URL
    var artifactStepName: String
}

private func videoCapturePlan(
    in plan: PRChangeEvidencePlan,
    steps: [PRChangeEvidenceStep],
    phase: PRChangeEvidencePhase,
    outputDirectory: URL
) throws -> VideoCapturePlan? {
    if let explicitStep = steps.first(where: { $0.kind == .startVideo })
        ?? steps.first(where: { $0.kind == .stopVideo }) {
        guard let outputURL = try artifactURL(
            for: explicitStep,
            phase: phase,
            outputDirectory: outputDirectory,
            fallbackExtension: "mov"
        ) else {
            return nil
        }
        let artifactStepName = steps.last(where: { $0.kind == .stopVideo })?.name ?? explicitStep.name
        return VideoCapturePlan(outputURL: outputURL, artifactStepName: artifactStepName)
    }

    guard plan.video.enabled else {
        return nil
    }

    let name = plan.video.name?.nonEmpty ?? "flow"
    let outputURL = outputDirectory
        .appendingPathComponent(phase.rawValue, isDirectory: true)
        .appendingPathComponent("\(name).mov")
    return VideoCapturePlan(outputURL: outputURL, artifactStepName: name)
}

private func artifactURL(
    for step: PRChangeEvidenceStep,
    phase: PRChangeEvidencePhase,
    outputDirectory: URL,
    fallbackExtension: String?
) throws -> URL? {
    let rawPath = step.path?.trimmingCharacters(in: .whitespacesAndNewlines)
    let fallback = fallbackExtension.map { "\(fileSafeName(for: step.name)).\($0)" }
    guard let relativePath = rawPath?.isEmpty == false ? rawPath : fallback else {
        return nil
    }
    guard !relativePath.hasPrefix("/") else {
        throw CLIError.config("Invalid PR change evidence plan: artifact path '\(relativePath)' must be relative.")
    }
    var components = relativePath.split(separator: "/").map(String.init)
    guard !components.isEmpty, !components.contains("..") else {
        throw CLIError.config("Invalid PR change evidence plan: artifact path '\(relativePath)' must stay inside the output directory.")
    }
    if components.first != PRChangeEvidencePhase.before.rawValue,
       components.first != PRChangeEvidencePhase.after.rawValue {
        components.insert(phase.rawValue, at: 0)
    }
    return components.reduce(outputDirectory) { url, component in
        url.appendingPathComponent(component)
    }
}

private func fallbackExtension(for kind: PRChangeEvidenceStep.Kind) -> String? {
    switch kind {
    case .screenshot:
        return "png"
    case .startVideo, .stopVideo:
        return "mov"
    default:
        return nil
    }
}

private func mediaType(for url: URL) -> String {
    switch url.pathExtension.lowercased() {
    case "png":
        return "image/png"
    case "mp4":
        return "video/mp4"
    case "mov":
        return "video/quicktime"
    default:
        return "application/octet-stream"
    }
}

private func fileSafeName(for name: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    let scalars = name.unicodeScalars.map { scalar in
        allowed.contains(scalar) ? Character(scalar) : "-"
    }
    let collapsed = String(scalars)
        .split(separator: "-", omittingEmptySubsequences: true)
        .joined(separator: "-")
        .lowercased()
    return collapsed.isEmpty ? "step" : collapsed
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

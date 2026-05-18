import Foundation

public struct AppBundleLocation: Codable, Equatable {
    public var path: String

    public init(path: String) {
        self.path = path
    }
}

public struct RevisionBuildRequest: Equatable {
    public var phase: PRChangeEvidencePhase
    public var worktree: ComparisonWorktree
    public var ios: PRChangeEvidenceIOSSettings
    public var outputDirectory: URL

    public init(
        phase: PRChangeEvidencePhase,
        worktree: ComparisonWorktree,
        ios: PRChangeEvidenceIOSSettings,
        outputDirectory: URL
    ) {
        self.phase = phase
        self.worktree = worktree
        self.ios = ios
        self.outputDirectory = outputDirectory
    }
}

public protocol XcodeBuilding {
    func build(_ request: RevisionBuildRequest) throws -> RevisionBuildResult
}

public protocol FilesystemWorkspace {
    func derivedDataDirectory(
        outputDirectory: URL,
        phase: PRChangeEvidencePhase,
        configuredBasePath: String?
    ) throws -> URL

    func buildLogURL(outputDirectory: URL, phase: PRChangeEvidencePhase) throws -> URL
}

public struct FileManagerWorkspace: FilesystemWorkspace {
    public var fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func derivedDataDirectory(
        outputDirectory: URL,
        phase: PRChangeEvidencePhase,
        configuredBasePath: String?
    ) throws -> URL {
        let base: URL
        if let configuredBasePath, !configuredBasePath.isEmpty {
            base = Self.url(forPath: configuredBasePath, relativeTo: outputDirectory)
        } else {
            base = outputDirectory.appendingPathComponent("derived-data", isDirectory: true)
        }
        let url = base.appendingPathComponent(phase.rawValue, isDirectory: true)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public func buildLogURL(outputDirectory: URL, phase: PRChangeEvidencePhase) throws -> URL {
        let logs = outputDirectory.appendingPathComponent("logs", isDirectory: true)
        try fileManager.createDirectory(at: logs, withIntermediateDirectories: true)
        return logs.appendingPathComponent("build-\(phase.rawValue).log")
    }

    private static func url(forPath path: String, relativeTo base: URL) -> URL {
        path.hasPrefix("/") ? URL(fileURLWithPath: path) : base.appendingPathComponent(path, isDirectory: true)
    }
}

public struct XcodebuildAdapter: XcodeBuilding {
    public var runner: CommandRunning
    public var xcrunPath: String
    public var workspace: any FilesystemWorkspace
    public var fileManager: FileManager
    public var clock: any EvidenceClock

    public init(
        runner: CommandRunning,
        xcrunPath: String,
        workspace: any FilesystemWorkspace,
        fileManager: FileManager = .default,
        clock: any EvidenceClock = SystemEvidenceClock()
    ) {
        self.runner = runner
        self.xcrunPath = xcrunPath
        self.workspace = workspace
        self.fileManager = fileManager
        self.clock = clock
    }

    public func build(_ request: RevisionBuildRequest) throws -> RevisionBuildResult {
        let scheme = try required(request.ios.scheme, field: "ios.scheme")
        if request.ios.workspace != nil, request.ios.project != nil {
            throw CLIError.config("Invalid PR change evidence plan: only one of ios.workspace or ios.project may be set.")
        }
        guard request.ios.workspace != nil || request.ios.project != nil else {
            throw CLIError.config("Invalid PR change evidence plan: one of ios.workspace or ios.project is required for iOS builds.")
        }

        let derivedData = try workspace.derivedDataDirectory(
            outputDirectory: request.outputDirectory,
            phase: request.phase,
            configuredBasePath: request.ios.derivedDataPath
        )
        let logURL = try workspace.buildLogURL(outputDirectory: request.outputDirectory, phase: request.phase)

        var arguments = ["xcodebuild", "build"]
        if let xcodeWorkspace = request.ios.workspace {
            arguments.append(contentsOf: ["-workspace", xcodeWorkspace])
        } else if let xcodeProject = request.ios.project {
            arguments.append(contentsOf: ["-project", xcodeProject])
        }
        arguments.append(contentsOf: ["-scheme", scheme])
        let configuration = request.ios.configuration?.nonEmpty ?? "Debug"
        if let configured = request.ios.configuration?.nonEmpty {
            arguments.append(contentsOf: ["-configuration", configured])
        }
        arguments.append(contentsOf: ["-destination", destination(for: request.ios)])
        arguments.append(contentsOf: ["-derivedDataPath", derivedData.path])
        arguments.append(contentsOf: request.ios.extraBuildArguments)

        let start = clock.now()
        let result = try runner.run(
            xcrunPath,
            arguments,
            workingDirectory: URL(fileURLWithPath: request.worktree.path, isDirectory: true),
            environment: [:]
        )
        let duration = max(0, clock.now().timeIntervalSince(start))
        let appBundlePath = locateAppBundle(
            under: derivedData,
            fallbackScheme: scheme,
            configuration: configuration
        ).path

        try writeBuildLog(
            to: logURL,
            executable: xcrunPath,
            arguments: arguments,
            workingDirectory: request.worktree.path,
            result: result
        )

        return RevisionBuildResult(
            phase: request.phase,
            command: [xcrunPath] + arguments,
            exitCode: result.exitCode,
            durationSeconds: duration,
            stdoutExcerpt: Self.excerpt(result.stdout),
            stderrExcerpt: Self.excerpt(result.stderr),
            appBundlePath: appBundlePath,
            derivedDataPath: derivedData.path,
            logPath: logURL.path
        )
    }

    public static func excerpt(_ text: String, limit: Int = 2_000) -> String {
        text.count <= limit ? text : String(text.prefix(limit))
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

    private func locateAppBundle(under derivedData: URL, fallbackScheme: String, configuration: String) -> URL {
        let products = derivedData.appendingPathComponent("Build/Products", isDirectory: true)
        let fallback = products
            .appendingPathComponent("\(configuration)-iphonesimulator", isDirectory: true)
            .appendingPathComponent("\(fallbackScheme).app", isDirectory: true)
        if fileManager.fileExists(atPath: fallback.path) {
            return fallback
        }

        if let enumerator = fileManager.enumerator(
            at: products,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            let matches = enumerator.compactMap { entry -> URL? in
                guard let url = entry as? URL, url.pathExtension == "app" else { return nil }
                return url
            }.sorted { $0.path < $1.path }
            if let first = matches.first {
                return first
            }
        }
        return fallback
    }

    private func writeBuildLog(
        to url: URL,
        executable: String,
        arguments: [String],
        workingDirectory: String,
        result: CommandResult
    ) throws {
        let log = """
        command: \(([executable] + arguments).joined(separator: " "))
        working_directory: \(workingDirectory)
        exit_code: \(result.exitCode)

        [stdout]
        \(result.stdout)

        [stderr]
        \(result.stderr)
        """
        try log.write(to: url, atomically: true, encoding: .utf8)
    }
}

public struct BuildRevisionForEvidence {
    public var builder: any XcodeBuilding

    public init(builder: any XcodeBuilding) {
        self.builder = builder
    }

    public func execute(_ request: RevisionBuildRequest) throws -> RevisionBuildResult {
        try builder.build(request)
    }
}

public enum CapturePREvidenceRuntime {
    public static func make(
        fileManager: FileManager,
        runner: CommandRunning,
        currentDirectory: URL,
        toolPaths: ToolPaths,
        clock: any EvidenceClock
    ) -> CapturePullRequestEvidence {
        let filesystemWorkspace = FileManagerWorkspace(fileManager: fileManager)
        let revisionBuilder = BuildRevisionForEvidence(
            builder: XcodebuildAdapter(
                runner: runner,
                xcrunPath: toolPaths.xcrun,
                workspace: filesystemWorkspace,
                fileManager: fileManager,
                clock: clock
            )
        )
        let simulatorController = SimctlSimulatorController(
            runner: runner,
            xcrunPath: toolPaths.xcrun
        )
        let artifactWriter = FileArtifactWriter(fileManager: fileManager)
        let planExecutor = DispatchingPlanExecutor(
            xctest: XcodeTestPlanExecutor(
                runner: runner,
                xcrunPath: toolPaths.xcrun,
                artifactWriter: artifactWriter,
                videoRecorder: SimctlVideoRecorder(xcrunPath: toolPaths.xcrun),
                fileManager: fileManager,
                clock: clock
            ),
            simctl: SimctlPlanExecutor(
                simulator: simulatorController,
                videoRecorder: SimctlVideoRecorder(xcrunPath: toolPaths.xcrun),
                artifactWriter: artifactWriter,
                fileManager: fileManager,
                clock: clock
            )
        )
        let git = GitCLIRepositoryPreparer(
            fileManager: fileManager,
            runner: runner,
            gitPath: toolPaths.git,
            repositoryRoot: currentDirectory
        )
        let metadataProvider = GitHubCLIPullRequestMetadataProvider(
            runner: runner,
            ghPath: toolPaths.gh
        )

        return CapturePullRequestEvidence(
            resolver: ResolvePullRequestComparison(metadataProvider: metadataProvider, git: git),
            worktreePreparer: PrepareComparisonWorktrees(git: git),
            revisionBuilder: revisionBuilder,
            planExecutor: planExecutor,
            reporter: RenderPullRequestEvidenceReport(
                comparisonRenderer: ImageMagickComparisonRenderer(
                    fileManager: fileManager,
                    runner: runner,
                    toolPaths: toolPaths
                ),
                fileManager: fileManager
            ),
            fileManager: fileManager,
            clock: clock
        )
    }
}

public struct SimulatorSelection: Equatable {
    public var name: String?
    public var udid: String

    public init(name: String? = nil, udid: String) {
        self.name = name
        self.udid = udid
    }
}

public struct SimulatorRunContext: Equatable {
    public var selection: SimulatorSelection
    public var bundleID: String
    public var launch: PRChangeEvidenceLaunch
    public var preserveState: Bool

    public init(
        selection: SimulatorSelection,
        bundleID: String,
        launch: PRChangeEvidenceLaunch,
        preserveState: Bool
    ) {
        self.selection = selection
        self.bundleID = bundleID
        self.launch = launch
        self.preserveState = preserveState
    }
}

public protocol SimulatorControlling {
    func resolve(_ ios: PRChangeEvidenceIOSSettings) throws -> SimulatorSelection
    func boot(_ selection: SimulatorSelection) throws
    func installAndLaunch(
        phase: PRChangeEvidencePhase,
        appBundle: AppBundleLocation,
        context: SimulatorRunContext
    ) throws
    func screenshot(_ selection: SimulatorSelection, outputURL: URL) throws
    func openURL(_ url: String, selection: SimulatorSelection) throws
    func terminate(bundleID: String, selection: SimulatorSelection) throws
    func shutdown(_ selection: SimulatorSelection) throws
}

public struct SimctlSimulatorController: SimulatorControlling {
    public var runner: CommandRunning
    public var xcrunPath: String

    public init(runner: CommandRunning, xcrunPath: String) {
        self.runner = runner
        self.xcrunPath = xcrunPath
    }

    public func resolve(_ ios: PRChangeEvidenceIOSSettings) throws -> SimulatorSelection {
        if let udid = ios.simulatorUDID?.nonEmpty ?? destinationValue("id", in: ios.destination) {
            return SimulatorSelection(name: ios.simulator?.nonEmpty, udid: udid)
        }

        guard let name = ios.simulator?.nonEmpty ?? destinationValue("name", in: ios.destination) else {
            throw CLIError.config("Invalid PR change evidence plan: missing simulator_udid, simulator, or destination id/name for iOS simulator preparation.")
        }

        let result = try runner.run(xcrunPath, ["simctl", "list", "devices", "--json"])
        guard result.exitCode == 0 else {
            throw CLIError.commandFailed("simulator resolution failed for '\(name)': \(detail(from: result))")
        }
        let devices = try JSONDecoder().decode(SimctlDeviceList.self, from: Data(result.stdout.utf8))
        guard let match = devices.devices.values.flatMap({ $0 }).first(where: { device in
            device.name == name && (device.isAvailable ?? true)
        }) else {
            throw CLIError.commandFailed("simulator resolution failed for '\(name)': no available simulator with that name was found.")
        }
        return SimulatorSelection(name: match.name, udid: match.udid)
    }

    public func boot(_ selection: SimulatorSelection) throws {
        let boot = try runner.run(xcrunPath, ["simctl", "boot", selection.udid])
        if boot.exitCode != 0 {
            let text = detail(from: boot)
            guard text.localizedCaseInsensitiveContains("booted")
                    || text.localizedCaseInsensitiveContains("already") else {
                throw CLIError.commandFailed("simulator boot failed for \(selection.udid): \(text)")
            }
        }

        let bootstatus = try runner.run(xcrunPath, ["simctl", "bootstatus", selection.udid, "-b"])
        guard bootstatus.exitCode == 0 else {
            throw CLIError.commandFailed("simulator boot failed while waiting for \(selection.udid): \(detail(from: bootstatus))")
        }

        _ = try? runner.run(xcrunPath, ["simctl", "ui", selection.udid, "appearance", "light"])
        _ = try? runner.run(
            xcrunPath,
            [
                "simctl", "status_bar", selection.udid, "override",
                "--time", "9:41",
                "--dataNetwork", "wifi",
                "--wifiBars", "3",
                "--cellularBars", "4",
                "--batteryState", "charged",
                "--batteryLevel", "100"
            ]
        )
    }

    public func installAndLaunch(
        phase: PRChangeEvidencePhase,
        appBundle: AppBundleLocation,
        context: SimulatorRunContext
    ) throws {
        if !context.preserveState {
            let uninstall = try runner.run(xcrunPath, ["simctl", "uninstall", context.selection.udid, context.bundleID])
            if uninstall.exitCode != 0 {
                let text = detail(from: uninstall)
                guard text.localizedCaseInsensitiveContains("not installed")
                        || text.localizedCaseInsensitiveContains("no such app")
                        || text.localizedCaseInsensitiveContains("not found") else {
                    throw CLIError.commandFailed("\(phase.rawValue) uninstall failed for \(context.bundleID): \(text)")
                }
            }
        }

        let install = try runner.run(xcrunPath, ["simctl", "install", context.selection.udid, appBundle.path])
        guard install.exitCode == 0 else {
            throw CLIError.commandFailed("\(phase.rawValue) install failed for \(context.bundleID): \(detail(from: install))")
        }

        let launch = try runner.run(
            xcrunPath,
            ["simctl", "launch", context.selection.udid, context.bundleID] + context.launch.arguments,
            workingDirectory: nil,
            environment: simctlChildEnvironment(context.launch.environment)
        )
        guard launch.exitCode == 0 else {
            throw CLIError.commandFailed("\(phase.rawValue) launch failed for \(context.bundleID): \(detail(from: launch))")
        }
    }

    public func screenshot(_ selection: SimulatorSelection, outputURL: URL) throws {
        let result = try runner.run(
            xcrunPath,
            ["simctl", "io", selection.udid, "screenshot", outputURL.path]
        )
        guard result.exitCode == 0 else {
            throw CLIError.commandFailed("simulator screenshot failed for \(selection.udid): \(detail(from: result))")
        }
    }

    public func openURL(_ url: String, selection: SimulatorSelection) throws {
        let result = try runner.run(
            xcrunPath,
            ["simctl", "openurl", selection.udid, url]
        )
        guard result.exitCode == 0 else {
            throw CLIError.commandFailed("simulator openurl failed for \(selection.udid): \(detail(from: result))")
        }
    }

    public func terminate(bundleID: String, selection: SimulatorSelection) throws {
        _ = try runner.run(xcrunPath, ["simctl", "terminate", selection.udid, bundleID])
    }

    public func shutdown(_ selection: SimulatorSelection) throws {
        let result = try runner.run(xcrunPath, ["simctl", "shutdown", selection.udid])
        guard result.exitCode == 0 else {
            throw CLIError.commandFailed("simulator shutdown failed for \(selection.udid): \(detail(from: result))")
        }
    }

    private func simctlChildEnvironment(_ environment: [String: String]) -> [String: String] {
        environment.reduce(into: [:]) { result, entry in
            result["SIMCTL_CHILD_\(entry.key)"] = entry.value
        }
    }

    private func destinationValue(_ key: String, in destination: String?) -> String? {
        guard let destination else { return nil }
        return destination
            .split(separator: ",")
            .compactMap { component -> String? in
                let pair = component.split(separator: "=", maxSplits: 1).map(String.init)
                guard pair.count == 2, pair[0] == key else { return nil }
                return pair[1].isEmpty ? nil : pair[1]
            }
            .first
    }

    private func detail(from result: CommandResult) -> String {
        result.stderr.nonEmpty ?? result.stdout.nonEmpty ?? "exit code \(result.exitCode)"
    }
}

public struct PrepareSimulatorForEvidenceRun {
    public var simulator: any SimulatorControlling

    public init(simulator: any SimulatorControlling) {
        self.simulator = simulator
    }

    @discardableResult
    public func execute(
        ios: PRChangeEvidenceIOSSettings,
        launch: PRChangeEvidenceLaunch,
        builds: [RevisionBuildResult]
    ) throws -> PRChangeEvidenceSimulator {
        let bundleID = try required(ios.bundleID, field: "ios.bundle_id")
        let selection = try simulator.resolve(ios)
        let context = SimulatorRunContext(
            selection: selection,
            bundleID: bundleID,
            launch: launch,
            preserveState: ios.preserveSimulatorState
        )
        try simulator.boot(selection)
        defer {
            try? simulator.terminate(bundleID: bundleID, selection: selection)
            try? simulator.shutdown(selection)
        }

        for build in builds {
            try simulator.installAndLaunch(
                phase: build.phase,
                appBundle: AppBundleLocation(path: build.appBundlePath),
                context: context
            )
            try? simulator.terminate(bundleID: bundleID, selection: selection)
        }

        return PRChangeEvidenceSimulator(name: selection.name, udid: selection.udid)
    }

    private func required(_ value: String?, field: String) throws -> String {
        guard let value = value?.nonEmpty else {
            throw CLIError.config("Invalid PR change evidence plan: missing required field '\(field)'.")
        }
        return value
    }
}

private struct SimctlDeviceList: Decodable {
    var devices: [String: [SimctlDevice]]
}

private struct SimctlDevice: Decodable {
    var name: String
    var udid: String
    var isAvailable: Bool?
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

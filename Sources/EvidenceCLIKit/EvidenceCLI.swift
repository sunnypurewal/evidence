import Foundation

public struct EvidenceCLI {
    public var fileManager: FileManager
    public var runner: CommandRunning
    public var stdout: (String) -> Void
    public var stderr: (String) -> Void
    public var currentDirectory: URL
    public var toolPaths: ToolPaths
    public var httpClient: HTTPClient
    /// Directory used for the xcresult cache when
    /// `xcresult_keep_full_bundle = false`. Defaults to `~/.evidence/cache`.
    public var cacheDirectory: URL

    public init(
        fileManager: FileManager = .default,
        runner: CommandRunning = ProcessCommandRunner(),
        stdout: @escaping (String) -> Void = { print($0) },
        stderr: @escaping (String) -> Void = { FileHandle.standardError.write(Data(($0 + "\n").utf8)) },
        currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true),
        toolPaths: ToolPaths = ToolPaths(),
        httpClient: HTTPClient = URLSessionHTTPClient(),
        cacheDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".evidence", isDirectory: true)
            .appendingPathComponent("cache", isDirectory: true)
    ) {
        self.fileManager = fileManager
        self.runner = runner
        self.stdout = stdout
        self.stderr = stderr
        self.currentDirectory = currentDirectory
        self.toolPaths = toolPaths
        self.httpClient = httpClient
        self.cacheDirectory = cacheDirectory
    }

    public static func main() {
        let exitCode = EvidenceCLI().run(Array(CommandLine.arguments.dropFirst()))
        Foundation.exit(exitCode)
    }

    @discardableResult
    public func run(_ arguments: [String]) -> Int32 {
        do {
            try execute(arguments)
            return 0
        } catch {
            stderr((error as? LocalizedError)?.errorDescription ?? String(describing: error))
            // Honor `CLIError.exit(code, ...)` so subcommands like
            // `evidence diff` can return CI-stable exit codes (1 = regression,
            // 2 = baseline missing). All other errors fall back to 1.
            if let cliError = error as? CLIError {
                return cliError.exitCode
            }
            return 1
        }
    }

    public func execute(_ arguments: [String]) throws {
        let arguments = arguments.first == "--" ? Array(arguments.dropFirst()) : arguments
        guard let first = arguments.first else {
            stdout(Help.root)
            return
        }

        if first == "--help" || first == "-h" || first == "help" {
            stdout(Help.root)
            return
        }

        let commandArguments = Array(arguments.dropFirst())
        if commandArguments.contains("--help") || commandArguments.contains("-h") {
            stdout(try Help.text(for: first))
            return
        }

        let config = try loadConfig()

        switch first {
        case "capture-screenshots":
            try captureScreenshots(config: config)
        case "resize":
            try resize(commandArguments, config: config)
        case "render-marketing":
            try renderMarketing(commandArguments, config: config)
        case "record-preview":
            try recordPreview(commandArguments, config: config)
        case "capture-evidence":
            try captureEvidence(commandArguments, config: config)
        case "diff":
            try diff(commandArguments, config: config)
        case "accept-baseline":
            try acceptBaseline(commandArguments, config: config)
        case "upload-screenshots":
            try uploadScreenshots(commandArguments, config: config)
        default:
            throw CLIError.usage("Unknown command '\(first)'. Run `evidence --help`.")
        }
    }

    public func loadConfig() throws -> EvidenceConfig {
        try EvidenceConfig.load(from: currentDirectory.appendingPathComponent(".evidence.toml"))
    }

    private func captureScreenshots(config: EvidenceConfig) throws {
        try requireTool(toolPaths.xcrun, versionArguments: ["simctl", "help"], installHint: "Install Xcode and command line tools.")

        let arguments = xcodebuildTestArguments(config: config)
        let result = try runner.run(toolPaths.xcrun, ["xcodebuild"] + arguments)
        guard result.exitCode == 0 else {
            throw CLIError.commandFailed("xcodebuild screenshot capture failed. \(result.stderr)")
        }
    }

    /// Build the `xcodebuild test` argument list shared by `capture-screenshots`
    /// and the xcresult bundle capture path of `capture-evidence`. Caller is
    /// responsible for prepending the `xcodebuild` token (xcrun forwards it).
    private func xcodebuildTestArguments(config: EvidenceConfig, resultBundlePath: String? = nil) -> [String] {
        var arguments: [String] = ["test"]
        if let workspace = config.xcodeWorkspace {
            arguments.append(contentsOf: ["-workspace", workspace])
        } else if let project = config.xcodeProject {
            arguments.append(contentsOf: ["-project", project])
        }
        arguments.append(contentsOf: [
            "-scheme", config.scheme,
            "-destination", "platform=iOS Simulator,id=\(config.simulatorUDID)"
        ])
        if !config.deviceMatrix.isEmpty {
            arguments.append(contentsOf: ["-only-testing", config.deviceMatrix.joined(separator: ",")])
        }
        if let resultBundlePath {
            arguments.append(contentsOf: ["-resultBundlePath", resultBundlePath])
        }
        return arguments
    }

    private func resize(_ arguments: [String], config: EvidenceConfig) throws {
        let input = try option("input", in: arguments)
        let output = try option("output", in: arguments)
        let targetName = optionValue("target", in: arguments) ?? "6.9"
        guard let target = ScreenshotTarget(named: targetName) else {
            throw CLIError.usage("Unknown resize target '\(targetName)'. Run `evidence resize --help`.")
        }

        try requireTool(toolPaths.magick, versionArguments: ["--version"], installHint: "Install ImageMagick, for example with `brew install imagemagick`.")
        let result = try runner.run(
            toolPaths.magick,
            [input, "-resize", "\(target.width)x\(target.height)^", "-gravity", "center", "-extent", "\(target.width)x\(target.height)", output]
        )
        guard result.exitCode == 0 else {
            throw CLIError.commandFailed("Image resize failed. \(result.stderr)")
        }
    }

    private func renderMarketing(_ arguments: [String], config: EvidenceConfig) throws {
        let scenePath = try option("scene", in: arguments)
        let outputPath = try option("output", in: arguments)
        let targetName = optionValue("target", in: arguments) ?? config.screenshotTargets.first?.name ?? "6.9"
        guard let target = ScreenshotTarget(named: targetName) else {
            throw CLIError.usage("Unknown marketing target '\(targetName)'. Run `evidence render-marketing --help`.")
        }

        let sceneURL = url(forPath: scenePath)
        let outputURL = url(forPath: outputPath)
        let defaultSVGPath = outputURL.deletingPathExtension().appendingPathExtension("svg").path
        let svgURL = url(forPath: optionValue("svg", in: arguments) ?? defaultSVGPath)

        try requireTool(toolPaths.magick, versionArguments: ["--version"], installHint: "Install ImageMagick, for example with `brew install imagemagick`.")
        let renderer = MarketingRenderer(fileManager: fileManager, runner: runner, toolPaths: toolPaths)
        let scene = try renderer.loadScene(from: sceneURL, target: target)
        try renderer.render(scene: scene, svgURL: svgURL, pngURL: outputURL)
        stdout("Rendered marketing screenshot at \(outputURL.path)")
    }

    private func recordPreview(_ arguments: [String], config: EvidenceConfig) throws {
        let input = try option("input", in: arguments)
        let output = try option("output", in: arguments)
        let defaults = config.previewDefaults
        let duration = optionValue("duration", in: arguments).flatMap(Double.init) ?? defaults.maxDuration
        let fps = optionValue("fps", in: arguments).flatMap(Int.init) ?? defaults.fps
        let width = optionValue("width", in: arguments).flatMap(Int.init) ?? defaults.width
        let height = optionValue("height", in: arguments).flatMap(Int.init) ?? defaults.height
        let trimStart = optionValue("trim-start", in: arguments).flatMap(Double.init) ?? defaults.trimStart
        let trimEnd = optionValue("trim-end", in: arguments).flatMap(Double.init) ?? defaults.trimEnd

        try requireTool(toolPaths.ffmpeg, versionArguments: ["-version"], installHint: "Install ffmpeg, for example with `brew install ffmpeg`.")
        var ffmpegArguments = ["-y"]
        if trimStart > 0 {
            ffmpegArguments.append(contentsOf: ["-ss", "\(trimStart)"])
        }
        ffmpegArguments.append(contentsOf: ["-i", input, "-an", "-t", "\(duration)"])
        if let trimEnd {
            ffmpegArguments.append(contentsOf: ["-to", "\(trimEnd)"])
        }
        ffmpegArguments.append(contentsOf: [
            "-vf", "scale=\(width):\(height),fps=\(fps)",
            "-c:v", "libx264",
            "-pix_fmt", "yuv420p",
            output
        ])

        let result = try runner.run(
            toolPaths.ffmpeg,
            ffmpegArguments
        )
        guard result.exitCode == 0 else {
            throw CLIError.commandFailed("Preview recording encode failed. \(result.stderr)")
        }
    }

    private func captureEvidence(_ arguments: [String], config: EvidenceConfig) throws {
        let ticket = try option("ticket", in: arguments)
        let outputDirectory = currentDirectory.appendingPathComponent(config.evidenceDirectory, isDirectory: true)
        let output = outputDirectory.appendingPathComponent("\(ticket)-running.png")

        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try requireTool(toolPaths.xcrun, versionArguments: ["simctl", "help"], installHint: "Install Xcode and command line tools.")

        let result = try runner.run(toolPaths.xcrun, ["simctl", "io", config.simulatorUDID, "screenshot", output.path])
        guard result.exitCode == 0 else {
            throw CLIError.commandFailed("Build evidence capture failed. \(result.stderr)")
        }

        if let url = markdownURL(for: output, config: config) {
            stdout("![Build evidence](\(url))")
        } else {
            stdout("Captured build evidence at \(output.path)")
        }

        if config.xcresult.enabled {
            // CLI flag `--xcresult-summary-only` mirrors the toggle: when set,
            // the full bundle is dropped to the cache directory and only the
            // summary markdown is committed under `evidence_dir`.
            let summaryOnly = arguments.contains("--xcresult-summary-only") || !config.xcresult.keepFullBundle
            try captureXcresult(
                ticket: ticket,
                config: config,
                evidenceDirectory: outputDirectory,
                summaryOnly: summaryOnly
            )
        }
    }

    private func captureXcresult(
        ticket: String,
        config: EvidenceConfig,
        evidenceDirectory: URL,
        summaryOnly: Bool
    ) throws {
        let bundleName = "\(ticket).xcresult"
        let summaryName = "\(ticket)-tests.md"
        let summaryURL = evidenceDirectory.appendingPathComponent(summaryName)

        // Always run xcodebuild against a deterministic working bundle path
        // inside `evidence_dir`. When `summaryOnly` is true we move it to the
        // cache directory after the summary is written.
        let workingBundleURL = evidenceDirectory.appendingPathComponent(bundleName)
        // xcodebuild refuses to overwrite an existing -resultBundlePath, so a
        // re-run on the same ticket would otherwise fail. Wipe any previous
        // bundle (and any orphan from an earlier summary-only run in the
        // cache) before kicking off the test.
        if fileManager.fileExists(atPath: workingBundleURL.path) {
            try fileManager.removeItem(at: workingBundleURL)
        }

        let xcodebuildArguments = xcodebuildTestArguments(
            config: config,
            resultBundlePath: workingBundleURL.path
        )
        let testResult = try runner.run(toolPaths.xcrun, ["xcodebuild"] + xcodebuildArguments)

        // `xcodebuild test` exits non-zero on either a build error (bundle is
        // not produced) or a test failure (bundle IS produced). Distinguish
        // by looking for the bundle on disk.
        let bundleExists = fileManager.fileExists(atPath: workingBundleURL.path)
        if !bundleExists {
            // Build error fast-fail: still write a markdown summary so the PR
            // / PR comment surfaces what went wrong, then propagate the
            // failure as a non-zero exit.
            let markdown = XcresultMarkdown.renderBuildError(ticket: ticket, stderr: testResult.stderr)
            try markdown.write(to: summaryURL, atomically: true, encoding: .utf8)
            stdout("Wrote build-error summary to \(summaryURL.path)")
            throw CLIError.commandFailed("xcodebuild test failed before producing a result bundle. \(testResult.stderr)")
        }

        // Bundle exists — parse summary even if `xcodebuild` returned non-zero
        // (test failures are expected to surface in the markdown rather than
        // crash the CLI).
        let summaryArguments = [
            "xcresulttool", "get", "test-results", "summary",
            "--path", workingBundleURL.path
        ]
        let summaryResult = try runner.run(toolPaths.xcrun, summaryArguments)
        guard summaryResult.exitCode == 0 else {
            throw CLIError.commandFailed("xcresulttool failed to summarize \(workingBundleURL.path). \(summaryResult.stderr)")
        }

        let parsed = try XcresultSummary.parse(summaryResult.stdout)
        let markdown = XcresultMarkdown.render(parsed, ticket: ticket)
        try markdown.write(to: summaryURL, atomically: true, encoding: .utf8)
        stdout("Wrote test summary to \(summaryURL.path)")

        if summaryOnly {
            // Move the bundle out of the committed evidence directory and
            // into the user's cache so it remains inspectable locally without
            // bloating the repo.
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            let cachedBundleURL = cacheDirectory.appendingPathComponent(bundleName)
            if fileManager.fileExists(atPath: cachedBundleURL.path) {
                try fileManager.removeItem(at: cachedBundleURL)
            }
            try fileManager.moveItem(at: workingBundleURL, to: cachedBundleURL)
            stdout("Cached full xcresult bundle at \(cachedBundleURL.path)")
        } else {
            stdout("Captured xcresult bundle at \(workingBundleURL.path)")
        }

        // The markdown is now persisted regardless of pass/fail state. If the
        // underlying `xcodebuild test` reported failures, propagate that as a
        // non-zero CLI exit so CI catches the regression — `<KEY>-tests.md`
        // is still authoritative for the PR comment.
        if testResult.exitCode != 0 {
            throw CLIError.commandFailed("xcodebuild test reported \(parsed.failedTests) failure(s). See \(summaryURL.path).")
        }
    }

    private func diff(_ arguments: [String], config: EvidenceConfig) throws {
        try requireTool(toolPaths.magick, versionArguments: ["--version"], installHint: "Install ImageMagick, for example with `brew install imagemagick`.")

        // Resolve directories. CLI flags override `.evidence.toml`; all paths
        // are anchored to the working directory so the tool composes cleanly
        // with monorepos that run `evidence` from a sub-folder.
        let baselinePath = optionValue("baseline", in: arguments) ?? config.diff.baselineDirectory
        let currentPath = optionValue("current", in: arguments) ?? config.evidenceDirectory
        // Default to `<evidence_dir>/diff` and `<output>/diff-report.json`.
        // Build these as plain joined strings rather than via
        // `URL(fileURLWithPath:)` because the latter resolves relative paths
        // against the process CWD, which is wrong when `currentDirectory` is
        // injected for tests or for monorepos that run `evidence` outside
        // the package root.
        let outputPath = optionValue("output", in: arguments) ?? joinPath(currentPath, "diff")
        let reportPath = optionValue("report", in: arguments) ?? joinPath(outputPath, "diff-report.json")
        let markdownPath = optionValue("markdown", in: arguments)

        let baselineURL = url(forPath: baselinePath)
        let currentURL = url(forPath: currentPath)
        let outputURL = url(forPath: outputPath)
        let reportURL = url(forPath: reportPath)

        // Threshold flag override. Parses 0.0–1.0 by default; numbers >1 are
        // treated as percent-style (`--threshold 5` => 0.05) which is how
        // most CI configs express the value.
        let threshold: Double
        if let raw = optionValue("threshold", in: arguments) {
            guard let value = Double(raw), value >= 0 else {
                throw CLIError.usage("Invalid --threshold '\(raw)': expected a non-negative number.")
            }
            threshold = value > 1 ? value / 100 : value
        } else {
            threshold = config.diff.threshold
        }

        let visualDiff = VisualDiff(fileManager: fileManager, runner: runner, magickPath: toolPaths.magick)

        // Surface a clean error when the consumer points us at a missing
        // current-run directory — without this, the run silently produces an
        // empty report.
        guard fileManager.fileExists(atPath: currentURL.path) else {
            throw CLIError.usage("Current capture directory '\(currentURL.path)' does not exist. Run `evidence capture-screenshots` first.")
        }

        let scenes = try visualDiff.compareDirectory(
            currentDirectory: currentURL,
            baselineDirectory: baselineURL,
            diffOutputDirectory: outputURL,
            threshold: threshold,
            ignoreRegions: config.diff.ignoreRegions,
            fuzzPercent: config.diff.fuzzPercent,
            repoRoot: currentDirectory
        )
        let report = DiffReport(scenes: scenes, threshold: threshold)

        try fileManager.createDirectory(
            at: reportURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try DiffReportEncoder.encode(report).write(to: reportURL)
        stdout("Wrote diff report to \(reportURL.path)")

        let rawBaseURL = config.repositoryRawBaseURL ?? inferredRepositoryRawBaseURL()
        let markdown = VisualDiff.renderMarkdown(report: report, repoRawBaseURL: rawBaseURL)
        if let markdownPath {
            let markdownURL = url(forPath: markdownPath)
            try fileManager.createDirectory(
                at: markdownURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try markdown.write(to: markdownURL, atomically: true, encoding: .utf8)
            stdout("Wrote PR-comment markdown to \(markdownURL.path)")
        } else {
            stdout(markdown)
        }

        // Translate the report's verdict into the CI-contract exit codes.
        // `.exit` carries the message so the caller still gets a one-line
        // summary on stderr.
        if report.hasRegression {
            let count = report.scenes.filter { $0.status == .regression }.count
            throw CLIError.exit(1, message: "\(count) scene(s) exceeded threshold \(threshold). See \(reportURL.path).")
        }
        if report.hasMissingBaseline {
            let count = report.scenes.filter { $0.status == .baselineMissing }.count
            throw CLIError.exit(2, message: "\(count) scene(s) missing baseline images. Run `evidence accept-baseline` to lock them in.")
        }
    }

    private func acceptBaseline(_ arguments: [String], config: EvidenceConfig) throws {
        let force = arguments.contains("--force")
        let allowDirty = force || config.diff.acceptAllowDirty

        let sourcePath = optionValue("source", in: arguments) ?? config.evidenceDirectory
        let baselinePath = optionValue("baseline", in: arguments) ?? config.diff.baselineDirectory
        let sourceURL = url(forPath: sourcePath)
        let baselineURL = url(forPath: baselinePath)

        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw CLIError.usage("Source directory '\(sourceURL.path)' does not exist. Run `evidence capture-screenshots` first.")
        }

        // Refuse to overwrite baselines from a dirty working tree by default.
        // Baselines are committed into the consumer repo, so a stray local
        // edit silently flowing into `git add` is the worst-case bug.
        if !allowDirty {
            let status = try runner.run(toolPaths.git, ["status", "--porcelain"])
            if status.exitCode == 0 {
                let porcelain = status.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                if !porcelain.isEmpty {
                    throw CLIError.commandFailed(
                        "Refusing to accept baseline: working tree has uncommitted changes. " +
                        "Commit or stash them first, pass --force, or set diff_accept_allow_dirty = true in .evidence.toml."
                    )
                }
            }
        }

        try fileManager.createDirectory(at: baselineURL, withIntermediateDirectories: true)

        // Mirror the latest run's PNGs into the baseline directory. We
        // deliberately walk the source tree (rather than `cp -R`) so we can
        // skip non-PNG artifacts like `diff/`, `diff-report.json`, and the
        // xcresult bundle/markdown pair.
        let enumerator = fileManager.enumerator(at: sourceURL, includingPropertiesForKeys: [.isRegularFileKey])
        var copied = 0
        // Resolve symlinks once so a `/var -> /private/var` redirection on
        // macOS doesn't smear the prefix and produce bogus relative paths.
        let resolvedSourcePrefix = sourceURL.resolvingSymlinksInPath().path + "/"
        if let enumerator {
            for case let url as URL in enumerator where url.pathExtension.lowercased() == "png" {
                let resolvedPath = url.resolvingSymlinksInPath().path
                let relative: String
                if resolvedPath.hasPrefix(resolvedSourcePrefix) {
                    relative = String(resolvedPath.dropFirst(resolvedSourcePrefix.count))
                } else if url.path.hasPrefix(sourceURL.path + "/") {
                    relative = String(url.path.dropFirst(sourceURL.path.count + 1))
                } else {
                    relative = url.lastPathComponent
                }
                // Skip our own diff outputs so accepting a baseline never
                // pulls last-run's diff PNGs into the baseline tree.
                if relative.hasPrefix("diff/") {
                    continue
                }
                let destinationURL = baselineURL.appendingPathComponent(relative)
                try fileManager.createDirectory(
                    at: destinationURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                try fileManager.copyItem(at: url, to: destinationURL)
                copied += 1
            }
        }

        stdout("Accepted \(copied) baseline image(s) at \(baselineURL.path).")
    }

    private func uploadScreenshots(_ arguments: [String], config: EvidenceConfig) throws {
        try AppStoreScreenshotUploader(
            fileManager: fileManager,
            httpClient: httpClient,
            stdout: stdout
        ).upload(arguments: arguments, config: config, currentDirectory: currentDirectory)
    }

    private func markdownURL(for output: URL, config: EvidenceConfig) -> String? {
        guard let baseURL = config.repositoryRawBaseURL ?? inferredRepositoryRawBaseURL() else {
            return nil
        }
        let relativePath = output.path.replacingOccurrences(of: currentDirectory.path + "/", with: "")
        return baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/" + relativePath
    }

    private func url(forPath path: String) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return currentDirectory.appendingPathComponent(path)
    }

    /// Join two path-like strings while preserving relative-vs-absolute
    /// semantics. `URL(fileURLWithPath:)` would silently rebase a relative
    /// `"docs/build-evidence/diff"` against the process CWD, which breaks
    /// tests that inject `currentDirectory` and breaks monorepos that run
    /// `evidence` from a sub-folder.
    private func joinPath(_ left: String, _ right: String) -> String {
        if right.hasPrefix("/") {
            return right
        }
        if left.hasSuffix("/") {
            return left + right
        }
        return left + "/" + right
    }

    private func inferredRepositoryRawBaseURL() -> String? {
        guard let result = try? runner.run(toolPaths.git, ["remote", "get-url", "origin"]),
              result.exitCode == 0 else {
            return nil
        }

        let remote = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if remote.hasPrefix("git@github.com:") {
            let path = remote
                .replacingOccurrences(of: "git@github.com:", with: "")
                .replacingOccurrences(of: ".git", with: "")
            return "https://raw.githubusercontent.com/\(path)/main"
        }

        if remote.hasPrefix("https://github.com/") {
            let path = remote
                .replacingOccurrences(of: "https://github.com/", with: "")
                .replacingOccurrences(of: ".git", with: "")
            return "https://raw.githubusercontent.com/\(path)/main"
        }

        return nil
    }

    private func requireTool(_ executable: String, versionArguments: [String], installHint: String) throws {
        guard fileManager.isExecutableFile(atPath: executable) else {
            throw CLIError.missingTool(URL(fileURLWithPath: executable).lastPathComponent, installHint: installHint)
        }
        let result = try runner.run(executable, versionArguments)
        guard result.exitCode == 0 else {
            throw CLIError.missingTool(URL(fileURLWithPath: executable).lastPathComponent, installHint: installHint)
        }
    }

    private func option(_ name: String, in arguments: [String]) throws -> String {
        guard let value = optionValue(name, in: arguments), !value.isEmpty else {
            throw CLIError.usage("Missing required option --\(name).")
        }
        return value
    }

    private func optionValue(_ name: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: "--\(name)") else {
            return nil
        }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else {
            return nil
        }
        return arguments[valueIndex]
    }
}

public struct ToolPaths: Equatable {
    public var xcrun: String
    public var magick: String
    public var ffmpeg: String
    public var git: String

    public init(
        xcrun: String = "/usr/bin/xcrun",
        magick: String = "/opt/homebrew/bin/magick",
        ffmpeg: String = "/opt/homebrew/bin/ffmpeg",
        git: String = "/usr/bin/git"
    ) {
        self.xcrun = xcrun
        self.magick = magick
        self.ffmpeg = ffmpeg
        self.git = git
    }
}
